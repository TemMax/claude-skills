# Wave 3 Plan — auth refactor

- T1: Split session validation out of `auth/middleware.ts` into `auth/session.ts`.
  Model: sonnet. Branch: feat/session-split.
- T2: Replace hand-rolled JWT parsing with `jose`; keep claim-validation behavior.
  Model: opus. Branch: feat/jose-migrate.
- T3: Delete dead `auth/legacy/` tree and its test fixtures.
  Model: haiku. Branch: feat/legacy-rm.

Merge gate (applies to every task): the orchestrator re-runs that branch's
test suite itself and sees it pass before merging. An executor's own report
of green tests does not satisfy the gate.
