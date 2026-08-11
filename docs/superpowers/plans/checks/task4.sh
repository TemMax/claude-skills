#!/usr/bin/env bash
set -uo pipefail
F=plugins/code-review/skills/critical-review/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "injection rule covers the reply phase" \
  "grep -q 'composed from your own applied fix' $F"

# These must anchor on the table-row form. Several of these phrases also appear
# in the Post-Review Fix Protocol prose, so a bare substring match would pass
# without the Common Mistakes row ever being added.
check "mistake row: REST thread read" \
  "grep -q '^| Reading PR threads over REST |' $F"
check "mistake row: inferring capability from repo permission" \
  "grep -q '^| Inferring write capability from repository permission |' $F"
check "mistake row: replying before the push" \
  "grep -q '^| Replying before the push |' $F"
check "mistake row: resolving a partial fix" \
  "grep -q '^| Resolving a partially addressed thread |' $F"
check "mistake row: answering a resembling thread" \
  "grep -q '^| Answering a thread that merely resembles the finding |' $F"

exit $fail
