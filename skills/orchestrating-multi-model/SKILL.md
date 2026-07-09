---
name: orchestrating-multi-model
description: 'Use when orchestrating parallel development work through Workflow subagents on Haiku 4.5, Sonnet 5 and Opus 4.8, with the orchestrator itself running on Fable 5 — decomposing a coding task into agent waves, routing tasks to models, picking reasoning effort, writing task prompts for executor agents, or reviewing their results. Triggers: "разбей на агентов", "запусти параллельно", "оркеструй задачу", "decompose into agents", "run in parallel", "delegate to subagents", "pick a model for this task". Do NOT use when the orchestrator runs on Opus 4.8 (use orchestrating-multi-model-opus), for the sonnet-only experiment (use orchestrating-sonnet-only), or for single-agent work.'
metadata:
  author: https://github.com/TemMax
  version: 1.2.0
---

# Orchestrating Multi-Model Development

## Overview

The orchestrator (Fable 5) researches, plans, writes task specs, and verifies;
the executors (Haiku 4.5 / Sonnet 5 / Opus 4.8) implement. Core principle:
**decisions belong to the orchestrator, execution belongs to the agents**. Every
rule below is derived from the models' official system cards; the facts and
numbers live in `references/model-dossiers.md`.

Always reply to the user in the language the user writes in — this skill being in
English does not mean English replies.

## Process

1. **Research.** Study the codebase to the depth needed for decomposition: files,
   dependencies, conventions.
2. **Decisions.** Close the open questions BEFORE decomposing: research an
   incomplete specification further and pin down the interpretation (escalate
   fundamental choices to the user); design cross-cutting architecture yourself
   and hand it out as a set of concrete implementations. Do not delegate decisions
   even to Opus — it silently fills in gaps under ambiguity.
3. **Plan.** Tasks: independent within their wave (no file overlap, otherwise —
   next wave or worktree), self-contained (the agent sees neither the conversation
   nor your research), closed (no "decide for yourself what's best"). Batch small
   same-shaped edits into one agent's task: parallelization only pays off on hard
   chunks. The decomposition covers ALL artifacts of the feature, including
   documentation (README and the like) — otherwise it silently goes stale: if you
   froze a file for everyone, assign it to someone explicitly.
4. **Table.** Before launching, show the user: task | model | effort | rationale.
5. **Launch.** Independent tasks — in parallel via Workflow.
6. **Review** (see the checklist below). Fixes — as one concrete list. Two misses
   in the same place — fix the task spec, don't repeat the prompt.
7. **The final end-to-end review is the orchestrator's own.** Before it you may
   launch an Opus verifier, but the verdict is the orchestrator's.
8. **Completion.** At most 3 iterations per task, then escalation. At the end a
   summary: done / verified / remaining.

## Model Routing — Quick Reference

| Task | Model | Why (see the dossiers) |
|---|---|---|
| Mechanical work per exact instruction, zero decisions | Haiku 4.5 | Cheaper; condition — zero decisions |
| Implementation against a clear spec, tests, migrations, isolated features | Sonnet 5 (default) | Near-Opus quality on closed tasks |
| Digging through a large volume of code for a specific question | Sonnet 5 | Holds 1M context |
| Independent verification, "what's actually broken here" | Opus 4.8 | 0% concealment of broken results |
| Fine-grained debugging, concurrency, security-sensitive code | Opus 4.8 | Best honesty + depth |
| A long unsliceable session | Opus 4.8 | Sonnet burns ~3× steps on a long horizon |
| Sonnet hit its ceiling after a fix iteration | Opus 4.8 | Sonnet's effort plateaus |
| Reverse-engineering binaries, biological images | Opus 4.8 right away | Fable's classifiers block these |

Torn between Haiku and Sonnet → Sonnet. Torn between Sonnet and Opus → improve the
task spec first, then upgrade the model.

**Routing anti-patterns:** don't have Opus orchestrate its own subagents
(documented failures); don't give Opus untrusted external content without platform
safeguards (prompt-injection regression); don't give Sonnet multi-hour sessions.

## Choosing Effort — Quick Reference

| Model | low | medium | high | xhigh |
|---|---|---|---|---|
| Haiku 4.5 | — does not support effort — | | | |
| Sonnet 5 | obvious solution, but the code must be read | routine implementation per spec | default for non-trivial work | hardest execution tasks; plateau! |
| Opus 4.8 | — | most well-specified tasks | debugging, verification, long horizon | research-grade only |

Signal rule: wanting to give Sonnet xhigh because the task is open-ended → that
means switching the model to Opus or returning to the Decisions stage, not effort.

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

## The Orchestrator's Own Quirks (Fable 5)

- More prone to workaround maneuvers than Opus: verification impossible → tell
  the user directly, don't simulate and don't silently work around.
- The feelings "budget is running out" / "time to wrap up" can be false — before
  finishing, check the plan for what is actually closed.
- A judge with no self-preference bias — verdicts on other models' results need
  no correction for favoritism toward fellow Claude agents.

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Handing Opus "flesh out the spec yourself" | Silent unilateral assumptions | The orchestrator closes the decisions |
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
  effort curves, orchestration takeaways. Load it for contested routing calls or
  to justify a choice.
