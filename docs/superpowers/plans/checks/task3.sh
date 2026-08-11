#!/usr/bin/env bash
set -uo pipefail
F=plugins/code-review/skills/critical-review/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "the section exists" \
  "grep -q '^## Post-Review Fix Protocol' $F"
check "the section is gated on an explicit user request" \
  "grep -q 'only after the user' $F"
check "the read-only review rule is still present verbatim" \
  "grep -q 'The review is read-only: do not mutate the working tree' $F"
check "starting HEAD is recorded before fixes" \
  "grep -q 'git rev-parse HEAD' $F"
check "commits are created before the gate" \
  "grep -q 'before the gate' $F"
check "cancel is a soft reset" \
  "grep -q 'git reset --soft' $F"
check "execution order is push then replies then resolves" \
  "grep -q 'push\` → replies → resolves' $F"
check "preflight does not use repository permission" \
  "! grep -q 'viewerPermission' $F"
check "identity is fetched for the idempotency check" \
  "grep -q 'gh api user --jq .login' $F"
check "reply endpoint is present" \
  "grep -q 'comments/<databaseId>/replies' $F"
check "resolve mutation is present" \
  "grep -q 'resolveReviewThread(input:{threadId:\$id})' $F"
check "resolve requires a complete fix" \
  "grep -q 'closes the comment completely' $F"
check "reply language follows the thread" \
  "grep -q 'language of the thread being answered' $F"
check "replies carry the idempotency marker" \
  "grep -q 'critical-review-fix-reply' $F"
check "idempotency skips on the marker, not on authorship" \
  "grep -q 'never on bare authorship' $F"
check "failure-case table exists" \
  "grep -q 'push\` rejected (needs rebase)' $F"

exit $fail
