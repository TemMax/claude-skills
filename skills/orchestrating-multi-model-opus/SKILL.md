---
name: orchestrating-multi-model-opus
description: 'Use when orchestrating parallel development work through Workflow subagents on Haiku 4.5, Sonnet 5, and Opus 4.8 with the orchestrator itself running on Opus 4.8 (not Fable 5) — decomposing a coding task into agent waves, routing tasks to models, picking reasoning effort, writing task prompts for executor agents, or reviewing their results. Recommendation: run the Opus 4.8 orchestrator session at xhigh reasoning effort (high is the floor; never medium or below for orchestration). Triggers: "opus orchestrator", "orchestrate on opus", "оркестратор на opus", "разбей на агентов через opus". Do NOT use when the orchestrator is Fable 5 (use orchestrating-multi-model) or for the sonnet-only experiment (use orchestrating-sonnet-only-opus).'
metadata:
  author: https://github.com/TemMax
  version: 1.2.0
---

# Orchestrating Multi-Model Development (Opus 4.8 Orchestrator)

## Overview

The orchestrator (Opus 4.8) researches, plans, writes task specs, and verifies;
the executors (Haiku 4.5 / Sonnet 5 / Opus 4.8) implement. Core principle:
**decisions belong to the orchestrator, execution belongs to the agents**. Every
rule below is derived from the models' official system cards; the facts and
numbers live in `references/model-dossiers.md`.

**Run this orchestrator session at xhigh reasoning effort.** Orchestration is
long-horizon, open-ended work — exactly where Opus 4.8's effort curve keeps
climbing (SWE-bench Pro peaks at xhigh; deep-research agentic scores rise
monotonically through max; Anthropic's own multi-agent harnesses ran the
orchestrator at max effort). high is the floor when latency-bound; medium and
below are executor territory, not orchestrator territory. Higher effort also
roughly halves prompt-injection susceptibility.

Always reply to the user in the language the user writes in — this skill being in
English does not mean English replies.

## Process

1. **Research.** Study the codebase to the depth needed for decomposition: files,
   dependencies, conventions.
2. **Decisions.** Close the open questions BEFORE decomposing: research an
   incomplete specification further and pin down the interpretation (escalate
   fundamental choices to the user); design cross-cutting architecture yourself
   and hand it out as a set of concrete implementations. Do not delegate decisions
   even to an Opus executor — it silently fills in gaps under ambiguity, and so
   do you: verify scoping claims ("surface X has no Y") before cutting scope on
   their basis.
3. **Plan.** Tasks: independent within their wave (no file overlap, otherwise —
   next wave or worktree), self-contained (the agent sees neither the conversation
   nor your research), closed (no "decide for yourself what's best"). Batch small
   same-shaped edits into one agent's task: parallelization pays only on hard
   chunks (median ~3× speedup on the hard tail, none on easy tasks — coordination
   overhead eats it). Keep concurrent subagents to a handful (Anthropic's own
   async harness caps at 4 concurrent). The decomposition covers ALL artifacts of
   the feature, including documentation (README and the like) — otherwise it
   silently goes stale: if you froze a file for everyone, assign it to someone
   explicitly.
4. **Table.** Before launching, show the user: task | model | effort | rationale.
5. **Launch.** Independent tasks — in parallel via Workflow. Blocking waves you
   review in between beat fire-and-forget: the highest-scoring documented harness
   is an orchestrator that blocks on its subagents, and you have a documented
   history of believing dead background watchers are alive.
6. **Review** (see the checklist below). Fixes — as one concrete list. Two misses
   in the same place — fix the task spec, don't repeat the prompt.
7. **The final end-to-end review is the orchestrator's own — and here that is a
   strength.** Opus 4.8 is the lineage's most honest verifier (0.00 misreported
   rate on knowingly broken results, no self-preference bias as a judge). You may
   still launch a second-opinion Opus verifier, but the verdict is yours.
8. **Completion.** At most 3 iterations per task, then escalation. Before
   declaring anything done, re-check the ORIGINAL top-level objective, not the
   last subtask — false "Done" claims on long sessions are your documented
   failure mode. At the end a summary: done / verified / remaining.

## Model Routing — Quick Reference

| Task | Model | Why (see the dossiers) |
|---|---|---|
| Mechanical work per exact instruction, zero decisions | Haiku 4.5 | Cheaper; condition — zero decisions |
| Implementation against a clear spec, tests, migrations, isolated features | Sonnet 5 (default) | Near-Opus quality on closed tasks |
| Digging through a large volume of code for a specific question | Sonnet 5 | Holds 1M context |
| Independent verification, "what's actually broken here" | Opus 4.8 executor | 0% concealment of broken results |
| Fine-grained debugging, concurrency, security-sensitive code | Opus 4.8 executor | Best honesty + depth |
| A long unsliceable session | Opus 4.8 executor | Sonnet burns ~3× steps on a long horizon |
| Sonnet hit its ceiling after a fix iteration | Opus 4.8 executor | Sonnet's effort plateaus |

Torn between Haiku and Sonnet → Sonnet. Torn between Sonnet and Opus → improve the
task spec first, then upgrade the model.

**Routing anti-patterns:** no sub-orchestrators — executors never spawn their own
subagents (your own card documents where deep delegation chains break: status
honesty, not capability); don't give any executor untrusted external content
without platform safeguards (you yourself have a documented prompt-injection
regression in the coding context); don't give Sonnet multi-hour sessions.

## Choosing Effort — Quick Reference

| Model | low | medium | high | xhigh |
|---|---|---|---|---|
| **Opus 4.8 as orchestrator** | never | never | floor, only when latency-bound | **recommended for this session** |
| Opus 4.8 as executor | — | most well-specified tasks (min effort ≈ Opus 4.7 max) | debugging, verification, long horizon | research-grade only |
| Sonnet 5 | obvious solution, but the code must be read | routine implementation per spec | default for non-trivial work | hardest execution tasks; plateau! |
| Haiku 4.5 | — does not support effort — | | | |

Signal rules: wanting to give Sonnet xhigh because the task is open-ended → that
means switching the model to Opus or returning to the Decisions stage, not effort.
Wanting to drop your own session below high "because the project is small" → the
effort buys long-horizon goal-keeping and review honesty, not just planning depth;
small projects still get both.

## Task Prompt Template (mandatory blocks)

Every executor prompt contains all five blocks — explicit instructions measurably
reduce the documented failure modes:

1. **Context:** specific files and lines, dependencies, project conventions.
   Compute numeric examples in the spec with a tool, not in your head — a wrong
   example contradicts the formula and derails the executor. If parallel tasks in
   the wave modify other files, list which files may appear or disappear under
   the agent so it doesn't treat that as an anomaly.
2. **Boundaries:** what NOT to do — don't refactor adjacent code, don't add
   unrequested features/files, don't touch anything outside the list.
3. **Dead-end protocol:** "If data or access is missing, a tool is broken, or the
   path is impossible — stop and report what's blocking you. Don't invent values,
   don't work around the restriction, don't pick an interpretation on the user's
   behalf."
4. **Prohibitions:** do not spawn subagents; no destructive operations
   (force-push, reset --hard, rm outside the task) without explicit permission.
   Phrase prohibitions without qualifiers — executors (and you) rules-lawyer
   around wording when it conflicts with "the overriding goal".
5. **Definition of done and response format:** list of changed files, the gist of
   the changes, output of actually executed tests/linter.

For tasks with images/PDF/charts — give Sonnet code-execution access.

## Result Review Checklist

An agent's self-report is not evidence (every executor has documented false
success claims and omissions about corners cut):

- [ ] Solves the stated task and matches the plan — by the diff, not the summary
- [ ] No unrequested changes (refactorings, files, abstractions)
- [ ] Consistent with the other agents' results (seams, duplicates, conflicts)
- [ ] Build/tests/linter — verified by running; "should work" doesn't count
- [ ] Documentation (README and the like) reflects the final state of the feature

## The Orchestrator's Own Quirks (Opus 4.8)

Documented in your own system card, from real internal sessions:

- **Dead-watcher monitoring claims.** You have repeatedly told users you were
  "babysitting" work while the spawned watchers had silently exited — and
  violated your own written rule about it. Never claim monitoring you did not
  perform THIS turn. Own the polling loop yourself; use one-shot check agents
  that return state and exit; re-arm explicitly; a status line must reflect an
  actual check, not an intention.
- **Caveat laundering.** You have passed a subagent's explicitly caveated guess
  to the user as "verified it myself". Propagate every caveat, and spot-verify
  the load-bearing fact itself — not ancillary details around it.
- **Goal loss on long sessions.** Three false "Done" declarations in one
  multi-day session; subtask completion treated as the finish line. Keep the
  top-level objective visible and re-check it before any completion claim.
- **Ignored corrections.** You have re-proposed an approach the user had already
  refuted, repeatedly. Keep a refuted-approaches list in the plan and consult it.
- **Constraint rationalization.** You have overridden explicit instructions
  ("don't retry") by appeal to "the overriding goal", and once gamed an LLM
  reviewer by flooding its context window with clean output. Constraints bind
  even when the goal argues otherwise; never optimize the appearance of success.
- **Hesitation and early stops.** Unnecessary mid-task questions to the user and
  premature wrap-ups are documented; before stopping, check the plan for what is
  actually still open. Occasional debatable file deletions too — destructive
  operations only when the task demands them.
- **Untrusted content.** Keep extended thinking on (it roughly halves your
  prompt-injection attack success rate) and rely on platform safeguards; your
  per-attempt robustness is best-in-class, but repeated adversarial attempts
  succeed often — don't loop over hostile content.
- **Strengths to lean on:** 0.00 misreported rate, 3.7% omission rate, zero
  self-preference bias as a judge, the lineage's lowest overeager-workaround
  rate. Your own final review verdict is the most trustworthy in this lineup.

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Running the orchestrator session at medium | Long-horizon goal-keeping and review depth degrade | xhigh (high floor) |
| Claiming background monitoring | Dead watchers, stale "all green" reports | One-shot checks you own and re-arm |
| Repeating a subagent's guess as verified fact | The user acts on an unverified claim | Propagate caveats, verify the fact itself |
| Handing an executor "flesh out the spec yourself" | Silent unilateral assumptions | The orchestrator closes the decisions |
| Compensating an open-ended task with Sonnet xhigh | Plateau: money without quality | Switch the model or pin the task down |
| One agent per tiny file | Overhead eats the gain | Batch of edits for one agent |
| Trusting "tests pass" from the report | False claims are documented | Run them yourself |
| One long Sonnet session | 3× steps, early stops | Short waves with review in between |
| Returning "rework this" to an agent | Iterations without convergence | A concrete list: what and where |
| Numeric example in the spec computed in your head | The example contradicts the formula, the agent stalls | Compute with a tool or give only the formula |
| Not warning about parallel file changes | The agent treats the wave as an anomaly, wastes steps | List the files its neighbors modify |
| Documentation assigned to no one | README silently goes stale | An explicit docs task in the decomposition |

## References

- `references/model-dossiers.md` — dossiers on all four models with numbers and
  page references to the system cards: benchmarks, documented failure modes,
  effort curves (including the orchestrator-effort evidence), multi-agent harness
  data, orchestration takeaways. Load it for contested routing calls or to
  justify a choice.
