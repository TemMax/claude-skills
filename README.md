# claude-skills

A Claude Code plugin with multi-agent orchestration skills. The orchestrator model
(Fable 5) researches, plans, writes closed task prompts, and reviews; executor
subagents (Haiku 4.5 / Sonnet 5 / Opus 4.8) implement. Every rule in these skills
is derived from the models' official Anthropic system cards and battle-tested with
RED/GREEN agent runs (baseline failures reproduced, then verified fixed).

## Skills

| Skill | When to use |
|---|---|
| `orchestrating-multi-model` | Default orchestration: executors are Haiku 4.5, Sonnet 5, and Opus 4.8. Model routing, effort selection, task-prompt template, review checklist. |
| `orchestrating-sonnet-only` | The sonnet-only experiment: no Opus executors. Tests the hypothesis that task-spec quality substitutes for model horsepower. |

Each skill ships with `references/model-dossiers.md` — per-model dossiers with
benchmark numbers, documented failure modes, and page references to the system
cards (loaded on demand for contested routing calls).

The skills always reply to the user in the language the user writes in.

## Installation

```
/plugin marketplace add TemMax/claude-skills
/plugin install agent-orchestration@temmax-skills
```

## Usage

There are two ways to invoke the skills.

**Automatic (primary).** The skills trigger on their own: each skill's
description is always in Claude's context, and a matching request loads the
skill automatically — just ask in plain text:

```
Decompose this into agents and run in parallel: <task>
Orchestrate this task across subagents: <task>
Run this in sonnet-only mode: <task>
```

**Explicit slash command.** Guarantees the skill loads, and lets you force a
specific configuration (e.g. the sonnet-only experiment on a task where Claude
would pick multi-model). Everything after the skill name is passed as the task
description:

```
/agent-orchestration:orchestrating-multi-model Add multi-currency support to the pricing module
/agent-orchestration:orchestrating-sonnet-only Refactor the API client layer
```

Type `/orch` and let autocomplete fill in the namespaced name.

**What to expect.** The orchestrator does not jump straight to code. It runs
research → decisions → plan, then shows you a table (task | model | effort |
rationale) and waits for your approval before launching the executor waves.
After each wave it reviews the results by running tests and reading diffs —
executor self-reports are never trusted. The model dossiers in `references/`
load on demand when a routing call needs justification.

To verify the plugin is installed, run `/plugin` and look for
`agent-orchestration` with both skills listed.

## Local development

```bash
claude --plugin-dir /path/to/claude-skills
```

## Repository layout

```
.claude-plugin/
  plugin.json        # plugin manifest
  marketplace.json   # lets this repo act as its own marketplace
skills/
  orchestrating-multi-model/
    SKILL.md
    references/model-dossiers.md
  orchestrating-sonnet-only/
    SKILL.md
    references/model-dossiers.md
```
