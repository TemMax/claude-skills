# Codex-native supervised wave protocol

Use this protocol only for a GPT-5.6-only wave. It is the host adapter for the
shared wave contract, mechanical verifier, supervisor verdict schema,
escalation ladder, and result review in `SKILL.md`; it does not redefine any of
them. Claude-only waves use `wave-runner.workflow.mjs` instead. A mixed or
unknown-provider wave stops before any agent is spawned.

All commands in this reference resolve from the multi-model skill base directory:
the sibling plan linter is `../super-plan/references/plan-lint.mjs`, and the
state helper is `references/codex-wave-state.mjs`. A lint-clean plan that the
user explicitly approved is authoritative for adapter execution: use its exact
provider, model, and effort fields; do not re-route or reject them against seed
profile recommendations. This does not permit mixed/unknown providers or bypass
lint and user approval.

The state helper is the only state machine. Never hand-edit its state, bypass a
helper action, write a fresh runner, force-remove a worktree, or substitute a
missing model with a default or alias. It accepts only the exact GPT model IDs
and effort values already linted in the plan.

## Commands and action loop

The helper has exactly these seven commands:

```text
init  next  record-executor  verify  supervisor-prompt  record-verdict  summary
```

1. Run the canonical plan linter first. Stop on every linter error; do not
   repair a plan by hand during a live wave.

   ```sh
   node ../super-plan/references/plan-lint.mjs <plan-file> --repo <repo>
   ```

2. Resolve the exact fork point from the pushed default-branch tip and push it
   before spawning. Copy the full SHA from `git rev-parse origin/<default-branch>`;
   never use a local-only `HEAD`. Initialize one wave state and retain the
   returned state path:

   ```sh
   node references/codex-wave-state.mjs init \
     --plan <plan-file> --wave <N> --repo <absolute-repo> --base <pushed-full-sha>
   ```

   `init` creates the exact returned worktrees and `wave/<task-id>` branches.
   A conflict is a stop: preserve the existing worktree, branch, and state.

3. Call `next --state <state-path>`. Perform exactly its one returned action.
   Do not infer a next action, synthesize a prompt, or advance a task yourself.
   Native coordination uses `spawn_agent`, `followup_task`, and `wait_agent`:
   wait for a child’s final response with `wait_agent`; use `followup_task` only
   to deliver the helper-returned prompt as the entire message to an existing
   child. Do not add context, summaries, or supervision instructions.

4. For `spawn-executor`, create or re-trigger the executor with the returned
   `prompt` as its only task text. The executor receives only that
   helper-returned prompt and works only in the exact returned `worktree`.
   Every new `spawn_agent` call explicitly passes the returned exact `model`
   and exact `effort` as `reasoning_effort`; a missing value stops the wave.

   ```js
   await spawn_agent({
     task_name: `wave-${action.task}-executor`,
     fork_turns: "none",
     model: action.model,
     reasoning_effort: action.effort,
     message: action.prompt,
   })
   ```

   Record only the child’s final report, never hidden reasoning, tool traces,
   or an orchestrator paraphrase:

   ```sh
   printf '%s' '{"report":"<final report only>"}' | \
     node references/codex-wave-state.mjs record-executor \
       --state <state-path> --task <task-id>
   ```

5. For `verify`, run the helper’s mechanical verifier — do not ask a model to
   replace it:

   ```sh
   node references/codex-wave-state.mjs verify --state <state-path> --task <task-id>
   ```

   Then obtain the sole supervisor input from the helper:

   ```sh
   node references/codex-wave-state.mjs supervisor-prompt \
     --state <state-path> --task <task-id>
   ```

   The helper supplies the shared contract, verifier facts, redacted report,
   and existing supervisor prompt. Do not name or reveal executor identity in
   the supervisor prompt.

6. For `spawn-supervisor`, use the returned `model` and `effort`. It is the
   different exact model selected by `next`; never choose an alternative based
   on a label, availability guess, or default. Spawn the supervisor with the
   helper-returned supervisor prompt as its only task text and require its fixed
   verdict JSON. Pass that JSON unchanged to the recorder:

   ```js
   await spawn_agent({
     task_name: `wave-${action.task}-supervisor`,
     fork_turns: "none",
     model: action.model,
     reasoning_effort: action.effort,
     message: supervisorPrompt.prompt,
   })
   ```

   ```sh
   printf '%s' '<fixed verdict JSON>' | node references/codex-wave-state.mjs \
     record-verdict --state <state-path> --task <task-id>
   ```

7. If a native agent or tool returns no result, has a transport failure, or is
   unavailable, record exactly one fixed payload at the applicable point:

   ```json
   {"error":{"kind":"null-result"}}
   ```

   ```json
   {"error":{"kind":"transport"}}
   ```

   ```json
   {"error":{"kind":"tool-unavailable"}}
   ```

   Send a fixed error to `record-executor` for an executor failure or
   `record-verdict` for a supervisor failure. Do not persist free-form
   transport output, request hidden reasoning, fabricate a report/verdict, or
   reinterpret an infrastructure failure as success.

8. After every recorder response, call `next` again and repeat exactly the
   returned action. `stop` preserves every state file and branch; return the
   helper summary, verdict history, and branch names to the user without retrying
   outside the helper.

9. On `merge-ready`, wait until the final wave result is merge-ready, then call
   `summary --state <state-path>`. Confirm every task is `ok`, merge all `ok`
   branches in plan/task order, run the shared full-wave review, and push. Only
   after that push, derive the next wave’s exact base from the pushed branch and
   initialize its state with `init`. Do not merge early in a multi-task wave.

The action loop is intentionally narrow: helper state records reports, verifier
facts, and fixed verdicts only. It never stores credentials or hidden reasoning.
