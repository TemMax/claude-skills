// Ladder semantics of the SHIPPED wave-runner, asserted deterministically on
// the real file via the simulator. No model calls.
// Run: node tests/lib/wave-runner.test.mjs
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { runWorkflow } from './workflow-sim.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const SCRIPT = join(here, '..', '..', 'plugins', 'orchestration', 'skills',
  'multi-model', 'references', 'wave-runner.workflow.mjs')

// The marker doubles as the supervisor-call discriminator in the stub and must
// contain the word "verdict" to pass the runner's wrong-file tripwire.
const SUP = 'SIM SUPERVISOR PROMPT — check the branch yourself and return a verdict'

const V = {
  ok:     () => ({ ok: true, violations: [], remarks: [] }),
  files:  () => ({ ok: false, violations: [{ rule: 'files_allowed: [src/**]', class: 'files',
                   evidence: 'diff touches docs/readme.md', quote: '' }], remarks: [] }),
  report: () => ({ ok: false, violations: [{ rule: 'report_must_answer: what changed?', class: 'report',
                   evidence: 'the answer contradicts the diff', quote: '' }], remarks: [] }),
  paste:  () => ({ ok: false, violations: [{ rule: 'must_run: true', class: 'must_run',
                   evidence: 'report pasted a pass; supervisor got a failure', quote: '',
                   pasteReproduced: false, satisfiable: true }], remarks: [] }),
  unsat:  () => ({ ok: false, violations: [{ rule: 'must_run: true', class: 'must_run',
                   evidence: 'the command reads nothing under files_allowed', quote: '',
                   satisfiable: false }], remarks: [] }),
}

function task(over = {}) {
  return {
    id: 't-one',
    description: 'do the thing',
    context: '',
    contract: {
      files_allowed: ['src/**'],
      files_forbidden: [],
      must_run: [{ cmd: 'true', evidence: 'required' }],
      forbidden_moves: ['weakening, deleting or skipping an existing test'],
      report_must_answer: ['what changed?'],
    },
    executor: { model: 'sonnet', effort: 'medium' },
    ladder: ['opus'],
    ...over,
  }
}

function waveArgs(over = {}) {
  return {
    base: 'abc1234',
    defaultBranch: 'main',
    repoPath: '/tmp/simrepo',
    supervisorPromptText: SUP,
    supervisor: { model: 'opus', effort: 'high' },
    tasks: [task()],
    ...over,
  }
}

// verdictsById: taskId -> queue of verdicts, consumed one per supervisor call.
// execNulls: taskId -> how many leading EXECUTOR calls return null (dead agent).
function stub(verdictsById, { execNulls = {} } = {}) {
  const q = Object.fromEntries(Object.entries(verdictsById).map(([k, v]) => [k, [...v]]))
  const nulls = { ...execNulls }
  return (prompt) => {
    const id = (prompt.match(/wave\/([a-z0-9-]+)/) ?? [])[1]
    if (prompt.startsWith(SUP)) {
      if (!q[id] || q[id].length === 0) throw new Error('verdict queue exhausted for ' + id)
      return q[id].shift()
    }
    if ((nulls[id] ?? 0) > 0) { nulls[id]--; return null }
    return 'report for ' + id + '\n$ true\n(exit 0)'
  }
}

const execCalls = (calls, id) =>
  calls.filter((c) => !c.prompt.startsWith(SUP) && c.prompt.includes('wave/' + id))
const supCalls = (calls, id) =>
  calls.filter((c) => c.prompt.startsWith(SUP) && c.prompt.includes('wave/' + id))
const verdictAttempts = (t) => t.attempts.filter((a) => a.kind === 'verdict')

const tests = []
const test = (name, fn) => tests.push({ name, fn })

// ---------- S8: fail-closed validation ----------

test('S8 args passed as a string → invalid-args, zero agent calls', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: JSON.stringify(waveArgs()),
    agentStub: () => { throw new Error('no agent may be called') },
  })
  assert.equal(result.status, 'invalid-args')
  assert.match(result.errors[0], /object/)
  assert.equal(calls.length, 0)
})

test('S8b missing base and empty tasks → named errors, zero agent calls', async () => {
  const bad = waveArgs({ tasks: [] })
  delete bad.base
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: bad,
    agentStub: () => { throw new Error('no agent may be called') },
  })
  assert.equal(result.status, 'invalid-args')
  const all = result.errors.join('; ')
  assert.match(all, /base/)
  assert.match(all, /tasks/)
  assert.equal(calls.length, 0)
})

test('S8c wrong supervisor prompt text and bad model names are named', async () => {
  const bad = waveArgs({ supervisorPromptText: 'some other file entirely' })
  bad.tasks = [task({ executor: { model: 'claude-sonnet-5' }, ladder: ['gpt'] })]
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: bad,
    agentStub: () => { throw new Error('no agent may be called') },
  })
  assert.equal(result.status, 'invalid-args')
  const all = result.errors.join('; ')
  assert.match(all, /supervisorPromptText/)
  assert.match(all, /executor\.model/)
  assert.match(all, /ladder/)
  assert.equal(calls.length, 0)
})

test('S8d a null task entry fails closed, not with a crash', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs({ tasks: [null] }),
    agentStub: () => { throw new Error('no agent may be called') },
  })
  assert.equal(result.status, 'invalid-args')
  assert.match(result.errors.join('; '), /tasks\[0\]/)
  assert.equal(calls.length, 0)
})

let failed = 0
for (const t of tests) {
  try { await t.fn(); console.log('ok -', t.name) }
  catch (e) { failed++; console.log('not ok -', t.name); console.log('   ', e.message) }
}
process.exit(failed ? 1 : 0)
