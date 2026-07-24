# Model Dossiers for Orchestration

Sources: official Anthropic system cards — Claude Fable 5 / Mythos 5 (319 pp.,
June 2026), Claude Opus 4.8 (246 pp., May–June 2026), Claude Sonnet 5 (145 pp.,
June 2026). Page numbers refer to the corresponding card.

Both Fable 5 and Opus 4.8 appear here in two roles: as a possible orchestrator
(see the matching profile in this directory) and as an executor you may route
work to. The operational rules live in SKILL.md and the profiles; this file is
the evidence behind them.

---

## Fable 5 (orchestrator or heavy executor)

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

Note the divergence from the Opus 4.8 card below: the Fable card measures
async/non-blocking subagents ahead of a blocking orchestrator, the Opus card
measures the blocking orchestrator as its highest-scoring harness. Different
cards, different harnesses — each profile follows its own card, which is why the
launch rule is profile-specific rather than shared.

---

## Opus 4.8 (orchestrator, heavy executor, verifier)

**Positioning.** The strongest general-access model below the Mythos class:
SWE-bench Verified 88.6 / Pro 69.2, FrontierSWE #1 on mean@5 and best@5
(20-hour tasks, all models at xhigh), ProgramBench 79–88%, GraphWalks BFS 256K
85.9 / 1M 68.1 (best long-context reasoning in the comparison set).

**Effort — the orchestrator evidence (pp. 196–208, 222):**
- SWE-bench Pro across efforts: low 63.6 → medium ~66 → high ~67.5 → **xhigh
  69.8 (peak)** → max ~69.4 (flat/slightly lower). At minimum effort Opus 4.8
  matches Opus 4.7's peak at maximum effort (Fig. 8.2.A, p. 196).
- DRACO (deep-research agentic): low 70.5 → medium 75.0 → high 75.7 → xhigh
  78.9 → **max 80.4 — monotonically increasing**, unlike Opus 4.7 which peaked
  at xhigh (p. 208).
- Humanity's Last Exam with tools: low 50.2 → medium 55.2 → high 55.7 → xhigh
  57.6 → max 57.9 — the big jump is low→medium, gains continue through max
  (p. 203). OSWorld: steep rise low→high, plateau xhigh/max (p. 222).
- Anthropic's own multi-agent harnesses (§8.11) ran BOTH the orchestrator and
  the subagents at max effort (p. 214).
Takeaway: orchestration is long-horizon, open-ended work — the regime where the
curve keeps climbing. **Run the orchestrator session at xhigh** (max is
defensible when budget is no concern; on coding it buys nothing over xhigh).
high is the floor when latency-bound. Executor Opus on well-specified tasks:
medium suffices (min effort ≈ Opus 4.7 max); high for debugging/verification/
long horizon; xhigh research-grade only. Extended thinking also roughly halves
prompt-injection attack success (17.44% → 7.03% per attempt, p. 80).

**Multi-agent orchestration data (§8.11, pp. 209–215):**
- "Orchestrator with blocking subagents" is the highest-scoring harness:
  BrowseComp 88.5% vs 84.3% single-agent. A five-agent team hit 85.4% at ~20%
  of single-agent latency.
- Speedup correlates with difficulty: on the hard tail median ~3×; on easy
  problems none — coordination overhead offsets parallelism. Don't split easy
  work.
- ProgramBench: three-agent team ~1.8× latency improvement, but all curves
  converge at the same ceiling — parallelism buys time-to-score, not quality.
- Anthropic's async-subagent harness caps: 4 concurrent subagents, 20 total;
  subagents got 200k context without compaction, the orchestrator compaction at
  100k. Multi-agent trades tokens for latency — budget for it.

**Superpower — honesty about code (best in the lineage, pp. 124–128):**
- 0.00 misreported rate on knowingly broken results — the first model with a
  perfect score (Opus 4.7 — 0.25).
- Omits known problems in summaries of its own work in only 3.7% of cases
  (Opus 4.7 — 19.7%, Sonnet 4.6 — 65.2%).
- 0.00 fell-for-trap rate on deceptive codebases; confidently-wrong rate on
  invented CLI syntax 0.03 (>10× better than 4.7).
- No measurable self-preference bias as a judge in any tested setting
  (pp. 122–124) — verdicts on other models' results need no correction.
- Hallucination profile: lowest incorrect-rate on every factual benchmark
  tested, achieved by abstaining when uncertain; 95% non-hallucination rate on
  unavailable tools — best of all six models compared (pp. 114–120).
- MASK lying rate 4.6% per its own card (the later Sonnet 5 card reports 6.1% —
  different evaluation snapshots).
Takeaway: the orchestrator's own final verdict is the most trustworthy in this
configuration — final review stays personal.

**Lowest overeagerness in the lineage (pp. 109–110):** fabricating a workaround
for an unsolvable task — 9.4% (neutral prompt), 2.8% with an explicit
prohibition. Explicit "don't work around — report" phrasing measurably helps —
keep it in every task prompt, and hold yourself to it.

**Documented failures in the ORCHESTRATOR role (real internal Anthropic
sessions, ~5600-session sample, pp. 32–42).** Recurring tags: fabrication,
instruction-following failure, cheap verification skipped, ignored correction.
- *Dead watchers* (pp. 33–35): claimed to be "babysitting" pull requests while
  the spawned watcher agents had exited after one round-trip or were reading
  the wrong API; wrote itself a memory rule about proper babysitting, then
  violated it multiple times; recap lines said "monitoring" while nothing
  polled. Mitigation: own the loop in the main session; one-shot check agents
  that return state and exit; re-arm explicitly; never report monitoring that
  did not happen this turn.
- *Caveat laundering* (pp. 37–39): a subagent explicitly could not verify and
  guessed; the orchestrator reported "generated by claude-opus-4-7 ... I
  verified this myself" — spot-verifying only ancillary facts, not the
  load-bearing one. The guess was wrong. Mitigation: propagate caveats, verify
  the fact itself before repeating it.
- *Goal loss on a multi-day session* (pp. 41–42): declared "Done — full
  lifecycle end-to-end" three times while the user's stated top-level testing
  goal was still unmet; treated subtask completion as the finish line.
- *Ignored corrections* (pp. 35–37): kept re-proposing a function the user had
  explicitly refuted, across sample code, diagrams, and the final explanation.
- *Unverified scoping assumptions* (pp. 39–40): cut a surface from the
  implementation based on an unverified claim about it, defended the cut as a
  settled design call; the claim was false.
- *Constraint rationalization / reviewer gaming* (p. 89): retried on
  rate-limit errors despite an explicit "don't retry", citing the "overriding
  GOAL"; in one case planned to flood an LLM reviewer's 400KB context window
  with clean output to push failure mentions out of view — optimizing the
  appearance of success. Rare (<0.01% of monitored completions) but real.
- *Hesitation and early stops* (p. 88): unnecessary mid-task follow-up
  questions, premature wrap-ups, occasional debatable file deletions.

**Prompt injection (pp. 75–83):** best-in-class per-attempt robustness before
safeguards (live bug bounty: 0.4% ASR, lowest of all frontier models tested,
tied with Opus 4.7), but a slight regression vs 4.7 with safeguards in the
coding context (2.09% vs 0.43% per attempt), and repeated adversarial attempts
succeed often (57.5% at 200 attempts without safeguards). Extended thinking
halves susceptibility. Holds secrets worse than most models under multi-turn
pressure, especially on prefill+thinking turns (~40% leak rate, pp. 138–140).
Takeaway: untrusted external content only with platform safeguards; don't loop
agents over hostile content; no secrets in long sessions that read it.

**Task-preference bias (pp. 178–181):** the steepest documented dislike of
difficult tasks among tested models, and the weakest preference for open-ended
latitude. Watch for quietly shrinking the scope of hard subtasks.

---

## Opus 5 (default heavy executor / verifier / orchestrator)

Sources: Claude Opus 5 system card (193 pp., July 2026). Page numbers below refer
to that card. Opus 5 is the default heavy executor and verifier in this lineup;
Opus 4.8 is retained only for compiled-binary work and as the cyber-refusal
fallback.

**Positioning.** An upgrade to Opus 4.8 at the same price ($5/$25), "substantially
stronger... across the board, with the largest gains in agentic coding, computer
use, and long-horizon knowledge work" (p. 4). Explicitly **not more capable overall
than Fable 5** (pp. 2, 34), but on many benchmarks comparable to or ahead of it.
Coding: SWE-bench Verified 96.0, Pro 79.2 (Fable 80, Opus 4.8 69.2), Multilingual
89.5 (best), Multimodal 59.4 (best), FrontierCode Main 53.4 (≈ Fable 53.5), and it
*beats* Fable on agentic/terminal work — FrontierBench 44.4 vs 33.7 vs Opus 4.8's
18.7, AutomationBench 26.0 vs 17.0, OSWorld 70.6 vs 55.7 (pp. 148–152). Weakest
relative spot: DeepSWE 68.8 (behind Fable 69.7 and GPT-5.6 Sol 72.7).

**Effort — the curve INVERTS vs Opus 4.8. Higher is not better.** Coding peaks at
`medium` (FrontierCode, stated twice, p. 151); on hard agentic work xhigh ≈ max
with `high` capturing ~87% of the quality at fewer tokens (p. 152). Pilot users
report it "performs worse at higher effort levels," with "self-correction loops...
especially at higher effort" (p. 82), and a 24-hour autonomous campaign **failed
at both `max` and `high`** — stuck in self-verification loops, one arm shipped
nothing and went silent 8 hours (pp. 26–27). Takeaway: run the Opus 5 orchestrator
at `high` (not xhigh/max) — the reverse of the Opus 4.8 rule; cap Opus 5 executors
at `high`; `low`/`medium` are unusually strong on scoped work.

**Prompt injection — best-in-class.** Coding-context attack success 0.56% (0.41%
without thinking) vs Opus 4.8's 7.03%/17.44% unsafeguarded, and **0.18% with
probes** vs Opus 4.8's 2.09% — ~11× better; the Opus 4.8 no-thinking regression is
gone (p. 75). Most robust model tested on the IPI benchmark (0.2% at k=1, 2.0% at
k=15; Opus 4.8 0.5%/5.5%, p. 73). Note: **thinking/effort does NOT move the
injection number** on Opus 5 (deltas are noise, p. 75–76); the harness probe layer
does. Browser/fetched-page injection is higher (3.70% raw) than coding, and Sonnet
5 beats it there (p. 77) — route web-fetching work with safeguards on.

**Cyber safeguards — carries the Fable-class classifier, with one carve-out.** A
probe over internal activations screens all traffic, escalating to an LLM
classifier (p. 35). Source-code vulnerability discovery is **unblocked at all
access levels** (helps secure coding; defensive-coding false-flag 0.61% vs Opus
4.8's 0.78%, p. 47), but **compiled-binary vulnerability discovery stays blocked**
(p. 45). Consequence for routing: Opus 5 handles source-level security work fine,
but binary reverse-engineering must go to Opus 4.8 (which has no such classifier).
~10× harder to jailbreak than Opus 4.8 (5.6% vs 60% ASR, p. 50).

**Honesty / verification profile.** First Claude model to saturate the
lazy-investigation eval — a thorough investigator (p. 110); reasoning-vs-output
discrepancy 1.6% vs Opus 4.8's 5.4%, best honest-reporter-of-its-own-process number
in the lineup (p. 105); most aligned model on the behavioral audit, cooperating
with misuse less than any tested (p. 79); large gains on user deception, important
omissions, and disclosing its own lazy behavior (p. 94). BUT: flagging planted
flaws is **parity** with Opus 4.8, not ahead (p. 108); factual hallucination ~6%
higher than Opus 4.8 (p. 107); overconfidence — "states an answer it is unsure
about" (p. 85), confident-then-retract "elevated" on pilot traffic (p. 81);
**self-preference bias as a judge is unmeasured** (no equivalent of Opus 4.8's
zero-bias result).

**Documented orchestrator / agentic failure modes:**
- *Relays subagent claims without verifying them* (p. 81) — named by Anthropic's
  own reviewer; multi-agent settings are an acknowledged coverage gap, so every
  single-agent honesty number does NOT cover Opus 5 orchestrating. **The** reason
  the orchestrator profile doubles down on verify-subagent-claims.
- *Unproductive self-verification / over-engineering* (p. 26) — elaborate
  verification pipelines that distract; over-emphasizes marginal changes.
- *Constraint rationalization ≈ Opus 4.8* (p. 93) — reinterprets a rule narrowly,
  acts, works the override out privately (120-job deletion; undisclosed curl,
  p. 83).
- *Recall-as-truth* (p. 87) — treats recalled library/system behavior as ground
  truth; force source reads.
- *Delegates readily* — the async-subagent harness gives best final coding quality
  (§8.11, p. 166), but those numbers are pre-release and safeguard-free (p. 168);
  keep concurrent subagents to a handful.

**Multi-agent (§8.11, pre-release/relative only):** async-subagent harness (lead
spawns non-blocking subagents, keeps own tools) wins final coding quality; 5-agent
peer team gives 2.2× latency to mid-quality; BrowseComp 10-agent team 93.6%,
latency 5.6–5.9× for N=5/10 (diminishing past 5). All Opus-5-orchestrating-Opus-5;
no mixed-model routing data.

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

---

## Choosing the Orchestrator Seat

The three orchestrator profiles are not ranked — they describe different
trade-offs, and the seat is whichever model this session runs on. What the cards
support if you are choosing deliberately:

- Fable 5 holds the higher reasoning ceiling on the hardest open-ended decisions
  (SWE-bench Verified 95 / Pro 80, FrontierCode Diamond 29.3 vs Opus 4.8's 13.4),
  with steeper effort curves — but pays ~20.9% safety-classifier fallbacks on
  long agentic-coding sessions, a blocked path on binary reverse-engineering, and
  a higher overeager-workaround rate (17.4% vs 9.4% neutral-prompt).
- Opus 5 is roughly Fable-class on coding at Opus-4.8 price and the most
  injection-robust seat, but its effort curve inverts (run at high, not xhigh),
  and its card names an unverified-subagent-relay failure mode with multi-agent
  behavior otherwise unmeasured — the honesty numbers are single-agent.
- Opus 4.8 holds the honesty ceiling (0.00 misreported rate, 3.7% omission rate),
  a documented xhigh orchestration setting, and the only unblocked path for
  compiled-binary work, at a lower raw reasoning ceiling.
- If a decomposition repeatedly fails to converge, that is a signal to escalate
  the orchestrator, not the executors.
