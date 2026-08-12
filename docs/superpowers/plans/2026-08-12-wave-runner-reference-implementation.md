# Wave Runner Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the supervised-wave escalation logic as one tested workflow
script (`wave-runner.workflow.mjs`) that the orchestrator invokes instead of
rewriting, with a deterministic offline simulator proving every ladder rule.

**Architecture:** The reference script lives in the multi-model skill's
`references/`; a Node simulator in `tests/lib/` wraps the real script text in
an `AsyncFunction` with stubbed `agent()`/`pipeline()` and asserts the ladder
semantics scenario by scenario; a shell wrapper joins the offline suite; a live
eval tier proves only the real-Workflow boundary.

**Tech Stack:** plain JavaScript (workflow-script dialect: no filesystem, no
Date/Math.random, single export), Node ≥ 18 for the simulator, bash + tests/lib.sh
for wrappers.

**Spec:** `docs/superpowers/specs/2026-08-12-wave-runner-reference-implementation-design.md`

## Global Constraints

- No mention of the third-party reference implementation anywhere
  (structure.sh greps for the bracketed names; do not write them even in comments).
- Push only with the user's explicit approval. Local commits are fine.
- Workflow-script dialect (violations are launch rejections, verified 2026-08-12):
  `meta` is a pure literal; exactly one `export`; no `Date.`, `new Date`,
  `Math.random`; short model names (`haiku`/`sonnet`/`opus`/`fable`); result via
  top-level `return`; `agent()` may return `null`.
- `plugins/orchestration/.claude-plugin/plugin.json` version and the multi-model
  SKILL.md `metadata.version` must agree (structure.sh enforces it): both go
  `1.7.1 → 1.8.0` in Task 4, not before.
- The supervisor prompt (`references/supervisor-prompt.md`) is NOT edited by
  this work. `satisfiable` and `pasteReproduced` are per-violation fields, as
  that prompt already emits them.
- Verdict shape consumed by the runner:
  `{ok, violations: [{rule, class, evidence, quote, pasteReproduced?, satisfiable?}], remarks}`.

---

### Task 1: Simulator harness

**Files:**
- Create: `tests/lib/workflow-sim.mjs`
- Create: `tests/lib/fixtures/sim-smoke.workflow.mjs`
- Test: `tests/lib/workflow-sim.test.mjs`

**Interfaces:**
- Produces: `runWorkflow(scriptPath, {args, agentStub}) → Promise<{result, calls}>`
  where `agentStub(prompt, opts, index)` returns the stubbed agent reply (may be
  a Promise, may be `null`), and `calls` is `[{prompt, opts}]` in call order.
  Task 3's scenario tests consume exactly this signature.

- [ ] **Step 1: Write the failing self-test**

`tests/lib/workflow-sim.test.mjs`:

```js
// Self-test of the simulator harness against a tiny fixture script.
// Run: node tests/lib/workflow-sim.test.mjs
import assert from 'node:assert/strict'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { runWorkflow } from './workflow-sim.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const FIXTURE = join(here, 'fixtures', 'sim-smoke.workflow.mjs')

const tests = []
const test = (name, fn) => tests.push({ name, fn })

test('runs the real file text: agent stubbed, pipeline faithful, return captured', async () => {
  const { result, calls } = await runWorkflow(FIXTURE, {
    args: { greeting: 'hello' },
    agentStub: (prompt, opts) => {
      assert.equal(prompt, 'hello')
      assert.equal(opts.model, 'haiku')
      return 'world'
    },
  })
  assert.deepEqual(result, { r: 'world', doubled: [2, 4], broken: [null] })
  assert.equal(calls.length, 1)
})

test('a throwing pipeline stage drops the item to null, like the real tool', async () => {
  const { result } = await runWorkflow(FIXTURE, { args: { greeting: 'x' }, agentStub: () => 'y' })
  assert.deepEqual(result.broken, [null])
})

let failed = 0
for (const t of tests) {
  try { await t.fn(); console.log('ok -', t.name) }
  catch (e) { failed++; console.log('not ok -', t.name); console.log('   ', e.message) }
}
process.exit(failed ? 1 : 0)
```

`tests/lib/fixtures/sim-smoke.workflow.mjs`:

```js
export const meta = {
  name: 'sim-smoke',
  description: 'Fixture exercising every simulator seam',
  phases: [],
}
phase('Smoke')
log('smoke')
const r = await agent(args.greeting, { model: 'haiku' })
const doubled = await pipeline([1, 2], async (n) => n * 2)
const broken = await pipeline([1], async () => { throw new Error('boom') })
return { r, doubled, broken }
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `node tests/lib/workflow-sim.test.mjs`
Expected: FAIL — `Cannot find module ... workflow-sim.mjs`

- [ ] **Step 3: Implement the harness**

`tests/lib/workflow-sim.mjs`:

```js
// Runs a REAL workflow-script file offline: same file that ships, stubbed
// runtime. The workflow dialect has no imports and returns via top-level
// `return`, so the file body is legal inside an async function once the single
// `export` is neutralised.
import { readFile } from 'node:fs/promises'

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

export async function runWorkflow(scriptPath, { args, agentStub }) {
  let src = await readFile(scriptPath, 'utf8')
  src = src.replace(/^export const meta/m, 'const meta')

  const calls = []
  const agent = async (prompt, opts = {}) => {
    calls.push({ prompt, opts })
    return agentStub(prompt, opts, calls.length - 1)
  }
  // Faithful to the documented contract: stages run per item with no barrier;
  // a throwing stage drops that item to null and skips its remaining stages.
  const pipeline = (items, ...stages) =>
    Promise.all(items.map(async (item, index) => {
      let prev = item
      for (const stage of stages) {
        try { prev = await stage(prev, item, index) } catch { return null }
      }
      return prev
    }))
  // Thunks run concurrently; a rejecting thunk resolves to null, never rejects.
  const parallel = (thunks) => Promise.all(thunks.map((t) => Promise.resolve().then(t).catch(() => null)))
  const phase = () => {}
  const log = () => {}
  const budget = { total: null, spent: () => 0, remaining: () => Infinity }
  const workflow = async () => { throw new Error('nested workflow() is not simulated') }

  const fn = new AsyncFunction('agent', 'pipeline', 'parallel', 'phase', 'log', 'args', 'budget', 'workflow', src)
  const result = await fn(agent, pipeline, parallel, phase, log, args, budget, workflow)
  return { result, calls }
}
```

- [ ] **Step 4: Run the self-test, expect both cases green**

Run: `node tests/lib/workflow-sim.test.mjs`
Expected: `ok - runs the real file text...`, `ok - a throwing pipeline stage...`, exit 0

- [ ] **Step 5: Commit**

```bash
git add tests/lib/workflow-sim.mjs tests/lib/workflow-sim.test.mjs tests/lib/fixtures/sim-smoke.workflow.mjs
git commit -m "Add an offline simulator that runs real workflow-script files with stubbed agents"
```

---

### Task 2: Runner skeleton — fail-closed validation (scenario S8)

**Files:**
- Create: `plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs`
- Test: `tests/lib/wave-runner.test.mjs`

**Interfaces:**
- Consumes: `runWorkflow` from Task 1.
- Produces: the runner file at the path above; args contract per the spec;
  `{status: 'invalid-args', errors: [...], tasks: []}` on any validation
  failure with **zero** agent calls. Task 3 extends this same file and this
  same test file; Task 4's SKILL.md references this exact filename.

- [ ] **Step 1: Write the failing S8 scenarios**

`tests/lib/wave-runner.test.mjs` (whole file as of this task; Task 3 appends):

```js
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

let failed = 0
for (const t of tests) {
  try { await t.fn(); console.log('ok -', t.name) }
  catch (e) { failed++; console.log('not ok -', t.name); console.log('   ', e.message) }
}
process.exit(failed ? 1 : 0)
```

- [ ] **Step 2: Run to verify it fails**

Run: `node tests/lib/wave-runner.test.mjs`
Expected: FAIL — `ENOENT ... wave-runner.workflow.mjs`

- [ ] **Step 3: Write the runner with validation and a stub tail**

`plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs`
(whole file as of this task; Task 3 replaces the final stub `return`):

```js
export const meta = {
  name: 'wave-runner',
  description: 'Reference supervised-wave runner: isolation, executors, supervision, escalation ladder',
  phases: [
    { title: 'Wave', detail: 'per task: executor → supervisor → ladder' },
  ],
}

// Escalation policy tested by tests/lib/wave-runner.test.mjs — change the
// numbers there and here together.
const MODELS = ['haiku', 'sonnet', 'opus', 'fable']
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const LADDER_ORDER = ['haiku', 'sonnet', 'opus']
const MAX_ATTEMPTS_PER_RUNG = 2
const MAX_ATTEMPTS_PER_TASK = 6

function invalid(errors) { return { status: 'invalid-args', errors, tasks: [] } }

// Fail closed: a bad wave returns named errors and spawns nothing. `args`
// arriving as a string (the caller stringified it) has shipped twice; it dies
// here by name instead of running to a plausible, meaningless result.
if (typeof args !== 'object' || args === null || Array.isArray(args)) {
  return invalid(['args must be a JSON object, not a ' +
    (typeof args === 'string' ? 'string (the caller JSON-encoded it)' : typeof args)])
}

const errors = []
if (typeof args.base !== 'string' || !/^[0-9a-f]{7,40}$/.test(args.base)) {
  errors.push('base: a 7-40 char lowercase hex sha is required')
}
if (typeof args.repoPath !== 'string' || !args.repoPath.startsWith('/')) {
  errors.push('repoPath: an absolute path is required')
}
if (typeof args.defaultBranch !== 'string' || args.defaultBranch === '') {
  errors.push('defaultBranch: required')
}
if (typeof args.supervisorPromptText !== 'string' || !args.supervisorPromptText.includes('verdict')) {
  errors.push('supervisorPromptText: must be the text of references/supervisor-prompt.md (missing, or the wrong file was read)')
}
if (!args.supervisor || !MODELS.includes(args.supervisor.model)) {
  errors.push('supervisor.model: one of ' + MODELS.join('/'))
}
if (args.supervisor && args.supervisor.effort !== undefined && !EFFORTS.includes(args.supervisor.effort)) {
  errors.push('supervisor.effort: one of ' + EFFORTS.join('/'))
}
if (!Array.isArray(args.tasks) || args.tasks.length === 0) {
  errors.push('tasks: a non-empty array is required')
} else {
  const seen = new Set()
  args.tasks.forEach((t, i) => {
    const at = 'tasks[' + i + ']'
    if (typeof t.id !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(t.id)) {
      errors.push(at + '.id: kebab-case required')
    } else if (seen.has(t.id)) {
      errors.push(at + '.id: duplicate "' + t.id + '"')
    } else { seen.add(t.id) }
    if (typeof t.description !== 'string' || t.description.trim() === '') {
      errors.push(at + '.description: required')
    }
    const c = t.contract
    if (!c || typeof c !== 'object') {
      errors.push(at + '.contract: required, with all five keys')
    } else {
      for (const k of ['files_allowed', 'files_forbidden', 'forbidden_moves', 'report_must_answer']) {
        if (!Array.isArray(c[k])) errors.push(at + '.contract.' + k + ': array required')
      }
      if (!Array.isArray(c.must_run)) {
        errors.push(at + '.contract.must_run: array required')
      } else {
        c.must_run.forEach((m, j) => {
          if (!m || typeof m.cmd !== 'string' || m.cmd === '') {
            errors.push(at + '.contract.must_run[' + j + '].cmd: required')
          }
          if (!m || typeof m.evidence !== 'string') {
            errors.push(at + '.contract.must_run[' + j + '].evidence: required')
          }
        })
      }
    }
    if (!t.executor || !MODELS.includes(t.executor.model)) {
      errors.push(at + '.executor.model: one of ' + MODELS.join('/') + ' (short names only)')
    }
    if (t.executor && t.executor.effort !== undefined && !EFFORTS.includes(t.executor.effort)) {
      errors.push(at + '.executor.effort: one of ' + EFFORTS.join('/'))
    }
    if (t.ladder !== undefined && (!Array.isArray(t.ladder) || t.ladder.some((m) => !MODELS.includes(m)))) {
      errors.push(at + '.ladder: an array of ' + MODELS.join('/') + ' (short names only)')
    }
  })
}
if (errors.length > 0) return invalid(errors)

// Task 3 replaces this stub tail with the wave itself.
return { status: 'partial', errors: [], tasks: [] }
```

- [ ] **Step 4: Run tests, expect S8/S8b/S8c green, Task 1 self-test still green**

Run: `node tests/lib/wave-runner.test.mjs && node tests/lib/workflow-sim.test.mjs`
Expected: `ok -` × 3, then × 2; exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs tests/lib/wave-runner.test.mjs
git commit -m "Wave runner: fail-closed args validation, zero agents on bad input"
```

---

### Task 3: The ladder as code (scenarios S1–S7) + suite wiring

**Files:**
- Modify: `plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs` (replace the stub tail)
- Modify: `tests/lib/wave-runner.test.mjs` (append S1–S7)
- Create: `tests/wave-runner.test.sh`
- Modify: `tests/run.sh` (one line)

**Interfaces:**
- Consumes: Task 1's `runWorkflow`, Task 2's validation and test helpers
  (`task`, `waveArgs`, `stub`, `V`, `execCalls`, `supCalls`, `verdictAttempts`).
- Produces: full runner behavior per spec §4; return shape per spec §5
  (`status: done|partial|invalid-args`; task statuses
  `ok|failed|contract-unsatisfiable|error`; attempt records
  `{rung, model, effort, kind: 'verdict'|'agent-error', verdict, escalation}`
  with escalation ∈ `null|'same-rule-repeat'|'rung-exhausted'|'paste-two-strikes'`).
  Task 4's SKILL.md describes exactly this behavior.

- [ ] **Step 1: Append the failing S1–S7 scenarios**

In `tests/lib/wave-runner.test.mjs`, insert before the `let failed = 0` runner
block:

```js
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
```

- [ ] **Step 2: Run to verify the new scenarios fail**

Run: `node tests/lib/wave-runner.test.mjs`
Expected: S8 cases still `ok -`; every S1–S7 case `not ok -` (the stub tail
returns no tasks).

- [ ] **Step 3: Replace the stub tail with the wave**

In `wave-runner.workflow.mjs`, replace the two final lines

```js
// Task 3 replaces this stub tail with the wave itself.
return { status: 'partial', errors: [], tasks: [] }
```

with:

```js
// ---------- prompt assembly ----------
// The executor's contract block and the supervisor's contract are rendered
// from the same object; they cannot diverge.

function yamlInline(items) { return '[' + items.join(', ') + ']' }

function renderContract(c) {
  const lines = ['contract:']
  lines.push('  files_allowed: ' + yamlInline(c.files_allowed))
  lines.push('  files_forbidden: ' + yamlInline(c.files_forbidden))
  if (c.must_run.length === 0) {
    lines.push('  must_run: []')
  } else {
    lines.push('  must_run:')
    for (const m of c.must_run) {
      lines.push('    - cmd: ' + m.cmd)
      lines.push('      evidence: ' + m.evidence)
    }
  }
  for (const key of ['forbidden_moves', 'report_must_answer']) {
    if (c[key].length === 0) {
      lines.push('  ' + key + ': []')
    } else {
      lines.push('  ' + key + ':')
      for (const item of c[key]) lines.push('    - ' + item)
    }
  }
  return lines.join('\n')
}

function executorPrompt(t) {
  const worktree = args.repoPath + '/.worktrees/wave-' + t.id
  return [
    '# Task: ' + t.id,
    '',
    '## Context',
    t.description,
    t.context ? '' : null,
    t.context ? t.context : null,
    '',
    'You work in your own git worktree. You will not see any other task\'s',
    'edits; a quiet tree is expected, not a sign something is wrong.',
    '',
    '## Workspace (do this first)',
    'Repository: ' + args.repoPath,
    '- cd ' + args.repoPath,
    '- git worktree add ' + worktree + ' -b wave/' + t.id + ' ' + args.base,
    '  (if the worktree and branch already exist from a prior attempt, reuse them as they are)',
    '- git -C ' + worktree + ' merge-base --is-ancestor ' + args.base + ' origin/' + args.defaultBranch,
    '  (must exit 0; if it does not, STOP and report — do not pick another base)',
    'Work and commit ONLY inside ' + worktree + '.',
    '',
    '## Boundaries',
    'You may change only paths matching: ' + yamlInline(t.contract.files_allowed),
    t.contract.files_forbidden.length > 0
      ? 'You must not touch: ' + yamlInline(t.contract.files_forbidden) : null,
    'Do not refactor adjacent code. Do not add unrequested features or files.',
    '',
    '## Dead-end protocol',
    'If data or access is missing, a tool is broken, or the path is impossible —',
    'stop and report what is blocking you. Do not invent values, do not work',
    'around the restriction, do not pick an interpretation on the user\'s behalf.',
    '',
    '## Prohibitions',
    'Do not spawn subagents. No force-push, no reset --hard, no rm outside the',
    'task\'s files. Do not work around a failing check — report it.',
    '',
    '## Definition of done and report format',
    'Your report must contain: the list of changed files; the gist of the',
    'change; the verbatim output of every must_run command, actually executed',
    'in your worktree; an answer to every report_must_answer question.',
    'A claim that a command passed without its pasted output is a contract',
    'violation in its own right.',
    '',
    '## Contract (a supervisor will check every line of this against your branch)',
    renderContract(t.contract),
  ].filter((line) => line !== null).join('\n')
}

function reworkPrompt(t, verdict) {
  return executorPrompt(t) + [
    '',
    '',
    '## Prior attempt was rejected',
    'A supervisor checked your branch against the contract and rejected it.',
    'The verdict, including the supervisor\'s own evidence:',
    '',
    JSON.stringify(verdict, null, 2),
    '',
    'Continue in the SAME worktree and branch (wave/' + t.id + '). Fix the',
    'violations. Do not restart from scratch and do not delete the branch.',
  ].join('\n')
}

function supervisorPrompt(t, report) {
  return args.supervisorPromptText + [
    '',
    '',
    'CONTRACT:',
    renderContract(t.contract),
    '',
    'REPO: ' + args.repoPath,
    'BASE: ' + args.base,
    'BRANCH: wave/' + t.id,
    '',
    'REPORT:',
    String(report),
  ].join('\n')
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    ok: { type: 'boolean' },
    violations: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          rule: { type: 'string' },
          class: { type: 'string' },
          evidence: { type: 'string' },
          quote: { type: 'string' },
          pasteReproduced: { type: 'boolean' },
          satisfiable: { type: 'boolean' },
        },
        required: ['rule', 'class', 'evidence'],
      },
    },
    remarks: { type: 'array', items: { type: 'string' } },
  },
  required: ['ok', 'violations', 'remarks'],
}

// ---------- the ladder ----------

function defaultLadder(model) {
  const i = LADDER_ORDER.indexOf(model)
  return i === -1 ? [] : LADDER_ORDER.slice(i + 1)
}

function sameRuleRepeat(prevVerdict, verdict) {
  if (!prevVerdict) return false
  const prev = prevVerdict.violations ?? []
  return (verdict.violations ?? []).some((v) =>
    prev.some((p) => p.class === v.class && p.rule === v.rule))
}

async function runTask(t) {
  const rungs = [t.executor.model, ...(t.ladder ?? defaultLadder(t.executor.model))]
  const branch = 'wave/' + t.id
  const attempts = []
  const finish = (status) => ({ id: t.id, status, branch, attempts })
  let pasteStrikes = 0
  let verdictCount = 0
  let prevVerdict = null

  // One API death is retried once and recorded; a second is a task error —
  // never a wave error.
  async function call(prompt, opts, rung) {
    let r = await agent(prompt, opts)
    if (r === null) {
      attempts.push({ rung, model: opts.model, effort: opts.effort,
                      kind: 'agent-error', verdict: null, escalation: null })
      r = await agent(prompt, opts)
    }
    return r
  }

  for (let rung = 0; rung < rungs.length; rung++) {
    const model = rungs[rung]
    const effort = rung === 0 ? (t.executor.effort ?? 'medium') : 'high'
    for (let attemptOnRung = 1; attemptOnRung <= MAX_ATTEMPTS_PER_RUNG; attemptOnRung++) {
      if (verdictCount >= MAX_ATTEMPTS_PER_TASK) return finish('failed')
      verdictCount++

      const prompt = prevVerdict ? reworkPrompt(t, prevVerdict) : executorPrompt(t)
      const report = await call(prompt,
        { model, effort, label: 'exec:' + t.id, phase: 'Wave' }, rung)
      if (report === null) return finish('error')

      const verdict = await call(supervisorPrompt(t, report),
        { model: args.supervisor.model, effort: args.supervisor.effort ?? 'high',
          label: 'judge:' + t.id, phase: 'Wave', schema: VERDICT_SCHEMA }, rung)
      if (verdict === null) return finish('error')

      const attempt = { rung, model, effort, kind: 'verdict', verdict, escalation: null }
      attempts.push(attempt)
      const priorVerdict = prevVerdict
      prevVerdict = verdict
      const viols = verdict.violations ?? []

      // Priority order is load-bearing; see the spec.
      if (viols.some((v) => v.satisfiable === false)) return finish('contract-unsatisfiable')
      if (verdict.ok === true) return finish('ok')
      if (viols.some((v) => v.pasteReproduced === false)) pasteStrikes++
      if (pasteStrikes >= 2) { attempt.escalation = 'paste-two-strikes'; break }
      if (attemptOnRung === MAX_ATTEMPTS_PER_RUNG) {
        attempt.escalation = sameRuleRepeat(priorVerdict, verdict)
          ? 'same-rule-repeat' : 'rung-exhausted'
      }
    }
  }
  return finish('failed')
}

phase('Wave')
log('wave: ' + args.tasks.length + ' task(s) from base ' + args.base.slice(0, 7))
const results = await pipeline(args.tasks, (t) => runTask(t))
const tasks = results.map((r, i) => r ??
  { id: args.tasks[i].id, status: 'error', branch: 'wave/' + args.tasks[i].id, attempts: [] })
for (const t of tasks) log('task ' + t.id + ': ' + t.status)
return {
  status: tasks.every((t) => t.status === 'ok') ? 'done' : 'partial',
  errors: [],
  tasks,
}
```

- [ ] **Step 4: Run all scenarios, expect green**

Run: `node tests/lib/wave-runner.test.mjs`
Expected: every S1–S8 case `ok -`, exit 0.

- [ ] **Step 5: Write the shell wrapper with the static boundary checks**

`tests/wave-runner.test.sh`:

```bash
#!/usr/bin/env bash
# Tier 2.5 — does the SHIPPED wave-runner behave as the prose promises? The
# simulator runs the real file with stubbed agents, so every ladder rule is a
# deterministic offline assertion, not a live-model probe. The static checks
# pin the Workflow-boundary rules; each one cost a launch rejection once.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

W=plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs

section "Workflow-boundary rules (violations are launch rejections)"
check "the runner ships"                    "[ -f $W ]"
expect "exactly one export" "1" "$(grep -c '^export ' "$W")"
check "meta is a pure literal"              "! sed -n '/^export const meta/,/^}/p' $W | grep -qE '\\\$\\{|\\\`| \\+ '"
check "no Date or random (breaks resume)"   "! grep -qE 'Date\\.|new Date|Math\\.random' $W"
check "short model names only"              "! grep -q 'claude-' $W"
check "result leaves via top-level return"  "grep -qE '^return ' $W"

section "Ladder semantics, simulated on the shipped file"
if command -v node >/dev/null 2>&1; then
  if out="$(node tests/lib/workflow-sim.test.mjs 2>&1 && node tests/lib/wave-runner.test.mjs 2>&1)"; then
    printf '%s\n' "$out" | sed 's/^/    /'
    pass "all simulator scenarios"
  else
    printf '%s\n' "$out" | sed 's/^/    /'
    fail "simulator scenarios (output above)"
  fi
else
  fail "node is required for this tier and was not found on PATH"
fi

summary
```

Make it executable: `chmod +x tests/wave-runner.test.sh`

- [ ] **Step 6: Wire it into the runner**

In `tests/run.sh`, after the line
`run "contracts — the invariants behaviour depends on"            bash tests/skills-contract.sh`
add:

```bash
run "behaviour — wave-runner reference implementation (simulated)" bash tests/wave-runner.test.sh
```

- [ ] **Step 7: Run the full offline suite**

Run: `./tests/run.sh`
Expected: structure, contracts, wave-runner and hook tiers all green
(`all tiers passed`).

- [ ] **Step 8: Commit**

```bash
git add plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs tests/lib/wave-runner.test.mjs tests/wave-runner.test.sh tests/run.sh
git commit -m "Wave runner: the escalation ladder as tested code, simulated on the shipped file"
```

---

### Task 4: SKILL.md — the default path is invoking, not writing

**Files:**
- Modify: `plugins/orchestration/skills/multi-model/SKILL.md`
- Modify: `plugins/orchestration/.claude-plugin/plugin.json`
- Modify: `tests/skills-contract.sh`

**Interfaces:**
- Consumes: the runner filename `wave-runner.workflow.mjs`, its args contract
  and return statuses from Tasks 2–3.
- Produces: SKILL.md 1.8.0 whose wave-execution guidance names the shipped
  runner; contract checks that pin it.

- [ ] **Step 1: Add the failing contract checks**

In `tests/skills-contract.sh`, in the section
`"multi-model: supervision that cannot be skipped or gamed"`, after the line
`check "supervisor prompt is referenced"        "grep -q 'references/supervisor-prompt.md' $MM"` add:

```bash
check "the wave runner ships as a file" \
  "[ -f plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs ]"
check "SKILL points at the shipped runner"     "grep -q 'wave-runner.workflow.mjs' $MM"
check "default path is invoking, not writing"  "grep -q 'invoke the shipped runner' $MM"
check "the filesystem constraint is named"     "grep -q 'supervisorPromptText' $MM"
check "no ladder row resurrects the forgery class" "! grep -qi 'forged evidence' $MM"
```

- [ ] **Step 2: Run to verify the new checks fail**

Run: `bash tests/skills-contract.sh`
Expected: the first check passes (file exists since Task 2); the other four FAIL.

- [ ] **Step 3: Fix the stale ladder row**

In `SKILL.md`, replace:

```
| 1st violation, no forged evidence | Back to the same executor with the verdict attached |
```

with:

```
| 1st violation | Back to the same executor with the verdict attached |
```

- [ ] **Step 4: Replace the hand-written pipeline example with the runner invocation**

In `SKILL.md`, replace this entire block (paragraph plus fenced example):

````
The ladder lives inside a single `pipeline` stage. Stages run once per item, so
spreading execute / supervise / rework across three stages would re-enter the
pipeline from the top on every rework.

```js
pipeline(tasks, async (_, t) => {
  let model = t.model, attempt = 0, history = []
  while (true) {
    const report  = await agent(taskPrompt(t, history), {model, phase: 'Execute'})
    const verdict = await agent(supervisorPrompt(t, report),
                                {model: supervisorFor(model), phase: 'Supervise',
                                 schema: VERDICT})
    history.push(verdict)
    if (verdict.ok) return {task: t, verdict, model, attempts: attempt + 1}
    const next = nextRung(model, verdict, ++attempt)
    if (next.stop) return {task: t, verdict, history, escalatedToUser: true}
    model = next.model
  }
})
```
````

with:

````
### Running a wave — invoke the shipped runner, do not write one

The ladder above is implemented once, in
`references/wave-runner.workflow.mjs`, and covered by the deterministic
simulator tier in `tests/`. Your job is to assemble its inputs, not to
re-implement its rules — every hand-written wave script is a fresh chance to
get "two strikes escalate" subtly wrong, and the one hand-written run on
record was rejected at launch four times before it worked.

1. Read `references/supervisor-prompt.md`. Workflow scripts cannot read files,
   so its full text travels inside `args.supervisorPromptText`.
2. Invoke the runner (`args` must be a real JSON object — a string is rejected
   by validation, which exists because that bug shipped twice):

```
Workflow({
  scriptPath: "<this skill's base directory>/references/wave-runner.workflow.mjs",
  args: {
    base: "<pushed fork-point sha>",          // see Wave Isolation above
    defaultBranch: "main",
    repoPath: "/abs/path/to/repo",
    supervisorPromptText: "<text of supervisor-prompt.md>",
    supervisor: { model: "opus", effort: "high" },
    tasks: [{
      id: "auth-fix",
      description: "<the substantive ask>",
      context: "<files, lines, conventions>",
      contract: { files_allowed: [...], files_forbidden: [...],
                  must_run: [{ cmd: "...", evidence: "required" }],
                  forbidden_moves: [...], report_must_answer: [...] },
      executor: { model: "sonnet", effort: "medium" },
      ladder: ["opus"]      // rungs AFTER the first; omit for the routing default
    }]
  }
})
```

The runner assembles each executor's six-block prompt from the task object, so
the contract the executor reads and the contract the supervisor enforces are
the same object and cannot diverge. Escalated rungs run at `high` effort.

3. Act on the returned statuses, task by task:
   - `ok` — merge `wave/<id>` per the wave plan.
   - `contract-unsatisfiable` — run the amendment flow below (one amendment
     per task; removing or weakening a check goes to the user as a yes/no),
     then re-invoke with `resumeFromRunId`: the runner is deterministic, so
     every unchanged task replays from cache and only the amended one runs.
   - `failed` / `error` — hand the user the task, every verdict in order, and
     the branch name. Do not quietly retry.

Write a custom wave script only when the runner genuinely cannot express the
wave — and then follow "Delegating the Workflow Script Itself" below, because
every rule listed there was learned from a rejection.
````

- [ ] **Step 5: Reframe the delegation section's opening**

In `SKILL.md`, replace:

```
An executor asked to *write* a workflow script cannot read the `Workflow` tool's
documentation — the tool is not in its prompt and not available to it.
```

with:

```
This applies only to the rare wave the shipped runner cannot express; the
default path is invoking `references/wave-runner.workflow.mjs`, not writing a
script. An executor asked to *write* a workflow script cannot read the
`Workflow` tool's documentation — the tool is not in its prompt and not
available to it.
```

- [ ] **Step 6: Bump both versions to 1.8.0**

In `SKILL.md` frontmatter: `  version: 1.7.1` → `  version: 1.8.0`.
In `plugins/orchestration/.claude-plugin/plugin.json`: `"version": "1.7.1"` →
`"version": "1.8.0"`.

- [ ] **Step 7: Run the offline suite**

Run: `./tests/run.sh`
Expected: all green, including the five new contract checks and the version
agreement in structure.

- [ ] **Step 8: Commit**

```bash
git add plugins/orchestration/skills/multi-model/SKILL.md plugins/orchestration/.claude-plugin/plugin.json tests/skills-contract.sh
git commit -m "Multi-model 1.8.0: the wave is run by the shipped runner, not a hand-written script"
```

---

### Task 5: Live boundary tier + honest documentation

**Files:**
- Create: `tests/eval/wave.sh`
- Create: `tests/eval/wave-insession.md`
- Modify: `tests/README.md`

**Interfaces:**
- Consumes: the runner path and args contract from Tasks 2–3.
- Produces: a `--live` tier that proves Workflow accepts the shipped script,
  or — if the Workflow tool turns out unreachable from headless `claude -p` —
  a documented in-session probe.

- [ ] **Step 1: Write the live tier**

`tests/eval/wave.sh`:

```bash
#!/usr/bin/env bash
# Tier 3 — is the shipped wave-runner ACCEPTED by the real Workflow tool, and
# does one task reach a terminal status on real models? Ladder rules are NOT
# re-proven here: the simulator tier owns them offline. This tier proves only
# the boundary the simulator cannot: the launcher's parser and a real verdict.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh

MODEL="${EVAL_MODEL:-claude-haiku-4-5-20251001}"
RUNNER="$PWD/plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# The runner's isolation instructions verify base against origin/<defaultBranch>,
# so the fixture needs a real remote: a bare repo plus a clone of it.
git init -q --bare "$W/origin.git"
git clone -q "$W/origin.git" "$W/repo" 2>/dev/null
R="$W/repo"
mkdir -p "$R/src" "$R/tests"
printf 'def divide(a, b):\n    return a / b\n' > "$R/src/calc.py"
cat > "$R/tests/test_calc.py" <<'PY'
import unittest

from src.calc import divide


class TestDivide(unittest.TestCase):
    def test_divide(self):
        self.assertEqual(divide(6, 3), 2)

    def test_divide_by_zero_returns_none(self):
        self.assertIsNone(divide(1, 0))
PY
touch "$R/src/__init__.py" "$R/tests/__init__.py"
git -C "$R" add -A
git -C "$R" -c user.email=t@t -c user.name=t commit -q -m base
DEFBRANCH="$(git -C "$R" rev-parse --abbrev-ref HEAD)"
git -C "$R" push -q origin "HEAD:$DEFBRANCH"
BASE="$(git -C "$R" rev-parse HEAD)"

python3 - "$W/args.json" "$BASE" "$DEFBRANCH" "$R" <<'PY'
import json, sys
out, base, branch, repo = sys.argv[1:5]
sup = open('plugins/orchestration/skills/multi-model/references/supervisor-prompt.md').read()
json.dump({
    "base": base, "defaultBranch": branch, "repoPath": repo,
    "supervisorPromptText": sup,
    "supervisor": {"model": "haiku", "effort": "medium"},
    "tasks": [{
        "id": "divide-guard",
        "description": "Make divide() return None when the divisor is zero, so the whole suite passes.",
        "context": "src/calc.py holds divide(); tests/test_calc.py already expects None on zero.",
        "contract": {
            "files_allowed": ["src/**"],
            "files_forbidden": ["tests/**"],
            "must_run": [{"cmd": "python3 -m unittest discover -s tests -t .", "evidence": "required"}],
            "forbidden_moves": ["weakening, deleting or skipping an existing test"],
            "report_must_answer": ["What happens when the divisor is zero?"]
        },
        "executor": {"model": "haiku", "effort": "medium"},
        "ladder": []
    }]
}, open(out, "w"))
PY

section "the real Workflow boundary"
out="$(timeout 900 claude -p "Read the JSON object in $W/args.json. Invoke the Workflow tool with scriptPath \"$RUNNER\" and that object as args — a real JSON object, not a string. When it completes, print the workflow's returned JSON verbatim and nothing else." --permission-mode bypassPermissions --model "$MODEL" </dev/null 2>/dev/null)"

if [ -z "$out" ] || printf '%s' "$out" | grep -qiE 'no such tool|not available|do not have access'; then
  fail "Workflow tool unreachable from headless claude -p" \
       "run the in-session probe instead: tests/eval/wave-insession.md"
else
  contains "the wave returned a status" '"status"'      "$out"
  contains "the task is in the result"  'divide-guard'  "$out"
  case "$out" in
    *'"ok"'* | *'"failed"'* | *'"contract-unsatisfiable"'* | *'"error"'*)
      pass "the task carries a terminal status" ;;
    *)
      fail "the task carries a terminal status" "${out:0:160}" ;;
  esac
fi

summary
```

Make it executable: `chmod +x tests/eval/wave.sh`

- [ ] **Step 2: Probe the headless boundary once**

Run: `bash tests/eval/wave.sh`

Two acceptable outcomes; act on which one happens:
- **Workflow reachable** — assertions run against a real wave; fix anything
  they surface (the executor and supervisor are real Haiku agents; a
  legitimate `failed` status still passes the tier — the tier proves the
  boundary, not model quality).
- **Workflow unreachable headless** — the tier prints the documented FAIL. In
  that case change the unreachable branch from `fail` to a plainly labeled
  skip so `--live` stays usable:

```bash
  pass "SKIPPED: Workflow is session-only — the boundary is proven by the in-session probe (tests/eval/wave-insession.md), not this tier"
```

  and record in `tests/README.md` (Step 4) that the live wave boundary is
  covered only by the in-session probe. Do not silently keep a permanently
  red tier and do not delete it.

- [ ] **Step 3: Write the in-session probe doc**

`tests/eval/wave-insession.md`:

```markdown
# In-session probe of the wave-runner boundary

The simulator tier proves the ladder's semantics offline. What it cannot prove
is the real `Workflow` launcher accepting the script and a real model driving
it. When `tests/eval/wave.sh` cannot reach the Workflow tool from headless
`claude -p`, run this once from an interactive Claude Code session instead.

1. Build the fixture repo and args file: run the fixture block of
   `tests/eval/wave.sh` by hand, or let the session do it (everything up to
   the `section` line).
2. In the session, invoke:

   Workflow({
     scriptPath: "<repo>/plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs",
     args: <the parsed contents of args.json — a real object, not a string>
   })

3. The probe passes when all three hold:
   - the launch is accepted (no rejection about meta, exports, or parsing);
   - the returned JSON has `status` and a `divide-guard` task entry;
   - that entry's `status` is one of `ok | failed | contract-unsatisfiable | error`
     (a real verdict was produced; `invalid-args` or a missing entry is a fail).
4. Record the date and result in this file.

## Probe log

| Date | Result | Notes |
|---|---|---|
```

- [ ] **Step 4: Update tests/README.md**

Two edits.

First, in the "What this suite cannot tell you" list, replace the stale bullet:

```
- **The escalation ladder has never executed.** Every wave task so far passed on
  the first attempt, so rework, the forged-evidence rung-skip and the terminal
  rung are prose that has never run.
```

with:

```
- **The ladder's live coverage is one boundary probe.** Its rules — rework,
  two-strike escalation, the unsatisfiable-contract stop, the absolute cap —
  are asserted by the simulator on the shipped file, which is exactly as
  trustworthy as the simulator's fidelity to the real Workflow runtime. The
  live tier (or the in-session probe, see `tests/eval/wave-insession.md`)
  proves acceptance and one real verdict, nothing more.
```

Second, after the "**behaviour**" tier paragraph, add:

```
**wave-runner (simulated)** — `tests/wave-runner.test.sh` runs the shipped
`wave-runner.workflow.mjs` through an offline simulator
(`tests/lib/workflow-sim.mjs`) with stubbed agents: every escalation-ladder
rule is a deterministic assertion on the real file. Requires `node` on PATH.
The simulator's own fidelity is the tier's trust anchor, so it has a
self-test, and the Workflow-boundary rules (single export, literal meta, no
Date) are pinned by static checks that each cost a launch rejection once.
```

- [ ] **Step 5: Run the full suite both ways**

Run: `./tests/run.sh` — all offline tiers green.
Run: `./tests/run.sh --live` — supervisor, drift and wave tiers behave per
Step 2's outcome.

- [ ] **Step 6: Commit**

```bash
git add tests/eval/wave.sh tests/eval/wave-insession.md tests/README.md
git commit -m "Live boundary tier for the wave runner, honest about what it can and cannot prove"
```

---

## Self-review notes

- Spec coverage: §1 invocation → Task 4; §2 validation → Task 2; §3 prompts and
  §4 ladder and §5 return shape → Task 3; §6 simulator → Tasks 1–3; §7 live
  tier → Task 5; §8 SKILL/contract/version changes → Task 4. The spec's
  per-violation field placement (amended 2026-08-12) is what S-scenarios and
  the schema implement.
- The runner's `attempt.escalation` mutation after `attempts.push(attempt)` is
  intentional: the pushed object and the mutated object are the same reference.
- `t.ladder ?? defaultLadder(...)` deliberately honors an explicit empty
  ladder (`[]` = no escalation), used by the live fixture.
