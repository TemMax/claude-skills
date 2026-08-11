# Supervised waves — catching executors that drift from the plan

Date: 2026-08-11
Skill: `plugins/orchestration/skills/multi-model` (1.5.0 → 1.6.0)

## Problem

`multi-model` decomposes work into waves of executor subagents and reviews their
results afterwards. The review is the orchestrator reading what the executors
say they did. Two documented failure modes make that insufficient:

- Executors fabricate a workaround when the path is blocked instead of reporting
  it — 17.4% of cases for Fable 5 on a neutral prompt, 9.4% for Opus 4.8
  (dossier: Fable pp. 161–163, Opus 4.8 pp. 109–110).
- Orchestrators relay those claims without checking them. Opus 5 is named for
  this by Anthropic's own reviewer (p. 81), and the Opus 4.8 orchestrator
  sessions document "caveat laundering": a subagent could not verify and
  guessed, the orchestrator reported "I verified this myself" having spot-checked
  only ancillary facts (pp. 37–39).

So the current review is a self-report about self-reports. A wave can complete,
report success, and have produced nothing that works.

The property that fixes this is **unskippability, not persuasion**. A check the
executor is asked to perform is a check the executor may decide it already
satisfied. A check that sits in the control flow around the executor is one it
never gets a vote on.

## Goal

Every executor result in a wave passes a supervisor stage that judges it against
a machine-checkable contract, using artifacts the supervisor gathers itself. A
result that violates the contract goes back for rework, then to a stronger model,
then to the user.

## Non-goals

- The orchestrator session's own drift. That needs a plugin hook (see Appendix),
  not a workflow stage. Deliberately deferred.
- Replacing the existing Result Review Checklist. The supervisor gates
  individual tasks; the orchestrator's final review of the whole wave stays.
- Style, taste, or architecture opinions. The supervisor checks contract
  compliance, not quality.
- A separate `multi-model-supervised` skill. Per-model variants were collapsed
  into self-routing skills in `85284fc`; a `-supervised` variant reintroduces
  the same sprawl and forces the user to choose before knowing if they need it.
  Supervision is a mode inside `multi-model`.

## Design

### 1. Task isolation — the precondition for everything else

Today a wave runs its executors against **one shared working tree**: the skill
tells each agent which files its neighbours will change, "so it doesn't treat
that as an anomaly" (`SKILL.md:122–124`). Contract checking cannot work on top of
that. Two things break:

- `files_forbidden` becomes undecidable. The supervisor sees a diff containing
  every task's concurrent edits and cannot tell "task A wandered into a file it
  was forbidden" from "task B legitimately owns that file". That is precisely
  the violation class the contract exists to catch.
- `must_run` becomes non-deterministic. A command re-run by the supervisor
  executes against a tree a neighbour is editing right now, so a failure can be
  charged to an innocent task — and the escalation ladder will then send correct
  work back for rework.

**Therefore, supervised waves run each executor in its own git worktree, and the
executor commits its work to a per-task branch `wave/<task-id>`.** Supervision
reads that branch, never the shared tree.

Verified locally on 2026-08-11: a commit created inside a worktree survives
`git worktree remove` (worktrees share the object database and refs), the branch
stays resolvable from the main repository, `git diff <base>..wave/<task-id>`
contains that task's changes and nothing else, and a second worktree can be
checked out from the branch for independent verification. This relies only on
documented git behaviour — notably **not** on a Workflow worktree surviving
between `pipeline` stages, which is undocumented and must not be assumed.

The wave plan records the base SHA once, before the wave starts. Every diff and
every "was this test weakened" question is answered against that SHA, so no
comparison depends on a moving `HEAD`.

### 2. The task contract

The existing "Task Prompt Template (mandatory blocks)" section gains a
**Contract** block. Prose stays — it carries intent, and a contract-only task
makes the executor optimize for the checks instead of the work.

```yaml
task: http-retry
model: claude-sonnet-5
branch: wave/http-retry
base: 7c05ff5
contract:
  files_allowed:   [src/http/**, tests/http/**]
  files_forbidden: [src/auth/**]          # another task owns these this wave
  must_run:
    - cmd: pytest tests/http -q
      evidence: required
  forbidden_moves:
    - weakening, deleting or skipping an existing test
    - catching an exception to make a check pass
  report_must_answer:
    - Which call sites now retry?
    - What happens after the final failed attempt?
```

`evidence: required` is what replaces trust. A report claiming "tests pass"
without the command's actual output is not weak evidence — it is a contract
violation in its own right.

Every field is decidable from artifacts. Nothing in the contract requires
judging intent, because intent is exactly what a drifting executor will argue
about.

### 3. The supervisor stage

Supervision is a stage in the `Workflow` script, not an instruction to
self-check. The executor cannot skip it because the script decides the control
flow, not the model — and unlike an advisory check, a stage can reject and
re-run.

**What the supervisor may trust: artifacts only.** It receives the contract and
the executor's report, checks out `wave/<task-id>` into its own worktree, and
from there runs `git diff <base>..HEAD` itself, executes each `must_run` command
itself, and greps for `forbidden_moves` itself. The report is a set of claims to
check, never a source of facts.

#### Forged evidence is its own violation class

The executor pastes command output; the supervisor re-runs the same command.
**Those two outputs are compared.** A mismatch is the cheapest and least
deniable proof of fabrication available anywhere in this design, and collecting
both without comparing them would throw it away.

The distinction matters because the two failures deserve different treatment. An
executor whose tests genuinely fail made a mistake — that is what rework is for.
An executor that pasted "11 passed" over a real "2 failed" did something else,
and returning that task to the same model with a polite verdict is the wrong
response. Forged evidence therefore **skips the rework rung and escalates
immediately** (§5).

#### Verdict shape

```json
{"ok": false,
 "violations": [
   {"rule": "must_run:pytest tests/http -q",
    "class": "forged-evidence",
    "evidence": "report pasted '11 passed'; supervisor ran it: 2 failed, 11 passed",
    "quote": "tests/http/test_retry.py::test_backoff FAILED"}],
 "remarks": [
   "src/http/backoff.py:41 duplicates the jitter helper in src/net/retry.py"]}
```

`violations` decide `ok`. `remarks` never do — they carry everything the
supervisor finds doubtful but cannot pin to a contract predicate, and they flow
into the wave report (§6).

`class` is one of `files`, `must_run`, `forbidden-move`, `report`, or
`forged-evidence`.

Every violation carries its own evidence — a path, a line, or command output. A
violation without evidence is dropped. Otherwise the supervisor fabricates as
readily as the executor it is judging, and we have moved the problem rather than
solved it.

#### Flaky commands

A `must_run` failure is retried once before it becomes a violation. If the retry
passes, the task is not blocked and the disagreement is recorded as a remark
naming the command as unstable. Blocking correct work on a flaky test spends the
supervisor's credibility on noise.

### 4. Control flow

`pipeline` stages run once per item, so the ladder lives inside one stage rather
than being spread across three — otherwise a rework would re-enter the pipeline
from the top and the earlier stages would run again for the wrong reason:

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
    const next = nextRung(model, verdict, ++attempt)   // §5
    if (next.stop) return {task: t, verdict, history, escalatedToUser: true}
    model = next.model
  }
})
```

### 5. The escalation ladder

| Situation | Action |
|---|---|
| 1st violation, no forged evidence | Task returns to the same executor with the verdict attached |
| 2nd violation of the same rule | Task goes to a stronger model — repeating a prompt on the model that just failed it reproduces the failure |
| Any `forged-evidence` violation | Skip the rework rung; go straight to a stronger model, and mark the task in the wave report |
| Executor is already the strongest model | There is no higher rung. Retry once at raised effort; if it violates again, stop |
| Stop | Hand the user the task, every verdict in order, and the branch name so nothing is lost |

The "already the strongest" row is not hypothetical: `081382d` made Opus 5 the
default heavy executor, so the top of the ladder is reached on ordinary work.

### 6. Anti-deception rules, each traced to measured behavior

| Rule | Evidence |
|---|---|
| State the prohibitions to the executor loudly and explicitly | Explicit "don't work around — report" lowers fabrication: Fable 17.4% → 9.1%, Opus 4.8 9.4% → 2.8% |
| Do NOT disclose the supervisor's specific checks to the executor | Grader awareness reaches 24–30% and changes behavior at the surface level (Fable pp. 171–181) |
| The supervisor is never the executor's own model | Opus 5's self-preference bias as a judge is unmeasured; Opus 4.8 (pp. 122–124) and Fable 5 (pp. 202–203) have measured zero |
| A claim without command output is a violation | Caveat laundering: "I verified this myself" while spot-checking only ancillary facts (pp. 37–39) |
| The orchestrator attaches verdicts; it never paraphrases executor reports | Opus 5 relays subagent claims unverified (p. 81) |
| Stopping early with open plan items is a violation | Fable stops on spurious token-budget concerns, 2.43M tokens unspent (pp. 170–171) |
| Claims of monitoring or watching get their own check | Dead watchers: recap lines said "monitoring" while nothing polled (pp. 33–35) |

Rules explicit, checks opaque. The two halves come from opposite findings and
must not be collapsed into one policy.

**What "opaque" does and does not mean.** The contract of §2 is handed to the
executor in full — that is the explicit-prohibition half, and withholding it
would raise fabrication rather than lower it. What is never disclosed is the
supervisor's *method*: that a second model re-runs the commands rather than
reading the pasted output, that it compares the two, that it diffs the tests
against the recorded base SHA to catch a weakened assertion, that it greps for
the forbidden moves. An executor told the rules complies with the rules; an
executor told how compliance is measured optimizes for the measurement.

**Choosing the supervisor's model.** Never the executor's own. Prefer a model
with measured zero self-preference as a judge — Opus 4.8 or Fable 5. When the
executor is one of those, supervise with the other. Opus 5 may execute under
supervision but does not supervise, because the property that would justify it
is unmeasured, and an unmeasured property is not a permission.

### 7. The blocking threshold sits above the suspicion threshold

A probe run on 2026-08-11 (see Appendix) had a supervisor block exactly the file
the user had asked for, because its rule was slightly wrong. The model noticed
and said so: "This conflicts with your explicit request."

Therefore: **rework is triggered only by contract violations** — the decidable
predicates of §2. Anything the supervisor merely finds doubtful goes into
`remarks` and reaches the user through the wave report, never through a
rejection. A supervisor that blocks legitimate work is worse than none, because
it also manufactures confidence.

## Cost

Supervision is not cheap and the spec should not pretend otherwise.

- **One supervisor invocation per task attempt** — but that invocation is an
  agent with tools: it checks out a branch, runs a diff, executes the `must_run`
  commands, greps. The probe measured 2 API requests for a *trivial* check with
  no tool use; a real supervisor costs more.
- **The tiers invert.** §6 requires a judge with measured zero self-preference,
  so a Haiku 4.5 task is supervised by Opus 4.8 or Fable 5 — the supervisor is
  the expensive half.
- **Worktree isolation adds setup cost per executor** (~200–500 ms plus disk),
  which is the price of §1 being decidable at all.

**Proportionality rule.** Full agentic supervision is for tasks whose contract
has `must_run` commands or `files_forbidden` entries that matter — migrations,
shared helpers, security-adjacent code. For a small mechanical task, run the
predicate checks (paths touched, commands run, evidence present) as plain script
logic in the workflow and skip the supervisor model entirely. A supervisor that
costs more than the work it guards will be switched off, and then it guards
nothing.

## Changes required

1. `plugins/orchestration/skills/multi-model/SKILL.md`
   - New section "Wave Isolation" (§1): per-task worktree, `wave/<task-id>`
     branch, base SHA recorded in the plan. This supersedes the current
     shared-tree advice at `:122–124`, which must be rewritten rather than left
     to contradict it.
   - "Task Prompt Template (mandatory blocks)": add the Contract block (§2) as a
     mandatory block, with the explicit-prohibition wording from §6.
   - New section "Wave Plan Artifact": the plan file holding per-task prose,
     contract, model, branch and base SHA.
   - New section "Supervised Waves" (§3, §4, §5, §7).
   - New section "Anti-Deception Rules" (§6) with the dossier citations.
   - "Result Review Checklist": state that it now consumes supervisor verdicts
     and remarks, and that paraphrasing an executor report in place of a verdict
     is a failure.
   - "Common Mistakes": rows for supervising with the executor's own model,
     disclosing the checks, accepting a claim with no command output, treating
     forged evidence as an ordinary failure, and blocking on suspicion rather
     than on a contract violation.
   - Frontmatter `version: 1.6.0`. Also fix the stale executor list in the
     description — it still reads "Haiku 4.5, Sonnet 5 and Opus 4.8" although
     `081382d` made Opus 5 the default heavy executor.
2. `plugins/orchestration/.claude-plugin/plugin.json` — `version` 1.5.0 → 1.6.0.
3. `README.md` line 20 — the `multi-model` row gains supervised waves.

Orchestrator profiles (`references/orchestrator-*.md`) are unchanged: the
supervisor stage is model-independent, and the model-specific facts it relies on
already live in `references/model-dossiers.md`.

## Verification owed before this ships

The `critical-review` fix phase taught that a rehearsal with seeded traps finds
what review does not. Two traps are obvious in advance and must be seeded:

- an executor that pastes invented command output into its report — must be
  caught as `forged-evidence`, not as an ordinary test failure;
- an executor that weakens a test instead of fixing the code — must be caught as
  a `forbidden-move` against the recorded base SHA.

A third is worth seeding because §7 exists precisely because of it: a task whose
contract is slightly wrong, to confirm the supervisor records a remark instead of
blocking correct work.

## Appendix — harness capabilities, verified 2026-08-11

Probed with a throwaway plugin loaded via `claude --plugin-dir`, two headless
runs, debug logs captured. Relevant to the deferred orchestrator-drift layer:

- A plugin ships hooks as `hooks/hooks.json`; they load
  (`Read hooks.json for plugin superv-test (enabled=true)`, `Registered 9 hooks
  from 17 plugins`).
- Hook `type: "agent"` works from a plugin, with its own `model` and `timeout`
  (`Processing agent hook`, `[API REQUEST] ... source=hook_agent`).
- The hook input carries `transcript_path` — the full session transcript — plus
  `tool_name`, `tool_input`, `tool_response`, `cwd`, `permission_mode`.
- Its output contract is a verdict, not a suggestion list:
  `{"ok": false, "reason": "..."}`. On `ok:false` the tool result is blocked and
  the reason reaches the main agent, which read it and reported it.
- `agent` and `prompt` hook types are available only on `PreToolUse`,
  `PostToolUse` and `PermissionRequest`. `Stop` and `SubagentStop` take
  `command` hooks only.
- Non-blocking advice is possible through a `command` hook returning
  `hookSpecificOutput.additionalContext`.

This makes the orchestrator-drift layer implementable as a plugin hook whenever
we want it, with no settings.json editing by the user: installing the plugin
turns supervision on, removing it turns supervision off.
