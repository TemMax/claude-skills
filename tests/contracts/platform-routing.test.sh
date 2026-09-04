#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh

MM=plugins/orchestration/skills/multi-model/SKILL.md
SP=plugins/orchestration/skills/super-plan/SKILL.md
SH=plugins/orchestration/skills/ship/SKILL.md
CR=plugins/code-review/skills/critical-review/SKILL.md

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

summary
