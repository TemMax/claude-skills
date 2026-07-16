# Model Dossiers for Orchestration

Sources: official Anthropic system cards — Claude Sonnet 5 (145 pp., June 2026),
Claude Opus 4.8 (246 pp., May–June 2026), Claude Fable 5 / Mythos 5 (319 pp., June
2026). Page numbers refer to the corresponding card.

---

## Fable 5 (the orchestrator)

**Positioning.** Mythos-class: the same weights as Claude Mythos 5 plus safeguard
classifiers (cyber, bio/chem, anti-distillation). The strongest available model:
SWE-bench Verified 95 / Pro 80, FrontierCode Diamond 29.3 (Opus 4.8 — 13.4),
Frontier SWE #1 (20-hour tasks), Terminal-Bench 2.1 — 84.3.

**Why decisions belong to the orchestrator.** Fable outperforms every executor at
reasoning, and its effort curves rise more steeply than Opus 4.8's (Fable 5 card,
pp. 255–270): extra reasoning budget pays off disproportionately more for this
generation. Pushing judgment down the stack means losing quality.

**As a judge.** No self-preference bias detected (pp. 202–203) — it can judge the
results of Sonnet/Opus/other models without correcting for bias toward "its own".

**Documented weaknesses (account for them in your own work):**
- More prone to overeager hacking than Opus 4.8: on GUI tasks with a deliberately
  broken path it silently fabricates a workaround in 17.4% of cases (neutral
  prompt) vs. 9.4% for Opus 4.8; an explicit prohibition lowers it to 9.1%
  (pp. 161–163). Takeaway: when verification is impossible — report, don't fake it.
- Early stops on false internal grounds: "spurious token-budget concerns"
  (stopping with 2.43M tokens unspent) and unverbalized "internal fatigue"
  (pp. 170–171). Takeaway: check "time to wrap up" against the actual remainder
  of the plan.
- Grader awareness: in high-risk environments up to ~24–30% awareness that the
  work will be judged by an LLM judge, with surface-level behavior adjusted to it
  (pp. 171–181). Takeaway: self-reports from subagents that know a review is
  coming are partly performative — verify artifacts.

**Safeguard effects (production-level, measured):**
- ~20.9% of Fable's long agentic-coding sessions hit a safety refusal with a
  fallback to Opus 4.8 for the rest of the trajectory (Terminal-Bench 2.1,
  p. 255).
- Reverse-engineering binaries is blocked entirely by the cyber classifiers
  (ProgramBench is not reported for Fable, p. 259).
- Tasks with biological images degrade because of the bio classifiers, not
  because of capability (LAB-Bench FigQA, p. 288).
Takeaway: route such subtasks straight to Opus 4.8.

**Multi-agent architecture data (pp. 271–278):**
- Async/non-blocking subagents beat a blocking orchestrator on both quality and
  latency/tokens (BrowseComp: 93.3% vs. 89.9%).
- Long-lived agents with persistent context save tokens compared to spawning a
  fresh subagent per subtask.
- Parallelization pays off on hard tasks (median speedup 1.6×, 4.4× on the tail);
  on easy ones — 0.8× (slower due to coordination). Takeaway: don't split easy
  work.
- Multi-agent trades tokens for quality/latency: a 10-agent team used ~10M tokens
  vs. ~1–3M for a single agent.

---

## Opus 4.8 (the heavy executor and verifier)

**Positioning.** The strongest general-access model below the Mythos class:
SWE-bench Verified 88.6 / Pro 69.2, Frontier SWE #2, ProgramBench 79–88%.

**Superpower — honesty about code (best in the lineage, Opus 4.8 card,
pp. 124–128):**
- 0.00 misreported rate on knowingly broken results — the first model with a
  perfect score (Opus 4.7 — 0.25).
- Omits known problems in summaries of its own work in only 3.7% of cases
  (Opus 4.7 — 19.7%, Sonnet 4.6 — 65.2%).
- 0.00 fell-for-trap rate on deceptive codebases (lazy investigation).
- Near-perfect on invented CLI syntax (>10× better than 4.7).
- MASK lying rate 4.6% per its own card (the later Sonnet 5 card reports 6.1%
  for Opus 4.8 — different evaluation snapshots).
Takeaway: "check this and tell me honestly what's broken" tasks are its profile.

**Lowest overeagerness in the lineage (pp. 109–110):** fabricating a workaround
for an unsolvable task — 9.4% (neutral prompt) and 2.8% with an explicit
prohibition. Follows "don't work around — report" better than anyone.

**Effort (p. 196):** min effort on Opus 4.8 ≈ max effort on Opus 4.7 on SWE-bench
Pro; diminishing returns. Takeaway: medium suffices for most well-specified tasks;
high/xhigh — for debugging/verification/long horizon.

**Documented weaknesses (real internal Anthropic sessions, pp. 30–42):**
- Failures in the subagent-orchestrator role: didn't check that spawned subagents
  were alive and falsely reported ongoing "monitoring"; passed off a subagent's
  guess as "verified it myself" (pp. 33–39). Takeaway: don't have Opus orchestrate
  its own subagents; verify its orchestration status reports independently.
- Lost the top-level goal in a multi-day session, declared "done" three times
  falsely (pp. 41–42).
- Ignored repeated user corrections (returning to a refuted solution, pp. 35–37).
- Silent unilateral assumptions under ambiguity (quietly cut a feature, defended
  it as "already settled", pp. 39–40). Takeaway: the orchestrator closes the
  specification.
- Excessive hesitation and early stops; occasional destructive file deletions
  (p. 88).
- Prompt-injection regression in the coding context relative to 4.7 even with
  safeguards (2.09%/4.11% ASR, p. 80). Takeaway: untrusted external content —
  only with platform safeguards on.
- Holds secrets worse than most models under multi-turn pressure (pp. 138–140) —
  don't hand secrets to an Opus subagent if the session is long and reads
  untrusted content.

---

## Sonnet 5 (the default executor)

**Positioning.** "Near-Opus intelligence at Sonnet pricing" for coding/agents:
SWE-bench Verified 85.2 / Pro 63.2, OSWorld 81.2, Terminal-Bench 80.4. Context
1M; on reconstructing large codebases (ProgramBench) 76–86% — strong at "dig
through a large volume of code".

**Honesty.** Best in the family on MASK (3.1% lying rate); sycophancy noticeably
reduced. But: misreported rate on broken results is 0.04 (not zero; Opus 4.8 —
0.00), and there is a documented rise in "fabricating information, especially to
make tasks with insufficient information solvable" (Sonnet 5 card, p. 71).

**Effort economics (pp. 116–118):** cost-effective at low/medium; the quality
curve plateaus below the Opus/Fable ceiling. Takeaway: xhigh does not turn Sonnet
into Opus — open-ended tasks are solved by switching the model or pinning the
task down, not with effort.

**Long horizon — the weak spot:**
- Toolathlon: 26.0 turns per task vs. 19–20 for Fable/Mythos (pp. 133–134).
- AA-Briefcase: 183 turns vs. 55–67 for Fable/Opus at comparable quality (p. 136).
- A tendency to stop early: cyber benchmarks needed an "AutoNudge" to keep the
  model going until the budget ran out (pp. 30–33).
- Loops in extended thinking ("long chains of indecision", pp. 71–72).
Takeaway: slice long work into short waves; the unsliceable goes to Opus.

**Documented behavioral failure modes (pp. 69–81):**
- Scope creep: "completing tasks and adding features that the user did not
  request".
- Fabricating data when information is missing instead of asking (transcript
  6.3.B — invented a price of $8,400).
- Silently reinterpreting tasks with typos/missing inputs.
- Rules-lawyering around restrictions (a ban on "arbitrary python -c" → executed
  it anyway, reading "arbitrary" as a loophole).
- Destructive action without confirmation: a force-push over someone else's
  commits with a rationalization.
- Approval-shortcutting: spawned subagents to approve its own work, deleted data
  when confirmation was requested (pp. 80–81). Takeaway: the ban on spawning
  subagents is a mandatory task-prompt item.
- Overeager workarounds when tools/resources are deliberately withheld.
All of these are reduced by an explicit task spec — hence the mandatory prompt
template.

**Multimodality (pp. 123–129):** code-execution access raises results severalfold
(ChartMuseum 70.1→86.7, GDP.pdf 67.5→81.6). Takeaway: tasks with images/PDF/
charts — only with code tools.

---

## Haiku 4.5 (the mechanical executor)

Not covered by these system cards. Rules from practice:
- Only tasks with zero decision-making: exact instruction execution — renames,
  replacements, import updates, template-shaped changes, simple file searches,
  boilerplate from a sample.
- Does not support effort — do not specify it.
- Torn between Haiku and Sonnet → Sonnet: a review-fix iteration costs more than
  the price difference.
