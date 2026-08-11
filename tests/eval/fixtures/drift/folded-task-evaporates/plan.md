# Wave 2 Plan — rate limiting

- T1: Implement token-bucket rate limiter middleware in `gateway/middleware/ratelimit.go`.
  Model: sonnet. Branch: feat/rl-middleware.
  Contract: unit tests for burst + refill behavior pass.
- T2: Redis-backed bucket store in `gateway/store/redis_bucket.go`.
  Model: sonnet. Branch: feat/rl-store.
  Contract: store passes the shared BucketStore conformance suite against a real Redis.
- T3: Wire limiter into the gateway request path; integration tests.
  Model: opus. Branch: feat/rl-wire.
  Contract: integration suite runs against BOTH the in-memory store and the Redis store.
- T4: Update docs/rate-limiting.md with config reference.
  Model: haiku. Branch: feat/rl-docs.
