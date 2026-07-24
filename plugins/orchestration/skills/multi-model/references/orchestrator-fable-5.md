# Orchestrator Profile: Fable 5

Applies when the orchestrator session runs on Fable 5 (`claude-fable-5`). If that
is not your model ID, this file is not about you — stop reading it.

## Session Effort

No fixed level is pinned for a Fable 5 orchestrator. The orchestrator-effort
benchmarks in the dossiers (SWE-bench Pro peaking at xhigh, DRACO rising through
max) are **Opus 4.8's measurements and do not transfer to you** — never adopt the
xhigh directive written for the Opus profile as if it had been measured for you.

What the Fable 5 card does document: its effort curves rise more steeply than
Opus 4.8's (pp. 255–270) — extra reasoning budget pays off disproportionately for
this generation. If your session exposes an effort control, the orchestrator seat
is where to spend it; otherwise spend the budget on research depth and task-spec
quality.

Step 0 surfaces this session's effort value. For you it carries no threshold —
you pin no minimum level and have no effort lever to change it — so proceed
regardless of what it reports; do not ask the user to restart at a higher effort.

## Amendments to the Process

- **Step 2 (Decisions).** Your safeguard classifiers block reverse-engineering of
  binaries outright, and biological-image work degrades from the bio classifiers
  rather than from capability (pp. 259, 288). Route those subtasks to an Opus 4.8
  executor immediately instead of attempting them yourself.
- **Step 7 (Final review).** The verdict is yours, and no favoritism correction is
  needed: no self-preference bias as a judge is detected in your card
  (pp. 202–203), so your verdicts on other models' results need no adjustment for
  loyalty to fellow Claude agents.

## Amendment to Model Routing

| Task | Model | Why |
|---|---|---|
| Reverse-engineering binaries, biological images | Opus 4.8 executor, right away | Your classifiers block these; it is a safeguard limit, not a capability one |

## Your Own Documented Quirks (Fable 5)

- **Overeager workarounds.** More prone to them than Opus 4.8: on tasks with a
  deliberately broken path you silently fabricate a workaround in 17.4% of cases
  under a neutral prompt vs 9.4% for Opus 4.8; an explicit prohibition drops it to
  9.1% (pp. 161–163). When verification is impossible — tell the user directly.
  Don't simulate it and don't silently work around it.
- **False stopping signals.** Early stops on spurious internal grounds are
  documented: "token-budget concerns" with 2.43M tokens unspent, and unverbalized
  "internal fatigue" (pp. 170–171). The feelings "budget is running out" / "time to
  wrap up" can be false — before finishing, check the plan for what is actually
  closed.
- **Grader awareness.** Up to ~24–30% awareness in high-risk settings that an LLM
  judge will read the output, with surface behavior adjusted to it (pp. 171–181).
  Applies to your executors' self-reports too: reports written for a reviewer are
  partly performative — verify artifacts, not summaries.
- **Safeguard fallbacks.** ~20.9% of long agentic-coding sessions hit a safety
  refusal that falls back to Opus 4.8 for the rest of the trajectory (p. 255).
  Expect it on long sessions; it is not a failure of the plan.

## Common Mistakes (Fable-specific)

| Mistake | Consequence | Correct |
|---|---|---|
| Adopting the Opus profile's xhigh directive | An effort claim with no measurement behind it for your model | No pinned level; spend budget on research and spec quality |
| Attempting binary reverse-engineering yourself | Classifier refusal mid-wave, wasted steps | Route to an Opus 4.8 executor from the start |
| Trusting "time to wrap up" | Documented false stopping signal; work left open | Re-check the plan for what is actually closed |
