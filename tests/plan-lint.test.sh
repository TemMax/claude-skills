#!/usr/bin/env bash
# Behaviour tier — does the SHIPPED plan linter catch each error class by
# name, pass the canonical clean plan, and keep warnings non-fatal? Mutants
# are generated from the clean fixture so the fixtures stay DRY.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

LINT=plugins/orchestration/skills/super-plan/references/plan-lint.mjs
CLEAN=tests/fixtures/plans/clean.md
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

if ! command -v node >/dev/null 2>&1; then
  fail "node is required for this tier and was not found on PATH"
  summary; exit 1
fi

mutate() {  # $1 = old, $2 = new  → writes $W/m.md
  python3 - "$CLEAN" "$W/m.md" "$1" "$2" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
assert old in s, 'mutation target missing: ' + old
open(dst, 'w').write(s.replace(old, new, 1))
PY
}

section "clean plan"
out="$(node "$LINT" "$CLEAN" 2>&1)"; rc=$?
expect "clean plan exits 0" "0" "$rc"
contains "clean summary line" "OK: 0 error(s)" "$out"

section "usage"
node "$LINT" >/dev/null 2>&1; expect "no args exits 2" "2" "$?"

section "each error class is caught by name"

mutate "status: draft" "status: banana"
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "bad status exits 1" "1" "$rc"
contains "bad status named" "status must be draft|active|done" "$out"

mutate "status: draft" "state: draft"
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "missing status named" "no column-0" "$out"

mutate '"waves"' '"waves'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "broken json exits 1" "1" "$rc"
contains "broken json named" "does not parse" "$out"

mutate '"id": "docs-sync"' '"id": "http-retry"'
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "duplicate id named" 'duplicate task id "http-retry"' "$out"

mutate '"branch": "wave/docs-sync"' '"branch": "docs-sync"'
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "bad branch named" 'must be "wave/docs-sync"' "$out"

mutate '"model": "haiku"' '"model": "claude-haiku-4-5"'
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "long model id rejected" "executor.model" "$out"

mutate '          "forbidden_moves": [],
' ''
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "missing contract key named" "contract.forbidden_moves: array required" "$out"

mutate '"files_allowed": ["docs/**"]' '"files_allowed": ["src/**"]'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "same-wave overlap exits 1" "1" "$rc"
contains "overlap names both tasks" 'tasks "http-retry" and "docs-sync" overlap' "$out"

mutate '"files_forbidden": ["src/auth/**"]' '"files_forbidden": ["src/http/impl/**"]'
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "self allowed/forbidden overlap named" "overlaps its own files_forbidden" "$out"

mutate "## Task docs-sync" "## Task docs-sync-two"
out="$(node "$LINT" "$W/m.md" 2>&1)"
contains "missing prose section named" 'no "## Task docs-sync" section' "$out"
contains "orphan prose section named" '"## Task docs-sync-two" has no matching task' "$out"

section "warnings stay non-fatal"

mutate '"must_run": [{ "cmd": "true", "evidence": "required" }],
          "forbidden_moves": ["weakening, deleting or skipping an existing test"]' \
       '"must_run": [],
          "forbidden_moves": ["weakening, deleting or skipping an existing test"]'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "empty must_run exits 0" "0" "$rc"
contains "empty must_run warned" "must_run is empty" "$out"

mutate '"files_allowed": ["docs/**"]' '"files_allowed": []'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "empty files_allowed exits 0" "0" "$rc"
contains "empty files_allowed warned" "files_allowed is empty" "$out"

mkdir -p "$W/repo/docs"
mutate '"cmd": "true"' '"cmd": "definitely-not-a-real-binary-xyz"'
out="$(node "$LINT" "$W/m.md" --repo "$W/repo" 2>&1)"; rc=$?
expect "repo warnings exit 0" "0" "$rc"
contains "missing path prefix warned" 'prefix "src/http" does not exist' "$out"
contains "missing command warned" 'command "definitely-not-a-real-binary-xyz" found neither' "$out"

section "the pinned full id"

mutate '"model": "sonnet"' '"model": "claude-opus-4-8"'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "pinned full id in executor.model exits 0" "0" "$rc"
contains "pinned full id in executor.model is clean" "OK: 0 error(s)" "$out"

mutate '"ladder": ["opus"]' '"ladder": ["claude-opus-4-8"]'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "pinned full id in ladder exits 0" "0" "$rc"
contains "pinned full id in ladder is clean" "OK: 0 error(s)" "$out"

mutate '"model": "sonnet"' '"model": "opus-4-8"'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "unpinned full-looking id exits 1" "1" "$rc"
contains "unpinned full-looking id named" "executor.model" "$out"

section "Codex exact ids"
while read -r executor supervisor rung; do
  cp "$CLEAN" "$W/m.md"
  python3 - "$W/m.md" "$executor" "$supervisor" "$rung" <<'PY'
import sys
p, executor, supervisor, rung = sys.argv[1:]
s = open(p).read()
s = s.replace('"model": "sonnet"', f'"model": "{executor}"')
s = s.replace('"model": "haiku"', f'"model": "{executor}"')
s = s.replace('"model": "fable"', f'"model": "{supervisor}"')
s = s.replace('"ladder": ["opus"]', f'"ladder": ["{rung}"]')
open(p, 'w').write(s)
PY
  out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
  expect "$executor plan exits 0" "0" "$rc"
done <<'CASES'
gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna
gpt-5.6-terra gpt-5.6-sol gpt-5.6-luna
gpt-5.6-luna gpt-5.6-terra gpt-5.6-sol
CASES

mutate '"model": "sonnet"' '"model": "gpt-5.6"'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "gpt-5.6 alias exits 1" "1" "$rc"
contains "gpt-5.6 alias is rejected" "executor.model" "$out"

mutate '"model": "sonnet"' '"model": "gpt-5.6-mini"'
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "gpt-5.6-mini alias exits 1" "1" "$rc"
contains "gpt-5.6-mini alias is rejected" "executor.model" "$out"

cp "$CLEAN" "$W/m.md"
python3 - "$W/m.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('"model": "sonnet"', '"model": "gpt-5.6-sol"')
open(p, 'w').write(s)
PY
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "mixed-provider wave exits 1" "1" "$rc"
contains "mixed-provider wave is named" "mixes providers" "$out"

cp "$CLEAN" "$W/m.md"
python3 - "$W/m.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('"model": "sonnet"', '"model": "gpt-5.6-sol"')
s = s.replace('"model": "haiku"', '"model": "gpt-5.6-luna"')
s = s.replace('"model": "fable"', '"model": "gpt-5.6-terra"')
s = s.replace('"ladder": ["opus"]', '"ladder": ["gpt-5.6-terra"]')
open(p, 'w').write(s)
PY
out="$(node "$LINT" "$W/m.md" 2>&1)"; rc=$?
expect "GPT supervisor collision exits 1" "1" "$rc"
contains "GPT supervisor collision is named" "supervisor model also appears as executor or ladder rung" "$out"

summary
