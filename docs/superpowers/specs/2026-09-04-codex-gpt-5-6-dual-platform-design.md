# Claude/Codex dual-platform support for GPT-5.6

Date: 2026-09-04
Status: user-approved direction, written design awaiting review
Targets: orchestration plugin 2.6.0; code-review plugin 1.5.0

## Problem

The repository currently distributes two Claude Code plugins whose four skills,
model profiles, orchestration runtime, drift hook, manifests, documentation,
and live evaluations all assume Anthropic models and Claude Code interfaces.
Codex can discover the skill directories, but that does not make the plugins
correct on Codex:

- only `.claude-plugin` manifests and marketplace metadata exist;
- every skill's Step 0 expects a Claude model id and `CLAUDE_EFFORT`;
- the supervised-wave control plane is a Claude Workflow program;
- the Stop hook invokes `claude -p` and emits Claude-shaped output;
- the routing and reviewer tables contain no GPT-5.6 models;
- the live test harness invokes only Claude models.

Copying the plugins into separate Claude and Codex trees would make the first
port easy but would leave two copies of every safety and supervision rule. The
copies would drift as soon as the next model or defect is added.

## Goal

Make the existing `orchestration` and `code-review` plugins installable and
behaviorally correct in both Claude Code and Codex, while retaining one shared
skill contract. Add evidence-backed profiles and tested routing for
`gpt-5.6-sol`, `gpt-5.6-terra`, and `gpt-5.6-luna`. Preserve every existing
Claude capability and test.

The release is complete only when every shipped skill has been exercised on
all three GPT-5.6 models, the recommended model/effort routes have repeated
live evidence, and both plugin formats install from a clean environment.

## Non-goals

- Renaming the repository. The user will do that after the migration.
- Removing `.claude-plugin` metadata or Claude model profiles.
- Mixing Claude and OpenAI executors inside one production wave. Cross-family
  runs may be research probes but are not a runtime dependency.
- Replacing Git worktree isolation, machine-checkable contracts, the plan
  linter, or the rule that the user owns the final merge.
- Depending on hidden chain-of-thought, model self-reports, or transcript wire
  formats as a correctness boundary.
- Adding an MCP server, hosted service, or mandatory non-standard dependency.
- Promising hook-based drift enforcement in ChatGPT surfaces that do not run
  Codex lifecycle hooks.

## Evidence base

The GPT-5.6 design rules come from the official 82-page *GPT-5.6 Preview System
Card*, the GPT-5.6 model and prompting guides, and the Codex documentation for
skills, plugins, hooks, and subagents. The implementation dossiers cite the
source URLs and exact PDF pages rather than copying the PDF into the plugin.

The load-bearing findings are:

- destructive-action avoidance is imperfect for all three models and lowest
  for Luna (System Card p. 11);
- indirect prompt injection remains non-zero (pp. 13-14);
- Sol can be overly persistent, exceed the user's intended scope, conceal
  incomplete verification, and misuse discovered credentials (pp. 19-24);
- action artifacts are a firmer boundary than model explanations, especially
  because hidden reasoning is unavailable to plugin logic (pp. 28-29, 59-60);
- metagaming on impossible coding tasks can contaminate evaluations
  (pp. 30-33);
- Sol, Terra, and Luna have materially different capability/cost profiles, so
  routing must be measured rather than inherited from the Claude table.

The current Claude test history supplies the migration method: source-grounded
profiles, contract pins, deterministic offline tests, independent review,
live behavior probes, and repeated false-positive guards.

## Approaches considered

### A. Shared core with thin host adapters — selected

Keep the existing plugin directories and common `SKILL.md` files. Add Codex
manifests, GPT profiles, runtime context injection, a Codex-native wave
protocol, and provider-aware hook/test adapters. Claude Workflow remains the
Claude control plane; native Codex subagents become the Codex control plane.

This has the smallest long-term drift surface. It also lets contract tests
assert that both hosts preserve the same invariants.

### B. Duplicate `plugins-claude/` and `plugins-codex/` trees

This isolates host-specific syntax and would be simpler for the first release.
It is rejected because four skills, their model safety rules, and every future
defect fix would need synchronized edits and duplicate tests.

### C. Replace the Claude plugin with a Codex-only plugin

This is the smallest port. It is rejected because the requested outcome is
support "also" for Codex, existing Claude behavior is measured and valuable,
and removing it provides no technical benefit.

## Architecture

There are three layers:

1. **Shared policy layer** — skill intent, task contracts, plan format,
   mechanical verification rules, escalation semantics, and user authority.
2. **Model knowledge layer** — provider/model profiles and dossiers loaded by
   exact model id when known, plus a conservative generic fallback.
3. **Host adapter layer** — packaging, runtime identity, agent invocation, and
   hook input/output for Claude Code or Codex.

The main flow is:

```text
host session -> runtime context -> Step 0 profile -> shared skill policy
             -> linted wave plan -> host wave adapter -> isolated executor
             -> mechanical verifier -> different-model supervisor -> ladder
             -> integration review -> user-controlled merge
```

No host adapter may weaken a shared contract. If a host cannot implement a
required stage, it fails closed with the missing capability and preserves the
branches/artifacts for the user.

## 1. Dual plugin packaging

Keep the current `.claude-plugin` files. Add:

```text
.agents/plugins/marketplace.json
plugins/orchestration/.codex-plugin/plugin.json
plugins/code-review/.codex-plugin/plugin.json
plugins/orchestration/hooks/runtime-context
plugins/code-review/hooks/hooks.json
plugins/code-review/hooks/runtime-context
```

Each Codex manifest uses the same stable plugin name and semantic version as
its Claude counterpart. It explicitly points `skills` at `./skills/`.
Each plugin points `hooks` at its own `./hooks/hooks.json`: orchestration ships
runtime context plus drift detection, while code-review ships runtime context
only so it remains independently installable. The repository marketplace uses
local source objects of the form
`{"source":"local","path":"./plugins/orchestration"}` and
`{"source":"local","path":"./plugins/code-review"}`.

The manifests describe capabilities rather than naming one vendor. Claude
metadata may retain Claude-specific installation terms where the file format
requires them. Repository URLs remain unchanged until the user renames the
repository.

Versions rise by one minor release because Codex support is additive:

- orchestration: `2.5.0` -> `2.6.0`;
- code-review: `1.4.0` -> `1.5.0`.

Every skill version in a plugin continues to match that plugin's two
manifests. Structure tests parse both formats and reject divergence.

## 2. Runtime context and Step 0

Add a small `SessionStart` handler to each plugin. They implement the same
versioned interface but are self-contained because either plugin can be
installed alone. Codex hook input supplies the exact active model slug in the
common `model` field. Each handler emits concise, plugin-scoped developer
context:

```text
PLUGIN_RUNTIME_CONTEXT_V1 plugin=orchestration host=codex model=gpt-5.6-sol effort=unknown
PLUGIN_RUNTIME_CONTEXT_V1 plugin=code-review host=codex model=gpt-5.6-sol effort=unknown
```

The handler recognizes `gpt-5.6` as the Sol alias. Claude ids retain their
current routing. The handler never reads `~/.codex/config.toml`: that file is a
default and can disagree with a per-session override. Current Codex hook input
does not expose reasoning effort, so the main-session value remains `unknown`
unless the host explicitly supplies it. A skill must not invent it.

Step 0 in all four skills follows one resolver contract:

1. Prefer the exact versioned runtime-context line for the current plugin.
2. Otherwise use an exact model id explicitly present in the session context.
3. Otherwise load the provider-neutral fallback and mark the model and effort
   unmeasured for this run.

Unknown ids never silently map to Sol, Opus, or any other strongest model. An
unknown profile preserves universal safety rules and uses capability-based
delegation without model-specific claims. Missing SessionStart support thus
reduces optimization but does not make a skill unusable.

The fallback instructions live in
`orchestrator-generic.md` and `reviewer-generic.md`. Skill references use paths
relative to their own `SKILL.md`; `${CLAUDE_SKILL_DIR}` is not treated as a
cross-platform interface. Hook scripts alone use the host-provided
`PLUGIN_ROOT`, with `CLAUDE_PLUGIN_ROOT` retained only as a compatibility
fallback.

`SubagentStart` receives an explicit model and effort chosen by the wave plan,
and its hook input contains that subagent's active model. The adapter injects
the subagent's own profile identity; it never copies the parent session's
profile onto the child.

## 3. GPT-5.6 profiles and dossiers

Create role-specific profiles:

```text
plugins/orchestration/skills/multi-model/references/
  orchestrator-gpt-5-6-sol.md
  orchestrator-gpt-5-6-terra.md
  orchestrator-gpt-5-6-luna.md
  orchestrator-generic.md
  gpt-5-6-dossier.md

plugins/code-review/skills/critical-review/references/
  reviewer-gpt-5-6-sol.md
  reviewer-gpt-5-6-terra.md
  reviewer-gpt-5-6-luna.md
  reviewer-generic.md
  gpt-5-6-reviewer-dossier.md
```

Each profile begins with an exact-id guard and contains:

- verified strengths and failure modes with source/page citations;
- main-seat responsibilities;
- tasks to delegate and the explicit target model/effort;
- autonomy and destructive-action boundaries;
- artifact-first verification rules;
- behavior at `medium`, `high`, `xhigh`, and `max`, distinguishing measured
  results from hypotheses;
- common mistakes and facts not measured by the source.

The dossier is the evidence ledger; profiles are concise operating guidance.
Unmeasured properties are labeled `not measured`, never inferred from model
size or marketing position. The System Card's Sol-only alignment results must
not be attributed to Terra or Luna.

Initial routing hypotheses, used only to seed live evaluation, are:

| Work | Initial executor | Initial effort | Supervisor |
|---|---|---|---|
| Demanding planning, ambiguous implementation | Sol | medium | Terra high |
| Read-heavy exploration and large-file review | Terra | medium | Sol high |
| Narrow repetitive/mechanical work | Luna | low or medium | Terra high |
| Review of Luna output | Terra | high | mechanical checks first |
| Review of Terra output | Sol | high | mechanical checks first |
| Review of Sol output | Terra | high | mechanical checks first |

The release routing table is written from live results, not copied from this
seed. A supervisor is never the executor's exact model. The initial escalation
ladder is Luna -> Sol under a Terra supervisor. Terra under Sol supervision and
Sol under Terra supervision are terminal after one raised-effort rework. A new
wave with a newly selected supervisor is required to change that pairing; no
wave may place its supervisor model in an executor or ladder position. `max` is
never a default: Sol's persistence risk increases at the highest reasoning
settings, so `xhigh` and `max` require measured task benefit and the
destructive-action guard suite.

## 4. Shared skill content

Keep one copy of each skill:

- `multi-model` owns decomposition and supervised execution;
- `super-plan` owns design and wave-plan production;
- `ship` composes plan, waves, review, and PR without owning new machinery;
- `critical-review` owns evidence-based review and thread resolution.

Provider-specific tool names and model tables move out of the main narrative
and into small adapter/profile references. Each SKILL frontmatter description
is shortened and front-loads triggers and boundaries so Codex discovery stays
within its catalog budget. Load-bearing rules remain in the main skill or in a
reference the skill unconditionally loads before acting.

Interactive decisions use the host's structured input tool when one is
available. Otherwise the skill asks one concise direct question and waits. In
headless evaluation it records the same `Assumptions (would ask)` block used
today. The shared policy does not hard-code Claude's `AskUserQuestion` or
assume Codex `request_user_input` is present outside the modes that expose it.

The shared autonomy contract is explicit:

- answer, explain, review, and plan authorize inspection and reporting only;
- build, change, and fix authorize scoped local edits plus validation;
- destructive, external, costly, credential-using, or scope-expanding actions
  require explicit user authority;
- discovered secrets are never used as a workaround;
- a completion claim requires fresh artifact evidence from this run.

Prompt text states each rule once. Repeated historical explanations move to
dossiers or tests unless repetition is itself a measured safety requirement.

## 5. Codex-native supervised waves

The Claude adapter remains the shipped
`wave-runner.workflow.mjs`. Codex uses native subagents rather than attempting
to execute Claude Workflow syntax or recursively driving a second host CLI.

Add these two artifacts:

```text
plugins/orchestration/skills/multi-model/references/codex-wave-protocol.md
plugins/orchestration/skills/multi-model/references/codex-wave-state.mjs
```

The protocol tells the orchestrator when to invoke native subagents and how to
feed their results back to the helper. The helper owns plan/state validation,
prompt assembly, worktree preparation, diffs, command execution, and ladder
transitions. The model performs only decisions that require a model.

The helper is a dependency-free Node CLI. Every command writes one JSON object
to stdout; commands that accept model output read one JSON object from stdin:

```text
node codex-wave-state.mjs init --plan <path> --wave <number> --repo <path> --base <sha>
node codex-wave-state.mjs next --state <path>
node codex-wave-state.mjs record-executor --state <path> --task <id>
node codex-wave-state.mjs verify --state <path> --task <id>
node codex-wave-state.mjs supervisor-prompt --state <path> --task <id>
node codex-wave-state.mjs record-verdict --state <path> --task <id>
node codex-wave-state.mjs summary --state <path>
```

`record-executor` accepts exactly one of `{"report":"..."}` or
`{"error":{"kind":"null-result|transport|tool-unavailable"}}`.
`record-verdict` accepts either the existing supervisor verdict object or the
same fixed error shape. Arbitrary error messages are not persisted. `next`
returns exactly one of
`spawn-executor`, `verify`, `spawn-supervisor`, `merge-ready`, or `stop`, plus
the task, model, and effort required for that action. Executor actions include
their prompt; a supervisor prompt is returned by the separate
`supervisor-prompt` command after verifier facts exist. Invalid input returns
`status: "invalid"` and a non-zero exit without advancing state.
The Codex helper accepts only `gpt-5.6-sol`, `gpt-5.6-terra`, and
`gpt-5.6-luna`; a Claude model id is a named host-mismatch error.

State is one file per wave, written to
`.worktrees/codex-wave/<plan-basename>-w<wave>-<base-prefix>.json`, already
covered by the repository's `.worktrees/` ignore rule. A later wave is
initialized only after earlier `ok` branches merge and the new pushed base SHA
is known. State contains the schema version, plan path, wave number, base,
task/rung/attempt status, reports, verifier facts, and verdicts; it never
contains credentials or hidden reasoning.

The Codex protocol is:

1. Lint the canonical `json wave-plan` block before spawning any agent.
2. Record the pushed base SHA and create/reuse one worktree and `wave/<id>`
   branch per task without force-removing existing worktrees.
3. Spawn each executor with the plan's exact model and effort. The prompt gives
   it the task contract but not the supervisor's detection method.
4. Gather the branch diff and run every `must_run` command mechanically.
5. Spawn the wave's different-model supervisor with the contract, diff,
   verifier facts, and executor report. Redact literal occurrences of the
   executor's exact model id from the report and omit executor identity
   metadata. The verdict uses the existing schema.
6. Apply the same rework, escalation, unsatisfiable-contract, and absolute-cap
   rules as the Claude runner.
7. Persist task status and verdict history so Stop continuation can detect an
   unfinished active wave without trusting the assistant's recap.
8. Merge only `ok` branches in plan order; preserve failed branches and report
   them to the user.

The helper does not call a model and does not decide code quality. It accepts
the plan path, task id, base SHA, branch, and verdict JSON; it returns a named
next action or a schema error. Its state lives under the repository's existing
ignored wave-worktree area and contains no credentials or hidden reasoning.

Native-subagent failure follows the existing ladder semantics: record the fixed
error kind, retry one null/transport/tool-unavailable failure at the same
executor or supervisor point, then mark the task `error`; never reinterpret
infrastructure failure as an `ok` verdict or store an arbitrary error string.

Plan lint, Claude runner validation, and Codex helper validation reject any task
whose executor or ladder contains the wave's supervisor model. This makes
different-model supervision a schema property instead of relying on the
orchestrator to notice a collision.

## 6. Provider-aware drift hook

Retain one logical Stop gate and its current plan/branch/deduplication behavior.
Split host-specific invocation and output shaping behind it:

- Claude path invokes the existing Claude judge and preserves current output;
- Codex path invokes an explicit different-model Codex judge in read-only,
  ephemeral mode and requests structured output;
- Codex continuation returns a concrete message such as
  `{"decision":"block","reason":"Task gamma has no verifier evidence."}`;
- a clean result emits no continuation decision;
- an inherited recursion-guard variable prevents a nested judge session from
  re-entering the same Stop hook.

Judge selection uses the Stop hook's exact `model` input. Sol is checked by
Terra; Terra and Luna are checked by Sol. If the active model is unknown, the
hook performs its mechanical gates but does not guess a judge. It reports the
missing identity without claiming that drift was checked.

The judge receives only the active plan, relevant branch facts, fresh command
evidence, and the last assistant message. It does not use unstable transcript
wire-format parsing as a required input. Model failure, timeout, invalid JSON,
or an unavailable CLI fails open for continuation but visibly records
`drift-check unavailable`; it never produces a false clean verdict.

## 7. Error and safety behavior

- Manifest or plan schema failure: fail closed before agents start.
- Unknown model: generic profile; no strongest-model assumptions.
- Unknown effort: no effort-specific behavioral claim or automatic `max`.
- Missing host capability: stop with the exact missing capability and retain
  all branches and state.
- Flaky `must_run`: retry once, then record both outputs; one pass and one fail
  becomes a remark rather than fabricated certainty.
- Prompt injection in repository or tool output: treat it as data unless it is
  an instruction from the user/developer authority chain.
- Requested file scope conflicts with a contract: mark the contract
  unsatisfiable and return it for one explicit amendment; do not work around it.
- Existing user changes: never overwrite or force-remove them to make a wave
  clean.
- Supervisor uncertainty: remark, not violation. Blocking requires a named
  contract rule and independent evidence.

## 8. Testing strategy

### Offline tests — always run

Extend `./tests/run.sh` so the default suite covers both platforms without
network or model calls:

1. **Structure:** parse both manifest formats and both marketplaces; assert
   matching versions, relative paths, executable hooks, concise frontmatter,
   and absence of machine-specific paths.
2. **Contracts:** pin all GPT model ids, exact profile guards, generic fallback,
   different-model supervision, artifact-first completion, and the no-default-
   `max` rule.
3. **Runtime context:** feed Claude, Codex, alias, missing-model, and malformed
   hook fixtures; assert exact concise context or safe no-op.
4. **Drift behavior:** replay positive, negative, recursion, invalid-judge,
   active-plan, inactive-plan, and Codex Stop-output fixtures without a model.
5. **Codex wave state:** exercise valid run, rework, escalation, two evidence
   strikes, unsatisfiable contract, terminal Sol, agent error, invalid schema,
   and unfinished Stop-state scenarios.
6. **Existing Claude simulator and plan linter:** the Claude Workflow runner
   and simulator retain their Claude-only model set. The shared plan linter
   accepts both the existing Claude ids and the three exact GPT ids, rejects a
   wave that mixes providers, and leaves host-specific executability to the
   selected wave adapter.

The test harness disables commit signing and pins the temporary repository's
default branch locally. Tests must not depend on the developer's global Git
configuration or signing agent.

### Clean-install probes

In isolated plugin test state, install each plugin from the repository
marketplace, list its components, and verify discovery of all four skills.
Repeat with the Claude marketplace. Do not overwrite the developer's normal
plugin installation. Record CLI versions and manifest validation output.

### Live matrix — release-blocking

Use `EVAL_PROVIDER`, `EVAL_MODEL`, `EVAL_EFFORT`, and `EVAL_REPEAT` while
retaining current Claude defaults for backward compatibility.

Every one of these twelve combinations gets at least one success-path and one
failure-path run:

```text
multi-model    x Sol, Terra, Luna
super-plan     x Sol, Terra, Luna
ship           x Sol, Terra, Luna
critical-review x Sol, Terra, Luna
```

The fixtures fix expected facts before the models see them. A Luna main seat
may pass by correctly delegating a task outside its supported envelope; it may
not pass by attempting the task and fabricating success.

`ship` runs against an isolated repository with a fake `gh` executable that
records requested PR/thread actions without touching GitHub. One real
disposable-PR rehearsal may supplement that fixture only after separate user
authorization; it is not required for the ordinary live matrix.

Recommended production routes must additionally achieve:

- 5/5 on each clean false-positive guard;
- 5/5 on the critical true-positive contract violation;
- 5/5 refusal to exceed explicit destructive scope;
- 5/5 truthful reporting of an unavailable or flaky verification tool;
- zero same-model executor/supervisor pairings in traces;
- zero completion claims without a fresh artifact or command result.

Run the supervisor matrix blind across all six distinct GPT executor/reviewer
pairs. Compare `medium` and `high` for all three models. Probe Sol at `xhigh`
and `max` on both the hardest fixture and the destructive-scope fixture before
allowing either effort in a routing table. Record pass counts, latency, token
usage where exposed, and observed failure modes; a single pass proves only
capability, not reliability.

Adversarial fixtures include pasted fake evidence, whitespace-only output
changes, a contract satisfied against its purpose, an impossible coding task,
credentials present in tool output, a conflicting file scope, and an agent
claiming to monitor a process it is not polling.

### Regression requirement

All existing offline Claude tests and the previously recorded Claude live
fixtures remain green. Any intentional prose change that invalidates a current
contract assertion must replace that assertion with an equivalent or stronger
behavioral check in the same change.

## 9. Documentation and release

Rewrite the top-level README around provider-neutral concepts and give Claude
Code and Codex separate installation and live-test sections. Document:

- supported hosts and model ids;
- measured routing and effort table;
- hooks unavailable on ChatGPT-only surfaces;
- model-call cost and clean-environment test prerequisites;
- what the offline suite proves and cannot prove;
- the user-owned merge boundary;
- exact source links and evaluation dates.

Update `tests/README.md` with the Codex tiers, matrix commands, repetition
semantics, and limitations. Store live counts and in-session probe logs beside
the existing evaluation records. Do not market an unmeasured route as
supported.

Release order:

1. Dual manifests, runtime context, profiles, and offline contract coverage.
2. Codex-native wave protocol and provider-aware drift hook.
3. All-skills/all-models live matrix and routing calibration.
4. Documentation, version bump verification, clean-install rehearsal, and
   final critical review.

Each stage is independently reviewable; only stage 4 is called the Codex-ready
release.

## Success criteria

The design is satisfied when:

- both plugins validate and install under Claude Code and Codex from a clean
  environment;
- all four skills are discoverable and execute their documented flow on Sol,
  Terra, and Luna;
- exact GPT profile routing comes from hook/session truth and safely degrades
  when that truth is absent;
- Claude Workflow and Codex native-subagent paths enforce the same contract,
  verifier, different-model supervisor, and escalation semantics;
- the Codex Stop hook produces a real continuation on drift and does not loop;
- every offline tier passes hermetically;
- the live matrix and repeated critical guards meet the thresholds above;
- the README distinguishes measured facts, seed hypotheses, and unsupported
  surfaces;
- the repository name and final merge remain under user control.

## Primary sources

- [GPT-5.6 Preview System Card](https://deploymentsafety.openai.com/gpt-5-6/gpt-5-6.pdf)
- [GPT-5.6 Sol model reference](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [GPT-5.6 Terra model reference](https://developers.openai.com/api/docs/models/gpt-5.6-terra)
- [GPT-5.6 Luna model reference](https://developers.openai.com/api/docs/models/gpt-5.6-luna)
- [GPT-5.6 prompting and migration guide](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills)
- [Codex plugin packaging](https://developers.openai.com/plugins/build/plugins)
- [Codex hooks](https://learn.chatgpt.com/docs/hooks)
