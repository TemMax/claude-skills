# In-session probe of the wave-runner boundary

The simulator tier proves the ladder's semantics offline. What it cannot prove
is the real `Workflow` launcher accepting the script and a real model driving
it. The tool-call layer routinely delivers the `args` parameter as a
JSON-encoded string rather than an object — reproduced 3/3 across headless
`claude -p` (two models, three prompt phrasings) and also seen from an
interactive session (run wf_e9a784c4-731, 2026-08-12), where a pre-fix runner
returned `invalid-args` for a perfectly valid wave. The runner is now
parse-then-validate: a string that `JSON.parse`s into a valid object is
accepted, and anything else still fails closed by name. `tests/eval/wave.sh`
now asserts a real wave result over that path rather than skipping; this
in-session probe remains the full-fidelity check of the actual `Workflow`
launcher and a real model driving the ladder.

1. Build the fixture repo and args file: run the fixture block of
   `tests/eval/wave.sh` by hand, or let the session do it (everything up to
   the `section` line).
2. In the session, invoke:

   Workflow({
     scriptPath: "<repo>/plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs",
     args: <the parsed contents of args.json — a real object, not a string>
   })

3. The probe passes when all three hold:
   - the launch is accepted (no rejection about meta, exports, or parsing);
   - the returned JSON has `status` and a `divide-guard` task entry;
   - that entry's `status` is one of `ok | failed | contract-unsatisfiable | error`
     (a real verdict was produced; `invalid-args` or a missing entry is a fail).
4. Record the date and result in this file.

## Probe log

| Date | Result | Notes |
|---|---|---|
| 2026-08-12 | launch accepted; pre-fix runner returned invalid-args (args delivered as string), which motivated parse-then-validate | run wf_e9a784c4-731, interactive session |
| 2026-08-12 | PASS end-to-end on the parse-then-validate runner: `status: done`, task `divide-guard` → `ok` on rung 0 (haiku executor + haiku supervisor, verdict `{ok:true, violations:[], remarks:[]}`), 2 agents, ~150s. Artifact verified independently of the report: branch `wave/divide-guard` exists, the diff is the correct `src/calc.py` guard, the suite passes in the worktree | run wf_e8701785-804, interactive session |
| 2026-08-12 | Resume replay: same run re-invoked with `resumeFromRunId` returned the identical result in 18ms, 0 tokens, 0 tool uses — both agents from cache. The amendment-flow cache claim in SKILL.md is now live-proven | run wf_e8701785-804 (resume) |
| 2026-08-12 | DEFECT then FIX, unsatisfiable-contract path. Pre-fix: honest executor stopped (empty diff), supervisor returned `ok:true` with the whole unsatisfiability analysis in `remarks` — the runner reported the task done with a red suite. Fix: supervisor prompt now states an unsatisfiable contract still fails the verdict; pinned by eval fixture F4. Post-fix re-run (executor replayed from cache, supervisor live): `ok:false`, `must_run` violation with `satisfiable:false` and `pasteReproduced:true`, runner returned `contract-unsatisfiable` after one attempt — no rework, no escalation. The satisfiable rung has now executed live, correctly | run wf_160ccefe-e00 (initial + resume), interactive session |
