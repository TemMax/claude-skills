#!/usr/bin/env bash
# Tier 3 wave probe. Claude retains the shipped Workflow boundary. Codex uses
# the native protocol/state helper and reports tool-unavailable as a named,
# release-blocking result instead of simulating native collaboration.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh
. tests/test-env.sh
. tests/eval/model-cli.sh

ROOT="$PWD"
CODEX_STATE="$ROOT/plugins/orchestration/skills/multi-model/references/codex-wave-state.mjs"
CODEX_PROTOCOL="$ROOT/plugins/orchestration/skills/multi-model/references/codex-wave-protocol.md"
MULTI_SKILL="$ROOT/plugins/orchestration/skills/multi-model/SKILL.md"
PLAN_LINT="$ROOT/plugins/orchestration/skills/super-plan/references/plan-lint.mjs"

find_state() {
  local repo="$1" candidate
  for candidate in "$repo"/.worktrees/codex-wave/*.json; do
    [ -f "$candidate" ] && { printf '%s' "$candidate"; return; }
  done
  return 1
}

make_failure_plan() { # clean-plan output
  python3 - "$1" "$2" <<'PY'
import sys

source, output = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    text = stream.read()
old = '"must_run": [{ "cmd": "python3 -m unittest discover -s tests -t .", "evidence": "required" }]'
new = '"must_run": [{ "cmd": "python3 -m unittest discover -s tests -t .", "evidence": "required" }, { "cmd": "python3 -c \\"import sys; print(\'independent verifier red\'); sys.exit(1)\\"", "evidence": "required" }]'
assert text.count(old) == 1
with open(output, "w", encoding="utf-8") as stream:
    stream.write(text.replace(old, new))
PY
}

file_sha256() {
  python3 - "$1" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest())
PY
}

capture_codex_evidence() { # expected repo base answer-source trace-source cell
  local expected="$1" repo="$2" base="$3" answer_source="$4" trace_source="$5" cell="$6"
  local evidence state before copy_hash after summary_rc wt rc
  evidence="$cell/evidence"
  mkdir -p "$evidence"
  if [ -f "$answer_source" ]; then
    command cp "$answer_source" "$evidence/final-answer.txt"
  else
    : > "$evidence/final-answer.txt"
  fi
  if [ -f "$trace_source" ]; then
    command cp "$trace_source" "$evidence/native-action-trace.txt"
  else
    : > "$evidence/native-action-trace.txt"
  fi
  printf '%s\n' "$expected" > "$evidence/expected.txt"
  printf '%s\n' "$base" > "$evidence/base.txt"
  printf '%s\n' "$repo" > "$evidence/repo.txt"

  state="$(find_state "$repo" 2>/dev/null || true)"
  if [ -n "$state" ]; then
    before="$(file_sha256 "$state")"
    command cp "$state" "$evidence/state.json"
    copy_hash="$(file_sha256 "$evidence/state.json")"
    if node "$CODEX_STATE" summary --state "$state" \
      > "$evidence/helper-summary.stdout" 2> "$evidence/helper-summary.stderr"; then
      summary_rc=0
    else
      summary_rc=$?
    fi
    after="$(file_sha256 "$state")"
    printf 'before=%s\ncopy=%s\nafter=%s\n' "$before" "$copy_hash" "$after" \
      > "$evidence/state-hashes.txt"
    printf '%s\n' "$summary_rc" > "$evidence/helper-summary.status"
    printf '%s\n' "$state" > "$evidence/canonical-state-path.txt"
  else
    printf '1\n' > "$evidence/helper-summary.status"
    printf 'missing canonical state\n' > "$evidence/helper-summary.stderr"
  fi
  [ -f "$repo/plan.md" ] && command cp "$repo/plan.md" "$evidence/plan.md"

  wt="$repo/.worktrees/wave-divide-guard"
  if git -C "$repo" rev-parse master > "$evidence/default-head.txt" 2> "$evidence/default-head.stderr"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" > "$evidence/default-head.status"
  if git -C "$wt" branch --show-current > "$evidence/task-branch.txt" 2> "$evidence/task-branch.stderr"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" > "$evidence/task-branch.status"
  if git -C "$wt" rev-parse HEAD > "$evidence/task-head.txt" 2> "$evidence/task-head.stderr"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" > "$evidence/task-head.status"
  if git -C "$wt" merge-base --is-ancestor "$base" HEAD \
    > "$evidence/task-ancestor.stdout" 2> "$evidence/task-ancestor.stderr"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" > "$evidence/task-ancestor.status"
  if (cd "$wt" && python3 -m unittest discover -s tests -t .) \
    > "$evidence/fresh-must-run.stdout" 2> "$evidence/fresh-must-run.stderr"; then
    rc=0
  else
    rc=$?
  fi
  printf '%s\n' "$rc" > "$evidence/fresh-must-run.status"
  if [ "$expected" = failure ]; then
    if (cd "$wt" && python3 -c "import sys; print('independent verifier red'); sys.exit(1)") \
      > "$evidence/fresh-independent.stdout" 2> "$evidence/fresh-independent.stderr"; then
      rc=0
    else
      rc=$?
    fi
    printf '%s\n' "$rc" > "$evidence/fresh-independent.status"
  fi
}

classify_codex() { # expected immutable-cell base
  local expected="$1" cell="$2" base="$3" evidence answer trace summary_status
  evidence="$cell/evidence"
  answer="$evidence/final-answer.txt"
  trace="$evidence/native-action-trace.txt"
  if [ ! -s "$answer" ]; then
    printf 'fail:empty-final-answer'
    return
  fi
  if [ ! -s "$trace" ]; then
    printf 'fail:empty-native-action-trace'
    return
  fi
  if grep -Eqi 'claude|Workflow' "$trace"; then
    printf 'fail:claude-workflow-in-codex-trace'
    return
  fi
  if grep -qi 'tool-unavailable' "$answer" "$trace" 2>/dev/null; then
    printf 'fail:tool-unavailable'
    return
  fi
  if ! python3 - "$trace" <<'PY' >/dev/null 2>&1
import sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
required = [
    "native:spawn-executor model=gpt-5.6-luna effort=medium",
    "native:wait executor",
    "native:spawn-supervisor model=gpt-5.6-terra effort=high",
    "native:wait supervisor",
]
positions = [lines.index(item) for item in required]
assert positions == sorted(positions)
PY
  then
    printf 'fail:invalid-native-action-trace'
    return
  fi
  if [ ! -s "$evidence/state.json" ]; then
    printf 'fail:missing-codex-wave-state'
    return
  fi
  summary_status="$(tr -d '[:space:]' < "$evidence/helper-summary.status" 2>/dev/null || true)"
  if [ "$summary_status" != 0 ]; then
    printf 'fail:invalid-helper-summary'
    return
  fi
  python3 - "$expected" "$evidence" "$base" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

expected, evidence_arg, base = sys.argv[1:]
evidence = Path(evidence_arg)

def text(name):
    return (evidence / name).read_text(encoding="utf-8")

def status(name):
    try:
        return int(text(name).strip())
    except (OSError, ValueError):
        return None

def fail(reason):
    print("fail:" + reason)
    raise SystemExit

try:
    hashes = dict(line.split("=", 1) for line in text("state-hashes.txt").splitlines())
    copied_bytes = (evidence / "state.json").read_bytes()
    copied_hash = hashlib.sha256(copied_bytes).hexdigest()
    if set(hashes) != {"before", "copy", "after"} \
            or len(set(hashes.values())) != 1 or hashes["copy"] != copied_hash:
        fail("state-changed-during-capture")
    state = json.loads(copied_bytes)
    summary = json.loads(text("helper-summary.stdout"))
    plan_text = text("plan.md")
    blocks = re.findall(r"```json wave-plan\r?\n([\s\S]*?)\r?\n```", plan_text)
    if len(blocks) != 1:
        fail("invalid-captured-state")
    plan = json.loads(blocks[0])
    wave = plan["waves"][0]
    plan_task = wave["tasks"][0]
    task = state["tasks"]["divide-guard"]
    if state.get("schema") != 1 or state.get("wave") != 1 or state.get("base") != base:
        fail("invalid-captured-state")
    if set(state.get("tasks", {})) != {"divide-guard"} or plan_task.get("id") != "divide-guard":
        fail("invalid-captured-state")
except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
    fail("invalid-captured-state")

expected_supervisor = {"model": "gpt-5.6-terra", "effort": "high"}
expected_executor = {"model": "gpt-5.6-luna", "effort": "medium"}
if wave.get("supervisor") != expected_supervisor \
        or plan_task.get("executor") != expected_executor \
        or plan_task.get("ladder") != ["gpt-5.6-sol"] \
        or state.get("supervisor") != expected_supervisor \
        or task.get("rungs") != ["gpt-5.6-luna", "gpt-5.6-sol"] \
        or task.get("rung") != 0:
    fail("wrong-plan-model-tuple")
verdicts = task.get("verdicts")
if not isinstance(verdicts, list) or not verdicts \
        or verdicts[-1].get("model") != "gpt-5.6-luna" \
        or verdicts[-1].get("effort") != "medium":
    fail("wrong-plan-model-tuple")

facts = task.get("verifierFacts")
if not isinstance(facts, list) or not facts:
    fail("invalid-terminal-state-or-evidence")
must_run = facts[-1].get("mustRun")
if not isinstance(must_run, list) or not must_run:
    fail("invalid-terminal-state-or-evidence")
primary = must_run[0]
if primary.get("cmd") != "python3 -m unittest discover -s tests -t ." \
        or not primary.get("attempts") or primary["attempts"][-1].get("exit") != 0:
    fail("invalid-terminal-state-or-evidence")
primary_output = "".join(str(primary["attempts"][-1].get(key, "")) for key in ("stdout", "stderr"))
if "Ran 2 tests" not in primary_output or "OK" not in primary_output:
    fail("invalid-terminal-state-or-evidence")

if status("default-head.status") != 0 or text("default-head.txt").strip() != base:
    fail("merged-failing-task" if expected == "failure" else "default-branch-changed")
if status("task-branch.status") != 0 or text("task-branch.txt").strip() != "wave/divide-guard" \
        or status("task-head.status") != 0 or text("task-head.txt").strip() == base \
        or status("task-ancestor.status") != 0:
    fail("invalid-task-branch-evidence")

summary_tasks = summary.get("tasks") if isinstance(summary, dict) else None
summary_task = summary_tasks[0] if isinstance(summary_tasks, list) and len(summary_tasks) == 1 else {}
fresh_output = text("fresh-must-run.stdout") + text("fresh-must-run.stderr")
if status("fresh-must-run.status") != 0 or "Ran 2 tests" not in fresh_output or "OK" not in fresh_output:
    fail("unverified-success" if expected == "success" else "invalid-fresh-primary-verifier")
if expected == "success":
    if task.get("status") != "merge-ready" or summary.get("status") != "done" \
            or summary_task.get("id") != "divide-guard" or summary_task.get("status") != "ok":
        fail("invalid-terminal-state-or-evidence")
else:
    if task.get("status") not in {"contract-unsatisfiable", "failed"} \
            or summary.get("status") != "partial" \
            or summary_task.get("status") not in {"contract-unsatisfiable", "failed"}:
        fail("invalid-terminal-state-or-evidence")
    if len(must_run) != 2 or not must_run[1].get("attempts") \
            or must_run[1]["attempts"][-1].get("exit") in {None, 0}:
        fail("missing-real-failing-verifier-facts")
    failing_output = "".join(str(must_run[1]["attempts"][-1].get(key, "")) for key in ("stdout", "stderr"))
    fresh_independent = text("fresh-independent.stdout") + text("fresh-independent.stderr")
    if "independent verifier red" not in failing_output \
            or status("fresh-independent.status") in {None, 0} \
            or "independent verifier red" not in fresh_independent:
        fail("missing-real-failing-verifier-facts")
print("pass")
PY
}

now_ms() { python3 -c 'import time; print(time.monotonic_ns() // 1000000)' ; }

record_codex_cell() { # scenario semantic expected repo base source-prompt trace
  local scenario="$1" semantic="$2" expected="$3" repo="$4" base="$5" source_prompt="$6" trace="$7"
  local slug cell prompt answer class_file status_file state_file start end elapsed eval_rc classification status
  slug="${EVAL_MODEL}-wave-${scenario}"
  cell="$EVAL_RESULTS_DIR/raw/$slug"
  if [ -e "$cell" ]; then
    printf 'wave: refusing to overwrite recorded cell %s\n' "$cell" >&2
    return 73
  fi
  mkdir -p "$cell"
  command cp "$source_prompt" "$cell/prompt.md"
  prompt="$cell/prompt.md"
  answer="$cell/final-answer.txt"
  class_file="$cell/classification.txt"
  status_file="$cell/status.txt"
  start="$(now_ms)"
  set +e
  eval_model "$repo" workspace-write "$prompt" "$answer"
  eval_rc=$?
  set -e
  end="$(now_ms)"
  elapsed=$((end - start))
  capture_codex_evidence "$expected" "$repo" "$base" "$answer" "$trace" "$cell"
  if [ "$eval_rc" -eq 0 ]; then
    classification="$(classify_codex "$expected" "$cell" "$base")"
  else
    classification="fail:model-exit-$eval_rc"
  fi
  case "$classification" in pass) status=pass ;; *) status=fail ;; esac
  state_file="$(find_state "$repo" 2>/dev/null || true)"
  printf '%s\n' "$classification" > "$class_file"
  printf 'status=%s\nexit=%s\nelapsed_ms=%s\ninput_tokens=unavailable\noutput_tokens=unavailable\ncost=unavailable\nstate=%s\n' \
    "$status" "$eval_rc" "$elapsed" "${state_file:-unavailable}" > "$status_file"
  printf 'wave\t%s\t%s\t%s\t%s\t%s\tyes\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tunavailable\tunavailable\tunavailable\n' \
    "$scenario" "$semantic" "${EVAL_PROVIDER:-codex}" "$EVAL_MODEL" "${EVAL_EFFORT:-medium}" "$status" "$classification" "$eval_rc" "$elapsed" \
    "$prompt" "$answer" "$class_file" "$status_file" >> "$ROWS"
  [ "$status" = pass ]
}

init_codex_repo() { # root success|failure
  local root="$1" mode="$2"
  R="$root/repo"
  mkdir -p "$R/src" "$R/tests" "$R/.eval"
  printf '.eval/\n.worktrees/\n' > "$R/.gitignore"
  printf 'def divide(a, b):\n    return a / b\n' > "$R/src/calc.py"
  cat > "$R/tests/test_calc.py" <<'PY'
import unittest
from src.calc import divide

class CalcTest(unittest.TestCase):
    def test_divide(self):
        self.assertEqual(divide(6, 3), 2)

    def test_divide_by_zero_returns_none(self):
        self.assertIsNone(divide(1, 0))
PY
  touch "$R/src/__init__.py" "$R/tests/__init__.py"
  if [ "$mode" = failure ]; then
    make_failure_plan tests/fixtures/plans/codex-clean.md "$R/plan.md"
  else
    command cp tests/fixtures/plans/codex-clean.md "$R/plan.md"
  fi
  git -C "$R" init -q
  git -C "$R" add -A
  git -C "$R" commit -q -m base
  BASE="$(git -C "$R" rev-parse HEAD)"
  BARE="$R/.eval/origin.git"
  git init -q --bare "$BARE"
  git -C "$R" remote add origin "$BARE"
  git -C "$R" push -q origin HEAD:master
}

evolve_test_wave() { # root success|failure
  local root="$1" expected="$2" init_out verdict worktree
  init_codex_repo "$root" "$expected"
  TEST_REPO="$R"; TEST_BASE="$BASE"
  init_out="$(node "$CODEX_STATE" init --plan "$R/plan.md" --wave 1 --repo "$R" --base "$BASE")"
  TEST_STATE="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' <<<"$init_out")"
  worktree="$R/.worktrees/wave-divide-guard"
  python3 - "$worktree/src/calc.py" <<'PY'
import sys
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    stream.write("def divide(a, b):\n    if b == 0:\n        return None\n    return a / b\n")
PY
  git -C "$worktree" add src/calc.py
  git -C "$worktree" commit -q -m 'guard division by zero'
  printf '{"report":"Implemented and tested the division-by-zero guard."}\n' \
    | node "$CODEX_STATE" record-executor --state "$TEST_STATE" --task divide-guard >/dev/null
  node "$CODEX_STATE" verify --state "$TEST_STATE" --task divide-guard >/dev/null
  if [ "$expected" = success ]; then
    verdict='{"ok":true,"violations":[],"remarks":[]}'
  else
    verdict='{"ok":false,"violations":[{"rule":"independent must_run","class":"must_run","evidence":"independent verifier red; exit 1","satisfiable":false}],"remarks":[]}'
  fi
  printf '%s\n' "$verdict" \
    | node "$CODEX_STATE" record-verdict --state "$TEST_STATE" --task divide-guard >/dev/null
  printf 'native:spawn-executor model=gpt-5.6-luna effort=medium\nnative:wait executor\nnative:spawn-supervisor model=gpt-5.6-terra effort=high\nnative:wait supervisor\n' \
    > "$R/.eval/native-trace.txt"
  printf 'Terminal %s wave result with fresh verifier evidence.\n' "$expected" > "$root/answer.txt"
}

if [ "${1:-}" = --self-test ]; then
  set -e
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

  evolve_test_wave "$W/success" success
  S_REPO="$TEST_REPO"; S_BASE="$TEST_BASE"
  mkdir -p "$W/success-cell"
  capture_codex_evidence success "$S_REPO" "$S_BASE" "$W/success/answer.txt" \
    "$S_REPO/.eval/native-trace.txt" "$W/success-cell"
  [ "$(classify_codex success "$W/success-cell" "$S_BASE")" = pass ]

  command cp -R "$W/success-cell" "$W/empty-answer"
  : > "$W/empty-answer/evidence/final-answer.txt"
  [ "$(classify_codex success "$W/empty-answer" "$S_BASE")" = 'fail:empty-final-answer' ]
  command cp -R "$W/success-cell" "$W/empty-trace"
  : > "$W/empty-trace/evidence/native-action-trace.txt"
  [ "$(classify_codex success "$W/empty-trace" "$S_BASE")" = 'fail:empty-native-action-trace' ]
  command cp -R "$W/success-cell" "$W/partial-state"
  printf '{"tasks":{}}\n' > "$W/partial-state/evidence/state.json"
  python3 - "$W/partial-state/evidence/state.json" "$W/partial-state/evidence/state-hashes.txt" <<'PY'
import hashlib, sys
digest = hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest()
open(sys.argv[2], 'w', encoding='utf-8').write(f"before={digest}\ncopy={digest}\nafter={digest}\n")
PY
  [ "$(classify_codex success "$W/partial-state" "$S_BASE")" = 'fail:invalid-captured-state' ]
  command cp -R "$W/success-cell" "$W/wrong-model"
  python3 - "$W/wrong-model/evidence/state.json" "$W/wrong-model/evidence/state-hashes.txt" <<'PY'
import hashlib, json, sys
path, hashes = sys.argv[1:]
data = json.load(open(path, encoding='utf-8'))
data['supervisor']['model'] = 'gpt-5.6-sol'
open(path, 'w', encoding='utf-8').write(json.dumps(data) + '\n')
digest = hashlib.sha256(open(path, 'rb').read()).hexdigest()
open(hashes, 'w', encoding='utf-8').write(f"before={digest}\ncopy={digest}\nafter={digest}\n")
PY
  [ "$(classify_codex success "$W/wrong-model" "$S_BASE")" = 'fail:wrong-plan-model-tuple' ]
  command cp -R "$W/success-cell" "$W/unverified"
  printf '1\n' > "$W/unverified/evidence/fresh-must-run.status"
  [ "$(classify_codex success "$W/unverified" "$S_BASE")" = 'fail:unverified-success' ]
  command cp -R "$W/success-cell" "$W/claude-trace"
  printf 'Claude Workflow\n' > "$W/claude-trace/evidence/native-action-trace.txt"
  [ "$(classify_codex success "$W/claude-trace" "$S_BASE")" = 'fail:claude-workflow-in-codex-trace' ]
  command cp -R "$W/success-cell" "$W/unrelated-trace"
  printf 'some unrelated nonempty activity\n' > "$W/unrelated-trace/evidence/native-action-trace.txt"
  [ "$(classify_codex success "$W/unrelated-trace" "$S_BASE")" = 'fail:invalid-native-action-trace' ]

  evolve_test_wave "$W/failure" failure
  F_REPO="$TEST_REPO"; F_BASE="$TEST_BASE"
  mkdir -p "$W/failure-cell"
  capture_codex_evidence failure "$F_REPO" "$F_BASE" "$W/failure/answer.txt" \
    "$F_REPO/.eval/native-trace.txt" "$W/failure-cell"
  [ "$(classify_codex failure "$W/failure-cell" "$F_BASE")" = pass ]
  command cp -R "$W/failure-cell" "$W/failure-stale-primary"
  printf '1\n' > "$W/failure-stale-primary/evidence/fresh-must-run.status"
  [ "$(classify_codex failure "$W/failure-stale-primary" "$F_BASE")" = 'fail:invalid-fresh-primary-verifier' ]
  command cp -R "$W/failure-cell" "$W/failure-late-merge"
  printf '%s\n' deadbeef > "$W/failure-late-merge/evidence/default-head.txt"
  [ "$(classify_codex failure "$W/failure-late-merge" "$F_BASE")" = 'fail:merged-failing-task' ]

  printf 'wave Codex scorer self-test: PASS\n'
  exit
fi

codex_probe() {
  : "${EVAL_RESULTS_DIR:?set EVAL_RESULTS_DIR to a new caller-owned results directory}"
  EVAL_MODEL="${EVAL_MODEL:-gpt-5.6-sol}"
  EVAL_EFFORT="${EVAL_EFFORT:-medium}"
  EVAL_PROVIDER=codex
  export EVAL_MODEL EVAL_EFFORT EVAL_PROVIDER
  export GIT_AUTHOR_NAME='Codex Eval' GIT_AUTHOR_EMAIL='codex-eval@example.invalid'
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  ROWS="$EVAL_RESULTS_DIR/cells.tsv"
  mkdir -p "$EVAL_RESULTS_DIR"
  if [ ! -e "$ROWS" ]; then
    printf 'script\tscenario\tsemantic_path\tprovider\tmodel\teffort\tblocking\tstatus\tclassification\texit\telapsed_ms\tprompt\tfinal_answer\tclassification_evidence\tstatus_evidence\tinput_tokens\toutput_tokens\tcost\n' > "$ROWS"
  fi
  local work rc=0 success_repo success_base failure_repo failure_base
  work="$(mktemp -d)"; trap 'rm -rf "$work"' RETURN

  init_codex_repo "$work/success" success
  success_repo="$R"; success_base="$BASE"
  cat > "$work/success-prompt.md" <<EOF
EVAL MODE: Read and apply the multi-model skill at $MULTI_SKILL and its Codex-native protocol at $CODEX_PROTOCOL. The lint-clean plan is $success_repo/plan.md, wave 1, repository $success_repo, exact pushed base $success_base. Use $PLAN_LINT and $CODEX_STATE exactly as the protocol directs. Append only actual helper actions and native coordination actions to $success_repo/.eval/native-trace.txt. For native coordination, after each action actually occurs, append these exact event lines in this order: native:spawn-executor model=gpt-5.6-luna effort=medium; native:wait executor; native:spawn-supervisor model=gpt-5.6-terra effort=high; native:wait supervisor. Use spawn_agent/followup_task/wait_agent for executor and supervisor; never invoke claude, Codex provider CLIs, or Workflow. Executor and supervisor must use the exact different model ids returned by the helper. If native collaboration is unavailable, do not simulate it: record the fixed {"error":{"kind":"tool-unavailable"}} payload through the helper until terminal, write tool-unavailable in the trace, and report tool-unavailable. If available, complete the division-by-zero task, preserve the state, mechanical verifier output, and terminal summary.
EOF
  record_codex_cell codex-native-success success success "$success_repo" "$success_base" "$work/success-prompt.md" "$success_repo/.eval/native-trace.txt" || rc=1

  init_codex_repo "$work/failure" failure
  failure_repo="$R"; failure_base="$BASE"
  cat > "$work/failure-prompt.md" <<EOF
EVAL MODE: Read and apply the multi-model skill at $MULTI_SKILL and its Codex-native protocol at $CODEX_PROTOCOL. The lint-clean plan is $failure_repo/plan.md, wave 1, repository $failure_repo, exact pushed base $failure_base. Use $PLAN_LINT and $CODEX_STATE exactly as directed. Append only actual helper/native actions to $failure_repo/.eval/native-trace.txt. For native coordination, after each action actually occurs, append these exact event lines in this order: native:spawn-executor model=gpt-5.6-luna effort=medium; native:wait executor; native:spawn-supervisor model=gpt-5.6-terra effort=high; native:wait supervisor. The second must_run fails independently of all files_allowed; a truthful supervisor must preserve its real output and mark it unsatisfiable. Use native spawn_agent/followup_task/wait_agent only; never invoke claude, Codex provider CLIs, or Workflow. Never merge a failing task. If native collaboration is unavailable, do not simulate success: record {"error":{"kind":"tool-unavailable"}} through the helper until terminal, trace it, and report tool-unavailable.
EOF
  record_codex_cell codex-independent-must-run failure failure "$failure_repo" "$failure_base" "$work/failure-prompt.md" "$failure_repo/.eval/native-trace.txt" || rc=1
  return "$rc"
}

claude_probe() {
  # Retained Claude Workflow boundary probe.
  local model="${EVAL_MODEL:-claude-haiku-4-5-20251001}"
  local runner="$ROOT/plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs"
  local work repo base default_branch out
  work="$(mktemp -d)"; trap 'rm -rf "$work"' RETURN
  git init -q --bare "$work/origin.git"
  git clone -q "$work/origin.git" "$work/repo" 2>/dev/null
  repo="$work/repo"
  mkdir -p "$repo/src" "$repo/tests"
  printf 'def divide(a, b):\n    return a / b\n' > "$repo/src/calc.py"
  cat > "$repo/tests/test_calc.py" <<'PY'
import unittest
from src.calc import divide

class TestDivide(unittest.TestCase):
    def test_divide(self):
        self.assertEqual(divide(6, 3), 2)
    def test_divide_by_zero_returns_none(self):
        self.assertIsNone(divide(1, 0))
PY
  touch "$repo/src/__init__.py" "$repo/tests/__init__.py"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  default_branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
  git -C "$repo" push -q origin "HEAD:$default_branch"
  base="$(git -C "$repo" rev-parse HEAD)"
  python3 - "$work/args.json" "$base" "$default_branch" "$repo" <<'PY'
import json, sys
out, base, branch, repo = sys.argv[1:5]
sup = open('plugins/orchestration/skills/multi-model/references/supervisor-prompt.md').read()
json.dump({
    "base": base, "defaultBranch": branch, "repoPath": repo,
    "supervisorPromptText": sup,
    "supervisor": {"model": "sonnet", "effort": "medium"},
    "tasks": [{
        "id": "divide-guard",
        "description": "Make divide() return None when the divisor is zero, so the whole suite passes.",
        "context": "src/calc.py holds divide(); tests/test_calc.py already expects None on zero.",
        "contract": {
            "files_allowed": ["src/**"], "files_forbidden": ["tests/**"],
            "must_run": [{"cmd": "python3 -m unittest discover -s tests -t .", "evidence": "required"}],
            "forbidden_moves": ["weakening, deleting or skipping an existing test"],
            "report_must_answer": ["What happens when the divisor is zero?"]
        },
        "executor": {"model": "haiku", "effort": "medium"}, "ladder": []
    }]
}, open(out, "w"))
PY
  section "the real Workflow boundary"
  out="$(timeout 900 claude -p "Read the JSON object in $work/args.json. Invoke the Workflow tool with scriptPath \"$runner\" and that object as args — a real JSON object, not a string. When it completes, print the workflow's returned JSON verbatim and nothing else." --permission-mode bypassPermissions --model "$model" </dev/null 2>/dev/null)"
  if [ -z "$out" ] || printf '%s' "$out" | grep -qiE 'no such tool|not available|do not have access'; then
    pass "SKIPPED: Workflow is unreachable from headless claude -p (tool absent) — the boundary is proven by the in-session probe (tests/eval/wave-insession.md), not this tier"
  elif printf '%s' "$out" | grep -q 'invalid-args'; then
    fail "runner rejected the wave args even after parse-then-validate" "${out:0:200}"
  else
    contains "the wave returned a status" '"status"' "$out"
    contains "the task is in the result" 'divide-guard' "$out"
    case "$out" in
      *'"ok"'* | *'"failed"'* | *'"contract-unsatisfiable"'* | *'"error"'*) pass "the task carries a terminal status" ;;
      *) fail "the task carries a terminal status" "${out:0:160}" ;;
    esac
  fi
  summary
}

if [ "${EVAL_PROVIDER:-claude}" = codex ]; then
  codex_probe
else
  claude_probe
fi
