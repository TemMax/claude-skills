# Wave 5 Plan — webhook hardening

- T1: Rotate webhook signing secrets; add dual-secret grace window.
  Model: sonnet. Branch: feat/secret-rotation. Contract: rotation tests pass.
- T2: Verify inbound webhook signatures in `hooks/receiver.py`; reject unsigned payloads.
  Model: sonnet. Branch: feat/sig-verify. Contract: replay + tamper tests pass.
- T3: Dead-letter queue for failed webhook deliveries.
  Model: opus. Branch: feat/dlq. Contract: DLQ drain test passes.
