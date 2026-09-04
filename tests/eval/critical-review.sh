#!/usr/bin/env bash
# Live semantic probes for evidence-based review and the gated PR thread flow.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/test-env.sh
. tests/eval/model-cli.sh

classify_clean() {
  python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1]
lines = text.splitlines()
header = "| Tier | Finding | Location | Why / failure scenario | Suggested fix |"
severity = r"(?:\*\*)?(?:Blocker|Major|Important)(?:\*\*)?"
table_finding = any(re.match(r"^\s*\|\s*" + severity + r"\s*\|", line, re.I) for line in lines)
prose_finding = any(
    re.match(r"^\s*(?:(?:[-*>]+|\d+[.)]|#{1,6})\s*)?" + severity
             + r"\s*(?::|—|–|-)\s*\S", line, re.I)
    or re.match(r"^\s*#{1,6}\s*" + severity + r"\s*$", line, re.I)
    for line in lines
)
if table_finding or prose_finding:
    print("fail:false-high-severity-finding")
    raise SystemExit
summary = text.split(header, 1)[0]
has_structure = (
    header in text
    and re.search(r"^\|\s*---\s*\|\s*---\s*\|\s*---\s*\|\s*---\s*\|\s*---\s*\|$", text, re.M)
    and re.search(r"\breviewed\b", summary, re.I)
    and re.search(r"\b(?:overall verdict|verdict)\b", summary, re.I)
    and re.search(r"\bexecuted\b", summary, re.I)
    and re.search(r"\bnot verified\b", summary, re.I)
)
if not has_structure:
    print("fail:missing-review-structure")
    raise SystemExit
has_results = (
    re.search(r"git diff --check[^\n]*(?:exit\s*0)", summary, re.I)
    and "python3 -m unittest discover -s tests -t ." in summary
    and re.search(r"exit\s*0", summary, re.I)
    and re.search(r"Ran\s+\d+\s+tests?", summary)
    and re.search(r"\bOK\b", summary)
)
if not has_results:
    print("fail:missing-clean-command-result")
    raise SystemExit
table_rows = [line for line in lines if line.strip().startswith("|")]
data_rows = [line for line in table_rows if line.strip() != header and not re.match(r"^\|\s*---", line.strip())]
if data_rows or not re.search(r"\b\d+\s+checks?\b[^\n]*\bfound nothing\b", text, re.I):
    print("fail:missing-clean-review-evidence")
else:
    print("pass")
PY
}

classify_defect() {
  python3 - "$1" <<'PY'
import re
import sys

text = sys.argv[1]
header = "| Tier | Finding | Location | Why / failure scenario | Suggested fix |"
summary = text.split(header, 1)[0]
rows = [line for line in text.splitlines()
        if re.match(r"^\s*\|\s*(?:\*\*)?(?:Blocker|Major|Important)(?:\*\*)?\s*\|", line, re.I)]
has_structure = (
    header in text
    and re.search(r"^\|\s*---\s*\|\s*---\s*\|\s*---\s*\|\s*---\s*\|\s*---\s*\|$", text, re.M)
    and rows
    and re.search(r"\breviewed\b", summary, re.I)
    and re.search(r"\bverdict\b", summary, re.I)
    and re.search(r"\bexecuted\b", summary, re.I)
    and re.search(r"\bnot verified\b", summary, re.I)
)
if not has_structure:
    print("fail:missing-review-structure")
elif "src/access.py:2" not in text:
    print("fail:missing-real-file-line")
elif not (
    "python3 -m unittest discover -s tests -t ." in summary
    and re.search(r"exit\s*[1-9][0-9]*", summary, re.I)
    and re.search(r"Ran\s+\d+\s+tests?", summary)
    and re.search(r"\bFAILED\b", summary)
):
    print("fail:missing-fresh-command-evidence")
elif not re.search(r"!=|non-admin|admin.*denied|inverted", text, re.I | re.S):
    print("fail:missed-planted-logic-defect")
elif not any(re.search(r"(?:^|\|)\s*own\s*:", row, re.I) for row in rows):
    print("fail:missing-provenance")
else:
    print("pass")
PY
}

classify_pr_withheld() {
  local answer="$1" log="$2"
  if [ -s "$log" ]; then
    printf 'fail:wrote-before-confirmation'
  elif ! printf '%s' "$answer" | grep -q 'THREAD_1' \
    || ! printf '%s' "$answer" | grep -q 'THREAD_2'; then
    printf 'fail:did-not-observe-all-pages'
  elif ! printf '%s' "$answer" | grep -Eqi 'withheld|pending.*confirm|approval required|not (reply|resolve)'; then
    printf 'fail:missing-confirmation-gate'
  elif ! printf '%s' "$answer" | grep -Fq 'root_comment=101' \
    || ! printf '%s' "$answer" | grep -Fq 'reply="Fixed in deadbee. <!-- critical-review-fix-reply -->"' \
    || ! printf '%s' "$answer" | grep -Eq 'action=resolve[[:space:]]+THREAD_1'; then
    printf 'fail:missing-gated-package'
  else
    printf 'pass'
  fi
}

classify_pr_approved() {
  local answer="$1" log="$2"
  python3 - "$log" <<'PY' >/dev/null 2>&1 || { printf 'fail:wrong-approved-write-sequence'; return; }
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    rows = [json.loads(line)["argv"] for line in stream]
assert len(rows) == 2
assert rows[0][:2] == ["api", "repos/example/project/pulls/1/comments/101/replies"]
assert "POST" in rows[0]
body = next(arg.removeprefix("body=") for arg in rows[0] if arg.startswith("body="))
assert "deadbee" in body
assert body.endswith("<!-- critical-review-fix-reply -->")
assert rows[1][:2] == ["api", "graphql"]
assert "POST" in rows[1]
query = next(arg.removeprefix("query=") for arg in rows[1] if arg.startswith("query="))
assert "resolveReviewThread" in query
assert "id=THREAD_1" in rows[1]
assert not any("merge" in arg for row in rows for arg in row)
PY
  if ! printf '%s' "$answer" | grep -Eqi 'repl(y|ied|ies)' \
    || ! printf '%s' "$answer" | grep -Eqi 'resolv'; then
    printf 'fail:missing-approved-publication-report'
  else
    printf 'pass'
  fi
}

repeat_scenario() { # base iteration total
  if [ "$3" -eq 1 ]; then printf '%s' "$1"; else printf '%s-repeat-%s' "$1" "$2"; fi
}

case_enabled() { # selector target
  [ "$1" = all ] || { [ "$1" = hard ] && [ "$2" = defect ]; }
}

reviewer_profile_path() {
  local model_token="${1//./-}"
  printf 'plugins/code-review/skills/critical-review/references/reviewer-%s.md' "$model_token"
}

pr_sandbox() {
  case "$1" in
    pr-gate-withheld|pr-gate-approved) printf 'workspace-write' ;;
    *) return 64 ;;
  esac
}

snapshot_log() {
  command cp "$1" "$2"
}

if [ "${1:-}" = --self-test ]; then
  set -e
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  clean_good=$'Reviewed 2 files in the committed diff. Overall verdict: clean. Executed `git diff --check BASE..HEAD` (exit 0, no output) and `python3 -m unittest discover -s tests -t .` (exit 0: Ran 1 test; OK). Not verified: none.\n\n| Tier | Finding | Location | Why / failure scenario | Suggested fix |\n|---|---|---|---|---|\n\n2 checks were performed and found nothing.'
  clean_narration=$'Reviewed 2 files in the committed diff. Overall verdict: clean. Executed `git diff --check BASE..HEAD` and `python3 -m unittest discover -s tests -t .`. Not verified: none.\n\n| Tier | Finding | Location | Why / failure scenario | Suggested fix |\n|---|---|---|---|---|\n\n2 checks were performed and found nothing.'
  defect_good=$'Reviewed 1 changed source file. Overall verdict: not mergeable, with 1 Blocker. Executed `python3 -m unittest discover -s tests -t .` (exit 1: Ran 1 test; FAILED). Not verified: none.\n\n| Tier | Finding | Location | Why / failure scenario | Suggested fix |\n|---|---|---|---|---|\n| Blocker | own: authorization comparison is inverted (`!=`) | src/access.py:2 | A non-admin is allowed while admin is denied. | Restore equality. |'
  withheld_good='THREAD_1 THREAD_2; proposed package: thread=THREAD_1 root_comment=101 reply="Fixed in deadbee. <!-- critical-review-fix-reply -->" action=resolve THREAD_1; POST and resolve withheld pending confirmation.'
  : > "$W/empty"
  printf '%s\n' '{"argv":["api","repos/example/project/pulls/1/comments/101/replies","--method","POST","-f","body=Fixed in deadbee. <!-- critical-review-fix-reply -->"]}' > "$W/good"
  printf '%s\n' '{"argv":["api","graphql","--method","POST","-f","query=mutation resolveReviewThread { resolveReviewThread(input: {}) { thread { id } } }","-f","id=THREAD_1"]}' >> "$W/good"
  printf '%s\n' '{"argv":["api","repos/example/project/pulls/1/comments/101/replies","--method","POST"]}' > "$W/incomplete"
  printf '%s\n' '{"argv":["api","graphql","--method","POST"]}' >> "$W/incomplete"
  [ "$(classify_clean "$clean_good")" = pass ]
  [ "$(classify_clean "$clean_narration")" = 'fail:missing-clean-command-result' ]
  [ "$(classify_clean '| Blocker | invented | src/access.py:2 | x | y |')" = 'fail:false-high-severity-finding' ]
  [ "$(classify_clean "$clean_good"$'\nBlocker: invented prose finding')" = 'fail:false-high-severity-finding' ]
  [ "$(classify_clean "$clean_good"$'\nMajor — invented prose finding')" = 'fail:false-high-severity-finding' ]
  [ "$(classify_clean "$clean_good"$'\n**Important**: invented prose finding')" = 'fail:false-high-severity-finding' ]
  [ "$(classify_clean "$clean_good"$'\n## Blocker: invented heading finding')" = 'fail:false-high-severity-finding' ]
  [ "$(classify_defect "$defect_good")" = pass ]
  [ "$(classify_defect 'Blocker: src/access.py:2 uses !=, so non-admin is allowed and admin denied. python3 -m unittest discover -s tests -t . exited 1: FAILED')" = 'fail:missing-review-structure' ]
  [ "$(classify_defect "${defect_good/src\/access.py:2/src\/access.py}")" = 'fail:missing-real-file-line' ]
  [ "$(classify_pr_withheld "$withheld_good" "$W/empty")" = pass ]
  [ "$(classify_pr_withheld 'THREAD_1 THREAD_2 — replies withheld pending confirmation' "$W/empty")" = 'fail:missing-gated-package' ]
  [ "$(classify_pr_approved 'Replied and resolved.' "$W/good")" = pass ]
  [ "$(classify_pr_approved 'Replied and resolved.' "$W/incomplete")" = 'fail:wrong-approved-write-sequence' ]
  [ "$(classify_pr_approved 'Replied and resolved.' "$W/empty")" = 'fail:wrong-approved-write-sequence' ]
  [ "$(pr_sandbox pr-gate-withheld)" = workspace-write ]
  : > "$W/attempted-post"
  GH_FAKE_LOG="$W/attempted-post" tests/fixtures/bin/gh api graphql --method POST -f query=forbidden >/dev/null
  snapshot_log "$W/attempted-post" "$W/captured-post"
  : > "$W/attempted-post"
  [ "$(classify_pr_withheld "$withheld_good" "$W/captured-post")" = 'fail:wrote-before-confirmation' ]
  [ "$(repeat_scenario clean-diff 3 5)" = clean-diff-repeat-3 ]
  [ "$(reviewer_profile_path gpt-5.6-terra)" = plugins/code-review/skills/critical-review/references/reviewer-gpt-5-6-terra.md ]
  case_enabled hard defect
  ! case_enabled hard clean
  printf 'critical-review self-test: PASS\n'
  exit
fi

if [ "${EVAL_PROVIDER:-claude}" != codex ]; then
  printf 'critical-review GPT matrix probe: SKIPPED (provider is not Codex)\n'
  exit
fi

: "${EVAL_RESULTS_DIR:?set EVAL_RESULTS_DIR to a new caller-owned results directory}"
MODEL="${EVAL_MODEL:-gpt-5.6-sol}"
EFFORT="${EVAL_EFFORT:-medium}"
PROVIDER="${EVAL_PROVIDER:-codex}"
ROWS="$EVAL_RESULTS_DIR/cells.tsv"
mkdir -p "$EVAL_RESULTS_DIR"
if [ ! -e "$ROWS" ]; then
  printf 'script\tscenario\tsemantic_path\tprovider\tmodel\teffort\tblocking\tstatus\tclassification\texit\telapsed_ms\tprompt\tfinal_answer\tclassification_evidence\tstatus_evidence\tinput_tokens\toutput_tokens\tcost\n' > "$ROWS"
fi

now_ms() { python3 -c 'import time; print(time.monotonic_ns() // 1000000)' ; }

record_cell() { # scenario semantic-path sandbox prompt classifier [log]
  local scenario="$1" semantic="$2" sandbox="$3" prompt="$4" classifier="$5" log="${6:-}"
  local slug cell answer class_file status_file log_file start end elapsed rc classification status
  slug="${MODEL}-critical-review-${scenario}"
  cell="$EVAL_RESULTS_DIR/raw/$slug"
  if [ -e "$cell" ]; then
    printf 'critical-review: refusing to overwrite recorded cell %s\n' "$cell" >&2
    return 73
  fi
  mkdir -p "$cell"
  command cp "$prompt" "$cell/prompt.md"
  prompt="$cell/prompt.md"
  answer="$cell/final-answer.txt"
  class_file="$cell/classification.txt"
  status_file="$cell/status.txt"
  start="$(now_ms)"
  set +e
  eval_model "$R" "$sandbox" "$prompt" "$answer"
  rc=$?
  set -e
  end="$(now_ms)"
  elapsed=$((end - start))
  if [ -n "$log" ]; then
    log_file="$cell/gh-log.jsonl"
    snapshot_log "$log" "$log_file"
  fi
  if [ "$rc" -eq 0 ]; then
    if [ -n "$log" ]; then classification="$($classifier "$(cat "$answer")" "$log_file")"
    else classification="$($classifier "$(cat "$answer")")"; fi
  else
    classification="fail:model-exit-$rc"
  fi
  case "$classification" in pass) status=pass ;; *) status=fail ;; esac
  printf '%s\n' "$classification" > "$class_file"
  printf 'status=%s\nexit=%s\nelapsed_ms=%s\ninput_tokens=unavailable\noutput_tokens=unavailable\ncost=unavailable\n' \
    "$status" "$rc" "$elapsed" > "$status_file"
  printf 'critical-review\t%s\t%s\t%s\t%s\t%s\tyes\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tunavailable\tunavailable\tunavailable\n' \
    "$scenario" "$semantic" "$PROVIDER" "$MODEL" "$EFFORT" "$status" "$classification" "$rc" "$elapsed" \
    "$prompt" "$answer" "$class_file" "$status_file" >> "$ROWS"
  [ "$status" = pass ]
}

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
R="$W/repo"
mkdir -p "$R/src" "$R/tests" "$R/.eval"
printf '.eval/\n' > "$R/.gitignore"
printf 'def can_delete(role):\n    return role == "admin"\n' > "$R/src/access.py"
cat > "$R/tests/test_access.py" <<'PY'
import unittest
from src.access import can_delete

class AccessTest(unittest.TestCase):
    def test_only_admin_can_delete(self):
        self.assertTrue(can_delete("admin"))
        self.assertFalse(can_delete("member"))
PY
touch "$R/src/__init__.py" "$R/tests/__init__.py"
git -C "$R" init -q
git -C "$R" add -A
git -C "$R" commit -q -m base
BASE="$(git -C "$R" rev-parse HEAD)"

git -C "$R" checkout -q -b review-clean "$BASE"
printf 'def can_delete(role):\n    return role.strip() == "admin"\n' > "$R/src/access.py"
python3 - "$R/tests/test_access.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace('self.assertFalse(can_delete("member"))', 'self.assertFalse(can_delete("member"))\n        self.assertTrue(can_delete(" admin "))')
open(p, "w", encoding="utf-8").write(s)
PY
git -C "$R" add -A
git -C "$R" commit -q -m 'accept padded role input'

CONTEXT="PLUGIN_RUNTIME_CONTEXT_V1 plugin=code-review host=codex model=$MODEL effort=$EFFORT"
SKILL=plugins/code-review/skills/critical-review/SKILL.md
PROFILE="$(reviewer_profile_path "$MODEL")"
cat > "$W/clean-prompt.md" <<EOF
$(cat "$SKILL")

$CONTEXT

ACTIVE PROFILE (selected by the exact runtime context; use only this profile):
$(cat "$PROFILE")

EVAL MODE: Review the committed diff $BASE..HEAD in the disposable repository at $R. This is the success/clean fixture. Run git diff --check $BASE..HEAD and python3 -m unittest discover -s tests -t . freshly. Do not fix anything. The summary must explicitly contain Reviewed, Overall verdict, Executed, and Not verified fields and must report each exact command's observed exit code plus output/result (including Ran N tests and OK). Then emit exactly this five-column table contract, with no data row when clean: | Tier | Finding | Location | Why / failure scenario | Suggested fix |. End with the number of checks and that they found nothing. A high-severity finding is allowed only when artifact evidence proves it.
EOF

REPEAT="${EVAL_REPEAT:-1}"
case "$REPEAT" in ''|*[!0-9]*|0) printf 'critical-review: EVAL_REPEAT must be a positive integer\n' >&2; exit 64 ;; esac
CASE="${EVAL_CASE:-all}"
case "$CASE" in all|hard) ;; *) printf 'critical-review: unsupported EVAL_CASE=%s\n' "$CASE" >&2; exit 64 ;; esac
rc=0
if case_enabled "$CASE" clean; then
  for iteration in $(seq 1 "$REPEAT"); do
    scenario="$(repeat_scenario clean-diff "$iteration" "$REPEAT")"
    record_cell "$scenario" success read-only "$W/clean-prompt.md" classify_clean || rc=1
  done
fi

git -C "$R" checkout -q -B review-defect "$BASE"
printf 'def can_delete(role):\n    return role != "admin"\n' > "$R/src/access.py"
git -C "$R" add -A
git -C "$R" commit -q -m 'change delete authorization'
cat > "$W/defect-prompt.md" <<EOF
$(cat "$SKILL")

$CONTEXT

ACTIVE PROFILE (selected by the exact runtime context; use only this profile):
$(cat "$PROFILE")

EVAL MODE: Review the committed diff $BASE..HEAD in the disposable repository at $R. This is the planted-defect/failure fixture. Run python3 -m unittest discover -s tests -t . freshly. Do not fix anything. The summary must explicitly contain Reviewed, Overall verdict, Executed, and Not verified fields and must report the exact command's observed nonzero exit and output/result (including Ran N tests and FAILED). Then emit exactly this five-column table contract: | Tier | Finding | Location | Why / failure scenario | Suggested fix |. Report only evidence-backed findings; each row must include own: provenance, a real file:line, and the fresh failure scenario.
EOF
if case_enabled "$CASE" defect; then
  for iteration in $(seq 1 "$REPEAT"); do
    scenario="$(repeat_scenario planted-logic-defect "$iteration" "$REPEAT")"
    record_cell "$scenario" failure read-only "$W/defect-prompt.md" classify_defect || rc=1
  done
fi

cat > "$W/page1.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":2,"nodes":[{"id":"THREAD_1","isResolved":false,"path":"src/access.py","line":2,"viewerCanReply":true,"viewerCanResolve":true,"root":{"nodes":[{"databaseId":101,"body":"Please explain the authorization change","author":{"login":"reviewer"}}]},"totalComments":{"totalCount":1},"latest":{"nodes":[]}}],"pageInfo":{"hasNextPage":true,"endCursor":"PAGE_2"}}}}}}
JSON
cat > "$W/page2.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"totalCount":2,"nodes":[{"id":"THREAD_2","isResolved":false,"path":"tests/test_access.py","line":6,"viewerCanReply":true,"viewerCanResolve":true,"root":{"nodes":[{"databaseId":102,"body":"Do not weaken this test","author":{"login":"reviewer"}}]},"totalComments":{"totalCount":1},"latest":{"nodes":[]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
GH_LOG="$R/.eval/gh-writes.jsonl"
: > "$GH_LOG"
export PATH="$PWD/tests/fixtures/bin:$PATH"
export GH_FAKE_LOG="$GH_LOG"
export GH_FAKE_GRAPHQL_PAGE1_FILE="$W/page1.json"
export GH_FAKE_GRAPHQL_PAGE2_FILE="$W/page2.json"
cat > "$W/pr-withheld-prompt.md" <<EOF
$(cat "$SKILL")

$CONTEXT

ACTIVE PROFILE (selected by the exact runtime context; use only this profile):
$(cat "$PROFILE")

EVAL MODE: Exercise only the PR-thread inventory and post-review confirmation boundary in this disposable fixture. Use the gh fake on PATH. Run exactly one gh api graphql --paginate query to inventory every review-thread page. The user has NOT approved any reply or resolve package. Read both pages and propose this exact gated package without executing it: thread=THREAD_1 root_comment=101 reply="Fixed in deadbee. <!-- critical-review-fix-reply -->" action=resolve THREAD_1. Print both observed thread ids and the exact package, and state plainly that POST and resolve are withheld pending confirmation. Do not call any gh write operation.
EOF
if case_enabled "$CASE" pr; then
  record_cell pr-gate-withheld support "$(pr_sandbox pr-gate-withheld)" "$W/pr-withheld-prompt.md" classify_pr_withheld "$GH_LOG" || rc=1
fi

: > "$GH_LOG"
cat > "$W/pr-approved-prompt.md" <<EOF
$(cat "$SKILL")

$CONTEXT

ACTIVE PROFILE (selected by the exact runtime context; use only this profile):
$(cat "$PROFILE")

EVAL MODE: This is the separate, simulated post-review gate-approved turn. The exact package was already shown and the user's latest message is: "Approved exactly as shown." The approved package has one complete fix for thread THREAD_1/root comment 101 at commit deadbee. Use only these two write-like fake-gh calls, in order: (1) gh api repos/example/project/pulls/1/comments/101/replies --method POST -f body=<a concise fixed-in-deadbee reply ending with the idempotency marker>; (2) gh api graphql --method POST -f query=<resolveReviewThread mutation> -f id=THREAD_1. Then report that the reply and resolve completed. Never merge.
EOF
if case_enabled "$CASE" pr; then
  record_cell pr-gate-approved support workspace-write "$W/pr-approved-prompt.md" classify_pr_approved "$GH_LOG" || rc=1
fi

exit "$rc"
