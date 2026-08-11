#!/usr/bin/env bash
# One entry point. Default is offline and free; --live adds the tiers that call
# a model and therefore cost money and minutes.
#
#   ./tests/run.sh          structure + contracts + behaviour   (seconds)
#   ./tests/run.sh --live   the above, plus the evaluation tiers (~1 min, ~7 calls)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

LIVE=""
[ "${1:-}" = "--live" ] && LIVE=1

rc=0
run() {
  printf '\n\033[1;34m▸ %s\033[0m\n' "$1"
  shift
  if "$@"; then :; else rc=1; fi
}

run "structure — manifests, frontmatter, versions, prohibitions" bash tests/structure.sh
run "contracts — the invariants behaviour depends on"            bash tests/skills-contract.sh

for t in plugins/*/hooks/*.test.sh; do
  [ -e "$t" ] || continue
  run "behaviour — $(basename "$(dirname "$(dirname "$t")")")/$(basename "$t")" bash "$t"
done

if [ -n "$LIVE" ]; then
  for e in tests/eval/*.sh; do
    [ -e "$e" ] || continue
    run "evaluation (live model) — $(basename "$e" .sh)" bash "$e"
  done
else
  printf '\n\033[33m▸ evaluation tiers skipped — run with --live to include them\033[0m\n'
  printf '  they are the only tiers that ask whether the prompts actually work\n'
fi

printf '\n'
if [ "$rc" -eq 0 ]; then printf '\033[32mall tiers passed\033[0m\n'; else printf '\033[31mSOME TIERS FAILED\033[0m\n'; fi
exit $rc
