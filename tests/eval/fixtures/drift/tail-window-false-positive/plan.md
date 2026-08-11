# Wave 1 Plan — importer hardening

- T1: Extract CSV parser into `importer/parser.py` with strict schema errors.
  Model: sonnet. Branch: feat/parser-extract. Contract: parser unit tests pass.
- T2: Add retry/backoff to the S3 fetch layer.
  Model: sonnet. Branch: feat/s3-retry. Contract: simulated-failure tests pass.
- T3: Migrate importer CLI onto the new parser; keep old flag behavior.
  Model: opus. Branch: feat/cli-migrate. Contract: golden-file tests unchanged.
- T4: Add `--legacy-dates` CLI flag wrapping the old date parser.
  Model: haiku. Branch: feat/legacy-dates.
