#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

section "disposable Git repositories ignore developer signing configuration"
. tests/test-env.sh
expect "commit signing disabled only in test process" "false" "$(git config --get commit.gpgsign)"
expect "default branch pinned" "master" "$(git config --get init.defaultBranch)"

section "contract directory is part of the default runner"
check "contract test loop exists" "grep -q 'tests/contracts/\\*.test.sh' tests/run.sh"
summary
