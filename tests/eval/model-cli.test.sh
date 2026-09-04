#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh
. tests/eval/model-cli.sh

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
BIN="$W/bin"; LOG="$W/log"; REPO="$W/repo"
mkdir -p "$BIN" "$LOG" "$REPO"
export EVAL_STUB_LOG="$LOG"

cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'claude\n' >> "$EVAL_STUB_LOG/calls"
printf '%s\n' "$@" > "$EVAL_STUB_LOG/claude.argv"
cat > "$EVAL_STUB_LOG/claude.stdin"
printf 'claude final answer\n'
SH
cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'codex\n' >> "$EVAL_STUB_LOG/calls"
printf '%s\n' "$@" > "$EVAL_STUB_LOG/codex.argv"
cat > "$EVAL_STUB_LOG/codex.stdin"
answer_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message) answer_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'codex final answer\n' > "$answer_file"
printf 'codex stdout is not the final answer\n'
SH
chmod +x "$BIN/claude" "$BIN/codex"

PROMPT="$W/prompt.md"
printf 'Give only the final answer.\n' > "$PROMPT"

run_model() {
  PATH="$BIN:$PATH" EVAL_PROVIDER="$1" EVAL_MODEL="$2" EVAL_EFFORT="$3" EVAL_TIMEOUT=5 \
    eval_model "$REPO" "$4" "$PROMPT" "$5"
}

section "Claude read-only uses only the Claude permission contract"
CLAUDE_READONLY="$W/claude-read-only.md"
run_model claude claude-test low read-only "$CLAUDE_READONLY"
expect "Claude writes its final answer" "claude final answer" "$(cat "$CLAUDE_READONLY")"
expect "Claude reads the prompt from stdin" "$(cat "$PROMPT")" "$(cat "$LOG/claude.stdin")"
expect "Claude read-only argv is exact" "$(printf '%s\n' -p --model claude-test --effort low --permission-mode plan --permission-prompts none --no-session-persistence)" "$(cat "$LOG/claude.argv")"
check "Claude receives no Codex flags" "! rg -q -- '--(ephemeral|ignore-user-config|ignore-rules|sandbox|output-last-message)' '$LOG/claude.argv'"
check "Claude receives no unsafe bypass flag" "! rg -q -- 'bypassPermissions|dangerously-bypass' '$LOG/claude.argv'"

section "Claude workspace-write uses its narrow edit contract"
CLAUDE_WRITE="$W/claude-write.md"
run_model claude claude-test high workspace-write "$CLAUDE_WRITE"
expect "Claude workspace-write argv is exact" "$(printf '%s\n' -p --model claude-test --effort high --permission-mode acceptEdits --permission-prompts none --no-session-persistence --allowedTools 'Read,Glob,Grep,Edit,Write,Bash')" "$(cat "$LOG/claude.argv")"
check "Claude workspace-write receives no unsafe bypass flag" "! rg -q -- 'bypassPermissions|dangerously-bypass' '$LOG/claude.argv'"

section "Codex writes only its final assistant message"
CODEX_ANSWER="$W/codex-answer.md"
out="$(run_model codex gpt-5.6-sol high read-only "$CODEX_ANSWER")"
expect "Codex writes its final answer" "codex final answer" "$(cat "$CODEX_ANSWER")"
expect "Codex stdout is suppressed" "" "$out"
expect "Codex reads the prompt from stdin" "$(cat "$PROMPT")" "$(cat "$LOG/codex.stdin")"
expect "Codex argv is exact" "$(printf '%s\n' exec --ephemeral --ignore-user-config --ignore-rules --sandbox read-only --model gpt-5.6-sol -c 'model_reasoning_effort="high"' --output-last-message "$CODEX_ANSWER" -)" "$(cat "$LOG/codex.argv")"
check "Codex receives no unsafe bypass flag" "! rg -q -- 'bypassPermissions|dangerously-bypass' '$LOG/codex.argv'"

section "Invalid provider or sandbox cannot invoke a model"
before="$(wc -l < "$LOG/calls")"
set +e
PATH="$BIN:$PATH" EVAL_PROVIDER=unknown eval_model "$REPO" read-only "$PROMPT" "$W/unknown.md"
provider_rc=$?
PATH="$BIN:$PATH" EVAL_PROVIDER=codex eval_model "$REPO" invalid "$PROMPT" "$W/invalid.md"
sandbox_rc=$?
set -e
expect "unknown provider exits 2" "2" "$provider_rc"
expect "unknown sandbox exits 2" "2" "$sandbox_rc"
expect "invalid input invokes neither stub" "$before" "$(wc -l < "$LOG/calls")"

summary
