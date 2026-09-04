#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh

MM=plugins/orchestration/skills/multi-model/SKILL.md
SP=plugins/orchestration/skills/super-plan/SKILL.md
SH=plugins/orchestration/skills/ship/SKILL.md
CR=plugins/code-review/skills/critical-review/SKILL.md

section "skill discovery stays trigger-first and preserves boundaries"

expect "multi-model discovery description" \
  "description: 'Use when implementation work should be delegated, parallelized, or routed across Claude or GPT-5.6 agents, especially when isolated worktrees and independent supervision are required. Do not use for single-agent work.'" \
  "$(sed -n '3p' "$MM")"
expect "super-plan discovery description" \
  "description: 'Use when a feature or change needs a wave-ready implementation plan for parallel or multi-agent execution. Do not use to implement the plan.'" \
  "$(sed -n '3p' "$SP")"
expect "ship discovery description" \
  "description: 'Use when the user wants the complete delivery pipeline from planning through a reviewed pull request. Do not use for a single planning, implementation, or review stage, and never merge.'" \
  "$(sed -n '3p' "$SH")"
expect "critical-review discovery description" \
  "description: 'Use when the user requests evidence-based review of uncommitted changes or a GitHub pull request, with optional follow-up fixes and thread resolution. Do not use as an orchestration-wave supervisor.'" \
  "$(sed -n '3p' "$CR")"

section "all skills resolve one active-seat profile from runtime context"

check "no universal Claude skill dir" \
  "! rg -q 'CLAUDE_SKILL_DIR' plugins/*/skills/*/SKILL.md"
check "no universal Claude effort variable" \
  "! rg -q 'CLAUDE_EFFORT' plugins/*/skills/*/SKILL.md"
check "runtime context contract named" \
  "[ \$(rg -l 'PLUGIN_RUNTIME_CONTEXT_V1' plugins/*/skills/*/SKILL.md | wc -l | tr -d ' ') -eq 4 ]"
check "one-profile rule is named by every skill" \
  "[ \$(rg -l 'Never load more than one active-seat profile' \"$MM\" \"$SP\" \"$SH\" \"$CR\" | wc -l | tr -d ' ') -eq 4 ]"
check "config identity guessing is forbidden by every skill" \
  "[ \$(rg -l 'Never read a user config file to guess a session override' \"$MM\" \"$SP\" \"$SH\" \"$CR\" | wc -l | tr -d ' ') -eq 4 ]"

section "orchestration skills map every supported GPT id and generic fallback"

for skill in "$SP" "$SH"; do
  check "$skill maps Sol" \
    "grep -qF '| \`gpt-5.6-sol\` | \`../multi-model/references/orchestrator-gpt-5-6-sol.md\` |' '$skill'"
  check "$skill maps Terra" \
    "grep -qF '| \`gpt-5.6-terra\` | \`../multi-model/references/orchestrator-gpt-5-6-terra.md\` |' '$skill'"
  check "$skill maps Luna" \
    "grep -qF '| \`gpt-5.6-luna\` | \`../multi-model/references/orchestrator-gpt-5-6-luna.md\` |' '$skill'"
  check "$skill maps unknown identity to generic" \
    "grep -qF '| unknown | \`../multi-model/references/orchestrator-generic.md\` |' '$skill'"
done

check "multi-model maps Sol" \
  "grep -qF '| \`gpt-5.6-sol\` | \`references/orchestrator-gpt-5-6-sol.md\` |' '$MM'"
check "multi-model maps Terra" \
  "grep -qF '| \`gpt-5.6-terra\` | \`references/orchestrator-gpt-5-6-terra.md\` |' '$MM'"
check "multi-model maps Luna" \
  "grep -qF '| \`gpt-5.6-luna\` | \`references/orchestrator-gpt-5-6-luna.md\` |' '$MM'"
check "multi-model maps unknown identity to generic" \
  "grep -qF '| unknown | \`references/orchestrator-generic.md\` |' '$MM'"

section "critical-review maps every supported GPT id and generic fallback"

check "critical-review maps Sol" \
  "grep -qF '| \`gpt-5.6-sol\` | \`references/reviewer-gpt-5-6-sol.md\` |' '$CR'"
check "critical-review maps Terra" \
  "grep -qF '| \`gpt-5.6-terra\` | \`references/reviewer-gpt-5-6-terra.md\` |' '$CR'"
check "critical-review maps Luna" \
  "grep -qF '| \`gpt-5.6-luna\` | \`references/reviewer-gpt-5-6-luna.md\` |' '$CR'"
check "critical-review maps unknown identity to generic" \
  "grep -qF '| unknown | \`references/reviewer-generic.md\` |' '$CR'"

section "super-plan asks questions through host-neutral behavior"

check "super-plan has host-neutral questions" \
  "grep -qF 'host-native structured input tool' '$SP'"
check "super-plan keeps exact headless heading" \
  "grep -qF 'Assumptions (would ask)' '$SP'"
check "super-plan no longer pins a Claude-only question tool" \
  "! grep -q 'AskUserQuestion' '$SP'"

CP=plugins/orchestration/skills/multi-model/references/codex-wave-protocol.md

section "multi-model selects the native host adapter"

check "Claude adapter remains the shipped Workflow runner" \
  "grep -qF 'references/wave-runner.workflow.mjs' '$MM'"
check "GPT adapter names the Codex protocol" \
  "grep -qF 'references/codex-wave-protocol.md' '$MM'"
check "Codex spawns name exact model and effort" \
  "grep -qF 'model and reasoning_effort' '$MM'"
check "Codex protocol ships" \
  "[ -f '$CP' ]"
check "approved plan controls adapter execution" \
  "grep -qF 'approved plan is authoritative for adapter execution' '$MM'"
check "Codex protocol resolves sibling plan linter" \
  "grep -qF '../super-plan/references/plan-lint.mjs' '$CP'"
check "Codex protocol resolves state helper from its skill base" \
  "grep -qF 'multi-model skill base directory' '$CP'"

summary
