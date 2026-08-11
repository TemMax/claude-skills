#!/usr/bin/env bash
# Tier 2 — the invariants a skill's behaviour depends on.
#
# Honest about what this tier is: assertions over prose. It catches a rule being
# deleted or silently reworded, and it caught nothing in the 2026-08-11 review,
# where all three serious findings came from probing behaviour instead. So only
# load-bearing text lives here — a line whose loss changes what the agent DOES,
# or reopens a defect that has already cost us once. Wording that is merely nice
# is deliberately not pinned: a suite that fails on rephrasing gets neutered.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

CR=plugins/code-review/skills/critical-review/SKILL.md
MM=plugins/orchestration/skills/multi-model/SKILL.md

section "critical-review: the PR read must be able to answer what it promises"
# REST exposes no thread id and no resolution state, so a REST-based read makes
# thread classification and the whole fix phase impossible.
check "threads are read over GraphQL"          "grep -q 'reviewThreads(first:100, after:\$endCursor)' $CR"
check "the read is paginated"                  "grep -q -- '--paginate' $CR"
check "REST is not invoked for inline threads" "! grep -q 'gh api repos/{owner}/{repo}/pulls/<n>/comments' $CR"
check "per-thread write capability is fetched" "grep -q 'viewerCanReply viewerCanResolve' $CR"
check "node count is reconciled"               "grep -q 'totalCount' $CR"

section "critical-review: rules that stop the fix phase harming a PR"
check "findings carry provenance"              "grep -q 'thread:<threadId>:<rootCommentDatabaseId>' $CR"
check "replies carry the idempotency marker"   "grep -q 'critical-review-fix-reply' $CR"
check "skip on the marker, not on authorship"  "grep -q 'never on bare authorship' $CR"
check "push precedes replies"                  "grep -q 'push\` → replies → resolves' $CR"
check "resolve only on a complete fix"         "grep -q 'closes the comment completely' $CR"
check "cancel is a soft reset"                 "grep -q 'git reset --soft' $CR"
check "reply language follows the thread"      "grep -q 'language of the thread being answered' $CR"

section "multi-model: wave isolation, where a wrong base blocks correct work"
check "per-task worktree"                      "grep -q 'its own git worktree' $MM"
check "branch convention"                      "grep -q 'wave/<task-id>' $MM"
check "base is the fork point, not local HEAD" "grep -q 'not your local' $MM"
check "the fork point is named"                "grep -q 'origin/<default-branch>' $MM"

section "multi-model: the contract a supervisor can actually decide"
for k in files_allowed files_forbidden must_run forbidden_moves report_must_answer; do
  check "contract field $k" "grep -q '$k' $MM"
done
check "evidence is a contract term"            "grep -q 'evidence: required' $MM"
check "a claim without output is a violation"  "grep -q 'violation in its own right' $MM"

section "multi-model: supervision that cannot be skipped or gamed"
check "supervision is a stage, not advice"     "grep -q 'not an instruction to self-check' $MM"
check "artifacts only"                         "grep -q 'artifacts only' $MM"
check "forged evidence is its own class"       "grep -q 'forged-evidence' $MM"
check "remarks do not block"                   "grep -q 'remarks' $MM"
check "the ladder has a terminal rung"         "grep -q 'already the strongest' $MM"
check "blocking threshold above suspicion"     "grep -q 'Blocking correct work' $MM"
check "supervisor prompt is referenced"        "grep -q 'references/supervisor-prompt.md' $MM"

section "multi-model: the lifecycle belongs to the orchestrator, not the user"
check "plan is opened at launch"               "grep -q 'Write the wave plan file' $MM"
check "plan is closed at completion"           "grep -q 'Set the wave plan.*status: done' $MM"
check "the user never hand-edits it"           "grep -q 'You own both transitions' $MM"
check "status gate fails closed"               "grep -q 'first code fence' $MM"
check "branch gate reads declared branches"    "grep -q 'declared branches only' $MM"

section "multi-model: the evidence base for every anti-deception rule"
# Losing a citation turns a measured rule into an opinion. Each of these points
# at a specific page in references/model-dossiers.md.
for c in "161–163" "109–110" "171–181" "p. 81" "37–39" "170–171" "33–35" "122–124" "202–203"; do
  check "citation $c survives" "grep -qF '$c' $MM"
done

section "Both skills: rules must be findable by the model that needs them"
check "critical-review names the fix-phase triggers" \
  "sed -n '3p' $CR | grep -q 'answer the PR comments'"
check "multi-model names Opus 5 as an executor" \
  "sed -n '3p' $MM | grep -q 'Opus 5'"

summary
