# super-plan — Wave-Native Planning Skill Design

Date: 2026-08-13
Status: approved design, pre-implementation
Target: orchestration plugin 2.1.0 (new skill `super-plan`; multi-model version
rides along per the plugin-wide versioning that structure.sh enforces)

## Problem

The pipeline's execution half is built and tested (multi-model 2.0.1 with the
shipped wave-runner; critical-review 1.3.0). The planning half is not: real
sessions (salvador / douala / osaka, researched 2026-08-13) planned with the
third-party superpowers skills, whose plans are sequential single-executor
chains — no contracts, no wave grouping, shared-checkout assumptions. Every
orchestrator hand-converted them into waves differently, and the most damaging
planning defect — two tasks in one wave touching the same files — is invisible
until the merge conflicts arrive.

`super-plan` is the missing first link: a planning skill whose output is
directly executable by the wave-runner, with the load-bearing plan rules
enforced by shipped code, not prose.

## Decisions already made (user-approved)

1. Own planning skill, forked from the best of superpowers (MIT, Jesse
   Vincent) with attribution — not a dependency on it, not a conversion layer.
2. Name: **`super-plan`** (homage in the name, no namespace collision).
3. Dialogue posture: **questions only where the code cannot answer** —
   product forks and trade-offs go to the user as ONE batched
   AskUserQuestion, everything derivable from the codebase is decided by the
   skill. Exactly two approval gates: design, finished plan.
4. Sequencing: super-plan ships first as a standalone skill; the thin
   `pipeline` skill (plan → waves → critical-review) is a separate follow-up
   project.

## 1. Skill structure

`plugins/orchestration/skills/super-plan/SKILL.md` with:

- **Step 0 — orchestrator profile.** Same mechanism and same profile files as
  multi-model (`../multi-model/references/orchestrator-<model>.md`); the
  planning session loads exactly one, by its own model id.
- **Process:**
  1. **Research** — codebase to the depth needed for decomposition. For a
     large surface, fan out read-only Explore agents; the synthesis and every
     decision stay with the orchestrator (dossier rule: do not delegate
     decisions).
  2. **Decisions** — close every open question. Derivable-from-code → decide
     and record. Not derivable (product behavior, trade-offs, scope cuts) →
     one batched AskUserQuestion (up to 4 forks per batch, more batches only
     if answers open new forks).
  3. **Gate 1: design** — a compact design summary (architecture, per-wave
     decomposition sketch, what was decided and why); one approval, no
     section-by-section loop.
  4. **Tasks** — written by multi-model's rules (closed, self-contained, full
     code where the solution is known — the superpowers "No Placeholders"
     discipline survives here), each with a five-key contract, grouped into
     waves by file-independence; dependent chains become consecutive waves.
     Models/efforts from multi-model's routing tables; supervisor from its
     supervisor table.
  5. **Lint** — run the shipped `plan-lint.mjs` (below). Red findings are the
     orchestrator's to fix; the user never edits the plan.
  6. **Gate 2: plan** — user approves the finished, lint-clean plan file.
  7. **Handoff** — "execute with multi-model (supervised waves)"; the plan
     file IS the wave-plan artifact, no translation step exists.
- **Attribution:** `references/LICENSE-superpowers` (verbatim MIT notice) and
  one SKILL.md line: "The dialogue and no-placeholders planning discipline is
  adapted from Jesse Vincent's superpowers (MIT)."

## 2. Canonical plan format

One markdown file, `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` (the path
the drift hook already watches). Three layers:

**a) Unfenced header** (column 0, before any code fence — the drift hook's
status gate stops at the first fence):

```
status: draft          # draft | active | done — active is set at LAUNCH, by multi-model, never by super-plan
base: pending          # filled with the pushed fork-point sha at launch
```

**b) The machine half** — one fenced block whose info string is
`json wave-plan` (rendered as JSON, but distinguishable from ordinary
```json snippets inside task prose, which stay legal; JSON, not YAML: zero
dependencies to parse, and it is byte-for-byte the wave-runner's `tasks`
input):

```json wave-plan
{
  "waves": [
    { "wave": 1,
      "supervisor": { "model": "opus", "effort": "high" },
      "tasks": [
      { "id": "auth-fix",
        "branch": "wave/auth-fix",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": ["src/http/**"],
          "files_forbidden": [],
          "must_run": [{ "cmd": "pytest tests/http -q", "evidence": "required" }],
          "forbidden_moves": ["weakening, deleting or skipping an existing test"],
          "report_must_answer": ["Which call sites now retry?"]
        } } ] }
  ]
}
```

The supervisor sits on the **wave**, not the task, because the runner takes
one judge per invocation: execution is one runner call per wave, and the
wave's supervisor is chosen from multi-model's routing table for the
strongest executor in that wave. Lint checks the field at the wave level.

**c) The prose half** — one `## Task <id>` section per task carrying
`description` and `context` (the substantive ask, full code where known). At
launch the orchestrator composes runner args as: JSON task + its prose
section, verbatim.

**Drift-hook compatibility:** the hook's declared-branch gate currently
matches only unquoted `branch:` keys; it gains `"branch":` (quoted, JSON)
support — one sed pattern extension in `hooks/drift-check`, covered by a new
offline test case in `drift-check.test.sh`. The status gate needs no change
(`draft` is not `active`, so a plan under construction never wakes the hook —
fail-closed as designed).

## 3. plan-lint.mjs — the load-bearing rules as code

`plugins/orchestration/skills/super-plan/references/plan-lint.mjs`, run as
`node plan-lint.mjs <plan-file> [--repo <path>]`. No dependencies. Exit 0 =
clean; exit 1 = errors (named, one per line, `error:` / `warn:` prefixes;
warnings alone keep exit 0).

Errors:
- header: `status:` line present, value `draft|active|done`;
- exactly one fenced `json wave-plan` block that `JSON.parse`s (plain
  ```json fences in task prose are ignored); shape
  `waves[].tasks[]`;
- ids kebab-case, globally unique; `branch` equals `wave/<id>`;
- `executor.model` / `ladder[]` / `supervisor.model` ∈ short names;
  efforts ∈ low/medium/high/xhigh/max;
- contract has all five keys; `must_run` entries have `cmd` + `evidence`;
- **within one wave, no two tasks' `files_allowed` may overlap** —
  literal-prefix comparison of globs before the first wildcard (documented
  approximation: `src/http/**` vs `src/**` collide, `src/a/**` vs `src/b/**`
  do not);
- a task's own `files_allowed` and `files_forbidden` must not overlap;
- every task id has a matching `## Task <id>` prose section, and vice versa.

Warnings:
- empty `must_run` (allowed for pure-docs tasks, but flagged);
- empty `files_allowed` (the executor has nothing it may change);
- with `--repo`: a `files_allowed` glob whose literal prefix matches nothing
  in the repo; a `must_run` command whose argv[0] is neither on PATH nor a
  repo-relative path.

## 4. Tests

- **structure.sh** — picks the new SKILL.md up automatically (frontmatter,
  version agreement at 2.1.0, prohibitions).
- **skills-contract.sh** — new section: lint script exists and is referenced;
  the no-file-overlap rule is named; "one batched AskUserQuestion" survives;
  attribution line survives; `status: draft` lifecycle line survives.
- **behaviour tier** — `tests/plan-lint.test.sh`: runs the real lint script
  against fixture plans under `tests/fixtures/plans/` — one clean plan (exit
  0), and one bad fixture per error class above (each must produce its named
  error); plus the two warning cases. Node, offline, seconds.
- **drift-check.test.sh** — one added case: a plan whose branches are
  declared in the quoted JSON form is still recognized by the branch gate.

## 5. Testing the skill itself (the eval tier)

§4 proves the shipped code; this section is the tier that asks whether the
PROMPT works — same philosophy as the supervisor fixtures, expectations fixed
before any run.

- **`tests/eval/super-plan.sh`** (`--live` only): a small fixture repo plus a
  feature request; a headless model is handed the SKILL's planning rules and
  produces a plan file (gates are skipped in eval mode — there is no user to
  answer them, and the SKILL states this explicitly). The output must pass
  `plan-lint.mjs` and structural assertions: ≥2 tasks, contracts referencing
  the fixture's real commands and paths, tasks grouped into waves.
- **Overlap trap fixture**: a request that naturally tempts two tasks into
  the same file (the №1 defect observed in real sessions). Fixed expectation:
  the planner either merges them into one task or splits them across waves —
  lint stays green.
- **Silent-decision trap fixture**: a request carrying a genuine product
  fork. Fixed expectation: the fork is NAMED as an open question in the
  design summary, not silently resolved (the dossier's gap-filling risk);
  asserted by grep on the output.
- **In-session probe log** (`tests/eval/super-plan-insession.md`, the
  `wave-insession.md` pattern): the first real feature planned with the skill
  is recorded — date, lint result, and how the plan fared in execution. What
  headless eval cannot exercise (the two gates, the batched AskUserQuestion)
  is exercised here and only here, and the file says so honestly.
- The future `pipeline` skill extends this into one end-to-end probe on a
  fixture repo — plan → wave → critical-review — specified in its own design.

## Out of scope

- The `pipeline` chaining skill (separate spec).
- Any change to the wave-runner or supervisor prompt.
- Converting third-party plan formats (obsoleted by owning the planning
  skill).
- Auto-updating `status:` from super-plan (launch-time transitions belong to
  multi-model's orchestrator, unchanged).
