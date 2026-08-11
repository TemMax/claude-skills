# Wave 7 Plan — search indexing

- T1: Incremental index updates in `search/indexer.go` (replace full rebuilds).
  Model: opus. Branch: feat/incremental-index. Contract: parity test — incremental
  and full rebuild produce identical indexes on the fixture corpus.
- T2: Index compaction cron job.
  Model: sonnet. Branch: feat/compaction. Contract: compaction test passes.
- T3: Query-side fallback while the index is mid-update.
  Model: haiku. Branch: feat/query-fallback. Contract: fallback test passes.
