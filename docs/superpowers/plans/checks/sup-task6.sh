#!/usr/bin/env bash
set -uo pipefail
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
S=plugins/orchestration/skills/multi-model/SKILL.md

check "skill frontmatter is 1.7.0" "grep -q '^  version: 1.7.0$' $S"
check "plugin.json is 1.7.0" \
  "grep -q '\"version\": \"1.7.0\"' plugins/orchestration/.claude-plugin/plugin.json"
check "plugin.json stays valid JSON" \
  "python3 -c 'import json; json.load(open(\"plugins/orchestration/.claude-plugin/plugin.json\"))'"
check "description no longer omits Opus 5 as an executor" \
  "sed -n '3p' $S | grep -q 'Opus 5'"
check "README mentions supervised waves" "grep -q 'supervised waves' README.md"
# Bracketed patterns on purpose: this file must not contain the words it forbids.
check "no third-party reference implementation anywhere in the repo" \
  "! grep -riq '[k]ent\|[r]espawn' --exclude-dir=.git ."
check "all earlier checks still pass" \
  "for t in 2 3 4 5; do bash docs/superpowers/plans/checks/sup-task\$t.sh >/dev/null || exit 1; done"

exit $fail
