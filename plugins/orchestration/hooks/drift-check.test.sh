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

# The payload carries last_assistant_message; the transcript file is only extra
# context for the model. $1 overrides the message, defaulting to a claim.
run_hook() {
  local msg="${1-Summary: 2 tasks done, verified, nothing remaining.}"
  ( cd "$WORK/repo" && python3 -c "
import json,sys
print(json.dumps({'transcript_path': sys.argv[1], 'last_assistant_message': sys.argv[2]}))
" "$WORK/transcript.jsonl" "$msg" \
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

CLAIM='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Summary: 2 tasks done, verified, nothing remaining."}]}}'
NOCLAIM='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me look at the file now."}]}}'
TOOLNOISE='{"type":"user","message":{"role":"user","content":"12 passed in 0.4s, all tests complete and verified"}}'

# 1. no plan at all
setup_repo; write_transcript "$CLAIM"
expect "no plan in the repo" "silent: no-plan" "$(run_hook)"

# 2. plan present but the wave is finished
setup_repo; write_plan done "branch: wave/alpha"; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha 2>/dev/null
expect "status: done wins over live branches" "silent: wave-not-active" "$(run_hook)"

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
expect "cost pre-filter, nothing claimed" "silent: nothing-claimed" "$(run_hook 'Let me look at the file now.')"

# 7. an explicitly active plan naming no branches still runs — opting in is a
#    deliberate act, and the branch net simply has nothing to check
setup_repo; write_plan active ""; write_transcript "$CLAIM"
expect "explicitly active plan without branches runs" "would-call" "$(run_hook)"

# 7b. THE REGRESSION THAT MATTERS: a plan with no status field at all must not
#     switch the hook on. Open-by-default is what made the plan file a permanent
#     trigger in the first place.
setup_repo; write_transcript "$CLAIM"
cat > "$WORK/repo/docs/superpowers/plans/2026-01-01-wave-test.md" <<'EOF'
base: deadbee
tasks:
  - task: alpha
EOF
expect "plan with no status stays off" "silent: wave-not-active" "$(run_hook)"

# 7c. an unrecognised status is not an invitation either
setup_repo; write_plan paused ""; write_transcript "$CLAIM"
expect "unknown status stays off" "silent: wave-not-active" "$(run_hook)"

# 5b. a turn our own advice caused must not be advised on again
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha
expect "continuation after advice stays quiet" "silent: already-advised-this-chain" \
  "$( cd "$WORK/repo" && printf '{"stop_hook_active":true,"last_assistant_message":"Summary: all tasks done, nothing remaining."}' \
     | CLAUDE_DRIFT_CHECK_DRYRUN=1 CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "$HOOK" )"

# 6b. tool output full of the old keywords must NOT trigger a call: this is the
#     measured failure of the previous filter, which passed 99% of real turns.
setup_repo; write_plan active "branch: wave/alpha"; write_transcript "$TOOLNOISE"
git -C "$WORK/repo" branch wave/alpha
expect "tool output alone does not trigger" "silent: nothing-claimed" "$(run_hook '12 passed in 0.4s, all tests complete and verified')"

# 8. the payload carries no final message (the turn said nothing)
setup_repo; write_plan active "branch: wave/alpha"
git -C "$WORK/repo" branch wave/alpha
expect "empty final message" "silent: nothing-said" "$(run_hook '')"

# 8b. a missing transcript file must NOT stop the check: the payload is the gate,
#     the file is only extra context, and at Stop time it may not be written yet.
setup_repo; write_plan active "branch: wave/alpha"
git -C "$WORK/repo" branch wave/alpha
rm -f "$WORK/transcript.jsonl"
expect "missing transcript still runs" "would-call" "$(run_hook)"

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
