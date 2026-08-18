---
name: super-plan
description: 'Use when planning a feature, refactor or fix into wave-ready tasks for the multi-model skill — researching the codebase to decomposition depth, closing open questions (one batched round to the user for what code cannot answer), then writing a plan whose tasks carry machine-checkable contracts, grouped into waves by file-independence and validated by the shipped plan linter. Works on whatever model this session runs on; it loads the matching orchestrator profile itself. Triggers: "составь план", "спланируй фичу", "план под волны", "plan this feature", "make a wave plan", "super plan". Do NOT use for executing a plan (that is multi-model) or reviewing a diff (that is critical-review).'
metadata:
  author: https://github.com/TemMax
  version: 2.1.0
---

# Planning Waves (super-plan)

The dialogue and no-placeholders planning discipline here is adapted from
Jesse Vincent's superpowers (MIT — see `references/LICENSE-superpowers`);
the output format and every contract rule are this plugin's own.

## Step 0 — Load Your Own Orchestrator Profile (before anything else)

Your environment block states the model you are running as. Read it and load
the ONE matching profile — the same profiles the multi-model skill uses:

| Your model ID | Read this file |
|---|---|
| `claude-fable-5` | `../multi-model/references/orchestrator-fable-5.md` |
| `claude-opus-5` (any context-window suffix) | `../multi-model/references/orchestrator-opus-5.md` |
| `claude-opus-4-8` (any suffix) | `../multi-model/references/orchestrator-opus-4-8.md` |
| anything else | no profile exists — use the rules below only, and say so |

Read exactly one. Always reply to the user in the language the user writes in.

## Process

1. **Research** to decomposition depth: files, dependencies, conventions,
   test commands that actually run. For a large surface, fan out read-only
   Explore agents; synthesis and every decision stay with you — do not
   delegate decisions, executors silently fill gaps under ambiguity.
2. **Decisions.** Everything derivable from the codebase you decide and
   record. What code cannot answer — product behavior, trade-offs, scope
   cuts — goes to the user as ONE batched AskUserQuestion (up to 4 forks);
   a second batch only if the answers open new forks. Never drip questions
   one at a time, and never resolve a product fork silently.
3. **Gate 1 — design.** Present a compact summary: architecture, the wave
   sketch (which tasks, which waves, why), decisions taken, forks the user
   answered. One approval, then stop touching the design.
4. **Tasks.** Write them by multi-model's rules: closed (no "decide what's
   best"), self-contained (the executor sees nothing but its prompt), full
   code included where the solution is known. Each task carries the
   five-key contract; models and efforts come from multi-model's routing
   and effort tables, the wave's supervisor from its supervisor table
   (chosen for the strongest executor in the wave). Group into waves by
   file-independence: same-wave tasks must not share files — merge
   colliding tasks or split them across consecutive waves. Dependent
   chains are consecutive waves, never one wave.
5. **Lint.** Run the shipped linter and fix every error yourself — the
   user never edits the plan:

   ```
   node <this skill's base directory>/references/plan-lint.mjs <plan-file> --repo <repo>
   ```

   Warnings are judgment calls; errors are not negotiable. A plan that
   fails lint is not presented to the user.
6. **Gate 2 — plan.** Show the lint-clean plan file; one approval.
7. **Handoff.** "Execute with multi-model (supervised waves)." The plan
   file IS the wave-plan artifact: the json block feeds the runner directly —
   each runner task is the json entry plus its `## Task` prose as
   `description` (the runner rejects a task without one, by name). The
   `status:` field stays `draft` here — status transitions belong
   to execution (multi-model sets `active` at launch and
   `done` at completion), never to planning and never to the user.

## Plan Format

One file in `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`, three layers:

1. **Unfenced header** at column 0, before any code fence (the drift hook
   reads it there):

   ```
   status: draft
   base: pending
   ```

2. **The machine half** — exactly one fenced block whose info string is
   `json wave-plan` (plain ```json fences inside task prose stay legal and
   are ignored by the linter):

   ```json wave-plan
   { "waves": [
     { "wave": 1,
       "supervisor": { "model": "opus", "effort": "high" },
       "tasks": [
         { "id": "http-retry",
           "branch": "wave/http-retry",
           "executor": { "model": "sonnet", "effort": "medium" },
           "ladder": ["opus"],
           "contract": {
             "files_allowed": ["src/http/**"],
             "files_forbidden": [],
             "must_run": [{ "cmd": "pytest tests/http -q", "evidence": "required" }],
             "forbidden_moves": ["weakening, deleting or skipping an existing test"],
             "report_must_answer": ["Which call sites now retry?"] } } ] }
   ] }
   ```

   Short model names only. `branch` is always `wave/<id>`. The supervisor
   sits on the wave because execution is one runner invocation per wave.

3. **The prose half** — one `## Task <id>` section per task: the
   substantive description and context, with full code where the solution
   is known. At launch, multi-model composes each runner task as the json
   entry plus its prose section, verbatim.

## Headless evaluation mode

When there is no user to answer gates (an eval harness runs you), skip both
gates and record every fork you would have asked under a section titled
`## Assumptions (would ask)` in the plan file. Deciding a product fork
silently is the failure this mode exists to measure.

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Two same-wave tasks sharing a file | Merge conflicts after isolation did its job | Merge the tasks or split the waves; lint enforces it |
| Dripping questions one at a time | The user becomes the bottleneck | ONE batched AskUserQuestion for genuine forks |
| Deciding a product fork silently | The most expensive wrong turn there is | Batch it to the user; in headless mode, record it |
| Presenting a plan that fails lint | The user debugs your format | Lint first, fix every error, then present |
| Setting `status: active` while planning | The drift hook pays for a wave that is not running | Leave `draft`; execution owns transitions |
| A task whose fix is "see the conversation" | The executor sees only its prompt | Self-contained tasks, full code where known |
