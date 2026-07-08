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

Skills are then invoked automatically when relevant, or explicitly:

```
/agent-orchestration:orchestrating-multi-model
/agent-orchestration:orchestrating-sonnet-only
```

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
