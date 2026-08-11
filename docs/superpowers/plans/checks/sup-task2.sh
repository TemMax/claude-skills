#!/usr/bin/env bash
set -uo pipefail
F=plugins/orchestration/skills/multi-model/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "wave isolation section exists" \
  "grep -q '^## Wave Isolation' $F"
check "per-task worktree is required" \
  "grep -q 'its own git worktree' $F"
check "branch convention is stated" \
  "grep -q 'wave/<task-id>' $F"
check "base SHA is recorded before the wave" \
  "grep -q 'base SHA' $F"
check "the old shared-tree advice is gone" \
  "! grep -q 'may appear or disappear under' $F"
# Bracketed patterns on purpose: this file must not contain the words it forbids.
check "no third-party reference implementation is named" \
  "! grep -riq '[k]ent\|[r]espawn' $F"

exit $fail
