#!/usr/bin/env bash
set -uo pipefail
F=plugins/orchestration/skills/multi-model/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "section exists" "grep -q '^## Supervised Waves' $F"
check "supervision is a stage, not an instruction" \
  "grep -q 'not an instruction to self-check' $F"
check "supervisor trusts artifacts only" \
  "grep -q 'artifacts only' $F"
check "pasted output is compared with the re-run" \
  "grep -q 'compare' $F && grep -q 'forged-evidence' $F"
check "verdict carries non-blocking remarks" \
  "grep -q 'remarks' $F"
check "flaky commands retry once" \
  "grep -q 'run it a second time' $F"
check "ladder has a terminal rung" \
  "grep -q 'already the strongest' $F"
check "supervisor prompt is referenced" \
  "grep -q 'references/supervisor-prompt.md' $F"
check "blocking threshold above suspicion threshold" \
  "grep -q 'Blocking correct work' $F"
check "control-flow sketch is present" \
  "grep -q 'while (true)' $F"
check "proportionality rule is stated" \
  "grep -q 'skip the supervisor model' $F"
# Bracketed patterns on purpose: this file must not contain the words it forbids.
check "the orchestrator opens the plan at launch" \
  "grep -q 'Write the wave plan file' $F"
check "the orchestrator closes the plan at completion" \
  "grep -q 'Set the wave plan.*status: done' $F"
check "the user never edits the lifecycle by hand" \
  "grep -q 'You own both transitions' $F"
check "no third-party reference implementation is named" \
  "! grep -riq '[k]ent\|[r]espawn' $F"

exit $fail
