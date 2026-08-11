#!/usr/bin/env bash
set -uo pipefail
F=plugins/orchestration/skills/multi-model/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "anti-deception section exists" "grep -q '^## Anti-Deception Rules' $F"
check "rules explicit, checks opaque" "grep -q 'Rules explicit, checks opaque' $F"
check "supervisor is never the executor's model" "grep -q 'never the executor' $F"
for c in "161–163" "109–110" "171–181" "p. 81" "37–39" "170–171" "33–35" "122–124" "202–203"; do
  check "citation $c survives" "grep -qF '$c' $F"
done
check "checklist consumes verdicts" "grep -q 'supervisor verdict' $F"
check "mistake row: supervising with the executor's own model" \
  "grep -q '^| Supervising with the executor' $F"
check "mistake row: disclosing the checks" \
  "grep -q '^| Telling the executor how compliance is measured' $F"
check "mistake row: claim with no command output" \
  "grep -q '^| Accepting a claim with no command output' $F"
check "mistake row: forged evidence as ordinary failure" \
  "grep -q '^| Treating forged evidence as an ordinary failure' $F"
check "mistake row: blocking on suspicion" \
  "grep -q '^| Blocking on suspicion rather than on a contract violation' $F"
# Bracketed patterns on purpose: this file must not contain the words it forbids.
check "no third-party reference implementation is named" \
  "! grep -riq '[k]ent\|[r]espawn' $F"

exit $fail
