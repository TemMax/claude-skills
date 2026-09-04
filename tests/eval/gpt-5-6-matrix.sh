#!/usr/bin/env bash
# Full GPT-5.6 semantic matrix. This driver is intentionally not called by
# tests/run.sh --live; every invocation requires a fresh caller-owned result
# directory because failures must be recorded before any rerun.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/test-env.sh

models='gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna'
skill_scripts='super-plan wave critical-review ship'
support_scripts='profile-routing safety supervisor drift'

HEADER='script\tscenario\tsemantic_path\tprovider\tmodel\teffort\tblocking\tstatus\tclassification\texit\telapsed_ms\tprompt\tfinal_answer\tclassification_evidence\tstatus_evidence\tinput_tokens\toutput_tokens\tcost'

now_ms() { python3 -c 'import time; print(time.monotonic_ns() // 1000000)' ; }

results_dir_is_fresh() {
  local directory="$1"
  [ ! -e "$directory" ] || {
    [ -d "$directory" ] && [ -z "$(find "$directory" -mindepth 1 -print -quit)" ]
  }
}

append_row() { # rows plus the 18 data fields
  local rows="$1"; shift
  if [ ! -e "$rows" ]; then printf '%b\n' "$HEADER" > "$rows"; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >> "$rows"
}

make_capture_wrappers() { # capture-root real-codex
  local capture="$1" real_codex="$2"
  mkdir -p "$capture/bin" "$capture/prompts" "$capture/finals" "$capture/tmp" "$capture/removed"
  cat > "$capture/bin/codex" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
counter="$EVAL_CAPTURE_DIR/counter"
[ -f "$counter" ] || printf '0\n' > "$counter"
n=$(( $(cat "$counter") + 1 ))
printf '%s\n' "$n" > "$counter"
prompt="$EVAL_CAPTURE_DIR/prompts/prompt-$n.md"
command cat > "$prompt"
answer=""
prev=""
for arg in "$@"; do
  if [ "$prev" = --output-last-message ]; then answer="$arg"; break; fi
  prev="$arg"
done
"$EVAL_REAL_CODEX" "$@" < "$prompt"
rc=$?
[ -n "$answer" ] && [ -f "$answer" ] && command cp "$answer" "$EVAL_CAPTURE_DIR/finals/final-$n.txt"
exit "$rc"
SH
  cat > "$capture/bin/rm" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
target=""
for arg in "$@"; do case "$arg" in -*) ;; *) target="$arg" ;; esac; done
case "$target" in
  "$EVAL_CAPTURE_TMP"/*)
    name="$(basename "$target")"
    [ -e "$target" ] && command cp -R "$target" "$EVAL_CAPTURE_DIR/removed/$name"
    ;;
esac
exec /bin/rm "$@"
SH
  chmod +x "$capture/bin/codex" "$capture/bin/rm"
  export EVAL_CAPTURE_DIR="$capture" EVAL_CAPTURE_TMP="$capture/tmp" EVAL_REAL_CODEX="$real_codex"
}

combine_numbered() { # directory glob-prefix output
  local dir="$1" prefix="$2" output="$3" file
  : > "$output"
  for file in "$dir"/$prefix-*; do
    [ -f "$file" ] || continue
    printf '\n===== %s =====\n' "$(basename "$file")" >> "$output"
    command cat "$file" >> "$output"
  done
}

legacy_section_status() { # stdout section-start next-section-or-empty
  python3 - "$1" "$2" "$3" <<'PY'
import re
import sys
path, start, end = sys.argv[1:]
text = open(path, encoding="utf-8").read()
text = re.sub(r"\x1b\[[0-9;]*m", "", text)
part = text.split(start, 1)[1] if start in text else ""
if end and end in part:
    part = part.split(end, 1)[0]
print("pass" if "PASS" in part and "FAIL" not in part else "fail:legacy-fixture-failed")
PY
}

record_legacy_row() { # phase-dir script scenario semantic model effort status exit elapsed prompt final stdout
  local phase="$1" script="$2" scenario="$3" semantic="$4" model="$5" effort="$6" status="$7" exit_code="$8" elapsed="$9"
  shift 9
  local prompt="$1" final="$2" stdout="$3" cell class_file status_file classification
  cell="$phase/raw/${model}-${effort}-${script}-${scenario}"
  if [ -e "$cell" ]; then
    printf 'matrix: refusing to overwrite legacy cell %s\n' "$cell" >&2
    return 73
  fi
  mkdir -p "$cell"
  [ -f "$prompt" ] && command cp "$prompt" "$cell/prompt.md" || : > "$cell/prompt.md"
  [ -f "$final" ] && command cp "$final" "$cell/final-answer.txt" || : > "$cell/final-answer.txt"
  command cp "$stdout" "$cell/process-output.txt"
  class_file="$cell/classification.txt"; status_file="$cell/status.txt"
  case "$status" in pass) classification=pass ;; *) classification="$status" ;; esac
  printf '%s\n' "$classification" > "$class_file"
  printf 'status=%s\nexit=%s\nelapsed_ms=%s\ninput_tokens=unavailable\noutput_tokens=unavailable\ncost=unavailable\n' \
    "${status%%:*}" "$exit_code" "$elapsed" > "$status_file"
  append_row "$phase/cells.tsv" "$script" "$scenario" "$semantic" codex "$model" "$effort" yes \
    "${status%%:*}" "$classification" "$exit_code" "$elapsed" "$cell/prompt.md" "$cell/final-answer.txt" \
    "$class_file" "$status_file" unavailable unavailable unavailable
}

run_legacy() { # phase-dir script model effort
  local phase="$1" script="$2" model="$3" effort="$4" capture real_codex start end elapsed rc status prompt final removed
  capture="$phase/legacy-capture/${model}-${effort}-${script}"
  real_codex="$(command -v codex || true)"
  if [ -z "$real_codex" ]; then
    printf 'matrix: codex executable not found\n' >&2
    return 127
  fi
  make_capture_wrappers "$capture" "$real_codex"
  mkdir -p "$phase/process"
  start="$(now_ms)"
  set +e
  PATH="$capture/bin:$PATH" TMPDIR="$capture/tmp" EVAL_PROVIDER=codex EVAL_MODEL="$model" EVAL_EFFORT="$effort" \
    bash "tests/eval/$script.sh" > "$capture/stdout.txt" 2> "$capture/stderr.txt"
  rc=$?
  set -e
  end="$(now_ms)"; elapsed=$((end - start))
  combine_numbered "$capture/prompts" prompt "$capture/all-prompts.md"
  combine_numbered "$capture/finals" final "$capture/all-finals.txt"
  if [ "$script" = super-plan ]; then
    removed="$(find "$capture/removed" -type f -name p1.md -print -quit 2>/dev/null || true)"
    prompt="$capture/prompts/prompt-1.md"; final="${removed:-$capture/all-finals.txt}"
    status="$(legacy_section_status "$capture/stdout.txt" 'P1 — overlap temptation' 'P2 — a product fork')"
    record_legacy_row "$phase" super-plan overlap-safe success "$model" "$effort" "$status" "$rc" "$elapsed" "$prompt" "$final" "$capture/stdout.txt" || true
    removed="$(find "$capture/removed" -type f -name p2.md -print -quit 2>/dev/null || true)"
    prompt="$capture/prompts/prompt-2.md"; final="${removed:-$capture/all-finals.txt}"
    status="$(legacy_section_status "$capture/stdout.txt" 'P2 — a product fork' '')"
    record_legacy_row "$phase" super-plan product-fork failure "$model" "$effort" "$status" "$rc" "$elapsed" "$prompt" "$final" "$capture/stdout.txt" || true
  else
    if [ "$rc" -eq 0 ]; then status=pass; else status="fail:legacy-script-exit-$rc"; fi
    record_legacy_row "$phase" "$script" aggregate support "$model" "$effort" "$status" "$rc" "$elapsed" \
      "$capture/all-prompts.md" "$capture/all-finals.txt" "$capture/stdout.txt" || true
  fi
  [ "$rc" -eq 0 ]
}

run_persisting() { # phase-dir script model effort
  local phase="$1" script="$2" model="$3" effort="$4" rc
  mkdir -p "$phase/process"
  set +e
  EVAL_RESULTS_DIR="$phase" EVAL_PROVIDER=codex EVAL_MODEL="$model" EVAL_EFFORT="$effort" \
    bash "tests/eval/$script.sh" > "$phase/process/${model}-${effort}-${script}.stdout" \
    2> "$phase/process/${model}-${effort}-${script}.stderr"
  rc=$?
  set -e
  return "$rc"
}

run_one() { # phase script model effort
  case "$2" in
    super-plan|supervisor|drift) run_legacy "$@" ;;
    *) run_persisting "$@" ;;
  esac
}

run_full_matrix() { # phase effort
  local phase="$1" effort="$2" model script
  for model in $models; do
    export EVAL_PROVIDER=codex EVAL_MODEL="$model" EVAL_EFFORT="$effort"
    for script in $skill_scripts; do
      printf 'matrix: %s %s %s\n' "$model" "$effort" "$script"
      run_one "$phase" "$script" "$model" "$effort" || RELEASE_FAILURE=1
    done
    for script in $support_scripts; do
      printf 'matrix: %s %s %s (support)\n' "$model" "$effort" "$script"
      run_one "$phase" "$script" "$model" "$effort" || RELEASE_FAILURE=1
    done
  done
}

collect_rows() { # results-root
  local root="$1" file
  printf '%b\n' "$HEADER" > "$root/summary.tsv"
  while IFS= read -r file; do
    tail -n +2 "$file" >> "$root/summary.tsv"
  done < <(find "$root" -mindepth 2 -name cells.tsv -type f | LC_ALL=C sort)
}

write_markdown() { # results-root mode
  python3 - "$1/summary.tsv" "$1/summary.md" "$2" <<'PY'
import csv
import sys
from collections import defaultdict

source, output, mode = sys.argv[1:]
with open(source, newline="", encoding="utf-8") as stream:
    rows = list(csv.DictReader(stream, delimiter="\t"))
required = {"super-plan", "wave", "critical-review", "ship"}
pairs = defaultdict(set)
for row in rows:
    if row["script"] in required and row["effort"] == "medium":
        pairs[(row["model"], row["script"])].add(row["semantic_path"])
complete = sum({"success", "failure"} <= paths for paths in pairs.values())
blocking = [row for row in rows if row["blocking"] == "yes" and row["status"] != "pass"]
support = [row for row in rows if row["script"] not in required or row["semantic_path"] == "support"]
lines = [
    "# GPT-5.6 evaluation summary",
    "",
    f"Mode: `{mode}`",
    "",
    f"Required medium skill/model pairs with both success and failure rows: **{complete}/12**.",
    f"Supporting rows (not counted in the 12 pairs): **{len(support)}**.",
    f"Release-blocking failed cells: **{len(blocking)}**.",
    "",
    "Token and cost fields remain `unavailable` unless the model adapter observes them; this driver never estimates them.",
    "",
    "| Script | Scenario | Path | Model | Effort | Status | Classification | Elapsed ms |",
    "|---|---|---|---|---|---|---|---:|",
]
for row in rows:
    lines.append("| {script} | {scenario} | {semantic_path} | {model} | {effort} | {status} | {classification} | {elapsed_ms} |".format(**row))
with open(output, "w", encoding="utf-8") as stream:
    stream.write("\n".join(lines) + "\n")
PY
}

if [ "${1:-}" = --self-test ]; then
  set -e
  W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
  mkdir -p "$W/fresh"
  results_dir_is_fresh "$W/fresh"
  printf 'recorded\n' > "$W/fresh/first-failure.txt"
  ! results_dir_is_fresh "$W/fresh"
  mkdir -p "$W/base"
  printf '%b\n' "$HEADER" > "$W/base/cells.tsv"
  for model in $models; do
    for script in $skill_scripts; do
      for semantic in success failure; do
        append_row "$W/base/cells.tsv" "$script" fixture "$semantic" codex "$model" medium yes pass pass 0 1 p a c s unavailable unavailable unavailable
      done
    done
  done
  append_row "$W/base/cells.tsv" safety destructive-scope support codex gpt-5.6-sol medium yes pass pass 0 1 p a c s unavailable unavailable unavailable
  collect_rows "$W"
  write_markdown "$W" self-test
  grep -q '12/12' "$W/summary.md"
  grep -q 'Supporting rows.*1' "$W/summary.md"
  [ "$(tail -n +2 "$W/summary.tsv" | wc -l | tr -d ' ')" = 25 ]
  printf 'gpt-5.6 matrix self-test: PASS\n'
  exit
fi

MODE=default
RESULTS_ROOT="${EVAL_RESULTS_DIR:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --critical|--effort)
      [ "$MODE" = default ] || { printf 'matrix: choose only one mode\n' >&2; exit 64; }
      MODE="${1#--}"; shift
      ;;
    --results)
      [ "$#" -ge 2 ] || { printf 'matrix: --results requires a directory\n' >&2; exit 64; }
      RESULTS_ROOT="$2"; shift 2
      ;;
    *) printf 'matrix: unknown argument %s\n' "$1" >&2; exit 64 ;;
  esac
done
: "${RESULTS_ROOT:?pass --results DIR or set EVAL_RESULTS_DIR to a fresh caller-owned directory}"
if ! results_dir_is_fresh "$RESULTS_ROOT"; then
  printf 'matrix: refusing to overwrite nonempty results path %s\n' "$RESULTS_ROOT" >&2
  exit 73
fi
mkdir -p "$RESULTS_ROOT"
RESULTS_ROOT="$(cd "$RESULTS_ROOT" && pwd)"
export EVAL_PROVIDER=codex
unset EVAL_REPEAT EVAL_CASE
RELEASE_FAILURE=0

run_full_matrix "$RESULTS_ROOT/base" medium

if [ "$MODE" = critical ]; then
  export EVAL_REPEAT=5
  for model in $models; do
    export EVAL_MODEL="$model" EVAL_EFFORT=medium
    for script in critical-review safety supervisor drift; do
      printf 'matrix critical x5: %s %s\n' "$model" "$script"
      run_one "$RESULTS_ROOT/critical" "$script" "$model" medium || RELEASE_FAILURE=1
    done
  done
  unset EVAL_REPEAT
elif [ "$MODE" = effort ]; then
  run_full_matrix "$RESULTS_ROOT/high" high
  export EVAL_MODEL=gpt-5.6-sol
  for effort in xhigh max; do
    export EVAL_EFFORT="$effort"
    export EVAL_CASE=hard
    printf 'matrix effort hard: gpt-5.6-sol %s critical-review\n' "$effort"
    run_one "$RESULTS_ROOT/$effort" critical-review gpt-5.6-sol "$effort" || RELEASE_FAILURE=1
    export EVAL_CASE=destructive
    printf 'matrix effort destructive: gpt-5.6-sol %s safety\n' "$effort"
    run_one "$RESULTS_ROOT/$effort" safety gpt-5.6-sol "$effort" || RELEASE_FAILURE=1
    unset EVAL_CASE
  done
fi

collect_rows "$RESULTS_ROOT"
write_markdown "$RESULTS_ROOT" "$MODE"
if python3 - "$RESULTS_ROOT/summary.tsv" <<'PY'
import csv, sys
with open(sys.argv[1], newline="", encoding="utf-8") as stream:
    rows = list(csv.DictReader(stream, delimiter="\t"))
raise SystemExit(0 if all(row["blocking"] != "yes" or row["status"] == "pass" for row in rows) else 1)
PY
then :; else RELEASE_FAILURE=1; fi

printf 'matrix results: %s\n' "$RESULTS_ROOT"
exit "$RELEASE_FAILURE"
