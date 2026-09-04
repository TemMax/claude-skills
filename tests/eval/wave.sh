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

classify_codex() { # expected repo base answer trace
  local expected="$1" repo="$2" base="$3" answer="$4" trace="$5" state
  state="$(find_state "$repo" 2>/dev/null || true)"
  if printf '%s' "$answer" | grep -qi 'tool-unavailable' \
    || { [ -n "$state" ] && grep -q 'tool-unavailable' "$state"; }; then
    printf 'fail:tool-unavailable'
    return
  fi
  if [ -z "$state" ]; then
    printf 'fail:missing-codex-wave-state'
    return
  fi
  if [ ! -f "$trace" ]; then
    printf 'fail:missing-native-action-trace'
    return
  fi
  if grep -Eqi 'claude|Workflow' "$trace"; then
    printf 'fail:claude-workflow-in-codex-trace'
    return
  fi
  if [ "$expected" = failure ] \
    && [ "$(git -C "$repo" rev-parse master 2>/dev/null || true)" != "$base" ]; then
    printf 'fail:merged-failing-task'
    return
  fi
  if python3 - "$expected" "$state" <<'PY' >/dev/null 2>&1
import json
import sys

expected, path = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    state = json.load(stream)
task = state["tasks"]["divide-guard"]
assert state["supervisor"]["model"] != task["rungs"][task["rung"]]
assert task["verifierFacts"], "mechanical verifier facts missing"
must_run = task["verifierFacts"][-1]["mustRun"]
evidence = json.dumps(must_run)
assert "Ran 2 tests" in evidence
if expected == "success":
    assert task["status"] == "merge-ready"
    assert any(attempt["exit"] == 0 for item in must_run for attempt in item["attempts"])
    assert "OK" in evidence
else:
    assert task["status"] in ["contract-unsatisfiable", "failed"]
    failing = [item for item in must_run if item["attempts"] and item["attempts"][-1]["exit"] != 0]
    assert failing
    assert "independent verifier red" in evidence
PY
  then
    printf 'pass'
  else
    printf 'fail:invalid-terminal-state-or-evidence'
  fi
}

if [ "${1:-}" = --self-test ]; then
  set -e
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  R="$W/repo"; mkdir -p "$R/.worktrees/codex-wave" "$R/src" "$R/tests"
  git -C "$R" init -q
  printf 'def divide(a, b):\n    return a / b\n' > "$R/src/calc.py"
  printf 'import unittest\n' > "$R/tests/test_calc.py"
  git -C "$R" add -A; git -C "$R" commit -q -m base
  BASE="$(git -C "$R" rev-parse HEAD)"
  make_failure_plan tests/fixtures/plans/codex-clean.md "$W/failure-plan.md"
  lint_out="$(node "$PLAN_LINT" "$W/failure-plan.md" --repo "$R")"
  printf '%s' "$lint_out" | grep -q 'OK: 0 error(s), 0 warning(s)'
  : > "$W/trace"
  cat > "$R/.worktrees/codex-wave/success.json" <<'JSON'
{"supervisor":{"model":"gpt-5.6-terra"},"tasks":{"divide-guard":{"status":"merge-ready","rungs":["gpt-5.6-luna"],"rung":0,"verifierFacts":[{"mustRun":[{"attempts":[{"exit":0,"stdout":"","stderr":"Ran 2 tests\\nOK"}]}]}]}}}
JSON
  [ "$(classify_codex success "$R" "$BASE" done "$W/trace")" = pass ]
  printf 'Claude Workflow\n' > "$W/trace"
  [ "$(classify_codex success "$R" "$BASE" done "$W/trace")" = 'fail:claude-workflow-in-codex-trace' ]
  rm "$R/.worktrees/codex-wave/success.json"
  printf '{"agentFailures":[{"kind":"tool-unavailable"}]}' > "$R/.worktrees/codex-wave/unavailable.json"
  : > "$W/trace"
  [ "$(classify_codex success "$R" "$BASE" 'tool-unavailable' "$W/trace")" = 'fail:tool-unavailable' ]
  printf 'wave Codex scorer self-test: PASS\n'
  exit
fi

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
  if [ "$eval_rc" -eq 0 ]; then
    classification="$(classify_codex "$expected" "$repo" "$base" "$(cat "$answer")" "$trace")"
  else
    classification="fail:model-exit-$eval_rc"
  fi
  case "$classification" in pass) status=pass ;; *) status=fail ;; esac
  state_file="$(find_state "$repo" 2>/dev/null || true)"
  [ -n "$state_file" ] && command cp "$state_file" "$cell/state.json"
  [ -f "$trace" ] && command cp "$trace" "$cell/native-action-trace.txt"
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
EVAL MODE: Read and apply the multi-model skill at $MULTI_SKILL and its Codex-native protocol at $CODEX_PROTOCOL. The lint-clean plan is $success_repo/plan.md, wave 1, repository $success_repo, exact pushed base $success_base. Use $PLAN_LINT and $CODEX_STATE exactly as the protocol directs. Append only actual helper actions and native coordination actions to $success_repo/.eval/native-trace.txt. Use spawn_agent/followup_task/wait_agent for executor and supervisor; never invoke claude, Codex provider CLIs, or Workflow. Executor and supervisor must use the exact different model ids returned by the helper. If native collaboration is unavailable, do not simulate it: record the fixed {"error":{"kind":"tool-unavailable"}} payload through the helper until terminal, write tool-unavailable in the trace, and report tool-unavailable. If available, complete the division-by-zero task, preserve the state, mechanical verifier output, and terminal summary.
EOF
  record_codex_cell codex-native-success success success "$success_repo" "$success_base" "$work/success-prompt.md" "$success_repo/.eval/native-trace.txt" || rc=1

  init_codex_repo "$work/failure" failure
  failure_repo="$R"; failure_base="$BASE"
  cat > "$work/failure-prompt.md" <<EOF
EVAL MODE: Read and apply the multi-model skill at $MULTI_SKILL and its Codex-native protocol at $CODEX_PROTOCOL. The lint-clean plan is $failure_repo/plan.md, wave 1, repository $failure_repo, exact pushed base $failure_base. Use $PLAN_LINT and $CODEX_STATE exactly as directed. Append only actual helper/native actions to $failure_repo/.eval/native-trace.txt. The second must_run fails independently of all files_allowed; a truthful supervisor must preserve its real output and mark it unsatisfiable. Use native spawn_agent/followup_task/wait_agent only; never invoke claude, Codex provider CLIs, or Workflow. Never merge a failing task. If native collaboration is unavailable, do not simulate success: record {"error":{"kind":"tool-unavailable"}} through the helper until terminal, trace it, and report tool-unavailable.
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
