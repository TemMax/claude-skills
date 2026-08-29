status: done
base: 407451bd15a24db2b00db885db70b2b8ac1ae2e4

# Orchestration Hardening — mechanical verification, preflight, discipline

Source: transcript mining of five real ship sessions (wellington, osaka,
vilnius, quito, canberra — 292 subagent transcripts, 68 verdicts) plus the
agentic-graphs article's script-node principle. The measured defects this
plan fixes, in evidence order:

1. **"Work done but never committed" is the #1 rejection** (8+ occurrences
   across three runs) and every detection cost a full Opus verdict → the
   runner gains a mechanical verify stage (A) and the executor prompt gains
   commit discipline (C).
2. **~13% of verdicts were `satisfiable:false`** — contracts broken at BASE
   (fmt drift, nonexistent build target, base didn't compile) → contract
   preflight at the base before wave 1 (B).
3. **Stall watchdogs killed supervision during cold builds** (~4.8h burned,
   then supervision abandoned for a whole session; a separate ~10h dead
   judge stall) and one session re-ran the identical full-monorepo gate 12
   times → deterministic long-command protocol classified by command kind,
   never by predicted duration, plus module-scoped gates (D).
4. **Task breadth, not model choice, decided wave success** (two broad tasks
   failed for 717 and 139 minutes; re-cut into five narrow tasks, each
   passed first-try in 5–95 min) → right-sizing rule in super-plan (E).
5. **A verbally "authorized" contract amendment never reached the rework
   executor** and the regression shipped → amendments exist only via plan
   edit + `resumeFromRunId` (F).
6. **A contract-green ship still needed ~18h of manual QA** for defects
   visible in Figma references the plan never recorded → Acceptance
   References: static pins where greps can pin, an explicit "Not verified —
   manual QA needed" PR section for the rest, optional runtime pass via
   capability probe, never via a private skill name (G).
7. **Three finished tasks once waited ~47 min on a sibling's third
   attempt** — the wave only settles when its slowest task does → per-task
   runner invocations with merge-as-they-land allowed (H).

Wave shape: wave 1 carries all content on five disjoint files/pairs; wave 2
adds the contract-test pins and bumps every version atomically (the
structure tier requires plugin.json and all three SKILL frontmatters to
agree, so version lines cannot ride in wave 1 without breaking isolated
worktrees). Wave-2 greps can only pass after wave-1 content merges.

```json wave-plan
{ "waves": [
  { "wave": 1,
    "supervisor": { "model": "opus", "effort": "high" },
    "tasks": [
      { "id": "runner-verify-stage",
        "branch": "wave/runner-verify-stage",
        "executor": { "model": "sonnet", "effort": "high" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs",
            "tests/lib/wave-runner.test.mjs"
          ],
          "files_forbidden": [
            "plugins/orchestration/skills/multi-model/SKILL.md",
            "plugins/orchestration/skills/multi-model/references/supervisor-prompt.md",
            "tests/lib/workflow-sim.mjs"
          ],
          "must_run": [
            { "cmd": "node tests/lib/wave-runner.test.mjs", "evidence": "required" },
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "weakening, deleting or skipping an existing simulator test's assertion",
            "changing MODELS, EFFORTS, LADDER_ORDER, MAX_ATTEMPTS_PER_RUNG or MAX_ATTEMPTS_PER_TASK",
            "changing existing ladder semantics beyond what the task text specifies",
            "letting a verifier failure produce finish('error') — the stage must fail open"
          ],
          "report_must_answer": [
            "Which existing simulator tests changed, and why is each change forced by the new stage?",
            "Which test proves the verifier fails open on death, and what does it assert?",
            "Do mechanical verdicts ever set pasteStrikes or satisfiable? Cite the code and the test.",
            "Does a repeated mechanical rule reach the model judge? Cite the test."
          ] } },
      { "id": "supervisor-prompt-facts",
        "branch": "wave/supervisor-prompt-facts",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "plugins/orchestration/skills/multi-model/references/supervisor-prompt.md"
          ],
          "files_forbidden": [
            "plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs"
          ],
          "must_run": [
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "removing or rewording any existing section, rule or example in the file",
            "telling the supervisor to skip re-running commands it doubts"
          ],
          "report_must_answer": [
            "Which sections were added and where exactly (before/after which existing heading)?",
            "Was any existing line changed or removed? (must be no — show how you verified)"
          ] } },
      { "id": "mm-skill-hardening",
        "branch": "wave/mm-skill-hardening",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "plugins/orchestration/skills/multi-model/SKILL.md"
          ],
          "files_forbidden": [
            "plugins/orchestration/.claude-plugin/plugin.json"
          ],
          "must_run": [
            { "cmd": "bash tests/skills-contract.sh", "evidence": "required" },
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "removing or rewording any phrase pinned by tests/skills-contract.sh",
            "changing the frontmatter version line",
            "deleting any existing section"
          ],
          "report_must_answer": [
            "Which sections were added or amended, and where exactly?",
            "Does bash tests/skills-contract.sh pass with zero failures? Paste the summary line."
          ] } },
      { "id": "sp-skill-hardening",
        "branch": "wave/sp-skill-hardening",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "plugins/orchestration/skills/super-plan/SKILL.md"
          ],
          "files_forbidden": [
            "plugins/orchestration/skills/super-plan/references/plan-lint.mjs"
          ],
          "must_run": [
            { "cmd": "bash tests/skills-contract.sh", "evidence": "required" },
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "removing or rewording any phrase pinned by tests/skills-contract.sh",
            "changing the frontmatter version line",
            "deleting any existing section"
          ],
          "report_must_answer": [
            "Which sections were added or amended, and where exactly?",
            "Does bash tests/skills-contract.sh pass with zero failures? Paste the summary line."
          ] } },
      { "id": "ship-skill-hardening",
        "branch": "wave/ship-skill-hardening",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "plugins/orchestration/skills/ship/SKILL.md"
          ],
          "files_forbidden": [
            "plugins/orchestration/.claude-plugin/plugin.json"
          ],
          "must_run": [
            { "cmd": "bash tests/skills-contract.sh", "evidence": "required" },
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "removing or rewording any phrase pinned by tests/skills-contract.sh",
            "changing the frontmatter version line",
            "adding a new ship-level gate (the runtime pass must not ask the user mid-flow)"
          ],
          "report_must_answer": [
            "Which steps were amended and which added, and where exactly?",
            "Does the runtime QA pass reference any skill by name? (must be no — quote the capability-probe wording you used)"
          ] } }
    ] },
  { "wave": 2,
    "supervisor": { "model": "opus", "effort": "high" },
    "tasks": [
      { "id": "pins-and-versions",
        "branch": "wave/pins-and-versions",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "tests/skills-contract.sh",
            "plugins/orchestration/.claude-plugin/plugin.json",
            "plugins/orchestration/skills/multi-model/SKILL.md",
            "plugins/orchestration/skills/super-plan/SKILL.md",
            "plugins/orchestration/skills/ship/SKILL.md"
          ],
          "files_forbidden": [
            "tests/structure.sh"
          ],
          "must_run": [
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "deleting or weakening any existing check in tests/skills-contract.sh",
            "touching anything in the three SKILL.md files except the frontmatter version line"
          ],
          "report_must_answer": [
            "How many checks did tests/skills-contract.sh run before and after your change?",
            "Do plugin.json and all three SKILL frontmatters agree on the version? Paste the structure-tier lines proving it."
          ] } }
    ] }
] }
```

## Task runner-verify-stage

Two files change together (the simulator asserts the shipped runner file, so
they cannot be split): `plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs`
and `tests/lib/wave-runner.test.mjs`.

**What the stage is.** Between the executor's report and the model judge,
the runner spawns a cheap fact-collecting verifier agent, then applies the
deterministic part of the contract itself in script logic. A branch with no
commits, a path outside `files_allowed`/inside `files_forbidden`, a red
`must_run`, or missing pasted evidence bounces straight back to the executor
as a rework — no model judge is paid for discovering it. Three load-bearing
properties: **fail-open** (a dead verifier skips the stage; the judge then
runs everything itself, exactly as today), **once per rule** (the same
mechanical rule failing a second time routes to the model judge with the
facts attached — only a judge can decide `satisfiable`), and **facts, not
judgment** (the verifier never decides `ok`, `pasteReproduced` or
`satisfiable`).

### Runner edits (wave-runner.workflow.mjs)

1. After the `MAX_ATTEMPTS_PER_TASK` constant add:

```js
const VERIFIER_DEFAULT = { model: 'sonnet', effort: 'low' }
const VERIFY_MARKER = '# Mechanical verification (facts only)'
```

2. In the validation section, after the `supervisor.effort` check, add
validation for an optional `wave.verifier`:

```js
if (wave.verifier !== undefined) {
  if (!wave.verifier || !MODELS.includes(wave.verifier.model)) {
    errors.push('verifier.model: one of ' + MODELS.join('/'))
  }
  if (wave.verifier && wave.verifier.effort !== undefined && !EFFORTS.includes(wave.verifier.effort)) {
    errors.push('verifier.effort: one of ' + EFFORTS.join('/'))
  }
}
```

and after `if (errors.length > 0) return invalid(errors)`:

```js
const verifier = {
  model: (wave.verifier && wave.verifier.model) || VERIFIER_DEFAULT.model,
  effort: (wave.verifier && wave.verifier.effort) || VERIFIER_DEFAULT.effort,
}
```

3. In the prompt-assembly section add the glob matcher (deliberately tiny:
`**` crosses slashes, `*` and `?` do not; everything else is literal):

```js
function globRe(glob) {
  let re = ''
  for (let i = 0; i < glob.length; i++) {
    const ch = glob[i]
    if (ch === '*') {
      if (glob[i + 1] === '*') { re += '.*'; i++ } else { re += '[^/]*' }
    } else if (ch === '?') { re += '[^/]' }
    else re += ch.replace(/[.+^${}()|[\]\\]/g, '\\$&')
  }
  return new RegExp('^' + re + '$')
}

function pathAllowed(path, allowed, forbidden) {
  if (forbidden.some((g) => globRe(g).test(path))) return false
  return allowed.some((g) => globRe(g).test(path))
}
```

4. Add the verifier prompt and schema:

```js
function verifierPrompt(t, report) {
  const wt = wave.repoPath + '/.worktrees/verify-' + t.id
  return [
    VERIFY_MARKER,
    '',
    'You collect facts about a branch. You decide nothing and judge nothing —',
    'run the commands below exactly and report what happened. Every number and',
    'path you report must come from output you produced yourself.',
    '',
    'Repository: ' + wave.repoPath,
    'BASE: ' + wave.base,
    'BRANCH: wave/' + t.id,
    '',
    'Steps:',
    '1. Record whether the branch tip differs from BASE:',
    '   git -C ' + wave.repoPath + ' rev-parse ' + wave.base + ' wave/' + t.id,
    '2. Record the changed paths, verbatim, one per array entry:',
    '   git -C ' + wave.repoPath + ' diff --name-only ' + wave.base + '..wave/' + t.id,
    '3. If ' + wt + ' already exists, remove it first:',
    '   git -C ' + wave.repoPath + ' worktree remove --force ' + wt,
    '   Then: git -C ' + wave.repoPath + ' worktree add --detach ' + wt + ' wave/' + t.id,
    '   Run the must_run commands below IN ORDER inside that worktree, as one',
    '   pipeline in one workspace. Record each command\'s exit code and output',
    '   (tail is fine for long green output; keep failures verbatim).',
    '   Build-system commands (gradle, cargo, npm, pnpm, yarn, make, mvn and',
    '   the like) must be started in the background with output to a log file',
    '   and polled — never a silent foreground wait.',
    '4. For each must_run command whose evidence is "required", record whether',
    '   the REPORT below contains pasted output for that command.',
    '5. Clean up: git -C ' + wave.repoPath + ' worktree remove --force ' + wt,
    '',
    'must_run:',
    ...t.contract.must_run.map((m) => '- ' + m.cmd + '  (evidence: ' + m.evidence + ')'),
    '',
    'REPORT (the executor\'s report — scan it only for step 4):',
    String(report),
  ].join('\n')
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    branchHasCommits: { type: 'boolean' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    mustRun: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          cmd: { type: 'string' },
          exit: { type: 'integer' },
          output: { type: 'string' },
          pasteFoundInReport: { type: 'boolean' },
        },
        required: ['cmd', 'exit'],
      },
    },
    notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['branchHasCommits', 'filesChanged', 'mustRun'],
}
```

5. Add the deterministic contract check:

```js
// The deterministic half of the contract, applied by the runner itself.
// The verifier supplies facts; nothing here asks a model to judge.
function mechanicalViolations(t, facts) {
  const v = []
  if (facts.branchHasCommits === false) {
    v.push({ rule: 'work must be committed to the branch', class: 'report',
      evidence: 'wave/' + t.id + ' tip equals BASE ' + wave.base.slice(0, 7)
        + ' — the branch carries no commits' })
  }
  const outside = (facts.filesChanged ?? []).filter((p) =>
    !pathAllowed(p, t.contract.files_allowed, t.contract.files_forbidden))
  if (outside.length > 0) {
    v.push({ rule: 'files_allowed: ' + yamlInline(t.contract.files_allowed), class: 'files',
      evidence: 'paths outside the allowed globs: ' + outside.join(', ') })
  }
  for (const m of (facts.mustRun ?? [])) {
    if (m.exit !== 0) {
      v.push({ rule: 'must_run: ' + m.cmd, class: 'must_run',
        evidence: 'exit ' + m.exit + ' when the verifier ran it: '
          + String(m.output ?? '').slice(-2000) })
    }
  }
  for (const m of t.contract.must_run) {
    if (m.evidence !== 'required') continue
    const f = (facts.mustRun ?? []).find((x) => x.cmd === m.cmd)
    if (f && f.pasteFoundInReport === false) {
      v.push({ rule: 'must_run: ' + m.cmd, class: 'report',
        evidence: 'contract says evidence: required and the report pastes no output for this command' })
    }
  }
  return v
}
```

6. Give `supervisorPrompt` an optional third parameter and thread the facts
through:

```js
function supervisorPrompt(t, report, facts) {
  return wave.supervisorPromptText + [
    '',
    '',
    'CONTRACT:',
    renderContract(t.contract),
    '',
    'REPO: ' + wave.repoPath,
    'BASE: ' + wave.base,
    'BRANCH: wave/' + t.id,
    facts ? '' : null,
    facts ? 'VERIFIER FACTS (a separate fact-collecting agent ran the commands itself;'
      + ' you may rely on its exit codes and outputs, and re-run anything you doubt):' : null,
    facts ? JSON.stringify(facts, null, 2) : null,
    '',
    'REPORT:',
    String(report),
  ].filter((line) => line !== null).join('\n')
}
```

7. In `runTask`, add per-task state next to `pasteStrikes`:

```js
  const mechSeen = new Set()
```

and replace the block between "report received" and the `attempt` record
with (the surrounding loop, `call()`, and everything after the `attempt`
record stay exactly as they are):

```js
      // Mechanical verify: cheap facts before an expensive judge. Fail-open —
      // a dead verifier skips the stage and the judge runs everything itself;
      // this stage can only save a judge call, never remove supervision.
      log(t.id + ': report received — verifying (' + verifier.model + ')')
      const facts = await call(verifierPrompt(t, report),
        { model: verifier.model, effort: verifier.effort,
          label: 'verify:' + t.id, phase: 'Wave', schema: VERIFY_SCHEMA }, rung)

      let verdict = null
      let kind = 'verdict'
      if (facts !== null) {
        const mech = mechanicalViolations(t, facts)
        const freshRules = mech.filter((v) => !mechSeen.has(v.class + '|' + v.rule))
        if (mech.length > 0 && freshRules.length > 0) {
          // Once per rule: a repeat of every rule in this set goes to the
          // judge instead — only a judge can decide satisfiable.
          mech.forEach((v) => mechSeen.add(v.class + '|' + v.rule))
          verdict = { ok: false, violations: mech,
            remarks: ['mechanical verification — no model judged this attempt'] }
          kind = 'mechanical'
          log(t.id + ': mechanical reject [' + mech.map((v) => v.class).join(', ')
            + '] — rework without a judge')
        }
      }
      if (verdict === null) {
        log(t.id + ': judging (' + wave.supervisor.model + ')')
        verdict = await call(supervisorPrompt(t, report, facts),
          { model: wave.supervisor.model, effort: wave.supervisor.effort ?? 'high',
            label: 'judge:' + t.id, phase: 'Wave', schema: VERDICT_SCHEMA }, rung)
        if (verdict === null) return finish('error')
      }

      const attempt = { rung, model, effort, kind, verdict, escalation: null }
```

Note the existing line `log(t.id + ': report received — judging (' + ... )`
is replaced by the two logs above. Everything from `attempts.push(attempt)`
downward is untouched — mechanical verdicts flow through the same
`satisfiable`/`ok`/`pasteStrikes`/escalation logic, and since a mechanical
verdict never carries `satisfiable` or `pasteReproduced`, it can neither
stop the wave as unsatisfiable nor count a paste strike.

8. In `executorPrompt`, amend two blocks. In the Workspace block, after the
`merge-base --is-ancestor` lines, add:

```js
    'Build-system commands (gradle, cargo, npm, pnpm, yarn, make, mvn and the',
    'like) — start them in the background with output to a log file and poll',
    'the log; a silent foreground wait looks like a stall and gets killed.',
```

In the Definition-of-done block, after the `report_must_answer` sentence and
before the "A claim that a command passed" sentence, add:

```js
    'Commit every change to your branch before reporting. Your report must',
    'also paste, run in your worktree: git log --oneline ' + wave.base + '..HEAD',
    '(must be non-empty) and git status --porcelain (must be empty) —',
    'uncommitted work does not exist for the wave.',
```

### Test edits (tests/lib/wave-runner.test.mjs)

1. Teach the stub the third role. Replace the `stub` function with:

```js
const FACTS_GREEN = () => ({ branchHasCommits: true, filesChanged: ['src/x.js'],
  mustRun: [{ cmd: 'true', exit: 0, output: '(exit 0)', pasteFoundInReport: true }], notes: [] })

// verdictsById: taskId -> queue of verdicts, consumed one per supervisor call.
// factsById: taskId -> queue of verifier facts (default: green facts forever).
// execNulls / supNulls / verifyNulls: taskId -> leading null (dead-agent) counts.
function stub(verdictsById, { execNulls = {}, supNulls = {}, verifyNulls = {}, factsById = {} } = {}) {
  const q = Object.fromEntries(Object.entries(verdictsById).map(([k, v]) => [k, [...v]]))
  const fq = Object.fromEntries(Object.entries(factsById).map(([k, v]) => [k, [...v]]))
  const nulls = { ...execNulls }
  const supDead = { ...supNulls }
  const verDead = { ...verifyNulls }
  return (prompt, opts = {}) => {
    const id = (prompt.match(/wave\/([a-z0-9-]+)/) ?? [])[1]
    if ((opts.label ?? '').startsWith('verify:')) {
      if ((verDead[id] ?? 0) > 0) { verDead[id]--; return null }
      if (fq[id] && fq[id].length > 0) return fq[id].shift()
      return FACTS_GREEN()
    }
    if (prompt.startsWith(SUP)) {
      if ((supDead[id] ?? 0) > 0) { supDead[id]--; return null }
      if (!q[id] || q[id].length === 0) throw new Error('verdict queue exhausted for ' + id)
      return q[id].shift()
    }
    if ((nulls[id] ?? 0) > 0) { nulls[id]--; return null }
    return 'report for ' + id + '\n$ true\n(exit 0)'
  }
}
```

2. Update the helpers so verifier calls are counted separately (the verifier
prompt contains `wave/<id>`, so the old `execCalls` filter would miscount):

```js
const execCalls = (calls, id) =>
  calls.filter((c) => (c.opts.label ?? '').startsWith('exec:') && c.prompt.includes('wave/' + id))
const supCalls = (calls, id) =>
  calls.filter((c) => (c.opts.label ?? '').startsWith('judge:') && c.prompt.includes('wave/' + id))
const verifyCalls = (calls, id) =>
  calls.filter((c) => (c.opts.label ?? '').startsWith('verify:') && c.prompt.includes('wave/' + id))
```

(The runner already labels executor calls `exec:<id>` and judge calls
`judge:<id>`; if the SUP-prefix discriminator in the stub is kept for
verdict-queue routing that is fine — only the counting helpers switch to
labels.)

3. Existing tests: semantics are unchanged; only S1 gains one assertion:

```js
  assert.equal(verifyCalls(calls, 't-one').length, 1)
```

All other existing assertions must keep passing verbatim (S2–S8d). The
stub's default green facts make the mechanical stage pass-through for them.

4. New tests, appended before the runner loop at the bottom:

```js
// ---------- V1–V6: the mechanical verify stage ----------

test('V1 verify runs after the executor and before the judge', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  const labels = calls.map((c) => (c.opts.label ?? '').split(':')[0])
  assert.deepEqual(labels, ['exec', 'verify', 'judge'])
})

test('V2 no commits on the branch → mechanical bounce, judge not called', async () => {
  const noCommits = { ...FACTS_GREEN(), branchHasCommits: false }
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }, { factsById: { 't-one': [noCommits, FACTS_GREEN()] } }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.equal(supCalls(calls, 't-one').length, 1)
  assert.equal(execCalls(calls, 't-one').length, 2)
  assert.equal(result.tasks[0].attempts[0].kind, 'mechanical')
  assert.match(execCalls(calls, 't-one')[1].prompt, /Prior attempt was rejected/)
  assert.match(execCalls(calls, 't-one')[1].prompt, /carries no commits/)
})

test('V2b a path outside the globs → mechanical files violation', async () => {
  const outside = { ...FACTS_GREEN(), filesChanged: ['docs/readme.md'] }
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }, { factsById: { 't-one': [outside, FACTS_GREEN()] } }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  const mech = result.tasks[0].attempts[0]
  assert.equal(mech.kind, 'mechanical')
  assert.equal(mech.verdict.violations[0].class, 'files')
  assert.equal(supCalls(calls, 't-one').length, 1)
})

test('V3 the same mechanical rule twice → the second goes to the judge', async () => {
  const noCommits = () => ({ ...FACTS_GREEN(), branchHasCommits: false })
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] },
      { factsById: { 't-one': [noCommits(), noCommits()] } }),
  })
  // attempt 1: mechanical bounce; attempt 2: same rule again → judge decides,
  // and the judge's ok:true closes the task.
  assert.equal(result.tasks[0].status, 'ok')
  assert.equal(supCalls(calls, 't-one').length, 1)
  assert.match(supCalls(calls, 't-one')[0].prompt, /VERIFIER FACTS/)
})

test('V4 verifier dead twice → fail-open: judge runs, task passes', async () => {
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }, { verifyNulls: { 't-one': 2 } }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  assert.equal(supCalls(calls, 't-one').length, 1)
  assert.equal(verifyCalls(calls, 't-one').length, 2)
  assert.ok(!supCalls(calls, 't-one')[0].prompt.includes('VERIFIER FACTS'))
})

test('V5 red must_run in facts → mechanical must_run bounce with the output', async () => {
  const red = { ...FACTS_GREEN(), mustRun: [{ cmd: 'true', exit: 1, output: 'boom', pasteFoundInReport: true }] }
  const { result, calls } = await runWorkflow(SCRIPT, {
    args: waveArgs(),
    agentStub: stub({ 't-one': [V.ok()] }, { factsById: { 't-one': [red, FACTS_GREEN()] } }),
  })
  assert.equal(result.tasks[0].status, 'ok')
  const mech = result.tasks[0].attempts[0]
  assert.equal(mech.verdict.violations[0].class, 'must_run')
  assert.match(mech.verdict.violations[0].evidence, /boom/)
})

test('V6 mechanical verdicts never count paste strikes or stop as unsatisfiable', async () => {
  // Two different mechanical rules on consecutive attempts, then a judge pass:
  // if mechanical verdicts fed pasteStrikes or satisfiable, this would
  // escalate or stop instead of finishing ok on rung 0's judge call.
  const noCommits = { ...FACTS_GREEN(), branchHasCommits: false }
  const outside = { ...FACTS_GREEN(), filesChanged: ['docs/readme.md'] }
  const { result } = await runWorkflow(SCRIPT, {
    args: waveArgs({ tasks: [task({ ladder: [] })] }),
    agentStub: stub({ 't-one': [] , }, { factsById: { 't-one': [noCommits, outside] } }),
  })
  // rung 0 has 2 attempts, both consumed by mechanical bounces → failed,
  // with zero supervisor calls and no contract-unsatisfiable status.
  assert.equal(result.tasks[0].status, 'failed')
  assert.ok(result.tasks[0].attempts.every((a) => a.kind !== 'verdict'))
})
```

(If any of these interact with the attempt-cap accounting differently than
described, fix the TEST expectations to match the specified runner
semantics above — the runner semantics in this task text are the contract;
the tests document them.)

## Task supervisor-prompt-facts

File: `plugins/orchestration/skills/multi-model/references/supervisor-prompt.md`.
Purely additive — no existing line changes.

1. In the `## What you are given` list, append one item after the REPORT
line:

```markdown
- VERIFIER FACTS (optional) — structured output of a separate
  fact-collecting agent that already checked out the branch and ran the
  `must_run` pipeline itself: exit codes, captured outputs, the changed
  paths, and evidence-presence flags. Absent when the verifier died — the
  stage fails open onto you.
```

2. After the `## What to do` section, insert a new section:

```markdown
## When VERIFIER FACTS are attached

You may rely on the verifier's exit codes and captured outputs as your own
re-run for the `must_run` step — it is a different agent from the executor,
and its facts come from executing the commands, not from reading the
report. Re-run anything you doubt; doubt is always free to act on. Spend
your effort on what no script can decide: reading every hunk of the diff,
the `forbidden_moves`, whether each `report_must_answer` answer survives
your diff, and comparing the report's pasted output against the verifier's
captured output for `pasteReproduced`. When no facts are attached, run
everything yourself exactly as this prompt directs.
```

3. Before the `## If you cannot evaluate what you were asked to evaluate`
section, insert:

```markdown
## Long commands

Classify by kind, never by predicted duration — duration predictions are
unreliable and the rule does not need them. A build-system invocation
(gradle, cargo, npm, pnpm, yarn, mvn, make and the like) is started in the
background with output redirected to a log file and polled periodically;
everything else runs in the foreground. A silent foreground wait on a cold
build looks like a stall from the outside and gets the session killed —
measured at hours of lost supervision in real waves.
```

## Task mm-skill-hardening

File: `plugins/orchestration/skills/multi-model/SKILL.md`. Additive edits
plus two precisely-scoped amendments. Every phrase currently pinned by
`tests/skills-contract.sh` must survive verbatim — run it after editing.

1. In `## Supervised Waves`, immediately after the paragraph ending
"…with the contract, the report, the base SHA and the branch.", insert:

```markdown
### Mechanical verification before the judge

The shipped runner inserts a fact-collecting stage between the executor and
the judge. A cheap verifier agent (default `sonnet`/`low`, overridable via
`args.verifier`) checks out the branch and records facts: does the branch
carry commits at all, which paths changed, what each `must_run` command
returns when actually run, and whether the report pastes output where the
contract says `evidence: required`. The runner — not a model — then applies
the deterministic half of the contract: a branch with no commits, a path
outside `files_allowed`, a red `must_run`, or missing pasted evidence
bounces straight back to the executor as a rework, and no judge is paid for
discovering it. Transcript mining across five real sessions found "work
done but never committed" to be the single most common rejection (8+
occurrences), each costing a full Opus verdict to detect.

Three properties are load-bearing:

- **Fail-open.** A dead verifier skips the stage; the model judge then runs
  the full pipeline itself, exactly as before. Mechanical verification can
  only save a judge call, never remove supervision.
- **Once per rule.** The same mechanical rule failing twice routes to the
  model judge with the facts attached — only a judge can decide
  `satisfiable`, and a repeat is where that question arises.
- **Facts, not judgment.** The verifier never decides `ok`,
  `pasteReproduced` or `satisfiable`; those stay with the judge, which
  receives the verifier's facts and may rely on its exit codes and outputs
  while re-running anything it doubts.

**Long commands, everywhere in the wave, are classified by kind — never by
predicted duration.** Build-system invocations (gradle, cargo, npm, pnpm,
yarn, make, mvn and the like) start in the background with output to a log
file and are polled; everything else runs in the foreground. A silent
foreground wait on a cold build looks like a stall and gets the agent
killed — one real session lost ~4.8 hours of supervision to exactly this,
then abandoned supervision entirely.
```

2. In `### Running a wave — invoke the shipped runner, do not write one`,
insert a new step before the current step 1 (renumber the existing steps
1→2, 2→3, 3→4):

```markdown
1. **Preflight the contracts at the base.** Before the first wave forks, run
   each distinct `must_run` command once against the recorded base — route
   it to a cheap agent per the Research Routing table, or run it yourself.
   Compare against the plan's recorded expectation for each command: green
   at base, or expected-red (the task itself creates what the command
   checks). An unexpected red is a contract defect to fix now, before any
   executor is spawned — transcript mining found ~13% of all supervisor
   verdicts were `satisfiable:false`, every one tracing to a contract
   already broken at base (fmt drift at BASE, a command targeting a
   nonexistent build target), each costing an executor attempt plus an
   Opus verdict. The same run warms the build caches every worktree in the
   wave will fork from cold.
```

3. In the same section's numbered launch instructions, extend the example
`Workflow({...})` args with one optional line after the `supervisor` line:

```
    verifier: { model: "sonnet", effort: "low" },   // optional; this is the default
```

4. In the step that says act on returned statuses, append one sentence to
the paragraph (after "Do not quietly retry."):

```markdown
   A wave may also be launched as parallel single-task runner invocations —
   same-wave tasks are file-disjoint by construction, so each `ok` branch
   can merge as its result lands instead of waiting for the wave's slowest
   task (measured: three finished tasks once waited ~47 minutes on a
   sibling's third attempt). The wave's full suite still runs once, after
   all of the wave's invocations settle, before the push.
```

5. In `## Task Prompt Template (mandatory blocks)`, block 5, replace the
line "**Definition of done and response format:** list of changed files,
the gist of the changes, output of actually executed tests/linter." with:

```markdown
5. **Definition of done and response format:** list of changed files, the
   gist of the changes, output of actually executed tests/linter, plus the
   committed-work proof: `git log --oneline <base>..HEAD` (non-empty) and
   `git status --porcelain` (empty), both pasted — uncommitted work does
   not exist for the wave, and "done but never committed" is the most
   common rejection on record.
```

6. In `### When the contract is what is broken`, after the paragraph ending
"…Asking someone to hand-edit a config is how a safeguard ends up switched
off.", insert:

```markdown
**An amendment exists only when the plan file is edited and the runner is
re-invoked with `resumeFromRunId` carrying the amended task.** A mid-wave
"I authorize X" in conversation reaches nobody: the runner rebuilds every
rework prompt from the task object it was given, so an amendment that never
re-enters the runner never reaches an executor. Measured 2026-08: a
verbally pre-authorized dependency never propagated; the rework executor
fell back to a worse design, which passed supervision and shipped, and the
regression was fixed by a later wave at full price.
```

7. In `### Cost, and when to skip the model`, append one sentence to the
final paragraph:

```markdown
The shipped runner now performs the predicate half mechanically before
every judge call (see Mechanical verification above); what remains yours is
scoping each contract's gates to its files and choosing the judge's effort.
```

8. Add two rows to `## Common Mistakes`:

```markdown
| Amending a contract in conversation only | The rework prompt is rebuilt from the old task object; the amendment reaches nobody | Edit the plan, re-invoke with `resumeFromRunId` |
| A full-repo gate in a per-task contract | Wall-clock multiplied by the task count; stall watchdogs kill the wait | Scope `must_run` to the task's module; the full gate runs once per wave at merge |
```

## Task sp-skill-hardening

File: `plugins/orchestration/skills/super-plan/SKILL.md`. Additive edits;
every pinned phrase survives.

1. In `## Process` step 4 (**Tasks.**), append to the step's text:

```markdown
   **Right-size every task.** The measured lever for wave success is task
   breadth, not model choice: two broad tasks failed for 717 and 139
   minutes respectively and shipped only after being re-cut into five
   narrow tasks that each passed first-try in 5–95 minutes. Split signals —
   any one is enough: `files_allowed` spans more than one module or
   subsystem; the description carries more than ~3 distinct deliverables;
   the prose needs "and then" chains to say what done means. Prefer more,
   narrower tasks: one deliverable one executor can finish and one judge
   can check in a single session.

   **Scope each contract's gates to its files.** Derive `must_run` from
   `files_allowed`: a task confined to one module carries that module's
   check command, never the full-repo gate — the full gate runs once per
   wave at merge. Full-repo commands in per-task contracts multiply
   wall-clock by the task count for no added safety (measured: one session
   re-ran the identical full-monorepo gate 12 times).

   **Record the expected base status of every `must_run`.** For each
   command, state in the task prose whether it is green at base or
   expected-red because the task itself creates what it checks. Execution
   preflights every command at the base and compares against this
   expectation; a mismatch is a contract defect caught before any executor
   is spawned.
```

2. After the `## Plan Format` section, insert a new section:

```markdown
## Acceptance References

When the request carries product or visual references — Figma links,
screenshots, mockups, behavioral specs — the plan records them in a
dedicated `## Acceptance References` section: one entry per reference, its
source, and the concrete facts that must match (sizes, colors, copy, flow
order). Then convert everything statically checkable into contract pins: a
hex token, a dimension constant or a string of copy becomes a `must_run`
grep in the owning task's contract. What cannot be pinned statically —
animation feel, layout at runtime, end-to-end flow behavior — stays listed:
execution and review carry the unverified remainder into the PR body as an
explicit manual-QA list rather than letting it vanish. Measured cost of
skipping this: one contract-green feature needed ~18 hours of
after-the-fact manual QA for defects (wrong gradients, duplicated toolbars,
misplaced flows) that were all visible in references the plan never
recorded. No references given → no section: there is nothing to check
against.
```

3. Add three rows to `## Common Mistakes`:

```markdown
| A task spanning several modules | Hours-long attempts, repeated rejects | Split by deliverable; narrow `files_allowed` |
| A full-repo gate in a per-task contract | Wall-clock multiplied by the task count | Scope `must_run` to the task's module |
| Visual references left out of the plan | Fidelity defects surface as post-ship manual QA | Record Acceptance References; pin what greps can pin |
```

## Task ship-skill-hardening

File: `plugins/orchestration/skills/ship/SKILL.md`. Amendments to Stages 2
and 3; every pinned phrase survives; no new ship-level gate is added.

1. In `## Stage 2 — Execute`, replace steps 2 and 3 with:

```markdown
2. Run multi-model's contract preflight at the pushed tip before the first
   wave: each distinct `must_run` once, compared against the plan's
   recorded base expectations. A mismatch is fixed in the plan before any
   executor is spawned; the same run warms the build caches the wave's
   worktrees fork from cold.
3. Invoke **multi-model** to run the plan: one runner invocation per wave —
   or parallel single-task invocations for a wave that would otherwise wait
   on a long pole, merging each `ok` branch as it lands. Either way,
   `defaultBranch` = the feature branch, `base` = the branch's pushed tip,
   copied verbatim from `git rev-parse` output — a hand-typed sha has
   already burned one wave in this repository's history.
4. After each wave: merge every `ok` task branch into the feature branch
   (with single-task invocations, merge as they land), run the repository's
   offline test suite once when all of the wave's invocations have settled,
   push. The next wave's base is the new pushed tip.
```

and renumber the current steps 4 and 5 to 5 and 6.

2. In `## Stage 3 — Review`, amend step 2's PR-body sentence to:

```markdown
2. Open the PR. The body carries: what shipped, how it was built (waves,
   verdicts, reworks — the judges' catches included), what was tested, the
   honest limits — and, when the plan carries Acceptance References that no
   contract or runtime check verified, an explicit **"Not verified — manual
   QA needed"** section listing each one. An unverified reference that
   vanishes from the PR resurfaces as a production defect found by hand.
```

3. In the same stage, insert a new step after step 2 (renumbering the
rest):

```markdown
3. If the plan carries Acceptance References and this session has a tool or
   skill whose **described capability** is running the product and
   observing it — launching the app, driving its UI, capturing screenshots —
   run one runtime verification pass over those references before invoking
   the review, and route its findings like any review findings. Match by
   described capability, never by a hard-coded skill name: ship must work
   in sessions that have no such skill, where this step silently reduces to
   the "Not verified" section above. This step adds no gate and no new
   machinery — a missing or failing capability is not a ship failure.
```

4. Add one row to the `## Failure map` table:

```markdown
| The runtime QA capability is missing or fails mid-pass | Not a ship failure: the affected references go to the PR's "Not verified — manual QA needed" section |
```

5. Add one row to `## Common Mistakes`:

```markdown
| Dropping unverified Acceptance References from the PR body | They resurface as production defects found by hand | The "Not verified" section is mandatory whenever references exist |
```

## Task pins-and-versions

Wave 2 — runs only after wave 1 has merged (its greps target wave-1
content). Files: `tests/skills-contract.sh`, plus the version line in
`plugins/orchestration/.claude-plugin/plugin.json` and in the frontmatter of
the three SKILL files (nothing else in those files).

1. In `tests/skills-contract.sh`, after the section
"multi-model: research fan-out is routed, never inherited", insert:

```bash
WR=plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs
SUPP=plugins/orchestration/skills/multi-model/references/supervisor-prompt.md

section "multi-model: mechanical verification pays no judge for script-decidable facts"
check "the runner has a verify stage"           "grep -q 'Mechanical verification' \$WR"
check "the verifier stage fails open"           "grep -q 'Fail-open' \$WR"
check "mechanical repeat goes to the judge"     "grep -q 'Once per rule' \$WR"
check "commit discipline is in the executor prompt" "grep -q 'git log --oneline' \$WR"
check "long commands classified by kind in the runner" "grep -q 'started in the background' \$WR"
check "the supervisor may lean on verifier facts" "grep -q 'VERIFIER FACTS' \$SUPP"
check "the supervisor backgrounds long commands"  "grep -q 'never by predicted duration' \$SUPP"
check "the skill documents the verify stage"    "grep -q 'Mechanical verification before the judge' \$MM"
check "contracts are preflighted at the base"   "grep -q 'Preflight the contracts at the base' \$MM"
check "amendments propagate only mechanically"  "grep -q 'An amendment exists only when the plan file is edited' \$MM"
check "single-task invocations are allowed"     "grep -q 'parallel single-task runner invocations' \$MM"

section "super-plan and ship: sizing, scoped gates, acceptance references"
check "task right-sizing is a rule"             "grep -q 'Right-size every task' \$SP"
check "gates are scoped to the task's files"    "grep -q 'gates to its files' \$SP"
check "base expectations are recorded"          "grep -q 'expected base status' \$SP"
check "acceptance references exist"             "grep -q 'Acceptance References' \$SP"
check "ship preflights before the first wave"   "grep -q 'contract preflight at the pushed tip' \$SH"
check "unverified references reach the PR body" "grep -q 'Not verified — manual QA needed' \$SH"
check "the runtime pass probes capability, not names" "grep -q 'described capability' \$SH"
```

Note: `$SH` is currently defined *after* the research-routing section — move
the `SH=` assignment up next to `CR=`/`MM=`/`SP=` so the new section can use
it, changing nothing else about it.

2. Version bump 2.3.0 → 2.4.0 in exactly four places:
`plugins/orchestration/.claude-plugin/plugin.json` (`"version": "2.4.0"`)
and the `version:` frontmatter line of
`plugins/orchestration/skills/multi-model/SKILL.md`,
`plugins/orchestration/skills/super-plan/SKILL.md`,
`plugins/orchestration/skills/ship/SKILL.md`.

3. `bash tests/run.sh` must pass in full; the report answers how many
checks the contract tier ran before and after.
