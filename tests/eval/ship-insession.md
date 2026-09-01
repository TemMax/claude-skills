# In-session probe of ship

ship is a conductor: its behavior is two gates' worth of dialogue, three
skill invocations, and git/PR side effects. None of that runs headless
without spending real waves against a real remote, so there is no automated
tier — the contract greps pin the load-bearing prose, and everything
behavioral is recorded here, from real runs.

Procedure: deliver the next real feature with `ship`; record the date, the
feature, whether the single up-front gate was the only ship-level stop, how
findings were routed (inline vs fix-wave, and whether the behavior rule held),
whether the thread phase ran through critical-review's gate, and where the
run ended (PR link; the merge must have been left to the user).

## Probe log

| Date | Feature | One gate only? | Findings routed (inline/wave) | Threads via CR gate? | Ended at |
|---|---|---|---|---|---|
| 2026-09-01 | Fable 5.1 support (`fable-5-1-support`, orchestrator on `claude-fable-5-1` with no installed profile — the run that created it) | Yes: one branch/PR gate up front; the only other stops were super-plan's question batch and its two gates | 8 review findings, all prose (judge-bias wording overclaim, a narrowed security claim, a cite page, a variance note, three consistency nits) → applied inline by the orchestrator, committed and pushed; no fix-wave was needed because no finding changed behavior | Not exercised: the PR had zero threads, so critical-review's fix gate had nothing to publish | PR #5 open, merge left to the user |
