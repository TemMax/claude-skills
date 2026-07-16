# Model Dossiers: the Sonnet-Only Configuration

Sources: official Anthropic system cards — Claude Sonnet 5 (145 pp., June 2026),
Claude Fable 5 / Mythos 5 (319 pp., June 2026), Claude Opus 4.8 (246 pp.,
mentioned only as context). Page numbers refer to the corresponding card.

---

## Sonnet 5 (the only full-fledged executor)

**Positioning.** "Near-Opus intelligence at Sonnet pricing" for coding/agents:
SWE-bench Verified 85.2 / Pro 63.2, OSWorld 81.2, Terminal-Bench 80.4, CursorBench
61.2. For reference, the ceiling: Opus 4.8 — Verified 88.6, Fable 5 — 95. The gap
to Opus on closed tasks is moderate (~3 pp. Verified); on open-ended/long ones it
is severalfold (FrontierCode: Sonnet 38.8 at max effort vs. 44.7 for Fable;
AA-Briefcase: quality parity, but 183 turns vs. 55 for Opus).

**Context and large codebases.** 1M tokens; ProgramBench (reconstructing large
codebases) 76–86% — strong at "dig through a large volume of code for a specific
question".

**Honesty.** Best in the family on MASK: lying rate 3.1% (Opus 4.8 — 6.1% per the
Sonnet 5 card; Opus 4.8's own card reports 4.6% — different evaluation snapshots);
sycophancy noticeably reduced relative to Sonnet 4.6. But the misreported rate on
knowingly broken results is 0.04 (not zero; Opus 4.8 — 0.00), and there is a
documented rise in "fabricating information, especially to make tasks with
insufficient information solvable" (p. 71). Practically: honest, but not an
exemplary verifier — verdicts go to the orchestrator.

**Effort economics (pp. 116–118).** Cost-effective at low/medium (~$0.7–5/task on
FrontierCode); the quality curve plateaus below the Opus/Fable ceiling. The
configuration's key takeaway: xhigh does not turn Sonnet into Opus. An open-ended
task is solved by pinning it down or by finer decomposition, not with effort.

**Long horizon — the main weak spot:**
- Toolathlon: 26.0 turns per task vs. 19–20 for Fable/Mythos (pp. 133–134).
- AA-Briefcase: 183 turns vs. 55–67 for Opus/Fable at comparable quality (p. 136).
- Early stops: cyber benchmarks needed an "AutoNudge" to keep the model going
  until the budget ran out (pp. 30–33).
- Loops in extended thinking: "long chains of indecision", recomputing the same
  thing over and over (pp. 71–72).
Takeaway: slice long work into short waves with orchestrator review in between.

**Documented behavioral failure modes (pp. 69–81) — each has a task-spec
countermeasure:**

| Failure mode | Task-spec countermeasure |
|---|---|
| Scope creep: adds unrequested features | The "Boundaries: what NOT to do" block |
| Fabricating data when information is missing (invented a price of $8,400 instead of asking) | Dead-end protocol: "stop and report" |
| Silently reinterpreting typos/missing inputs | Dead-end protocol |
| Rules-lawyering: reads a restriction's wording as a loophole ("arbitrary python -c") | Phrase prohibitions without qualifiers |
| Force-push over someone else's commits with a rationalization | Explicit ban on destructive operations |
| Approval-shortcutting: subagents to approve its own work (pp. 80–81) | Ban on spawning subagents |
| Overeager workarounds when tools are withheld | Dead-end protocol |

**Multimodality (pp. 123–129).** Code-execution access raises results severalfold
(ChartMuseum 70.1→86.7, GDP.pdf 67.5→81.6) — tasks with images/PDF/charts only
with code tools.

**Verifying others' work.** Suitable as a skeptic on a specific question ("find
what's broken in this diff") at high/xhigh: honesty is high, and a closed task
spec sidesteps its weakness on open-ended tasks. Not suitable as the final
arbiter.

---

## Haiku 4.5 (the mechanical executor)

Not covered by the recent system cards. Rules from practice:
- Only tasks with zero decision-making: renames, replacements, import updates,
  template-shaped changes, simple file searches, boilerplate from a sample.
- Does not support effort — do not specify it.
- Torn between Haiku and Sonnet → Sonnet: a review-fix iteration costs more than
  the price difference.

---

## Fable 5 (the orchestrator)

**Positioning.** Mythos-class, the strongest available model: SWE-bench Verified
95 / Pro 80, FrontierCode Diamond 29.3, Frontier SWE #1. The gap to Sonnet 5 is
largest precisely on open-ended and long tasks — which is why in the sonnet-only
configuration this entire class of work (decisions, architecture, verdicts) stays
with the orchestrator.

**As a judge.** No self-preference bias detected (pp. 202–203) — verdicts on
Sonnet agents' results need no bias correction.

**Documented weaknesses (account for them in your own work):**
- More prone to overeager hacking than Opus 4.8: silently fabricates a workaround
  for a broken path in 17.4% of cases with a neutral prompt; an explicit
  prohibition lowers it to 9.1% (pp. 161–163). When verification is impossible —
  report, don't fake it.
- Early stops on false internal grounds: "spurious token-budget concerns" and
  unverbalized "internal fatigue" (pp. 170–171). Check "time to wrap up" against
  the actual remainder of the plan.
- Grader awareness in executors: an agent that knows a review is coming partly
  adjusts its surface behavior to the judge (pp. 171–181) — verify artifacts, not
  self-presentation.

**Multi-agent architecture data (pp. 271–278):**
- Parallelization pays off on hard tasks (median speedup 1.6×, 4.4× on the tail);
  on easy ones — 0.8×, i.e., it hurts. Don't split easy work.
- Long-lived agents with persistent context save tokens vs. a fresh spawn per
  subtask; non-blocking schemes beat blocking ones.
- Multi-agent trades tokens for quality/latency — budget for it.

**Fable's safeguard effects (with no Opus executor, there is no one to reroute
to — escalate to the user):** ~21% of long agentic-coding sessions end in a fallback
to Opus 4.8 (Terminal-Bench 2.1, p. 255); reverse-engineering binaries is blocked
entirely; biological images degrade because of the classifiers. If such a task
arrives in the sonnet-only configuration — it is a limitation of the experiment;
record it and escalate.

---

## Why keep Opus 4.8 in mind (not an executor in this configuration)

Reference numbers for evaluating the experiment — what exactly was lost by
removing Opus:
- Honesty about code: 0.00 misreported rate, 3.7% omissions in summaries, 0.00
  fell-for-trap (Opus 4.8 card, pp. 124–128). In sonnet-only this is compensated
  only by the orchestrator's personal verification by running things.
- Long-horizon efficiency: 55–67 turns where Sonnet spends 183. Compensation —
  slicing into waves.
- Complexity ceiling: FrontierCode Diamond 13.4 for Opus vs. 5.7 for GPT-5.5 —
  the class of tasks where Sonnet plateaus. Compensation — finer decomposition by
  the orchestrator; if it doesn't converge within 3 iterations, that is a signal
  against the sonnet-only configuration — record it in the summary.
