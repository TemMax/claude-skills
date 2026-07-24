---
name: multi-model
description: 'Use when orchestrating parallel development work through Workflow subagents on Haiku 4.5, Sonnet 5 and Opus 4.8 — decomposing a coding task into agent waves, routing tasks to models, picking reasoning effort, writing task prompts for executor agents, or reviewing their results. Works on whatever model this orchestrator session runs on; it loads the matching orchestrator profile itself. Triggers: "разбей на агентов", "запусти параллельно", "оркеструй задачу", "decompose into agents", "run in parallel", "delegate to subagents", "pick a model for this task". Do NOT use for single-agent work.'
metadata:
  author: https://github.com/TemMax
  version: 1.5.0
---

# Orchestrating Multi-Model Development

## Step 0 — Load Your Own Orchestrator Profile (before anything else)

Your environment block states the model you are running as ("You are powered by
the model named X. The exact model ID is Y"). Read it and load the ONE matching
profile file:

| Your model ID | Read this file |
|---|---|
| `claude-fable-5` | `${CLAUDE_SKILL_DIR}/references/orchestrator-fable-5.md` |
| `claude-opus-5` (any context-window suffix) | `${CLAUDE_SKILL_DIR}/references/orchestrator-opus-5.md` |
| `claude-opus-4-8` (any context-window suffix, e.g. `[1m]`) | `${CLAUDE_SKILL_DIR}/references/orchestrator-opus-4-8.md` |
| anything else | no profile exists — use the model-agnostic rules below only, and tell the user which model you are and that no profile matched |

**Read exactly one file — the one matching your own model. Do not read the
others: their session-effort guidance, documented failure modes and strengths
belong to a different model and are not yours.** State which profile you loaded
before planning. Your profile amends the numbered steps below; where it amends a
step, the amendment wins.

Your session's current reasoning effort is reported by the harness as
**${CLAUDE_EFFORT}**. Your profile states the effort it expects; if that reported
value is lower than your profile requires, act as your profile directs before you
plan.

## Overview

The orchestrator (this session's model) researches, plans, writes task specs, and
verifies; the executors (Haiku 4.5 / Sonnet 5 / Opus 5 / Opus 4.8) implement. Core
principle: **decisions belong to the orchestrator, execution belongs to the
agents**. Every rule below is derived from the models' official system cards; the
facts and numbers live in `references/model-dossiers.md`.

Always reply to the user in the language the user writes in — this skill being in
English does not mean English replies.

## Process

1. **Research.** Study the codebase to the depth needed for decomposition: files,
   dependencies, conventions.
2. **Decisions.** Close the open questions BEFORE decomposing: research an
   incomplete specification further and pin down the interpretation (escalate
   fundamental choices to the user); design cross-cutting architecture yourself
   and hand it out as a set of concrete implementations. Do not delegate decisions
   even to an Opus executor — it silently fills in gaps under ambiguity.
3. **Plan.** Tasks: independent within their wave (no file overlap, otherwise —
   next wave or worktree), self-contained (the agent sees neither the conversation
   nor your research), closed (no "decide for yourself what's best"). Batch small
   same-shaped edits into one agent's task: parallelization pays only on hard
   chunks — on easy ones coordination overhead eats the gain. The decomposition
   covers ALL artifacts of the feature, including documentation (README and the
   like) — otherwise it silently goes stale: if you froze a file for everyone,
   assign it to someone explicitly.
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
| Independent verification, "what's actually broken here" | Opus 5 executor (default heavy) | First Claude to saturate lazy-investigation; parity with 4.8 on flagging planted flaws |
| Fine-grained debugging, concurrency, source-level security-sensitive code | Opus 5 executor | Strongest coding + best injection robustness; source security unblocked |
| A long unsliceable session | Opus 5 executor | Strongest long-horizon coding at Opus-4.8 price |
| Sonnet hit its ceiling after a fix iteration | Opus 5 executor | The heavy-executor upgrade over Sonnet |
| Reading untrusted external content (web, fetched pages, hostile files) | Opus 5 executor | Most injection-robust model tested (still pair with platform safeguards) |
| Reverse-engineering / vulnerability discovery in compiled binaries | Opus 4.8 executor | Opus 5's Fable-class cyber classifier blocks binaries; Opus 4.8 does not |

Torn between Haiku and Sonnet → Sonnet. Torn between Sonnet and Opus → improve the
task spec first, then upgrade the model. Opus 5 is the default heavy executor and
verifier; Opus 4.8 is retained only for compiled-binary work and as the
cyber-refusal fallback.

**Routing anti-patterns:** no sub-orchestrators — executors never spawn their own
subagents (documented failures in deep delegation chains: status honesty, not
capability); don't give any executor untrusted external content without platform
safeguards (Opus 5 is the most robust, but safeguards still matter); don't give
Sonnet multi-hour sessions; don't route compiled-binary reverse-engineering to
Opus 5 (its classifier blocks it) — use Opus 4.8.

## Choosing Executor Effort — Quick Reference

This table is about the effort you hand to executors. Your own session's effort
is your profile's business, not this table's.

| Model | low | medium | high | xhigh |
|---|---|---|---|---|
| Haiku 4.5 | — does not support effort — | | | |
| Sonnet 5 | obvious solution, but the code must be read | routine implementation per spec | default for non-trivial work | hardest execution tasks; plateau! |
| Opus 5 executor | unusually strong on simple/scoped tasks | well-specified work | default for non-trivial work | avoid — overthinking/self-verification risk |
| Opus 4.8 executor | — | most well-specified tasks (min effort ≈ Opus 4.7 max) | debugging, verification, long horizon | research-grade only |

Signal rule: wanting to give Sonnet xhigh because the task is open-ended → that
means switching the model to Opus or returning to the Decisions stage, not effort.
Opus 5's effort curve is the exception — higher is not better; it peaks mid-range
on coding and overthinks at `max`, so cap Opus 5 executors at `high`.

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
   Phrase prohibitions without qualifiers — executors rules-lawyer around wording
   when it conflicts with "the overriding goal".
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

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Planning before loading your orchestrator profile | You inherit another model's effort advice and failure modes | Step 0 first, exactly one profile |
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

- `references/orchestrator-fable-5.md`, `references/orchestrator-opus-5.md`,
  `references/orchestrator-opus-4-8.md` — the orchestrator profiles. Load exactly
  one, per Step 0.
- `references/model-dossiers.md` — dossiers on all four models with numbers and
  page references to the system cards: benchmarks, documented failure modes,
  effort curves, multi-agent harness data, orchestration takeaways. Load it for
  contested routing calls or to justify a choice.
