#!/usr/bin/env bash
set -uo pipefail
F=plugins/code-review/skills/critical-review/SKILL.md
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "threads are read via GraphQL reviewThreads" \
  "grep -q 'reviewThreads(first:100, after:\$endCursor)' $F"
check "the read is paginated" \
  "grep -q -- '--paginate' $F"
check "per-thread capability fields are fetched" \
  "grep -q 'viewerCanReply viewerCanResolve' $F"
check "root comment databaseId is fetched for replies" \
  "grep -q 'root: comments(first:1)' $F"
check "latest comment authors are fetched for idempotency" \
  "grep -q 'latest: comments(last:10)' $F"
check "node count is reconciled against totalCount" \
  "grep -q 'totalCount' $F"
# The prose deliberately names the REST endpoint to explain why it is unusable,
# so this must match the invocation form, not any mention of the path.
check "REST is no longer invoked to read inline threads" \
  "! grep -q 'gh api repos/{owner}/{repo}/pulls/<n>/comments' $F"
check "issue-level comment read is retained" \
  "grep -q 'gh pr view <n> --comments' $F"
check "review verdict read is retained" \
  "grep -q 'pulls/<n>/reviews' $F"
check "the ledger is written to a file" \
  "grep -qi 'ledger' $F && grep -qi 'scratchpad' $F"
check "provenance marker format is defined" \
  "grep -q 'thread:<threadId>:<rootCommentDatabaseId>' $F"
check "own-provenance marker is defined" \
  "grep -q '\`own\`' $F"

exit $fail
