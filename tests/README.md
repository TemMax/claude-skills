# Tests

```
./tests/run.sh          structure + contracts + behaviour   — offline, seconds
./tests/run.sh --live   the above plus the evaluation tiers — ~7 model calls, a few minutes
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

**wave-runner (simulated)** — `tests/wave-runner.test.sh` runs the shipped
`wave-runner.workflow.mjs` through an offline simulator
(`tests/lib/workflow-sim.mjs`) with stubbed agents: every escalation-ladder
rule is a deterministic assertion on the real file. Requires `node` on PATH.
The simulator's own fidelity is the tier's trust anchor, so it has a
self-test, and the Workflow-boundary rules (single export, literal meta, no
Date) are pinned by static checks that each cost a launch rejection once.

## Repeating the guards

A single model call proves a case *can* pass, not that it reliably does. The two
false-positive guards — D3 (crying wolf on a clean run) and F3 (blocking correct
work) — take `EVAL_REPEAT`, because those are the failures that make a
supervision layer worse than none:

```
EVAL_REPEAT=5 ./tests/run.sh --live
```

Measured 2026-08-11 at 5 runs each: both 5/5. No flakiness observed on the cases
where a wrong answer costs the most.

## What this suite cannot tell you

Worth stating plainly, because a green run is easy to over-read.

- **Every fixture was written by the same mind that wrote the prompts.** They
  test imagined failures. The three serious defects found on 2026-08-11 all came
  from outside that imagination: a hash tool absent on another platform, a status
  key inside a documentation fence, a wave-specific gate left in a generalised
  path. No self-authored suite escapes its author's blind spots.
- **One model.** Every evaluation runs on Haiku 4.5 unless `EVAL_MODEL` says
  otherwise. The skills claim to work with Fable 5, Opus 4.8 and Opus 5 in the
  reviewing and supervising roles; that is untested here.
- **No adversarial fixtures.** Every case is an ordinary failure. Nobody has
  tried to *defeat* the supervisor — pasted output differing only in whitespace,
  or work that satisfies a contract's letter against its point. The dossiers
  document models rules-lawyering around wording, and nothing here tests it.
- **The ladder's live coverage is one boundary probe.** Its rules — rework,
  two-strike escalation, the unsatisfiable-contract stop, the absolute cap —
  are asserted by the simulator on the shipped file, which is exactly as
  trustworthy as the simulator's fidelity to the real Workflow runtime. The
  live tier (or the in-session probe, see `tests/eval/wave-insession.md`)
  proves acceptance and one real verdict, nothing more. As of 2026-08-12 even
  that acceptance is unproven from headless `claude -p`: `Workflow` is
  reachable, but the CLI's own tool-call serialization stringifies the
  object-typed `args` parameter before the runner sees it, so `wave.sh` skips
  rather than asserting — only the in-session probe can currently exercise the
  live boundary.

## Adding to it

A defect found in the wild earns a permanent case, in the tier that would have
caught it. Most of what has actually bitten us — a hash tool missing on another
platform, a status key inside a documentation fence, a wave-specific gate left
in a generalised path — was invisible to greps and obvious to a probe. Prefer
the behaviour and evaluation tiers.

The nine `task*.sh` / `sup-task*.sh` files that used to live under
`docs/superpowers/plans/checks/` were consolidated here. They were named after
plan tasks, which meant nothing once the plans were finished.
