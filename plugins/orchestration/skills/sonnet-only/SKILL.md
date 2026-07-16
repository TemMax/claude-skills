---
name: sonnet-only
description: 'Use when running the sonnet-only orchestration experiment with the orchestrator itself on Fable 5 — orchestrating parallel development work through Workflow subagents restricted to Sonnet 5 and Haiku 4.5 (no Opus executors), decomposing coding tasks into agent waves, writing closed task prompts, picking Sonnet effort, or reviewing executor results. Triggers: "sonnet-only", "эксперимент без opus", "разбей на sonnet-агентов", "experiment without opus", "decompose into sonnet agents". Do NOT use when the orchestrator runs on Opus 4.8 (use sonnet-only-opus) or when Opus 4.8 is available as an executor (use multi-model instead).'
metadata:
  author: https://github.com/TemMax
  version: 1.3.0
---

# Orchestrating Sonnet-Only Development

## Overview

An experimental configuration: the orchestrator (Fable 5) + executors limited to
Sonnet 5 / Haiku 4.5, with no Opus. The experiment's hypothesis: a well-decomposed
task with full context is within Sonnet's reach — task-spec quality substitutes
for model horsepower. The roles Opus carried in the multi-model setup (honest
verifier, long horizon, complexity ceiling) are redistributed: **decisions and
verdicts go to the orchestrator, long work gets sliced into waves, open-ended work
gets pinned down**. The facts and numbers live in `references/model-dossiers.md`.

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
3. **Plan.** Tasks: independent within a wave (no file overlap), self-contained
   (the agent sees neither the conversation nor your research), closed (a fork
   left over means the Decisions stage isn't finished), **short-horizon** — Sonnet
   burns ~3× more steps on long sessions and tends to stop early; slice prolonged
   work into waves with review in between. Batch small same-shaped edits into one
   agent's task. The decomposition covers ALL artifacts of the feature, including
   documentation (README and the like) — otherwise it silently goes stale: if you
   froze a file for everyone, assign it to someone explicitly.
4. **Table.** Before launching: task | model | effort | rationale.
5. **Launch.** Independent tasks — in parallel via Workflow.
6. **Review** (checklist below). Fixes — as one concrete list. Two misses in the
   same place — fix the task spec. A disputed result goes to a separate Sonnet
   skeptic with the task "find what's broken" (not "confirm it works"); the
   implementer never verifies its own work.
7. **The final end-to-end review — the orchestrator only.** The configuration has
   no model with Opus-grade honesty of diagnosis; the end-to-end diff, the seams,
   and conformance to the task are checked personally. The mechanics (tests,
   collecting the diff) can be delegated; the verdict cannot.
8. **Completion.** At most 3 iterations per task, then escalation. Summary:
   done / verified / remaining. Classes of tasks that systematically fail to
   converge within 3 iterations get recorded separately — that is the measurable
   result of the experiment.

## Routing — Quick Reference

| Task | Model |
|---|---|
| Mechanical work per exact instruction, zero decisions | Haiku 4.5 |
| Everything else: implementation per spec, tests, refactorings, migrations, isolated features, debugging a reproducible scenario | Sonnet 5 |
| Digging through a large volume of code for a specific question | Sonnet 5 (1M context) |
| Skeptic-verifier of someone else's result | Sonnet 5, high/xhigh |

Torn between Haiku and Sonnet → Sonnet. There are no "Opus tasks" in this
configuration — only tasks you haven't decomposed enough.

## Choosing Effort (Sonnet 5)

| Level | When |
|---|---|
| low | obvious solution, but the surrounding code must be read and understood |
| medium | routine implementation against a clear specification |
| high | default for non-trivial code |
| xhigh | debugging a complex scenario, concurrency, security-sensitive code, the skeptic role |

Haiku 4.5 does not support effort — do not specify it.

**Signal rule:** Sonnet's returns on effort plateau early — xhigh does not turn it
into Opus. Tempted to set xhigh because the task is open-ended/underspecified →
go back to the Decisions stage or decompose further.

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
   reset --hard, rm outside the task) without explicit permission.
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

## The Orchestrator's Own Quirks (Fable 5)

- Prone to workaround maneuvers: verification impossible → report to the user
  directly, don't simulate.
- "Budget is running out" / "time to wrap up" can be false feelings — before
  finishing, check against the plan.
- The honest-verifier role in this configuration is covered by no one but you —
  do not delegate verdicts.

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
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

- `references/model-dossiers.md` — dossiers on Sonnet 5, Haiku 4.5, and Fable 5
  with numbers from the system cards; load it for contested routing calls or to
  justify a choice.
