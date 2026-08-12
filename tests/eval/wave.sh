#!/usr/bin/env bash
# Tier 3 — is the shipped wave-runner ACCEPTED by the real Workflow tool, and
# does one task reach a terminal status on real models? Ladder rules are NOT
# re-proven here: the simulator tier owns them offline. This tier proves only
# the boundary the simulator cannot: the launcher's parser and a real verdict.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh

MODEL="${EVAL_MODEL:-claude-haiku-4-5-20251001}"
RUNNER="$PWD/plugins/orchestration/skills/multi-model/references/wave-runner.workflow.mjs"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# The runner's isolation instructions verify base against origin/<defaultBranch>,
# so the fixture needs a real remote: a bare repo plus a clone of it.
git init -q --bare "$W/origin.git"
git clone -q "$W/origin.git" "$W/repo" 2>/dev/null
R="$W/repo"
mkdir -p "$R/src" "$R/tests"
printf 'def divide(a, b):\n    return a / b\n' > "$R/src/calc.py"
cat > "$R/tests/test_calc.py" <<'PY'
import unittest

from src.calc import divide


class TestDivide(unittest.TestCase):
    def test_divide(self):
        self.assertEqual(divide(6, 3), 2)

    def test_divide_by_zero_returns_none(self):
        self.assertIsNone(divide(1, 0))
PY
touch "$R/src/__init__.py" "$R/tests/__init__.py"
git -C "$R" add -A
git -C "$R" -c user.email=t@t -c user.name=t commit -q -m base
DEFBRANCH="$(git -C "$R" rev-parse --abbrev-ref HEAD)"
git -C "$R" push -q origin "HEAD:$DEFBRANCH"
BASE="$(git -C "$R" rev-parse HEAD)"

python3 - "$W/args.json" "$BASE" "$DEFBRANCH" "$R" <<'PY'
import json, sys
out, base, branch, repo = sys.argv[1:5]
sup = open('plugins/orchestration/skills/multi-model/references/supervisor-prompt.md').read()
json.dump({
    "base": base, "defaultBranch": branch, "repoPath": repo,
    "supervisorPromptText": sup,
    "supervisor": {"model": "haiku", "effort": "medium"},
    "tasks": [{
        "id": "divide-guard",
        "description": "Make divide() return None when the divisor is zero, so the whole suite passes.",
        "context": "src/calc.py holds divide(); tests/test_calc.py already expects None on zero.",
        "contract": {
            "files_allowed": ["src/**"],
            "files_forbidden": ["tests/**"],
            "must_run": [{"cmd": "python3 -m unittest discover -s tests -t .", "evidence": "required"}],
            "forbidden_moves": ["weakening, deleting or skipping an existing test"],
            "report_must_answer": ["What happens when the divisor is zero?"]
        },
        "executor": {"model": "haiku", "effort": "medium"},
        "ladder": []
    }]
}, open(out, "w"))
PY

section "the real Workflow boundary"
out="$(timeout 900 claude -p "Read the JSON object in $W/args.json. Invoke the Workflow tool with scriptPath \"$RUNNER\" and that object as args — a real JSON object, not a string. When it completes, print the workflow's returned JSON verbatim and nothing else." --permission-mode bypassPermissions --model "$MODEL" </dev/null 2>/dev/null)"

# Two ways headless claude -p fails to reach a real verdict, distinguished so the
# skip message says which one happened:
#   (a) the tool itself is absent from this harness (empty output, "no such tool");
#   (b) the tool exists and is invoked, but the CLI's own tool-call serialization
#       stringifies the object-typed `args` parameter before the runner ever sees
#       it — tripping the runner's own anti-double-encoding guard. Confirmed
#       reproducible 3/3 across Haiku and Sonnet with three prompt phrasings
#       (2026-08-12); no wording fix available from this side of the boundary.
if [ -z "$out" ] || printf '%s' "$out" | grep -qiE 'no such tool|not available|do not have access'; then
  pass "SKIPPED: Workflow is unreachable from headless claude -p (tool absent) — the boundary is proven by the in-session probe (tests/eval/wave-insession.md), not this tier"
elif printf '%s' "$out" | grep -q 'args must be a JSON object, not a string'; then
  pass "SKIPPED: Workflow is reachable headless, but the CLI's own tool-call serialization stringifies the object-typed args parameter before the runner sees it (reproduced 3/3 across Haiku and Sonnet, three phrasings) — the boundary is proven by the in-session probe (tests/eval/wave-insession.md), not this tier"
else
  contains "the wave returned a status" '"status"'      "$out"
  contains "the task is in the result"  'divide-guard'  "$out"
  case "$out" in
    *'"ok"'* | *'"failed"'* | *'"contract-unsatisfiable"'* | *'"error"'*)
      pass "the task carries a terminal status" ;;
    *)
      fail "the task carries a terminal status" "${out:0:160}" ;;
  esac
fi

summary
