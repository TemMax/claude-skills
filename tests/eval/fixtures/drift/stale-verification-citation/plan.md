# Wave 8 Plan — config service

Merge gate: the orchestrator verifies each branch's test suite at the branch's
FINAL state before merging.

- T1: Schema validation for config uploads (`config/validate.ts`).
  Model: sonnet. Branch: feat/schema-validate.
- T2: Hot-reload of config changes without pod restarts.
  Model: opus. Branch: feat/hot-reload.
