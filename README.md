# claude-skills

A Claude Code plugin marketplace (`temmax-skills`) with two plugins — one skill
each. Every rule in these skills is derived from the models' official Anthropic
system cards and battle-tested with RED/GREEN agent runs (baseline failures
reproduced, then verified fixed).

- **`orchestration`** — the orchestrator model researches, plans, writes closed
  task prompts, and reviews; executor subagents (Haiku 4.5 / Sonnet 5 /
  Opus 4.8) implement.
- **`code-review`** — critical, evidence-based review of uncommitted changes or
  a GitHub PR, performed by the session's own model.

Each skill works on **whatever model the session runs on**: it reads its own
model identity and loads the matching profile from `references/`. There is no
`-opus` variant to pick between any more.

| Plugin | Skill | What it does |
|---|---|---|
| `orchestration` | `multi-model` | Model routing, effort selection, task-prompt template, wave planning, review checklist. |
| `code-review` | `critical-review` | Scope detection, PR description+threads protocol, tiered findings table (Blocker → Nit). |

## How the model routing works

Claude Code states the session model in the system prompt ("You are powered by
the model named X. The exact model ID is Y"). Step 0 of each skill maps that ID
to exactly one profile file and forbids reading the others:

| Model ID | orchestration profile | code-review profile |
|---|---|---|
| `claude-fable-5` | `references/orchestrator-fable-5.md` | `references/reviewer-fable-5.md` |
| `claude-opus-4-8` (any context suffix, e.g. `[1m]`) | `references/orchestrator-opus-4-8.md` | `references/reviewer-opus-4-8.md` |
| anything else | none — model-agnostic rules only, and the skill says so | same |

The profile carries everything that is genuinely model-specific: the session's
reasoning-effort guidance, amendments to the numbered process steps, and the
model's own documented failure modes. The shared body carries everything else.

**Why the split matters.** Merging the variants naively — leaving an
unconditional "run this session at xhigh reasoning effort" in the shared
overview — made a Fable 5 orchestrator adopt Opus 4.8's effort directive in 3 of
3 test runs, reasoning that "the imperative is phrased generically", and import
Opus-specific process amendments along with it. A model with no profile at all
hedged instead of falling back cleanly. With the effort directive scoped inside
the profile, a model-ID gate on each profile, and an explicit fallback row, 14
of 14 runs across Fable 5, Opus 4.8 and Sonnet 5 loaded the right profile,
refused the wrong one, and applied the right effort.

The Opus profile also **self-checks the session effort**: Step 0 surfaces the
live value via the `${CLAUDE_EFFORT}` substitution, and the profile halts an
orchestration started at `medium` or below with a request to restart higher
(review notes the shortfall rather than halting). If the substitution ever fails
to expand, the skill treats effort as unknown and proceeds — verified across 10
runs (medium halts, high notes the floor, xhigh proceeds silently, an unexpanded
placeholder degrades gracefully, Fable never false-warns).

**Recommendation for Opus 4.8 sessions:** run the orchestrator at `xhigh`
reasoning effort; `high` is the floor when latency-bound. Grounding from the
Opus 4.8 system card: SWE-bench Pro peaks at xhigh (69.8, p. 196), deep-research
agentic scores rise monotonically through max (DRACO 80.4, p. 208), Anthropic's
own multi-agent harnesses ran the orchestrator at max effort (p. 214), and
higher effort roughly halves prompt-injection susceptibility (p. 80). Low/medium
effort on Opus 4.8 is executor territory (its minimum effort already matches
Opus 4.7's maximum). No equivalent level is pinned for Fable 5 — that
measurement does not exist for it, and the Fable profile says so explicitly.

Both skills also ship a dossier (`references/model-dossiers.md`,
`references/reviewer-dossier.md`) with benchmark numbers, documented failure
modes, and page references to the system cards — loaded on demand for contested
calls.

All skills always reply to the user in the language the user writes in.

## Installation

```
/plugin marketplace add TemMax/claude-skills
/plugin install orchestration@temmax-skills
/plugin install code-review@temmax-skills
```

## Usage

There are two ways to invoke the skills.

**Automatic (primary).** The skills trigger on their own: each skill's
description is always in Claude's context, and a matching request loads the
skill automatically — just ask in plain text:

```
Decompose this into agents and run in parallel: <task>
Orchestrate this task across subagents: <task>
Разбей на агентов и запусти параллельно: <задача>
Review my uncommitted changes critically
Сделай критическое ревью ПР #42
```

**Explicit slash command.** Guarantees the skill loads. Everything after the
skill name is passed as the task description:

```
/orchestration:multi-model Add multi-currency support to the pricing module
/code-review:critical-review <PR number optional>
```

Type `/orch` or `/code` and let autocomplete fill in the namespaced name.

**What to expect from orchestration.** The orchestrator loads its profile, then
runs research → decisions → plan, shows you a table (task | model | effort |
rationale) and waits for your approval before launching the executor waves.
After each wave it reviews the results by running tests and reading diffs —
executor self-reports are never trusted.

**What to expect from review.** The reviewer loads its profile, detects the
scope (a named PR, a PR opened this session, uncommitted changes, or the
session's own commits), reads the PR description and every comment thread first
when reviewing a PR, verifies findings by running what is cheap, and delivers a
short summary plus one findings table tiered Blocker / Important / Medium / Low
/ Nit. The review is read-only — fixes happen only when you ask afterwards.

To verify the plugins are installed, run `/plugin` and look for
`orchestration` and `code-review` with their skills listed.

## Migration from 1.x

This release (orchestration 1.4.0, code-review 1.1.0) collapsed the per-model
skill variants and dropped the sonnet-only experiment:

| Before | After |
|---|---|
| `multi-model`, `multi-model-opus` | `multi-model` (loads its own profile) |
| `critical-review`, `critical-review-opus` | `critical-review` (loads its own profile) |
| `sonnet-only`, `sonnet-only-opus` | removed |

The `-opus` slash commands no longer exist. Use the base name on any model.

## Local development

```bash
claude --plugin-dir /path/to/claude-skills/plugins/orchestration
claude --plugin-dir /path/to/claude-skills/plugins/code-review
```

## Repository layout

```
.claude-plugin/
  marketplace.json     # lets this repo act as its own marketplace
plugins/
  orchestration/
    .claude-plugin/plugin.json
    skills/
      multi-model/
        SKILL.md
        references/
          orchestrator-fable-5.md
          orchestrator-opus-4-8.md
          model-dossiers.md
  code-review/
    .claude-plugin/plugin.json
    skills/
      critical-review/
        SKILL.md
        references/
          reviewer-fable-5.md
          reviewer-opus-4-8.md
          reviewer-dossier.md
```
