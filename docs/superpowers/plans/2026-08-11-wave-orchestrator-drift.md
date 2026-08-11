# Wave plan — orchestrator drift layer

base: 9da3e3ab19f5ec481f869260424213f397467e2c
supervision: on
supervisor model: fable (measured zero self-preference; never the executor's own)

Decisions closed before decomposition, per the skill's Process step 2:

- The hook **advises, it does not block** — a `command` hook returning
  `hookSpecificOutput.additionalContext`. Verified 2026-08-11 that the harness
  accepts this on `Stop` (`Hook Stop (...) provided additionalContext`).
- It fires on **`Stop`**, once per turn, not per edit. `Stop` accepts only
  `command`-type hooks, which matches the advisory choice.
- The advice is produced by a **separate model invocation** from inside the hook
  script, so the orchestrator does not grade itself.

## Tasks

### drift-hook
- model: sonnet
- branch: wave/drift-hook
- contract:
  - files_allowed: `plugins/orchestration/hooks/**`
  - files_forbidden: `plugins/orchestration/skills/**`, `README.md`,
    `plugins/orchestration/.claude-plugin/plugin.json`
  - must_run:
    - `python3 -c "import json;json.load(open('plugins/orchestration/hooks/hooks.json'))"` — evidence required
    - `printf '{}' | ./plugins/orchestration/hooks/drift-check` — evidence required
  - forbidden_moves: naming any third-party reference implementation; making the
    hook block instead of advise; hardcoding an absolute path outside
    `${CLAUDE_PLUGIN_ROOT}`
  - report_must_answer: What does the script emit when the model call fails?
    What does it emit when there is nothing to say?

### drift-prompt
- model: sonnet
- branch: wave/drift-prompt
- contract:
  - files_allowed:
    `plugins/orchestration/skills/multi-model/references/orchestrator-drift-prompt.md`
  - files_forbidden: everything else
  - must_run:
    - `test -f plugins/orchestration/skills/multi-model/references/orchestrator-drift-prompt.md` — evidence required
  - forbidden_moves: naming any third-party reference implementation; asking the
    model for a blocking verdict; inventing dossier page numbers
  - report_must_answer: What does the prompt tell the model to do when it has
    nothing to say?

### drift-docs
- model: sonnet
- branch: wave/drift-docs
- contract:
  - files_allowed: `plugins/orchestration/skills/multi-model/SKILL.md`,
    `README.md`, `plugins/orchestration/.claude-plugin/plugin.json`
  - files_forbidden: `plugins/orchestration/hooks/**`,
    `plugins/orchestration/skills/multi-model/references/**`
  - must_run:
    - `python3 -c "import json;json.load(open('plugins/orchestration/.claude-plugin/plugin.json'))"` — evidence required
  - forbidden_moves: naming any third-party reference implementation; weakening
    or deleting any existing section; changing the version to anything other
    than 1.7.0
  - report_must_answer: Which sections did you add, and where exactly?

## Why this is a genuine wave and not a rehearsal dressed as one

Three disjoint file sets, three different kinds of artifact (an executable
mechanism, a prompt, documentation), no shared edits. The skill warns that
parallelization pays only on hard chunks; these are separable rather than hard,
so the honest claim is that this wave tests the supervision machinery on real
work, not that it saves wall-clock time.
