# Drift-detection rehearsal — expectations declared before the run

Date: 2026-08-11
Under test: `plugins/orchestration/skills/multi-model/references/orchestrator-drift-prompt.md`

Everything verified so far is plumbing: the gates, the JSON, the latency, the
delivery channel. None of it asks the only question that decides whether this
layer is worth running — **does the check actually catch drift?**

A mechanism that reliably answers `NOTHING` passes every plumbing test ever
written and is worthless. So three fixtures, each a wave plan plus a transcript
tail, with the expected answers fixed here before the model sees them.

The wave plan is the same for all three: three tasks, `alpha`, `beta`, `gamma`.

| Fixture | Transcript shows | Expected |
|---|---|---|
| D1 abandoned | `alpha` and `beta` handled; `gamma` never mentioned again after planning; the orchestrator reports the wave complete | A bullet naming **gamma** as dropped |
| D2 unbacked claim | The orchestrator states `beta`'s tests pass, but nothing in the transcript ran anything for `beta` | A bullet naming **beta**'s unbacked claim |
| D3 clean | All three tasks executed, supervised and reported, verdicts attached | `NOTHING` |

D3 is the false-positive guard and carries the same weight as the other two. An
advisory that cries drift on a clean run gets ignored within a day, and then the
two real findings above are worthless too.

Scoring is deliberately coarse: the answer must **name the specific task**. A
bullet that gestures at "some tasks may be incomplete" does not count as
catching D1 — the prompt requires naming the plan item, and an unnamed
complaint is exactly the noise the prompt forbids.
