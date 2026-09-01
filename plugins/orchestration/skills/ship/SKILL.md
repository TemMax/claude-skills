---
name: ship
description: 'Use when delivering a feature end-to-end — from a request to a reviewed pull request — through the full pipeline: super-plan turns it into contract-carrying waves, multi-model executes them supervised on a feature branch, critical-review reviews the PR and answers its threads. One confirmation up front (the feature branch will be pushed and a PR opened); the merge stays with the user. Triggers: "сделай под ключ", "доведи фичу до PR", "полный цикл", "ship this", "ship it", "end to end". Do NOT use for a single stage — invoke super-plan, multi-model or critical-review directly instead.'
metadata:
  author: https://github.com/TemMax
  version: 2.5.0
---

# Shipping a Feature (ship)

One command, three shipped stages, one promise: what leaves this skill is a
pushed feature branch with a reviewed pull request — never a touched default
branch. **The merge stays with the user.**

## Step 0 — Load Your Own Orchestrator Profile (before anything else)

Your environment block states the model you are running as. Read it and load
the ONE matching profile — the same profiles the multi-model skill uses:

| Your model ID | Read this file |
|---|---|
| `claude-fable-5-1` | `../multi-model/references/orchestrator-fable-5-1.md` |
| `claude-fable-5` | `../multi-model/references/orchestrator-fable-5.md` |
| `claude-opus-5` (any context-window suffix) | `../multi-model/references/orchestrator-opus-5.md` |
| `claude-opus-4-8` (any suffix) | `../multi-model/references/orchestrator-opus-4-8.md` |
| anything else | no profile exists — use the rules below only, and say so |

Read exactly one. Always reply to the user in the language the user writes in.

## What ship owns — and what it does not

ship adds no machinery. The stages, gates, verdicts and safety rules all
belong to the three link skills — super-plan, multi-model, critical-review —
and every one of them runs as itself, by invocation, not by paraphrase. ship
owns exactly three things: the branch discipline, the artifact handoffs
between stages, and the routing of review findings. If you are tempted to
re-implement a stage inline instead of invoking its skill, stop — that is
how tested behavior silently diverges.

## Stage 0 — Preflight, and the one gate ship adds

Checks, in order, before anything is created:

- the working tree is clean (uncommitted work is the user's, not ship's — stop
  and ask rather than stash);
- `origin` exists and the default branch is known;
- `gh` is present and authenticated (the PR and thread phases need write);
  if it is not, say so now — the run can still proceed to a pushed branch,
  with the PR left for the user.

Derive a kebab-case feature branch name from the request. Then the gate —
the only one ship adds: tell the user, in one message, that branch
`<name>` will be created and pushed to origin, that the waves will fork from
it, and that a PR into the default branch will be opened at the end. One
yes/no. After yes, ship itself never stops the flow again — only the link
skills' own gates do.

## Stage 1 — Plan

Invoke **super-plan**. Its two gates (design, lint-clean plan) run inside it.
The output is the plan file; its `status:` stays `draft` — transitions belong
to execution.

## Stage 2 — Execute

1. Create the feature branch from `origin/<default>` and push it.
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
5. Failures follow multi-model's rules unchanged: `failed`/`error` → stop and
   hand the user the verdicts and branch names; `contract-unsatisfiable` →
   the amendment flow. ship never quietly retries anything.
6. multi-model owns the plan's status transitions (`active` at launch,
   `done` at completion), as always.

## Stage 3 — Review

1. The orchestrator's own end-to-end review (multi-model's checklist) plus a
   full offline suite run.
2. Open the PR. The body carries: what shipped, how it was built (waves,
   verdicts, reworks — the judges' catches included), what was tested, the
   honest limits — and, when the plan carries Acceptance References that no
   contract or runtime check verified, an explicit **"Not verified — manual
   QA needed"** section listing each one. An unverified reference that
   vanishes from the PR resurfaces as a production defect found by hand.
3. If the plan carries Acceptance References and this session has a tool or
   skill whose **described capability** is running the product and
   observing it — launching the app, driving its UI, capturing screenshots —
   run one runtime verification pass over those references before invoking
   the review, and route its findings like any review findings. Match by
   described capability, never by a hard-coded skill name: ship must work
   in sessions that have no such skill, where this step silently reduces to
   the "Not verified" section above. This step adds no gate and no new
   machinery — a missing or failing capability is not a ship failure.
4. Invoke **critical-review** on the PR.
5. Route every finding by behavior, not size:
   - the fix **changes behavior** (code paths, tests, contracts, scripts) →
     a fix-wave: a contract and a judge through the runner, merged and
     pushed like any wave;
   - the fix **changes no behavior** (prose, docs, comments, config strings)
     → the orchestrator applies it inline and commits.
   The line is what the change can break, not how many lines it takes.
6. If the PR has review threads, run critical-review's post-review fix phase
   end-to-end. Its own single gate — the exact reply texts, then
   `push → replies → resolves` — is the only barrier before anything is
   published.

## Stage 4 — Handoff

ship ends at: PR open, review clean or every finding routed, threads
answered. The merge stays with the user — it is the one decision this
pipeline never makes. Report: the branch, the PR link, waves run, verdicts
and reworks, what was fixed inline versus by wave, and anything left open.

## Failure map

| Where it broke | What ship does |
|---|---|
| A preflight check fails | Stop before the gate; name the missing piece |
| The user declines a super-plan gate | Stop; nothing was created yet |
| A wave returns `failed` / `error` | Stop with verdicts and branch names (multi-model's rule) |
| The suite is red after a merge | Stop before the push; hand the output over |
| `gh` loses write capability mid-flow | critical-review degrades per its own protocol; prepared texts go to the user |
| The user declines critical-review's fix gate | Soft reset per that skill; the PR stays open |
| The runtime QA capability is missing or fails mid-pass | Not a ship failure: the affected references go to the PR's "Not verified — manual QA needed" section |

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Re-implementing a stage inline | Silent divergence from tested behavior | Invoke the link skill |
| Merging the PR yourself | The one decision that is not yours | The merge stays with the user |
| Routing a behavior change inline because it is small | A code fix lands with no judge | Behavior → fix-wave, whatever the size |
| Adding a second ship-level gate mid-flow | The pipeline stops being automatic | One gate up front; the links keep their own |
| Basing a wave on a hand-typed sha | A corrupted base already burned a wave once | Copy the tip verbatim from `git rev-parse` output |
| Opening the PR before the suite is green | The reviewers review a broken branch | Suite first, PR second |
| Dropping unverified Acceptance References from the PR body | They resurface as production defects found by hand | The "Not verified" section is mandatory whenever references exist |
