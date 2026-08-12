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
// supNulls: taskId -> how many leading SUPERVISOR calls return null (dead agent).
function stub(verdictsById, { execNulls = {}, supNulls = {} } = {}) {
  const q = Object.fromEntries(Object.entries(verdictsById).map(([k, v]) => [k, [...v]]))
  const nulls = { ...execNulls }
  const supDead = { ...supNulls }
  return (prompt) => {
    const id = (prompt.match(/wave\/([a-z0-9-]+)/) ?? [])[1]
    if (prompt.startsWith(SUP)) {
      if ((supDead[id] ?? 0) > 0) { supDead[id]--; return null }
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

test('S8 args passed as a JSON string are parsed, validated, and run', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: JSON.stringify(waveArgs()),
    agentStub: stub({ 't-one': [V.ok()] }),
  })
  assert.equal(result.status, 'done')
  assert.equal(result.tasks[0].status, 'ok')
  assert.ok(calls.length > 0)
})

test('S8e a string that is not valid JSON fails closed, zero agent calls', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: 'not json at all {',
    agentStub: () => { throw new Error('no agent may be called') },
  })
  assert.equal(result.status, 'invalid-args')
  assert.match(result.errors[0], /parse/i)
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

// ---------- S1–S7: the ladder itself ----------

test('S1 clean pass: one executor call, one supervisor call, no escalation', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }),
  })
  assert.equal(result.status, 'done')
  assert.equal(result.tasks[0].status, 'ok')
  assert.equal(result.tasks[0].branch, 'wave/t-one')
  assert.equal(execCalls(calls, 't-one').length, 1)
  assert.equal(supCalls(calls, 't-one').length, 1)
  assert.equal(execCalls(calls, 't-one')[0].opts.model, 'sonnet')
  assert.deepEqual(verdictAttempts(result.tasks[0]).map((a) => a.escalation), [null])
})

test('S2 rework: same model, prior verdict travels in the prompt', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.files(), V.ok()] }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  const ex = execCalls(calls, 't-one')
  assert.deepEqual(ex.map((c) => c.opts.model), ['sonnet', 'sonnet'])
  assert.match(ex[1].prompt, /Prior attempt was rejected/)
  assert.match(ex[1].prompt, /"class": "files"/)
})

test('S3 same (class, rule) twice → next rung, model actually changes', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.files(), V.files(), V.ok()] }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.deepEqual(execCalls(calls, 't-one').map((c) => c.opts.model), ['sonnet', 'sonnet', 'opus'])
  assert.deepEqual(verdictAttempts(result.tasks[0]).map((a) => a.escalation),
    [null, 'same-rule-repeat', null])
})

test('S3b a different rule the second time also escalates, labeled rung-exhausted', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.files(), V.report(), V.ok()] }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.equal(verdictAttempts(result.tasks[0])[1].escalation, 'rung-exhausted')
  assert.equal(execCalls(calls, 't-one')[2].opts.model, 'opus')
})

test('S4 two pasteReproduced:false strikes → escalation labeled paste-two-strikes', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.paste(), V.paste(), V.ok()] }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.equal(verdictAttempts(result.tasks[0])[1].escalation, 'paste-two-strikes')
  assert.equal(execCalls(calls, 't-one')[2].opts.model, 'opus')
})

test('S4b second strike on a later rung skips its remaining attempt', async () => {
  // strike 1 on rung 0, rung 0 exhausted, strike 2 on rung 1 attempt 1:
  // rung 1 is terminal, its second attempt must be skipped → failed after 3.
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.paste(), V.files(), V.paste()] }),
  })
  assert.equal(result.tasks[0].status, 'failed')
  assert.equal(execCalls(calls, 't-one').length, 3)
  assert.equal(verdictAttempts(result.tasks[0])[2].escalation, 'paste-two-strikes')
})

test('S5 satisfiable:false stops that task at once; the neighbour is untouched', async () => {
  const twoTasks = waveArgs({ tasks: [task({ id: 't-bad' }), task({ id: 't-good' })] })
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: twoTasks,
    agentStub: stub({ 't-bad': [V.unsat()], 't-good': [V.ok()] }),
  })
  const bad = result.tasks.find((t) => t.id === 't-bad')
  const good = result.tasks.find((t) => t.id === 't-good')
  assert.equal(bad.status, 'contract-unsatisfiable')
  assert.equal(execCalls(calls, 't-bad').length, 1)
  assert.equal(good.status, 'ok')
  assert.equal(result.status, 'partial')
})

test('S5b tie-break: ok:true with a satisfiable:false violation still stops the task', async () => {
  const contradictory = { ok: true, violations: [{ rule: 'must_run: true', class: 'must_run',
    evidence: 'command reads nothing under files_allowed', quote: '', satisfiable: false }], remarks: [] }
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [contradictory] }),
  })
  assert.equal(result.tasks[0].status, 'contract-unsatisfiable')
  assert.equal(execCalls(calls, 't-one').length, 1)
})

test('S6 ladder exhausted → failed with the full attempt trace', async () => {
  const { result } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.files(), V.report(), V.files(), V.report()] }),
  })
  assert.equal(result.tasks[0].status, 'failed')
  assert.equal(verdictAttempts(result.tasks[0]).length, 4)
  assert.deepEqual(verdictAttempts(result.tasks[0]).map((a) => a.model),
    ['sonnet', 'sonnet', 'opus', 'opus'])
})

test('S6b absolute cap: six executor attempts, however long the ladder', async () => {
  // 5 rungs × 2 would be 10; the queue holds exactly 6 verdicts, so a 7th
  // supervisor call would throw and fail this test by itself.
  const capArgs = waveArgs({ tasks: [task({ ladder: ['opus', 'opus', 'opus', 'opus'] })] })
  const { result } = await runWorkflow(SCRIPT, {
    args: capArgs,
    agentStub: stub({ 't-one': [V.files(), V.report(), V.files(), V.report(), V.files(), V.report()] }),
  })
  assert.equal(result.tasks[0].status, 'failed')
  assert.equal(verdictAttempts(result.tasks[0]).length, 6)
})

test('S7 one dead executor call: recorded, retried, the task still passes', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }, { execNulls: { 't-one': 1 } }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.deepEqual(result.tasks[0].attempts.map((a) => a.kind), ['agent-error', 'verdict'])
  assert.equal(execCalls(calls, 't-one').length, 2)
})

test('S7b two dead calls in a row → task error, wave survives, no supervisor call', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [] }, { execNulls: { 't-one': 2 } }),
  })
  assert.equal(result.tasks[0].status, 'error')
  assert.equal(result.status, 'partial')
  assert.equal(supCalls(calls, 't-one').length, 0)
})

test('S7c a dead supervisor call: recorded, retried, the task still passes', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }, { supNulls: { 't-one': 1 } }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.deepEqual(result.tasks[0].attempts.map((a) => a.kind), ['agent-error', 'verdict'])
  assert.equal(supCalls(calls, 't-one').length, 2)
  assert.equal(execCalls(calls, 't-one').length, 1)
})

test('S7d two dead supervisor calls → task error, wave survives', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [] }, { supNulls: { 't-one': 2 } }),
  })
  assert.equal(result.tasks[0].status, 'error')
  assert.equal(result.status, 'partial')
  assert.equal(supCalls(calls, 't-one').length, 2)
  assert.equal(execCalls(calls, 't-one').length, 1)
})

let failed = 0
for (const t of tests) {
  try { await t.fn(); console.log('ok -', t.name) }
  catch (e) { failed++; console.log('not ok -', t.name); console.log('   ', e.message) }
}
process.exit(failed ? 1 : 0)
