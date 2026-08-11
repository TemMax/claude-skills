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

## Adding to it

A defect found in the wild earns a permanent case, in the tier that would have
caught it. Most of what has actually bitten us — a hash tool missing on another
platform, a status key inside a documentation fence, a wave-specific gate left
in a generalised path — was invisible to greps and obvious to a probe. Prefer
the behaviour and evaluation tiers.

The nine `task*.sh` / `sup-task*.sh` files that used to live under
`docs/superpowers/plans/checks/` were consolidated here. They were named after
plan tasks, which meant nothing once the plans were finished.
