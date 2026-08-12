# Wave Runner — Reference Implementation Design

Date: 2026-08-12
Status: approved design, pre-implementation
Target: orchestration plugin 1.8.0 (multi-model skill)

## Problem

Every consequence rule of supervised waves — "two same-rule violations escalate",
"`satisfiable: false` stops immediately", "two `pasteReproduced: false` strikes
change the model" — currently lives as prose in SKILL.md. The orchestrator
re-implements that prose in a freshly written workflow script for every wave.
Nothing guarantees the implementation matches the prose; the one implementation
that ever existed (the 2026-08-12 ladder probe) was written by a delegated
model, rejected at launch four times for Workflow-boundary rules, and proved
only that the ladder *can* work — not that the next orchestrator will write it
correctly.

The prompts are well tested. The control logic acting on their output is not.
This design turns that control logic into one shipped, tested artifact.

## Decisions already made (user-approved)

1. Scope: the **entire wave run** — isolation, executors, supervision, the
   escalation ladder, the unsatisfiable-contract stop — not just the ladder.
2. Testing: **offline simulator** (deterministic, free, in the default suite)
   plus **one live scenario** in `tests/eval/` proving the real Workflow
   boundary.
3. Prompt assembly: **the script assembles executor prompts** from structured
   args. The contract the executor reads and the contract the supervisor
   enforces are the same object; they cannot diverge.

## 1. Artifact and invocation

One file:

```
plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs
```

The orchestrator invokes it as:

```
Workflow({
  scriptPath: "<skill base dir>/references/wave-runner.workflow.mjs",
  args: { ...wave args as a real JSON object... }
})
```

The skill's base directory is announced when the skill loads, so the path is
computed, never guessed.

**Filesystem constraint:** workflow scripts have no filesystem access, so the
script cannot read `references/supervisor-prompt.md`. The orchestrator reads
that file and passes its text in `args.supervisorPromptText`. The file remains
the single source; the script carries no copy.

## 2. Args contract

```js
{
  base: "<sha>",                 // pushed fork point (verified by executor via merge-base)
  defaultBranch: "main",
  repoPath: "/abs/path/to/repo",
  supervisorPromptText: "<full text of supervisor-prompt.md>",
  supervisor: { model: "opus", effort: "high" },
  tasks: [{
    id: "auth-fix",              // kebab-case, unique within the wave
    description: "...",          // the substantive ask (prose)
    context: "...",              // optional: files, lines, conventions
    contract: {
      files_allowed:   ["src/http/**"],
      files_forbidden: [],
      must_run:        [{ cmd: "pytest tests/http -q", evidence: "required" }],
      forbidden_moves: ["weakening, deleting or skipping an existing test"],
      report_must_answer: ["Which call sites now retry?"]
    },
    executor: { model: "sonnet", effort: "medium" },
    ladder: ["opus"]             // rungs AFTER the first executor; optional
  }]
}
```

**Default ladder** when `ladder` is omitted: the next stronger executors from
the routing table, starting after `executor.model` in the order
`haiku → sonnet → opus`. `opus` is the terminal rung by default (`fable` is
allowed only when named explicitly in `ladder`).

**Validation — fail closed, zero agents spawned on failure.** The first thing
the script does is validate; any failure returns
`{ status: "invalid-args", errors: [...] }` immediately. Checks:

- `args` is an object (the passed-as-string bug has bitten twice; a string
  fails here with a named error, not a plausible meaningless run);
- `base` matches `^[0-9a-f]{7,40}$`; `repoPath` is absolute;
- `tasks` is a non-empty array; ids are kebab-case and unique;
- every task has a non-empty `description` and a `contract` with all five keys
  (`must_run` entries each have `cmd` and `evidence`);
- `executor.model` and every ladder entry ∈ {`haiku`, `sonnet`, `opus`,
  `fable`}; effort ∈ {`low`, `medium`, `high`, `xhigh`, `max`} when present;
- `supervisorPromptText` is non-empty and contains the string `"verdict"`
  (a sanity tripwire against passing the wrong file's text).

## 3. Prompt assembly (inside the script)

**Executor prompt** — the six mandatory blocks from SKILL.md's template,
assembled from the task object:

1. Context: `description` + `context` + the isolation notice ("you work in
   your own worktree; you will not see neighbours' edits").
2. Boundaries: derived from `files_allowed` / `files_forbidden`.
3. Dead-end protocol: fixed text ("stop and report; don't invent values, don't
   work around, don't pick an interpretation on the user's behalf").
4. Prohibitions: fixed text, no qualifiers (no subagents; no destructive git).
5. Definition of done and report format: changed files, gist, actual outputs of
   `must_run` commands.
6. Contract: the task's `contract` object rendered as YAML — the same object
   the supervisor receives.

Isolation instructions in the prompt: create
`git worktree add <repoPath>/.worktrees/wave-<id> -b wave/<id> <base>` (reuse
if it exists), verify `git merge-base --is-ancestor <base> origin/<defaultBranch>`,
work and commit only there.

**Rework prompt** (attempts after a failed verdict): the original prompt, plus
the full prior verdict JSON, plus "continue in the same worktree and branch;
fix the violations; do not restart from scratch."

**Supervisor prompt**: `supervisorPromptText` + CONTRACT (same object, as
YAML) + BASE + BRANCH (`wave/<id>`) + the executor's report, exactly as the
existing eval fixtures compose it. The verdict is taken via `opts.schema`
(Workflow-validated JSON) — no regex parsing:

```js
{ ok, violations: [{rule, class, evidence, quote, pasteReproduced?, satisfiable?}], remarks }
```

(`satisfiable` and `pasteReproduced` are per-violation fields — that is what the
adversarially-hardened supervisor prompt already emits, and the prompt is not
edited by this work. The runner reads "any violation with `satisfiable: false`"
and "any violation in this verdict with `pasteReproduced: false` counts one
strike for the verdict".)

## 4. Execution flow — the ladder as code

`pipeline()` over tasks; no barrier. Per task, a rung loop over
`[executor.model, ...ladder]`:

- Each **rung** allows at most **2 verdict attempts** (initial + one rework).
- After every executor attempt, the supervisor judges. Then, in priority order:
  1. `ok: true` → task `ok`, done.
  2. `satisfiable: false` (regardless of `ok`) → task
     `contract-unsatisfiable` immediately; no further attempts; the verdict is
     returned for the orchestrator's amendment flow. Other tasks continue.
  3. `pasteReproduced: false` **for the second time across all attempts of
     this task** → escalate to the next rung immediately (skip the remaining
     attempt on the current rung). On the terminal rung → task `failed`.
  4. `ok: false` on attempt 1 of a rung → rework on the same rung, verdict
     attached.
  5. `ok: false` on attempt 2 of a rung → escalate to the next rung. The
     escalation reason is recorded as `same-rule-repeat` when the new verdict
     shares a `(class, rule)` pair with the previous one, else
     `rung-exhausted`. Both escalate — two failures on a rung mean the rung is
     not working; the reason is diagnostic, not a branch.
  6. Ladder exhausted → task `failed`, full attempt trace attached.
- **Absolute cap**: 6 executor attempts per task, whatever the ladder length.
- **Dead subagents**: `agent()` returning `null` (executor or supervisor) is
  recorded as an `agent-error` attempt (it does not consume a verdict
  attempt), retried once at the same point; a second `null` → task `error`.
  One API failure never takes down the wave.
- The branch `wave/<id>` persists across attempts and rungs: an escalated
  model continues the same branch with the verdict history attached.

**Determinism**: no `Date.*`, no `Math.random`, `meta` is a pure literal,
exactly one `export`, short model names, top-level `return` for the result —
the full Workflow-boundary list from SKILL.md, honored so `resumeFromRunId`
works. After the orchestrator amends one task's contract and re-invokes, every
task whose args are unchanged replays from cache.

## 5. Return shape

```js
{
  status: "done" | "partial" | "invalid-args",   // done = every task ok
  errors: [...],                                  // invalid-args only
  tasks: [{
    id, status: "ok" | "failed" | "contract-unsatisfiable" | "error",
    branch: "wave/<id>",
    attempts: [{ rung, model, effort, kind: "verdict" | "agent-error",
                 verdict, escalation: null | "same-rule-repeat" | "rung-exhausted"
                          | "paste-two-strikes" }]
  }]
}
```

The orchestrator acts on this: merge `ok` branches, run the existing
one-amendment flow on `contract-unsatisfiable`, report `failed`/`error` with
the attached verdicts. The wave-plan artifact lifecycle (`status:
active`/`done`) stays with the orchestrator, unchanged.

## 6. Offline simulator (default suite tier)

Files:

- `tests/lib/workflow-sim.mjs` — loads the **real** script text, replaces
  `export const meta` with `const meta`, wraps the body in an
  `AsyncFunction(agent, pipeline, parallel, phase, log, args, budget)`, and
  runs it with stubs. `pipeline`/`parallel` are faithful minimal
  reimplementations (pipeline: per-item sequential stages, items concurrent;
  parallel: thunks, errors → `null`). The `agent` stub routes by prompt
  content (contains `supervisorPromptText` marker → supervisor call, else
  executor), pops canned responses from the scenario queue, and records every
  call (`model`, `effort`, prompt) for assertions.
- `tests/wave-runner.test.sh` — shell wrapper integrating with `tests/lib.sh`;
  runs the node scenarios plus static boundary checks.

The simulated artifact is the shipped file itself — not a copy of its logic.

**Scenarios** (deterministic, no model calls):

| # | Scenario | Asserts |
|---|---|---|
| S1 | ok:true first try | 1 executor + 1 supervisor call; task `ok`; model never changed |
| S2 | fail → rework → ok | rework prompt contains prior verdict; same model both attempts |
| S3 | same (class, rule) twice | escalation to next ladder model; reason `same-rule-repeat`; executor model actually changed |
| S4 | two pasteReproduced:false | immediate escalation, remaining rung attempt skipped; reason `paste-two-strikes` |
| S5 | satisfiable:false | task `contract-unsatisfiable`; zero further executor calls for that task; other tasks unaffected |
| S6 | ladder exhausted | task `failed`; attempt trace covers every rung; absolute cap respected |
| S7 | agent() → null | recorded as `agent-error`, retried once, no crash; second null → `error` |
| S8 | invalid args (string args; missing base; empty tasks) | `invalid-args` with named errors; **zero** agent calls |

**Static boundary checks** (shell, on the script file): exactly one `export`;
`meta` block free of `${`, `+`-concatenation and identifiers; no `Date.`,
`new Date`, `Math.random`; only short model names passed to `opts.model`;
a top-level `return` exists.

Requires `node` on PATH (already true of the dev machine; documented in
`tests/README.md` alongside the python3/ruby requirements).

## 7. Live tier

`tests/eval/wave.sh` (runs under `--live` only): a tiny fixture repo (the
supervisor eval's divide() shape), one task, everything on Haiku. It proves
the one thing the simulator cannot: the script is **accepted by the real
Workflow tool** and reaches a verdict on real models.

**Known risk**: the Workflow tool's availability inside headless `claude -p`
is unverified. Implementation includes a probe; if Workflow is not reachable
headless, the live tier degrades to a documented in-session procedure
(fixture + args file + a trace-assertion script that validates the returned
JSON), and `tests/README.md` states that honestly. Ladder *rules* are not
re-proven live — the simulator owns them for free.

## 8. SKILL.md changes (1.7.1 → 1.8.0)

- The wave-execution guidance is rewritten: the **default path is invoking the
  shipped script** — collect args from the plan, read
  `references/supervisor-prompt.md`, call `Workflow({scriptPath, args})`, act
  on the returned statuses. The orchestrator writes no wave script.
- "Delegating the Workflow Script Itself" survives, reframed: it applies only
  to the rare wave the reference script cannot express, and says so.
- The ladder table and the two-strike/satisfiable prose stay as the
  human-readable statement of what the script now enforces, with a pointer to
  the artifact.
- `tests/skills-contract.sh` additions: the script file exists; SKILL.md
  references `wave-runner.workflow.mjs`; the default path is phrased as
  invoking, not writing ("do not write a wave script" or equivalent
  load-bearing line); `supervisorPromptText` is named (the
  filesystem-constraint rule survives).
- Versions: orchestration `plugin.json` and multi-model SKILL.md → 1.8.0
  (structure.sh enforces agreement).

## Out of scope

- Merging passed branches into the base branch (orchestrator's job, as
  decided).
- The one-amendment contract-repair flow (already specified; stays with the
  orchestrator).
- Any change to critical-review or the drift hook.
- Multi-wave planning; the script runs exactly one wave per invocation.
