#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "skill frontmatter is 1.3.0" \
  "grep -q '^  version: 1.3.0$' plugins/code-review/skills/critical-review/SKILL.md"
check "plugin.json is 1.3.0" \
  "grep -q '\"version\": \"1.3.0\"' plugins/code-review/.claude-plugin/plugin.json"
check "plugin.json stays valid JSON" \
  "python3 -c 'import json,sys; json.load(open(\"plugins/code-review/.claude-plugin/plugin.json\"))'"
check "README mentions the fix phase" \
  "grep -q 'post-review fix phase' README.md"
check "all previous task checks still pass" \
  "bash docs/superpowers/plans/checks/task2.sh >/dev/null && bash docs/superpowers/plans/checks/task3.sh >/dev/null && bash docs/superpowers/plans/checks/task4.sh >/dev/null"

exit $fail
