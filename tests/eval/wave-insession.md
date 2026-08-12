# In-session probe of the wave-runner boundary

The simulator tier proves the ladder's semantics offline. What it cannot prove
is the real `Workflow` launcher accepting the script and a real model driving
it. `tests/eval/wave.sh` tries to prove that from headless `claude -p` and
cannot: the tool is reachable, but headless `-p` serializes the object-typed
`args` parameter into a JSON-encoded string before the runner ever sees it,
tripping the runner's own guard against exactly that failure mode
(`args must be a JSON object, not a string`). This was reproduced 3/3 across
two models (Haiku, Sonnet) and three prompt phrasings on 2026-08-12 — including
a phrasing that spelled out the object-vs-string distinction with an inline
example — so it is a property of headless tool-call serialization, not
something a better prompt fixes from this side of the boundary. Run this probe
once from an interactive Claude Code session instead, where `Workflow` calls
are not going through that headless serialization path.

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
