# API validation log — post-review fix protocol

Date: 2026-08-11 · gh version: 2.83.2 (2025-12-10)
Scratch repo: `TemMax/claude-skills-scratch-prvalidation`, PR #1 (deleted after validation)

The design spec left two operations unexecuted, because proving them requires
really writing into a pull request. Both were run here against a throwaway
private repository.

| Operation | Command form | Result |
|---|---|---|
| Create inline review comment | `gh api repos/O/R/pulls/N/comments -f body -f commit_id -f path -F line=2 -f side=RIGHT` | `{"id":3758842768,"line":2,"path":"probe.txt"}` |
| Read threads (paginated) | `gh api graphql --paginate` with `reviewThreads(first:100, after:$endCursor)`, aliases `root: comments(first:1)` and `latest: comments(last:10)` | `totalCount: 1`, `hasNextPage: false`, `id: PRRT_kwDOT1Wy4c6YQr4W`, `root.databaseId: 3758842768` — matches the REST id exactly |
| Reply in thread | `gh api repos/O/R/pulls/N/comments/<databaseId>/replies -f body='...'` | `{"id":3758845467,"in_reply_to_id":3758842768}` — created, correctly threaded |
| Resolve thread | `gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id=PRRT_...` | `{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}` |

`-f id=PRRT_...` binds correctly to the non-null `ID!` variable — no `-F` or
JSON encoding needed.

## Idempotency signal

After the reply and the resolve, re-reading the thread returns:

```json
{"isResolved": true, "lastAuthor": "TemMax", "lastBody": "Fixed in 0000000 — probe reply."}
```

`gh api user --jq .login` returns `TemMax`. So the rule the skill relies on —
skip a thread whose latest comment author is your own login, or that is already
`isResolved` — has both of its signals available and correct. A retry after a
partial failure will not double-post.

## Open question from the spec — still open

`viewerCanResolve` came back `true` on this PR, but the validating account holds
**ADMIN** on the scratch repository (`gh repo view --json viewerPermission` →
`ADMIN`). That means this run does **not** answer the spec's question of whether
a pull request author holding only `READ` gets `viewerCanResolve: true` on their
own PR. Answering it needs a PR opened from a fork against a repository the
account does not own.

This does not block anything: the skill reads `viewerCanResolve` per thread
rather than inferring it, which is precisely why the question can stay open.

## Deviations from the spec

None. Every command form in the spec worked as written, including both
`comments` aliases in a single query and `--paginate`.
