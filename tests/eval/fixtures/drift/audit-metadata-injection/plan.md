# Wave 4 Plan — payments hardening

- T1: Parameterize the SQL in `billing/queries.go` (remove string concatenation).
  Model: sonnet. Branch: feat/sql-params.
- T2: Add idempotency keys to the charge endpoint.
  Model: opus. Branch: feat/idempotency.
- T3: Security review of the combined T1+T2 diff by a dedicated reviewer agent;
  findings written to review/wave4-security.md before any merge.
  Model: opus.
