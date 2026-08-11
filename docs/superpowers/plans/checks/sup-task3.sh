#!/usr/bin/env bash
set -uo pipefail
F=plugins/orchestration/skills/multi-model/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "wave plan artifact section exists" \
  "grep -q '^## Wave Plan Artifact' $F"
check "contract is a mandatory block" \
  "grep -q '6. \*\*Contract:\*\*' $F"
for k in files_allowed files_forbidden must_run forbidden_moves report_must_answer; do
  check "contract field $k" "grep -q '$k' $F"
done
check "evidence: required is specified" \
  "grep -q 'evidence: required' $F"
check "a claim without output is itself a violation" \
  "grep -q 'violation in its own right' $F"
check "block count updated from five to six" \
  "grep -q 'all six blocks' $F"
# Bracketed patterns on purpose: this file must not contain the words it forbids.
check "no third-party reference implementation is named" \
  "! grep -riq '[k]ent\|[r]espawn' $F"

exit $fail
