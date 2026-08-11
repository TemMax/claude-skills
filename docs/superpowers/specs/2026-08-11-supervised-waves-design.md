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

The reference implementation for this feature is Kent (`respawn-llc/kent`), whose
supervisor is a harness interceptor: the runtime issues a separate model request
after every assistant turn or file edit and injects the result back as a
`developer` message. The executor cannot skip it. That unskippability — not the
prompt — is what makes it work.

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

### 1. The task contract

The existing "Task Prompt Template (mandatory blocks)" section gains a
**Contract** block. Prose stays — it carries intent, and a contract-only task
makes the executor optimize for the checks instead of the work.

```yaml
task: http-retry
model: claude-sonnet-5
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
violation in its own right, and the supervisor records it as one.

Every field is decidable from artifacts. Nothing in the contract requires
judging intent, because intent is exactly what a drifting executor will argue
about.

### 2. The wave plan as an artifact

Before launching a wave, the orchestrator writes the plan to a file: one entry
per task, each carrying the prose and the contract above, plus the assigned
model.

Without this file the word "deviation" has no referent — there is nothing to
deviate from. This is the same lesson the `critical-review` finding ledger
taught: the thing the later stage compares against must survive as a file, not
as something the orchestrator remembers.

### 3. The supervisor stage

Supervision is a stage in the `Workflow` script, not an instruction to
self-check:

```js
pipeline(tasks,
  t => agent(taskPrompt(t), {model: t.model, phase: 'Execute'}),
  (report, t) => agent(supervisorPrompt(t, report),
                       {model: supervisorFor(t.model), phase: 'Supervise',
                        schema: VERDICT}),
  (verdict, t, i) => verdict.ok ? verdict : remediate(t, verdict, i)
)
```

The executor cannot skip it because the script decides the control flow, not the
model. This is strictly stronger than Kent, whose supervisor can only suggest: a
stage can reject and re-run.

**What the supervisor may trust: artifacts only.** It receives the contract, the
executor's report, and the working tree. It runs `git diff` itself, executes each
`must_run` command itself, and greps for `forbidden_moves` itself. The report is
a set of claims to check, never a source of facts.

Verdict shape:

```json
{"ok": false,
 "violations": [
   {"rule": "must_run:pytest tests/http -q",
    "evidence": "supervisor ran it: 2 failed, 11 passed",
    "quote": "tests/http/test_retry.py::test_backoff FAILED"}]}
```

Every violation carries its own evidence — a path, a line, or command output. A
violation without evidence is dropped. Otherwise the supervisor fabricates as
readily as the executor it is judging, and we have moved the problem rather than
solved it.

### 4. The escalation ladder

| Attempt | Action |
|---|---|
| 1st violation | Task returns to the same executor with the verdict attached |
| 2nd violation, same rule | Task goes to a stronger model — repeating a prompt on the model that just failed it reproduces the failure |
| 3rd | Stop and hand the user all three verdicts |

### 5. Anti-deception rules, each traced to measured behavior

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

**What "opaque" does and does not mean.** The contract of §1 is handed to the
executor in full — that is the explicit-prohibition half, and withholding it
would raise fabrication rather than lower it. What is never disclosed is the
supervisor's *method*: that a second model re-runs the commands rather than
reading the pasted output, that it diffs the tests against `HEAD` to catch a
weakened assertion, that it greps for the forbidden moves. An executor told the
rules complies with the rules; an executor told how compliance is measured
optimizes for the measurement.

**Choosing the supervisor's model.** Never the executor's own. Prefer a model
with measured zero self-preference as a judge — Opus 4.8 or Fable 5. When the
executor is one of those, supervise with the other. Opus 5 may execute under
supervision but does not supervise, because the property that would justify it
is unmeasured, and an unmeasured property is not a permission.

### 6. The blocking threshold sits above the suspicion threshold

A probe run on 2026-08-11 (see Appendix) had a supervisor block exactly the file
the user had asked for, because its rule was slightly wrong. The model noticed
and said so: "This conflicts with your explicit request."

Therefore: **rework is triggered only by contract violations** — the decidable
predicates in §1. Anything else the supervisor finds doubtful goes into the wave
report as a remark, never as a rejection. A supervisor that blocks legitimate
work is worse than none, because it also manufactures confidence.

## Cost

One supervisor call per task, not per edit. Measured on the probe: an
agent-type check cost 2 API requests and 3.4s on the pass path, 5.9s on the fail
path. In a wave of N tasks that is N supervisor calls plus one per rework.

Kent's `frequency = "edits"` default would multiply this by the number of edits
per executor and is deliberately not copied.

## Changes required

1. `plugins/orchestration/skills/multi-model/SKILL.md`
   - "Task Prompt Template (mandatory blocks)": add the Contract block (§1) as a
     mandatory block, with the explicit-prohibition wording from §5.
   - New section "Wave Plan Artifact" (§2), placed before the task template.
   - New section "Supervised Waves" (§3, §4, §6) after "Task Prompt Template".
   - New section "Anti-Deception Rules" (§5) with the dossier citations.
   - "Result Review Checklist": state that it now consumes supervisor verdicts
     and that paraphrasing an executor report in place of a verdict is a failure.
   - "Common Mistakes": rows for supervising with the executor's own model,
     disclosing the checks, accepting a claim with no command output, and
     blocking on suspicion rather than on a contract violation.
   - Frontmatter `version: 1.6.0`. Also fix the stale executor list in the
     description — it still reads "Haiku 4.5, Sonnet 5 and Opus 4.8" although
     `081382d` made Opus 5 the default heavy executor.
2. `plugins/orchestration/.claude-plugin/plugin.json` — `version` 1.5.0 → 1.6.0.
3. `README.md` line 20 — the `multi-model` row gains supervised waves.

Orchestrator profiles (`references/orchestrator-*.md`) are unchanged: the
supervisor stage is model-independent, and the model-specific facts it relies on
already live in `references/model-dossiers.md`.

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
