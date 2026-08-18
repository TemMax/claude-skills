# claude-skills

A Claude Code plugin marketplace (`temmax-skills`) with two plugins covering the
full development pipeline: plan → supervised execution → review. Every rule in
these skills is derived from the models' official Anthropic system cards, and
the load-bearing logic ships as tested code, not prose — a wave runner, a plan
linter, and a four-tier test suite (see `tests/README.md`).

- **`orchestration`** — the full pipeline: `ship` conducts planning
  (`super-plan`) and execution (`multi-model`) into a reviewed PR. The
  orchestrator model researches, plans into contract-carrying waves, and
  launches executor subagents (Haiku 4.5 / Sonnet 5 / Opus 5 / Opus 4.8), each
  isolated in its own worktree and judged against its contract by a different
  model.
- **`code-review`** — critical, evidence-based review of uncommitted changes or
  a GitHub PR, performed by the session's own model.

Each skill works on **whatever model the session runs on**: it reads its own
model identity and loads the matching profile from `references/`. There is no
`-opus` variant to pick between any more.

| Plugin | Skill | What it does |
|---|---|---|
| `orchestration` | `super-plan` | Wave-native planning: research to decomposition depth, one batched round of user questions, tasks carrying machine-checkable contracts grouped into waves by file-independence, validated by the shipped `plan-lint.mjs` before the plan gate. Planning discipline adapted from Jesse Vincent's superpowers (MIT, attribution shipped). |
| `orchestration` | `ship` | The pipeline conductor: one command from request to reviewed PR — super-plan → supervised waves on a feature branch → critical-review of the PR and its threads. Adds no machinery of its own: one up-front gate, fixes routed by behavior change, and the merge always stays with the user. |
| `orchestration` | `multi-model` | Model routing, effort selection, task-prompt template, review checklist, and supervised waves executed by the shipped `wave-runner.workflow.mjs` — isolated executors judged against a machine-checkable contract by a different model, with the escalation ladder as tested code — plus an orchestrator-drift advisory hook that watches the orchestrator session itself. |
| `code-review` | `critical-review` | Scope detection, PR description+threads protocol, tiered findings table (Blocker → Nit), and a post-review fix phase that answers and resolves the PR threads its findings came from. |

## How the model routing works

Claude Code states the session model in the system prompt ("You are powered by
the model named X. The exact model ID is Y"). Step 0 of each skill maps that ID
to exactly one profile file and forbids reading the others:

| Model ID | orchestration profile | code-review profile |
|---|---|---|
| `claude-fable-5` | `references/orchestrator-fable-5.md` | `references/reviewer-fable-5.md` |
| `claude-opus-5` (any context suffix) | `references/orchestrator-opus-5.md` | `references/reviewer-opus-5.md` |
| `claude-opus-4-8` (any context suffix, e.g. `[1m]`) | `references/orchestrator-opus-4-8.md` | `references/reviewer-opus-4-8.md` |
| anything else | none — model-agnostic rules only, and the skill says so | same |

Opus 5 is the **default heavy executor and verifier**; Opus 4.8 is retained only
for compiled-binary reverse-engineering (Opus 5's Fable-class cyber classifier
blocks it) and as the cyber-refusal fallback. Opus 5's effort rule **inverts**
Opus 4.8's — higher effort makes it *worse* on long-horizon work (documented
overthinking / self-verification loops), so its profile runs at `high`, not
`xhigh`, and its effort self-check flags too-*high*, not too-low. Its card also
names an unverified-subagent-relay failure mode, so the Opus 5 orchestrator
profile doubles down on verifying subagent claims. Grounded in the Claude Opus 5
system card (193 pp., July 2026).

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
/orchestration:ship Add multi-currency support to the pricing module
/orchestration:super-plan Plan multi-currency support for the pricing module
/orchestration:multi-model Add multi-currency support to the pricing module
/code-review:critical-review <PR number optional>
```

`ship` runs the whole chain as one command: `super-plan` produces the plan
file whose machine half feeds the wave-runner directly (each task: json entry
+ its prose section as the description), `multi-model` executes it in
supervised waves on a pushed feature branch, `critical-review` closes the
loop on the PR — and the merge stays with the user. Each link also runs
standalone.

Type `/orch` or `/code` and let autocomplete fill in the namespaced name.

**What to expect from planning.** `super-plan` researches the codebase, asks
you ONE batched round of questions for what code cannot answer, and gates
twice: once on the design summary, once on the finished plan — which must pass
the shipped linter (same-wave file overlap, contract completeness) before you
ever see it.

**What to expect from orchestration.** The orchestrator loads its profile,
shows you a table (task | model | effort | rationale), then launches the waves
through the shipped runner: every executor works in its own worktree, and an
independent judge model checks out the branch, re-runs the contract's commands
itself and issues a verdict — executor self-reports are never trusted. Rework,
model escalation and the unsatisfiable-contract stop are code, not judgment
calls.

**What to expect from ship.** One confirmation up front — the feature branch
will be pushed and a PR opened — then only the link skills' own gates stop the
flow. ship ends at a reviewed PR with its threads answered; the merge always
stays with you.

**What to expect from review.** The reviewer loads its profile, detects the
scope (a named PR, a PR opened this session, uncommitted changes, or the
session's own commits), reads the PR description and every comment thread first
when reviewing a PR, verifies findings by running what is cheap, and delivers a
short summary plus one findings table tiered Blocker / Important / Medium / Low
/ Nit. The review is read-only — fixes happen only when you ask afterwards.

To verify the plugins are installed, run `/plugin` and look for
`orchestration` and `code-review` with their skills listed.

## Migration from 1.x

The 1.4.0/1.1.0 releases collapsed the per-model skill variants and dropped the
sonnet-only experiment (current versions: orchestration 2.1.0, code-review
1.3.0):

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
    hooks/                       # orchestrator-drift Stop hook + offline tests
    skills/
      ship/
        SKILL.md               # the pipeline conductor (no references of its own)
      super-plan/
        SKILL.md
        references/
          plan-lint.mjs          # the plan rules as code
          LICENSE-superpowers    # MIT attribution (Jesse Vincent)
      multi-model/
        SKILL.md
        references/
          wave-runner.workflow.mjs   # the escalation ladder as code
          supervisor-prompt.md
          orchestrator-{fable-5,opus-5,opus-4-8}.md
          model-dossiers.md
  code-review/
    .claude-plugin/plugin.json
    skills/
      critical-review/
        SKILL.md
        references/
          reviewer-{fable-5,opus-5,opus-4-8}.md
          reviewer-dossier.md
tests/                           # structure / contracts / behaviour / live eval
  run.sh                         # ./tests/run.sh [--live]
```
