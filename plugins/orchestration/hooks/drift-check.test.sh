#!/usr/bin/env bash
# Gate tests for drift-check. Every case runs in dry-run, so the suite is
# offline, deterministic and costs nothing. The live end-to-end path is checked
# separately — see the last case, which is skipped unless LIVE=1.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/drift-check"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A throwaway repo so the tests never depend on the state of the real one.
setup_repo() {
  rm -rf "$WORK/repo"
  mkdir -p "$WORK/repo/docs/superpowers/plans"
  git -C "$WORK/repo" init -q .
  git -C "$WORK/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
}

write_plan() {   # $1 = status, $2 = branch line ("" for none)
  cat > "$WORK/repo/docs/superpowers/plans/2026-01-01-wave-test.md" <<EOF
base: deadbee
status: $1

$2
EOF
}

write_transcript() {  # $1 = content
  printf '%s\n' "$1" > "$WORK/transcript.jsonl"
}

run_hook() {  # echoes the decision
  ( cd "$WORK/repo" && printf '{"transcript_path":"%s"}' "$WORK/transcript.jsonl" \
    | CLAUDE_DRIFT_CHECK_DRYRUN=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$HOOK" )
}

expect() {  # $1 = label, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 — expected '$2', got '$3'"
    fail=1
  fi
}

CLAIM='{"role":"assistant","text":"task drift-hook is done and verified"}'
NOCLAIM='{"role":"assistant","text":"looking at the file now"}'

# 1. no plan at all
setup_repo; write_transcript "$CLAIM"
expect "no plan in the repo" "silent: no-plan" "$(run_hook)"

# 2. plan present but the wave is finished
setup_repo; write_plan done "branch: wave/alpha"; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha 2>/dev/null
expect "status: done wins over live branches" "silent: wave-done" "$(run_hook)"

# 3. active, but every branch it names is gone — the self-clearing net
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$CLAIM"
expect "active status, no live branches" "silent: no-live-branches" "$(run_hook)"

# 4. active with a live branch and a claim in the transcript
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha
expect "active wave with a live branch" "would-call" "$(run_hook)"

# 5. re-entrancy guard beats every other gate
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha
expect "nested run short-circuits" "silent: reentrant" \
  "$( cd "$WORK/repo" && printf '{}' | CLAUDE_DRIFT_CHECK_DRYRUN=1 CLAUDE_DRIFT_CHECK_ACTIVE=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$HOOK" )"

# 6. active wave, but the turn claimed nothing worth checking
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$NOCLAIM"
git -C "$WORK/repo" branch wave/alpha
expect "cost pre-filter, nothing claimed" "silent: nothing-claimed" "$(run_hook)"

# 7. a plan naming no branches falls through to the pre-filter rather than
#    silently blocking on gate 4
setup_repo; write_plan active ""; write_transcript "$CLAIM"
expect "plan without branches still runs" "would-call" "$(run_hook)"

# 8. no transcript to read
setup_repo; write_plan active "branch: wave/alpha"
git -C "$WORK/repo" branch wave/alpha
rm -f "$WORK/transcript.jsonl"
expect "missing transcript" "silent: no-transcript" "$(run_hook)"

# 9. the prompt file must exist
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha
expect "missing prompt file" "silent: no-prompt" \
  "$( cd "$WORK/repo" && printf '{"transcript_path":"%s"}' "$WORK/transcript.jsonl" \
     | CLAUDE_DRIFT_CHECK_DRYRUN=1 CLAUDE_PLUGIN_ROOT="$WORK/nonexistent" "$HOOK" )"

# 10. the real path, model included. Off by default: it costs a model call.
if [ "${LIVE:-}" = "1" ]; then
  setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$CLAIM"
  git -C "$WORK/repo" branch wave/alpha
  out="$( cd "$WORK/repo" && printf '{"transcript_path":"%s"}' "$WORK/transcript.jsonl" \
         | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$HOOK" )"
  case "$out" in
    '{}'|'{"hookSpecificOutput"'*) echo "PASS  live path emits valid JSON: ${out:0:40}" ;;
    *) echo "FAIL  live path emitted: ${out:0:80}"; fail=1 ;;
  esac
  python3 -c "import json,sys;json.loads(sys.argv[1])" "$out" \
    && echo "PASS  live output parses as JSON" \
    || { echo "FAIL  live output is not JSON"; fail=1; }
else
  echo "SKIP  live path (set LIVE=1 to run it)"
fi

exit $fail
