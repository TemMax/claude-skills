# claude-skills

A Claude Code plugin marketplace (`temmax-skills`) with two plugins. Every rule
in these skills is derived from the models' official Anthropic system cards and
battle-tested with RED/GREEN agent runs (baseline failures reproduced, then
verified fixed).

- **`orchestration`** — the orchestrator model researches, plans, writes
  closed task prompts, and reviews; executor subagents (Haiku 4.5 / Sonnet 5 /
  Opus 4.8) implement. Two orchestrator variants: Fable 5 and Opus 4.8.
- **`code-review`** — critical, evidence-based review of uncommitted changes or
  a GitHub PR, performed by the session's own model. Two reviewer variants:
  Fable 5 and Opus 4.8.

## Plugin: orchestration

| Skill | Orchestrator | When to use |
|---|---|---|
| `multi-model` | Fable 5 | Default orchestration: executors are Haiku 4.5, Sonnet 5, and Opus 4.8. Model routing, effort selection, task-prompt template, review checklist. |
| `sonnet-only` | Fable 5 | The sonnet-only experiment: no Opus executors. Tests the hypothesis that task-spec quality substitutes for model horsepower. |
| `multi-model-opus` | Opus 4.8 | Same multi-model setup when your session runs on Opus 4.8 instead of Fable 5. Adds Opus-specific orchestrator mitigations (monitoring claims, caveat propagation, long-horizon goal-keeping). |
| `sonnet-only-opus` | Opus 4.8 | The sonnet-only experiment with an Opus 4.8 orchestrator — the orchestrator itself is the configuration's honest verifier. |

**Recommendation for the `-opus` skills: run the Opus 4.8 orchestrator session at
`xhigh` reasoning effort; `high` is the floor when latency-bound — never medium or
below for orchestration.** Grounding from the Opus 4.8 system card: SWE-bench Pro
peaks at xhigh (69.8, p. 196), deep-research agentic scores rise monotonically
through max (DRACO 80.4, p. 208), Anthropic's own multi-agent harnesses ran the
orchestrator at max effort (p. 214), and higher effort roughly halves
prompt-injection susceptibility (p. 80). Low/medium effort on Opus 4.8 is
executor territory (its minimum effort already matches Opus 4.7's maximum).

Each orchestration skill ships with `references/model-dossiers.md` — per-model
dossiers with benchmark numbers, documented failure modes, and page references
to the system cards (loaded on demand for contested routing calls).

## Plugin: code-review

| Skill | Reviewer | When to use |
|---|---|---|
| `critical-review` | Fable 5 | Critical review of uncommitted changes or a GitHub PR: scope detection, PR description+threads protocol, tiered findings table (Blocker → Nit). |
| `critical-review-opus` | Opus 4.8 | Same critical review when the session runs on Opus 4.8. Adds Opus-specific reviewer mitigations (untrusted PR content, goal-keeping, effort floor). |

Each review skill ships with `references/reviewer-dossier.md` — the
review-relevant system-card facts (judge properties, honesty rates, reviewer
failure modes).

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
Run this in sonnet-only mode: <task>
Orchestrate this on Opus as the orchestrator: <task>
Review my uncommitted changes critically
Сделай критическое ревью ПР #42
```

**Explicit slash command.** Guarantees the skill loads, and lets you force a
specific configuration (e.g. the sonnet-only experiment on a task where Claude
would pick multi-model). Everything after the skill name is passed as the task
description:

```
/orchestration:multi-model Add multi-currency support to the pricing module
/orchestration:sonnet-only Refactor the API client layer
/orchestration:multi-model-opus Add multi-currency support to the pricing module
/orchestration:sonnet-only-opus Refactor the API client layer
/code-review:critical-review
/code-review:critical-review-opus <PR number optional>
```

Type `/orch` or `/code` and let autocomplete fill in the namespaced name.

**What to expect from orchestration.** The orchestrator does not jump straight
to code. It runs research → decisions → plan, then shows you a table (task |
model | effort | rationale) and waits for your approval before launching the
executor waves. After each wave it reviews the results by running tests and
reading diffs — executor self-reports are never trusted. The model dossiers in
`references/` load on demand when a routing call needs justification.

**What to expect from review.** The reviewer detects the scope (a named PR, a
PR opened this session, uncommitted changes, or the session's own commits),
reads the PR description and every comment thread first when reviewing a PR,
verifies findings by running what is cheap, and delivers a short summary plus
one findings table tiered Blocker / Important / Medium / Low / Nit. The review
is read-only — fixes happen only when you ask afterwards.

To verify the plugins are installed, run `/plugin` and look for
`orchestration` and `code-review` with their skills listed.

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
        references/model-dossiers.md
      sonnet-only/
        SKILL.md
        references/model-dossiers.md
      multi-model-opus/
        SKILL.md
        references/model-dossiers.md
      sonnet-only-opus/
        SKILL.md
        references/model-dossiers.md
  code-review/
    .claude-plugin/plugin.json
    skills/
      critical-review/
        SKILL.md
        references/reviewer-dossier.md
      critical-review-opus/
        SKILL.md
        references/reviewer-dossier.md
```
