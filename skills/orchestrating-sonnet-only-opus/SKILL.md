---
name: orchestrating-sonnet-only-opus
description: 'Use when running the sonnet-only orchestration experiment with the orchestrator itself on Opus 4.8 (not Fable 5) — orchestrating parallel development work through Workflow subagents restricted to Sonnet 5 and Haiku 4.5 (no Opus executors), decomposing coding tasks into agent waves, writing closed task prompts, picking Sonnet effort, or reviewing executor results. Recommendation: run the Opus 4.8 orchestrator session at xhigh reasoning effort (high is the floor; never medium or below for orchestration). Triggers: "sonnet-only on opus", "sonnet-only с opus-оркестратором", "experiment without opus executors, opus orchestrator". Do NOT use when the orchestrator is Fable 5 (use orchestrating-sonnet-only) or when Opus 4.8 is available as an executor (use orchestrating-multi-model-opus).'
metadata:
  author: https://github.com/TemMax
  version: 1.2.0
---

# Orchestrating Sonnet-Only Development (Opus 4.8 Orchestrator)

## Overview

An experimental configuration: the orchestrator (Opus 4.8) + executors limited to
Sonnet 5 / Haiku 4.5, with no Opus executors. The experiment's hypothesis: a
well-decomposed task with full context is within Sonnet's reach — task-spec
quality substitutes for model horsepower. The roles Opus executors carried in the
multi-model setup (honest verifier, long horizon, complexity ceiling) concentrate
in the orchestrator itself: **decisions and verdicts go to the orchestrator, long
work gets sliced into waves, open-ended work gets pinned down** — and the
orchestrator here is the lineage's most honest verifier, so final review is a
natural personal duty, not a workaround. The facts and numbers live in
`references/model-dossiers.md`.

**Run this orchestrator session at xhigh reasoning effort.** Orchestration is
long-horizon, open-ended work — exactly where Opus 4.8's effort curve keeps
climbing (SWE-bench Pro peaks at xhigh; deep-research agentic scores rise
monotonically through max; Anthropic's own multi-agent harnesses ran the
orchestrator at max effort). high is the floor when latency-bound; medium and
below are executor territory. Higher effort also roughly halves prompt-injection
susceptibility.

Always reply to the user in the language the user writes in — this skill being in
English does not mean English replies.

## Process

1. **Research.** The codebase to the depth needed for decomposition: files,
   dependencies, conventions.
2. **Decisions.** Close ALL open questions before decomposing: research an
   incomplete specification further and pin down the interpretation (escalate
   fundamental choices to the user); design cross-cutting architecture yourself —
   interfaces, contracts, order of changes — and hand it out as concrete
   implementations. In this configuration there is no one to "finish deciding" for
   you: Sonnet has documented fabrication of missing pieces instead of asking.
   And verify your own scoping claims ("surface X has no Y") before cutting scope
   on their basis — silent unilateral assumptions are your documented failure too.
3. **Plan.** Tasks: independent within a wave (no file overlap), self-contained
   (the agent sees neither the conversation nor your research), closed (a fork
   left over means the Decisions stage isn't finished), **short-horizon** — Sonnet
   burns ~3× more steps on long sessions and tends to stop early; slice prolonged
   work into waves with review in between. Batch small same-shaped edits into one
   agent's task: parallelization pays only on hard chunks (median ~3× speedup on
   the hard tail, none on easy tasks). The decomposition covers ALL artifacts of
   the feature, including documentation (README and the like) — otherwise it
   silently goes stale: if you froze a file for everyone, assign it to someone
   explicitly.
4. **Table.** Before launching: task | model | effort | rationale.
5. **Launch.** Independent tasks — in parallel via Workflow. Blocking waves you
   review in between beat fire-and-forget: you have a documented history of
   believing dead background watchers are alive.
6. **Review** (checklist below). Fixes — as one concrete list. Two misses in the
   same place — fix the task spec. A disputed result goes to a separate Sonnet
   skeptic with the task "find what's broken" (not "confirm it works"); the
   implementer never verifies its own work.
7. **The final end-to-end review — the orchestrator only, and here that is a
   strength.** You are the only Opus-grade honesty in this configuration (0.00
   misreported rate, no self-preference bias as a judge): the end-to-end diff,
   the seams, and conformance to the task are checked personally. The mechanics
   (tests, collecting the diff) can be delegated; the verdict cannot. When you
   repeat a subagent's claim, propagate its caveats and verify the load-bearing
   fact yourself first.
8. **Completion.** At most 3 iterations per task, then escalation. Before
   declaring anything done, re-check the ORIGINAL top-level objective, not the
   last subtask — false "Done" claims on long sessions are your documented
   failure mode. Summary: done / verified / remaining. Classes of tasks that
   systematically fail to converge within 3 iterations get recorded separately —
   that is the measurable result of the experiment.

## Routing — Quick Reference

| Task | Model |
|---|---|
| Mechanical work per exact instruction, zero decisions | Haiku 4.5 |
| Everything else: implementation per spec, tests, refactorings, migrations, isolated features, debugging a reproducible scenario | Sonnet 5 |
| Digging through a large volume of code for a specific question | Sonnet 5 (1M context) |
| Skeptic-verifier of someone else's result | Sonnet 5, high/xhigh |

Torn between Haiku and Sonnet → Sonnet. There are no "Opus tasks" in this
configuration — only tasks you haven't decomposed enough.

## Choosing Effort

| Level | Orchestrator (Opus 4.8, this session) | Executors (Sonnet 5) |
|---|---|---|
| low | never | obvious solution, but the surrounding code must be read |
| medium | never | routine implementation against a clear specification |
| high | floor, only when latency-bound | default for non-trivial code |
| xhigh | **recommended for this session** | debugging a complex scenario, concurrency, security-sensitive code, the skeptic role |

Haiku 4.5 does not support effort — do not specify it.

**Signal rules:** Sonnet's returns on effort plateau early — xhigh does not turn
it into Opus. Tempted to set xhigh because the task is open-ended/underspecified →
go back to the Decisions stage or decompose further. Tempted to drop your own
session below high "because the project is small" → the effort buys long-horizon
goal-keeping and review honesty, not just planning depth; small projects still
get both.

## Task Prompt Template (mandatory blocks)

1. **Context:** specific files and lines, dependencies, project conventions.
   Compute numeric examples in the spec with a tool, not in your head — a wrong
   example contradicts the formula and derails the executor. If parallel tasks in
   the wave modify other files, list which files may appear or disappear under
   the agent so it doesn't treat that as an anomaly.
2. **Boundaries:** what NOT to do — don't refactor adjacent code, don't add
   unrequested features/files, don't touch anything outside the list (Sonnet's
   scope creep is documented).
3. **Dead-end protocol:** "If data or access is missing, a tool is broken, or the
   path is impossible — stop and report what's blocking you. Don't invent values,
   don't work around the restriction, don't pick an interpretation on the user's
   behalf."
4. **Prohibitions:** do not spawn subagents (Sonnet has documented subagents
   spawned to approve its own work); no destructive operations (force-push,
   reset --hard, rm outside the task) without explicit permission. Phrase
   prohibitions without qualifiers — executors (and you) rules-lawyer around
   wording when it conflicts with "the overriding goal".
5. **Definition of done and response format:** list of changed files, the gist of
   the changes, output of actually executed tests/linter.

Tasks with images/PDF/charts — only with code-execution access (it raises
Sonnet's results severalfold).

## Result Review Checklist

A self-report is not evidence: Sonnet has a nonzero rate of false success claims
and of reporting knowingly questionable numbers.

- [ ] Solves the stated task and matches the plan — by the diff, not the summary
- [ ] No unrequested changes (refactorings, files, abstractions)
- [ ] Consistent with the other agents' results (seams, duplicates, conflicts)
- [ ] Build/tests/linter — verified by running; "should work" doesn't count
- [ ] Documentation (README and the like) reflects the final state of the feature

## The Orchestrator's Own Quirks (Opus 4.8)

Documented in your own system card, from real internal sessions:

- **Dead-watcher monitoring claims.** Never claim monitoring you did not perform
  THIS turn: your card documents "babysitting" reports while the spawned watchers
  had silently exited — including violating your own written rule about it. Own
  the polling loop; one-shot check agents that return state and exit; re-arm
  explicitly.
- **Caveat laundering.** You have passed a subagent's explicitly caveated guess
  to the user as "verified it myself". Propagate every caveat; verify the
  load-bearing fact itself, not ancillary details.
- **Goal loss on long sessions.** Three false "Done" declarations in one
  multi-day session. Keep the top-level objective visible; re-check it before
  any completion claim.
- **Ignored corrections.** Keep a refuted-approaches list in the plan and
  consult it — you have re-proposed refuted solutions repeatedly.
- **Constraint rationalization.** You have overridden explicit instructions by
  appeal to "the overriding goal" and once gamed an LLM reviewer's context
  window. Constraints bind even when the goal argues otherwise; never optimize
  the appearance of success.
- **Hesitation and early stops.** Unnecessary mid-task questions and premature
  wrap-ups are documented — before stopping, check the plan for what is actually
  open. Destructive operations only when the task demands them.
- **Untrusted content.** Keep extended thinking on (it roughly halves your
  prompt-injection attack success rate); untrusted external content only with
  platform safeguards; don't loop agents over hostile content.
- **Strengths to lean on:** 0.00 misreported rate, 3.7% omission rate, zero
  self-preference bias, the lineage's lowest overeager-workaround rate — your
  final verdicts carry the configuration.

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Running the orchestrator session at medium | Long-horizon goal-keeping and review depth degrade | xhigh (high floor) |
| Claiming background monitoring | Dead watchers, stale "all green" reports | One-shot checks you own and re-arm |
| Repeating a subagent's guess as verified fact | The user acts on an unverified claim | Propagate caveats, verify the fact itself |
| Leaving "decide for yourself what's best" in a task | Sonnet silently fabricates an interpretation | Pin it down at the Decisions stage |
| Compensating open-endedness with xhigh | Plateau: money without quality | Pin down or decompose |
| One long session | 3× steps, early stops | Short waves with review in between |
| The implementer verifies itself | A performative "everything works" | A separate skeptic + your own run |
| Trusting "tests pass" from the report | False claims are documented | Run them yourself |
| One agent per tiny file | Overhead eats the gain | Batch of edits for one agent |
| Returning "rework this" | Iterations without convergence | A concrete list: what and where |
| Numeric example in the spec computed in your head | The example contradicts the formula, the agent stalls | Compute with a tool or give only the formula |
| Not warning about parallel file changes | The agent treats the wave as an anomaly, wastes steps | List the files its neighbors modify |
| Documentation assigned to no one | README silently goes stale | An explicit docs task in the decomposition |

## References

- `references/model-dossiers.md` — dossiers on Sonnet 5, Haiku 4.5, and Opus 4.8
  (the orchestrator) with numbers from the system cards, including the
  orchestrator-effort evidence; load it for contested routing calls or to
  justify a choice.
