# Tests

```
./tests/run.sh          structure + contracts + behaviour   — offline, seconds
./tests/run.sh --live   the above plus the evaluation tiers — ~a dozen model
                        calls (supervisor, drift, wave boundary, planner —
                        the last on Sonnet), several minutes
```

Enable the pre-push gate once per clone:

```
git config core.hooksPath .githooks
```

## The tiers, and what each is actually worth

**structure** — manifests parse, frontmatter is complete, skill and plugin
versions agree, shipped scripts are executable and syntactically valid, no
forbidden names or absolute home paths. Everything here breaks a plugin
outright, so this tier must never be red.

**contracts** — assertions over the skills' prose, limited to lines whose loss
changes what an agent *does* or reopens a defect that has already cost us. Be
clear-eyed about this tier: in the 2026-08-11 review it was fully green while
three serious defects were live. It catches deletion, not wrongness.

**behaviour** — `plugins/*/hooks/*.test.sh`, co-located with the code they
cover. The drift hook's gates run offline through `CLAUDE_DRIFT_CHECK_DRYRUN=1`,
which prints the decision instead of calling the model, and the logic after the
call through `CLAUDE_DRIFT_CHECK_FAKE_ANSWER`. Real assertions about real
behaviour, and the cheapest tier that can find a genuine bug.

**evaluation (live)** — the only tier that asks whether the prompts *work*. Each
fixture's correct answer was fixed in `docs/superpowers/specs/` before the
prompt ever saw it. A supervisor that returns `ok:true` unconditionally passes
every other tier in this repository and fails here; so does a drift check that
answers `NOTHING` to everything.

The super-plan tier asks the inverse planning questions: a request that
tempts same-wave file overlap must still produce a lint-clean plan, and a
request hiding a product fork must surface it under "Assumptions (would
ask)" rather than resolve it silently.

**wave-runner (simulated)** — `tests/wave-runner.test.sh` runs the shipped
`wave-runner.workflow.mjs` through an offline simulator
(`tests/lib/workflow-sim.mjs`) with stubbed agents: every escalation-ladder
rule is a deterministic assertion on the real file. Requires `node` on PATH.
The simulator's own fidelity is the tier's trust anchor, so it has a
self-test, and the Workflow-boundary rules (single export, literal meta, no
Date) are pinned by static checks that each cost a launch rejection once.

**plan linter** — `tests/plan-lint.test.sh` mutates the canonical clean plan
fixture one defect at a time and asserts the shipped `plan-lint.mjs` names
each error class; warnings are asserted non-fatal. Requires `node`.

## Repeating the guards

A single model call proves a case *can* pass, not that it reliably does. The two
false-positive guards — D3 (crying wolf on a clean run) and F3 (blocking correct
work) — take `EVAL_REPEAT`, because those are the failures that make a
supervision layer worse than none:

```
EVAL_REPEAT=5 ./tests/run.sh --live
```

Measured 2026-08-11 at 5 runs each: both 5/5. No flakiness observed on the cases
where a wrong answer costs the most. Repeated 2026-09-01 on Fable 5.1
(`EVAL_MODEL=claude-fable-5-1 EVAL_REPEAT=5`): F3 5/5, D3 5/5, and the
single-run cases (F1, F2, F4, D1, D2) passed a second time in the same run.

## What this suite cannot tell you

Worth stating plainly, because a green run is easy to over-read.

- **Every fixture was written by the same mind that wrote the prompts.** They
  test imagined failures. The three serious defects found on 2026-08-11 all came
  from outside that imagination: a hash tool absent on another platform, a status
  key inside a documentation fence, a wave-specific gate left in a generalised
  path. No self-authored suite escapes its author's blind spots.
- **Default model is the cheapest one that measured reliable.** Every
  evaluation runs on Haiku 4.5 unless `EVAL_MODEL` says otherwise, with one
  exception: the super-plan tier defaults to Sonnet 5. Measured 2026-08-12,
  one run per fixture: the supervisor tier passes 9/9 on Sonnet 5, Opus 5 and
  Fable 5 as well (`EVAL_MODEL=claude-sonnet-5|claude-opus-5|claude-fable-5`,
  F1–F4). Single runs prove each model *can* judge these fixtures, not a
  rate; Opus 4.8 and the drift tier's non-Haiku behaviour remain unmeasured.
  Fable 5.1 (`EVAL_MODEL=claude-fable-5-1`), measured 2026-09-01 in one run
  per tier: supervisor 9/9 (F1–F4), drift 3/3, wave 3/3 (a real verdict over
  the `Workflow` boundary, not the skip branch), super-plan 6/6 (P1 and P2
  lint-clean, the fork surfaced). Single runs — "can", not a rate — except
  the two false-positive guards, which hold 5/5 (see Repeating the guards). Its
  first live use as a wave supervisor is recorded in
  `tests/eval/wave-insession.md`.
- **The super-plan floor is Sonnet, not Haiku — measured, not assumed, and
  still not perfect.** Measured 2026-08-18 across repeated live runs of
  `tests/eval/super-plan.sh`: Haiku 4.5 did not reliably follow the skill's
  plan format — observed failures included prose printed before the plan
  content despite an explicit instruction not to, `branch` values that did
  not match `wave/<id>`, a `ladder` array holding branch names instead of
  short model names, and a same-wave file overlap that survived to lint — on
  some runs, while other runs were fully clean. Sonnet 5 was markedly more
  reliable (clean on most runs, including every run of the overlap-temptation
  fixture) but not flawless either: one run out of several produced a P2 plan
  that failed lint. This tier inherits the same limit as every live tier
  here — a run proves a case *can* pass, not that it reliably does.
  `EVAL_MODEL=claude-haiku-4-5-20251001` still runs it on Haiku for anyone
  who wants to see the weaker model's failure modes firsthand.
- **ship has no automated tier at all.** The conductor's behavior is gates,
  invocations of other skills, and git/PR side effects — none of it
  exercisable headless without spending real waves and touching a real
  remote. Its contract checks pin the load-bearing prose; everything else is
  covered only by the in-session probe log
  (`tests/eval/ship-insession.md`), and that log says so rather than
  pretending otherwise.
- **No adversarial fixtures.** Every case is an ordinary failure. Nobody has
  tried to *defeat* the supervisor — pasted output differing only in whitespace,
  or work that satisfies a contract's letter against its point. The dossiers
  document models rules-lawyering around wording, and nothing here tests it.
- **The ladder's live coverage is one boundary probe.** Its rules — rework,
  two-strike escalation, the unsatisfiable-contract stop, the absolute cap —
  are asserted by the simulator on the shipped file, which is exactly as
  trustworthy as the simulator's fidelity to the real Workflow runtime. The
  live tier (or the in-session probe, see `tests/eval/wave-insession.md`)
  proves acceptance and one real verdict, nothing more. The tool-call layer
  delivers `args` as a JSON-encoded string in every observed environment, so
  the runner parses before validating; the live tier asserts a real wave
  result over that path.

## Adding to it

A defect found in the wild earns a permanent case, in the tier that would have
caught it. Most of what has actually bitten us — a hash tool missing on another
platform, a status key inside a documentation fence, a wave-specific gate left
in a generalised path — was invisible to greps and obvious to a probe. Prefer
the behaviour and evaluation tiers.

The nine `task*.sh` / `sup-task*.sh` files that used to live under
`docs/superpowers/plans/checks/` were consolidated here. They were named after
plan tasks, which meant nothing once the plans were finished.
