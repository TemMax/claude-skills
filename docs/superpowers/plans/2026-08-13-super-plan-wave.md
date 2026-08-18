base: aa2cdef
status: done
plan: docs/superpowers/plans/2026-08-13-super-plan.md
note: three consecutive waves on the pushed feature branch super-plan-dev
  (defaultBranch for the runner); wave 1 merged at b2ce011 = wave-2 base;
  origin/main untouched until the final approved merge. Wave-1 supervisors
  caught a corrupted full base sha in the orchestrator's hand-typed args —
  bases are now copied verbatim from git rev-parse output.

waves:
  - wave: 1
    supervisor: opus/high
    tasks:
      - task: plan-lint
        model: claude-sonnet-5
        effort: medium
        ladder: [opus]
        branch: wave/plan-lint
        contract:
          files_allowed: [plugins/orchestration/skills/super-plan/references/plan-lint.mjs, tests/fixtures/plans/**, tests/plan-lint.test.sh, tests/run.sh]
          files_forbidden: [plugins/orchestration/hooks/**, plugins/orchestration/skills/multi-model/**]
          must_run: [bash tests/plan-lint.test.sh, bash tests/structure.sh]
          forbidden_moves: [weakening or deleting an existing test, hard-coding expected values]
      - task: drift-json-branch
        model: claude-sonnet-5
        effort: low
        ladder: [opus]
        branch: wave/drift-json-branch
        contract:
          files_allowed: [plugins/orchestration/hooks/drift-check, plugins/orchestration/hooks/drift-check.test.sh]
          files_forbidden: [plugins/orchestration/skills/**]
          must_run: [bash plugins/orchestration/hooks/drift-check.test.sh]
          forbidden_moves: [weakening or deleting an existing test case, changing any gate other than the declared-branch pattern]
  - wave: 2 (after wave 1 merges + push)
    supervisor: opus/high
    tasks:
      - task: skill-super-plan
        model: claude-sonnet-5
        effort: medium
        ladder: [opus]
        branch: wave/skill-super-plan
        contract:
          files_allowed: [plugins/orchestration/skills/super-plan/SKILL.md, plugins/orchestration/skills/super-plan/references/LICENSE-superpowers, tests/skills-contract.sh, plugins/orchestration/.claude-plugin/plugin.json, plugins/orchestration/skills/multi-model/SKILL.md]
          files_forbidden: [plugins/orchestration/skills/multi-model/references/**, plugins/orchestration/hooks/**]
          must_run: [bash tests/skills-contract.sh, bash tests/structure.sh]
          forbidden_moves: [weakening or deleting an existing check, any multi-model SKILL.md change beyond the version line]
  - wave: 3 (after wave 2 merges + push)
    supervisor: opus/high
    tasks:
      - task: eval-super-plan
        model: claude-sonnet-5
        effort: high
        ladder: [opus]
        branch: wave/eval-super-plan
        contract:
          files_allowed: [tests/eval/super-plan.sh, tests/eval/super-plan-insession.md, tests/README.md]
          files_forbidden: [plugins/**]
          must_run: [bash -n tests/eval/super-plan.sh, bash tests/plan-lint.test.sh]
          forbidden_moves: [weakening or deleting an existing test, editing the shipped skill to make the eval pass]
