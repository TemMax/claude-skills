# super-plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `super-plan` skill — wave-native planning with a shipped
deterministic plan linter — as orchestration 2.1.0.

**Architecture:** A prose SKILL.md (research → one batched question round →
design gate → wave-grouped tasks with contracts → mandatory lint → plan gate)
plus `plan-lint.mjs` enforcing the load-bearing plan rules as code. The plan
format's machine half is a JSON block that is byte-for-byte the wave-runner's
task input. One drift-hook sed pattern gains quoted-JSON branch support.

**Tech Stack:** plain Node ≥18 (no deps) for the linter; bash + tests/lib.sh
for test tiers; markdown skill prose.

**Spec:** `docs/superpowers/specs/2026-08-13-super-plan-design.md`

## Global Constraints

- No mention of the third-party reference implementation names (structure.sh
  greps bracketed patterns; do not write them even in comments).
- Push only with the user's explicit approval; local commits are fine.
- `plugins/orchestration/.claude-plugin/plugin.json` version and EVERY SKILL.md
  `metadata.version` in that plugin must agree (structure.sh enforces it):
  all go to `2.1.0` in Task 3, not before.
- Model names in plans are short (`haiku`/`sonnet`/`opus`/`fable`); efforts
  `low|medium|high|xhigh|max`; contract keys exactly `files_allowed`,
  `files_forbidden`, `must_run`, `forbidden_moves`, `report_must_answer`.
- The linter must have zero npm dependencies and never modify any file.
- Attribution: MIT notice for superpowers (Jesse Vincent) ships verbatim in
  `references/LICENSE-superpowers`; SKILL.md names the adaptation.
- The wave-runner, supervisor prompt and critical-review are NOT modified.

---

### Task 1: plan-lint.mjs + behaviour tier

**Files:**
- Create: `plugins/orchestration/skills/super-plan/references/plan-lint.mjs`
- Create: `tests/fixtures/plans/clean.md`
- Create: `tests/plan-lint.test.sh`
- Modify: `tests/run.sh` (one line)

**Interfaces:**
- Produces: `node plan-lint.mjs <plan-file> [--repo <path>]` → stdout lines
  `error: …` / `warn: …` + summary `OK:|FAIL: N error(s), M warning(s)`;
  exit 0 clean (warnings allowed), 1 errors, 2 usage. Task 3's SKILL.md and
  Task 4's eval invoke exactly this. The clean fixture is the canonical
  format example; Task 4's eval asserts the same shape.

- [ ] **Step 1: Write the clean fixture (the canonical plan example)**

`tests/fixtures/plans/clean.md`:

````markdown
status: draft
base: pending

# Plan — sample feature

```json wave-plan
{ "waves": [
  { "wave": 1,
    "supervisor": { "model": "opus", "effort": "high" },
    "tasks": [
      { "id": "http-retry",
        "branch": "wave/http-retry",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": ["src/http/**"],
          "files_forbidden": ["src/auth/**"],
          "must_run": [{ "cmd": "true", "evidence": "required" }],
          "forbidden_moves": ["weakening, deleting or skipping an existing test"],
          "report_must_answer": ["Which call sites now retry?"] } },
      { "id": "docs-sync",
        "branch": "wave/docs-sync",
        "executor": { "model": "haiku" },
        "contract": {
          "files_allowed": ["docs/**"],
          "files_forbidden": [],
          "must_run": [{ "cmd": "true", "evidence": "required" }],
          "forbidden_moves": [],
          "report_must_answer": ["What changed?"] } }
    ] }
] }
```

## Task http-retry

Add retry with backoff to the HTTP client. Full description and code go here.

## Task docs-sync

Update the docs to describe retries.
````

- [ ] **Step 2: Write the failing behaviour test**

`tests/plan-lint.test.sh`:

```bash
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

summary
```

Make it executable: `chmod +x tests/plan-lint.test.sh`

- [ ] **Step 3: Run to verify it fails**

Run: `bash tests/plan-lint.test.sh`
Expected: FAIL — the lint script does not exist (`Cannot find module`), every
case red.

- [ ] **Step 4: Implement the linter**

`plugins/orchestration/skills/super-plan/references/plan-lint.mjs`:

```js
#!/usr/bin/env node
// Deterministic linter for super-plan wave plans. Zero dependencies, never
// writes anything. The rules here are load-bearing for execution: a plan
// this script passes feeds the wave-runner without translation.
//
// Usage: node plan-lint.mjs <plan-file> [--repo <path>]
// Exit 0 = clean (warnings allowed), 1 = errors, 2 = usage.
import { readFileSync, existsSync } from 'node:fs'
import { join, isAbsolute } from 'node:path'

const MODELS = ['haiku', 'sonnet', 'opus', 'fable']
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const KEBAB = /^[a-z0-9]+(-[a-z0-9]+)*$/
const CONTRACT_KEYS = ['files_allowed', 'files_forbidden', 'must_run',
  'forbidden_moves', 'report_must_answer']

const argv = process.argv.slice(2)
const planFile = argv.find((a) => !a.startsWith('--'))
const repoIdx = argv.indexOf('--repo')
const repo = repoIdx === -1 ? null : argv[repoIdx + 1]
if (!planFile || (repoIdx !== -1 && !repo)) {
  console.error('usage: node plan-lint.mjs <plan-file> [--repo <path>]')
  process.exit(2)
}

const errors = []
const warns = []
const err = (m) => errors.push(m)
const warn = (m) => warns.push(m)

let text
try { text = readFileSync(planFile, 'utf8') } catch (e) {
  console.log('error: cannot read ' + planFile + ': ' + e.message)
  console.log('FAIL: 1 error(s), 0 warning(s)')
  process.exit(1)
}

// ---- header: the drift hook reads status at column 0 before any fence ----
const firstFence = text.indexOf('```')
const head = firstFence === -1 ? text : text.slice(0, firstFence)
const statusMatch = head.match(/^status:[ \t]*([a-zA-Z-]+)/m)
if (!statusMatch) {
  err('header: no column-0 `status:` line before the first code fence (the drift hook reads it there)')
} else if (!['draft', 'active', 'done'].includes(statusMatch[1])) {
  err('header: status must be draft|active|done, got "' + statusMatch[1] + '"')
}

// ---- machine half: exactly one `json wave-plan` fenced block; plain
// ```json fences inside task prose are deliberately NOT matched ----
const jsonBlocks = [...text.matchAll(/```json wave-plan\r?\n([\s\S]*?)\r?\n```/g)]
let plan = null
if (jsonBlocks.length !== 1) {
  err('machine half: expected exactly one ```json wave-plan block, found ' + jsonBlocks.length)
} else {
  try { plan = JSON.parse(jsonBlocks[0][1]) } catch (e) {
    err('machine half: JSON does not parse: ' + e.message)
  }
}

// Glob overlap by literal prefix (documented approximation: src/http/** vs
// src/** collide; src/a/** vs src/b/** do not; a leading wildcard collides
// with everything).
const literalPrefix = (glob) => {
  const i = glob.search(/[*?\[]/)
  return (i === -1 ? glob : glob.slice(0, i)).replace(/\/+$/, '')
}
const prefixesCollide = (a, b) => {
  const pa = literalPrefix(a), pb = literalPrefix(b)
  return pa === '' || pb === '' || pa === pb
    || pa.startsWith(pb + '/') || pb.startsWith(pa + '/')
}

const ids = []
if (plan) {
  if (!Array.isArray(plan.waves) || plan.waves.length === 0) {
    err('machine half: `waves` must be a non-empty array')
  } else {
    plan.waves.forEach((w, wi) => {
      const at = 'waves[' + wi + ']'
      if (!w || typeof w !== 'object') { err(at + ': must be an object'); return }
      if (!w.supervisor || !MODELS.includes(w.supervisor.model)) {
        err(at + '.supervisor.model: one of ' + MODELS.join('/') + ' (short names only)')
      }
      if (w.supervisor && w.supervisor.effort !== undefined && !EFFORTS.includes(w.supervisor.effort)) {
        err(at + '.supervisor.effort: one of ' + EFFORTS.join('/'))
      }
      if (!Array.isArray(w.tasks) || w.tasks.length === 0) {
        err(at + '.tasks: non-empty array required'); return
      }
      w.tasks.forEach((t, ti) => {
        const tat = at + '.tasks[' + ti + ']'
        if (!t || typeof t !== 'object') { err(tat + ': must be an object'); return }
        if (typeof t.id !== 'string' || !KEBAB.test(t.id)) {
          err(tat + '.id: kebab-case required')
        } else {
          ids.push(t.id)
        }
        if (t.branch !== 'wave/' + t.id) err(tat + '.branch: must be "wave/' + t.id + '"')
        if (!t.executor || !MODELS.includes(t.executor.model)) {
          err(tat + '.executor.model: one of ' + MODELS.join('/') + ' (short names only)')
        }
        if (t.executor && t.executor.effort !== undefined && !EFFORTS.includes(t.executor.effort)) {
          err(tat + '.executor.effort: one of ' + EFFORTS.join('/'))
        }
        if (t.ladder !== undefined && (!Array.isArray(t.ladder) || t.ladder.some((m) => !MODELS.includes(m)))) {
          err(tat + '.ladder: array of ' + MODELS.join('/') + ' (short names only)')
        }
        const c = t.contract
        if (!c || typeof c !== 'object') { err(tat + '.contract: required, with all five keys'); return }
        for (const k of CONTRACT_KEYS) {
          if (!Array.isArray(c[k])) err(tat + '.contract.' + k + ': array required')
        }
        if (Array.isArray(c.files_allowed) && c.files_allowed.length === 0) {
          warn(tat + ' ("' + t.id + '"): files_allowed is empty — the executor has nothing it may change')
        }
        if (Array.isArray(c.must_run)) {
          if (c.must_run.length === 0) {
            warn(tat + ' ("' + t.id + '"): must_run is empty — nothing for the supervisor to run')
          }
          c.must_run.forEach((m, mi) => {
            if (!m || typeof m.cmd !== 'string' || m.cmd === '') err(tat + '.contract.must_run[' + mi + '].cmd: required')
            if (!m || typeof m.evidence !== 'string') err(tat + '.contract.must_run[' + mi + '].evidence: required')
          })
        }
        if (Array.isArray(c.files_allowed) && Array.isArray(c.files_forbidden)) {
          for (const a of c.files_allowed) for (const f of c.files_forbidden) {
            if (typeof a === 'string' && typeof f === 'string' && prefixesCollide(a, f)) {
              err(tat + ' ("' + t.id + '"): files_allowed "' + a + '" overlaps its own files_forbidden "' + f + '"')
            }
          }
        }
      })
      // The rule the whole linter exists for: same-wave tasks must not share files.
      const list = w.tasks.filter((t) => t && t.contract && Array.isArray(t.contract.files_allowed))
      for (let i = 0; i < list.length; i++) {
        for (let j = i + 1; j < list.length; j++) {
          for (const a of list[i].contract.files_allowed) {
            for (const b of list[j].contract.files_allowed) {
              if (typeof a === 'string' && typeof b === 'string' && prefixesCollide(a, b)) {
                err(at + ': tasks "' + list[i].id + '" and "' + list[j].id + '" overlap on "'
                  + a + '" vs "' + b + '" — same-wave tasks must not share files; merge them or split the waves')
              }
            }
          }
        }
      }
    })
  }
  const dup = [...new Set(ids.filter((x, i) => ids.indexOf(x) !== i))]
  for (const d of dup) err('ids: duplicate task id "' + d + '"')
}

// ---- prose half ↔ machine half ----
const proseIds = [...text.matchAll(/^## Task ([a-z0-9-]+)/gm)].map((m) => m[1])
for (const id of ids) {
  if (!proseIds.includes(id)) err('prose: no "## Task ' + id + '" section for task "' + id + '"')
}
for (const id of proseIds) {
  if (!ids.includes(id)) err('prose: section "## Task ' + id + '" has no matching task in the json block')
}

// ---- optional repo checks (warnings only) ----
if (repo && plan && Array.isArray(plan.waves)) {
  const pathDirs = (process.env.PATH || '').split(':').filter(Boolean)
  for (const w of plan.waves) {
    for (const t of (Array.isArray(w.tasks) ? w.tasks : [])) {
      if (!t || !t.contract) continue
      for (const g of (t.contract.files_allowed || [])) {
        if (typeof g !== 'string') continue
        const p = literalPrefix(g)
        if (p && !existsSync(join(repo, p))) {
          warn('repo: files_allowed prefix "' + p + '" does not exist under ' + repo + ' (task "' + t.id + '")')
        }
      }
      for (const m of (t.contract.must_run || [])) {
        if (!m || typeof m.cmd !== 'string' || m.cmd === '') continue
        const bin = m.cmd.trim().split(/\s+/)[0]
        const found = bin.includes('/')
          ? existsSync(isAbsolute(bin) ? bin : join(repo, bin))
          : pathDirs.some((d) => existsSync(join(d, bin)))
        if (!found) warn('repo: must_run command "' + bin + '" found neither on PATH nor in the repo (task "' + t.id + '")')
      }
    }
  }
}

for (const w of warns) console.log('warn: ' + w)
for (const e of errors) console.log('error: ' + e)
console.log((errors.length ? 'FAIL' : 'OK') + ': ' + errors.length + ' error(s), ' + warns.length + ' warning(s)')
process.exit(errors.length ? 1 : 0)
```

- [ ] **Step 5: Run the behaviour test, expect green**

Run: `bash tests/plan-lint.test.sh`
Expected: every case PASS, `0 failed`.

- [ ] **Step 6: Wire into the suite**

In `tests/run.sh`, after the line
`run "behaviour — wave-runner reference implementation (simulated)" bash tests/wave-runner.test.sh`
add:

```bash
run "behaviour — plan linter on fixture mutants"                   bash tests/plan-lint.test.sh
```

- [ ] **Step 7: Full offline suite**

Run: `./tests/run.sh`
Expected: all green (`all tiers passed`). Note: structure/contract tiers do
not yet know about super-plan — that is Task 3; they must simply stay green.

- [ ] **Step 8: Commit**

```bash
git add plugins/orchestration/skills/super-plan/references/plan-lint.mjs tests/fixtures/plans/clean.md tests/plan-lint.test.sh tests/run.sh
git commit -m "super-plan: the plan rules ship as a linter, proven on fixture mutants"
```

---

### Task 2: drift-hook learns quoted JSON branches

**Files:**
- Modify: `plugins/orchestration/hooks/drift-check` (one sed pattern)
- Modify: `plugins/orchestration/hooks/drift-check.test.sh` (one case)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: the branch gate recognizes `"branch": "wave/x"` (quoted key and
  value, JSON style) in addition to `branch: wave/x` (YAML style). Task 3's
  plan format depends on this.

- [ ] **Step 1: Add the failing test case**

Open `plugins/orchestration/hooks/drift-check.test.sh` and find case 4
("active with a live branch and a claim in the transcript", around line 72).
Directly AFTER that case's `expect` line, add a new case that mirrors case 4
exactly — same `setup_repo`, `write_transcript "$CLAIM"`, same
`git -C "$WORK/repo" branch wave/alpha`, same expected string as case 4's
`expect` — changing ONLY the plan line and the test name:

```bash
# 4b. same as 4, but the plan declares its branch in the quoted JSON form
setup_repo; write_plan active '  "branch": "wave/alpha",'; write_transcript "$CLAIM"
git -C "$WORK/repo" branch wave/alpha
expect "quoted JSON branch is recognized" "would-call" "$(run_hook)"
```

(`would-call` is the hook's dry-run proceed outcome — the same string case 4
expects; verify it matches case 4's expect line in the file before running.)

- [ ] **Step 2: Run to verify it fails**

Run: `bash plugins/orchestration/hooks/drift-check.test.sh`
Expected: the new case FAILS with `silent: no-live-branches` (the quoted
form is invisible to the current sed, so the gate thinks no declared branch
is alive); every pre-existing case still passes.

- [ ] **Step 3: Extend the sed pattern**

In `plugins/orchestration/hooks/drift-check`, replace:

```bash
planned_branches="$(sed -n 's/^[[:space:]-]*branch:[[:space:]]*\([A-Za-z0-9._\/-]*\).*/\1/p' "$plan_file" 2>/dev/null | sort -u)"
```

with:

```bash
planned_branches="$(sed -n 's/^[[:space:]-]*"\{0,1\}branch"\{0,1\}:[[:space:]]*"\{0,1\}\([A-Za-z0-9._\/-]*\)"\{0,1\}.*/\1/p' "$plan_file" 2>/dev/null | sort -u)"
```

- [ ] **Step 4: Run the hook suite, expect green**

Run: `bash plugins/orchestration/hooks/drift-check.test.sh`
Expected: all cases pass, including 4b and every pre-existing YAML-form case.

- [ ] **Step 5: Commit**

```bash
git add plugins/orchestration/hooks/drift-check plugins/orchestration/hooks/drift-check.test.sh
git commit -m "drift-check: the branch gate reads quoted JSON branch keys too"
```

---

### Task 3: SKILL.md, attribution, contract checks, 2.1.0

**Files:**
- Create: `plugins/orchestration/skills/super-plan/SKILL.md`
- Create: `plugins/orchestration/skills/super-plan/references/LICENSE-superpowers`
- Modify: `tests/skills-contract.sh` (new section)
- Modify: `plugins/orchestration/.claude-plugin/plugin.json` (version)
- Modify: `plugins/orchestration/skills/multi-model/SKILL.md` (version only)

**Interfaces:**
- Consumes: Task 1's linter path and invocation; Task 2's quoted-branch
  support (the format section documents JSON branches).
- Produces: the skill the user invokes; the greppable phrases the contract
  checks pin: `plan-lint.mjs`, `must not share files`,
  `ONE batched AskUserQuestion`, `status transitions belong`,
  `Assumptions (would ask)`, `Jesse Vincent`.

- [ ] **Step 1: Add the failing contract checks**

In `tests/skills-contract.sh`, after the last multi-model section (the one
ending `check "branch gate reads declared branches" ...`), add:

```bash
SP=plugins/orchestration/skills/super-plan/SKILL.md

section "super-plan: planning that lands wave-ready"
check "the skill exists"                        "[ -f $SP ]"
check "the lint script ships"                   "[ -f plugins/orchestration/skills/super-plan/references/plan-lint.mjs ]"
check "lint is mandatory before the plan gate"  "grep -q 'plan-lint.mjs' $SP"
check "same-wave file overlap is forbidden"     "grep -q 'must not share files' $SP"
check "questions are batched, not dripped"      "grep -q 'ONE batched AskUserQuestion' $SP"
check "status transitions stay with execution"  "grep -q 'status transitions belong' $SP"
check "headless mode records assumptions"       "grep -q 'Assumptions (would ask)' $SP"
check "superpowers attribution survives"        "grep -q 'Jesse Vincent' $SP"
check "the MIT notice ships"                    "[ -f plugins/orchestration/skills/super-plan/references/LICENSE-superpowers ]"
```

Run `bash tests/skills-contract.sh` — only the two plan-lint.mjs file/grep-
target checks that Task 1 satisfied pass (`the lint script ships`, and
nothing else): 1 of 9 green, the other eight FAIL until Steps 2–3 create
SKILL.md and the license file.

- [ ] **Step 2: Write the license file**

`plugins/orchestration/skills/super-plan/references/LICENSE-superpowers`:

```
The planning dialogue discipline and the no-placeholders plan rigor in the
super-plan skill are adapted from "superpowers" by Jesse Vincent
(https://github.com/obra/superpowers), used under the MIT License:

MIT License

Copyright (c) 2025 Jesse Vincent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write the skill**

`plugins/orchestration/skills/super-plan/SKILL.md`:

````markdown
---
name: super-plan
description: 'Use when planning a feature, refactor or fix into wave-ready tasks for the multi-model skill — researching the codebase to decomposition depth, closing open questions (one batched round to the user for what code cannot answer), then writing a plan whose tasks carry machine-checkable contracts, grouped into waves by file-independence and validated by the shipped plan linter. Works on whatever model this session runs on; it loads the matching orchestrator profile itself. Triggers: "составь план", "спланируй фичу", "план под волны", "plan this feature", "make a wave plan", "super plan". Do NOT use for executing a plan (that is multi-model) or reviewing a diff (that is critical-review).'
metadata:
  author: https://github.com/TemMax
  version: 2.1.0
---

# Planning Waves (super-plan)

The dialogue and no-placeholders planning discipline here is adapted from
Jesse Vincent's superpowers (MIT — see `references/LICENSE-superpowers`);
the output format and every contract rule are this plugin's own.

## Step 0 — Load Your Own Orchestrator Profile (before anything else)

Your environment block states the model you are running as. Read it and load
the ONE matching profile — the same profiles the multi-model skill uses:

| Your model ID | Read this file |
|---|---|
| `claude-fable-5` | `../multi-model/references/orchestrator-fable-5.md` |
| `claude-opus-5` (any context-window suffix) | `../multi-model/references/orchestrator-opus-5.md` |
| `claude-opus-4-8` (any suffix) | `../multi-model/references/orchestrator-opus-4-8.md` |
| anything else | no profile exists — use the rules below only, and say so |

Read exactly one. Always reply to the user in the language the user writes in.

## Process

1. **Research** to decomposition depth: files, dependencies, conventions,
   test commands that actually run. For a large surface, fan out read-only
   Explore agents; synthesis and every decision stay with you — do not
   delegate decisions, executors silently fill gaps under ambiguity.
2. **Decisions.** Everything derivable from the codebase you decide and
   record. What code cannot answer — product behavior, trade-offs, scope
   cuts — goes to the user as ONE batched AskUserQuestion (up to 4 forks);
   a second batch only if the answers open new forks. Never drip questions
   one at a time, and never resolve a product fork silently.
3. **Gate 1 — design.** Present a compact summary: architecture, the wave
   sketch (which tasks, which waves, why), decisions taken, forks the user
   answered. One approval, then stop touching the design.
4. **Tasks.** Write them by multi-model's rules: closed (no "decide what's
   best"), self-contained (the executor sees nothing but its prompt), full
   code included where the solution is known. Each task carries the
   five-key contract; models and efforts come from multi-model's routing
   and effort tables, the wave's supervisor from its supervisor table
   (chosen for the strongest executor in the wave). Group into waves by
   file-independence: same-wave tasks must not share files — merge
   colliding tasks or split them across consecutive waves. Dependent
   chains are consecutive waves, never one wave.
5. **Lint.** Run the shipped linter and fix every error yourself — the
   user never edits the plan:

   ```
   node <this skill's base directory>/references/plan-lint.mjs <plan-file> --repo <repo>
   ```

   Warnings are judgment calls; errors are not negotiable. A plan that
   fails lint is not presented to the user.
6. **Gate 2 — plan.** Show the lint-clean plan file; one approval.
7. **Handoff.** "Execute with multi-model (supervised waves)." The plan
   file IS the wave-plan artifact: the json block is the runner's task
   input, verbatim. The `status:` field stays `draft` here — status
   transitions belong to execution (multi-model sets `active` at launch and
   `done` at completion), never to planning and never to the user.

## Plan Format

One file in `docs/superpowers/plans/YYYY-MM-DD-<feature>.md`, three layers:

1. **Unfenced header** at column 0, before any code fence (the drift hook
   reads it there):

   ```
   status: draft
   base: pending
   ```

2. **The machine half** — exactly one fenced block whose info string is
   `json wave-plan` (plain ```json fences inside task prose stay legal and
   are ignored by the linter):

   ```json wave-plan
   { "waves": [
     { "wave": 1,
       "supervisor": { "model": "opus", "effort": "high" },
       "tasks": [
         { "id": "http-retry",
           "branch": "wave/http-retry",
           "executor": { "model": "sonnet", "effort": "medium" },
           "ladder": ["opus"],
           "contract": {
             "files_allowed": ["src/http/**"],
             "files_forbidden": [],
             "must_run": [{ "cmd": "pytest tests/http -q", "evidence": "required" }],
             "forbidden_moves": ["weakening, deleting or skipping an existing test"],
             "report_must_answer": ["Which call sites now retry?"] } } ] }
   ] }
   ```

   Short model names only. `branch` is always `wave/<id>`. The supervisor
   sits on the wave because execution is one runner invocation per wave.

3. **The prose half** — one `## Task <id>` section per task: the
   substantive description and context, with full code where the solution
   is known. At launch, multi-model composes each runner task as the json
   entry plus its prose section, verbatim.

## Headless evaluation mode

When there is no user to answer gates (an eval harness runs you), skip both
gates and record every fork you would have asked under a section titled
`## Assumptions (would ask)` in the plan file. Deciding a product fork
silently is the failure this mode exists to measure.

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Two same-wave tasks sharing a file | Merge conflicts after isolation did its job | Merge the tasks or split the waves; lint enforces it |
| Dripping questions one at a time | The user becomes the bottleneck | ONE batched AskUserQuestion for genuine forks |
| Deciding a product fork silently | The most expensive wrong turn there is | Batch it to the user; in headless mode, record it |
| Presenting a plan that fails lint | The user debugs your format | Lint first, fix every error, then present |
| Setting `status: active` while planning | The drift hook pays for a wave that is not running | Leave `draft`; execution owns transitions |
| A task whose fix is "see the conversation" | The executor sees only its prompt | Self-contained tasks, full code where known |
````

- [ ] **Step 4: Bump versions to 2.1.0**

- `plugins/orchestration/.claude-plugin/plugin.json`: `"version": "2.0.1"` →
  `"version": "2.1.0"`.
- `plugins/orchestration/skills/multi-model/SKILL.md` frontmatter:
  `  version: 2.0.1` → `  version: 2.1.0` (no other change).

- [ ] **Step 5: Full offline suite**

Run: `./tests/run.sh`
Expected: all green — structure picks up the new skill's frontmatter and the
version agreement; all nine new contract checks pass; behaviour tiers
unchanged.

- [ ] **Step 6: Commit**

```bash
git add plugins/orchestration tests/skills-contract.sh
git commit -m "Orchestration 2.1.0: super-plan — wave-native planning with a shipped linter"
```

---

### Task 4: the planner eval tier + probe log

**Files:**
- Create: `tests/eval/super-plan.sh`
- Create: `tests/eval/super-plan-insession.md`
- Modify: `tests/README.md`

**Interfaces:**
- Consumes: Task 1's linter (`OK:`/`FAIL:` output, exit codes), Task 3's
  SKILL.md (fed verbatim to the headless model; its headless-mode section
  makes gate-skipping legitimate).
- Produces: the `--live` tier proving the planner prompt works; the probe
  log for what headless cannot cover.

- [ ] **Step 1: Write the eval tier**

`tests/eval/super-plan.sh`:

```bash
#!/usr/bin/env bash
# Tier 3 — does the PLANNER prompt produce a lint-clean, wave-grouped plan?
# Two fixtures with expectations fixed before any run:
#   P1 — a request that TEMPTS two tasks into the same file (the №1 defect
#        observed in real sessions); expectation: the plan passes lint, i.e.
#        the planner merged the colliding work or split the waves.
#   P2 — a request carrying a genuine product fork; expectation: the fork is
#        NAMED under "## Assumptions (would ask)", not silently resolved.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib.sh

MODEL="${EVAL_MODEL:-claude-haiku-4-5-20251001}"
SKILL=plugins/orchestration/skills/super-plan/SKILL.md
LINT=plugins/orchestration/skills/super-plan/references/plan-lint.mjs
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

R="$W/repo"; mkdir -p "$R/src" "$R/tests" "$R/docs"
cat > "$R/src/app.py" <<'PY'
def greet(name):
    return "hello " + name
PY
cat > "$R/tests/test_app.py" <<'PY'
import unittest

from src.app import greet


class TestGreet(unittest.TestCase):
    def test_greet(self):
        self.assertEqual(greet("ann"), "hello ann")
PY
touch "$R/src/__init__.py" "$R/tests/__init__.py"
printf '# demo\n\ngreet(name) says hello.\n' > "$R/docs/README.md"

plan() {  # $1 = feature request  → prints the model's plan file content
  timeout 600 claude -p "$(cat "$SKILL")

EVAL MODE: you are running headless under an evaluation harness — apply the
skill's headless evaluation mode. The repository to plan against is at $R
(explore it with your tools). Write NOTHING to disk. Print ONLY the complete
plan file content (markdown, all three layers), no prose before or after it.
Do not wrap the output in an outer code fence.

Feature request:
$1" --permission-mode bypassPermissions --model "$MODEL" </dev/null 2>/dev/null
}

section "P1 — overlap temptation (both changes land in src/app.py)"
plan "Two improvements to greet(): (a) raise ValueError when name is empty; (b) add an optional excited=True flag that appends an exclamation mark. Also update docs/README.md to describe both." > "$W/p1.md"
out="$(node "$LINT" "$W/p1.md" --repo "$R" 2>&1)"; rc=$?
expect "P1 plan passes lint (no same-wave overlap survived)" "0" "$rc"
contains "P1 lint summary" "OK:" "$out"
n="$(grep -c '"id":' "$W/p1.md" || true)"
check "P1 has at least 2 tasks (got $n)" "[ \"$n\" -ge 2 ]"
contains "P1 contracts reference the fixture's real test command" "unittest" "$(cat "$W/p1.md")"

section "P2 — a product fork must surface, not be silently resolved"
plan "Add a delete_user(name) function to src/app.py with tests. Decide nothing about edge-case behaviour on your own." > "$W/p2.md"
contains "P2 names its assumptions" "Assumptions (would ask)" "$(cat "$W/p2.md")"
out="$(node "$LINT" "$W/p2.md" --repo "$R" 2>&1)"; rc=$?
expect "P2 plan still passes lint" "0" "$rc"

summary
```

Make it executable: `chmod +x tests/eval/super-plan.sh`

- [ ] **Step 2: Run the eval once (live model calls, a few minutes)**

Run: `bash tests/eval/super-plan.sh`

Judge honestly. A failing assertion means either the planner prompt or the
eval's own plumbing needs work — read the saved `$W` output before deciding
which (add `echo "$W"` temporarily if needed; mktemp cleanup runs on exit).
Fix what the evidence indicates: prompt-side fixes go into SKILL.md's rules
(re-run `bash tests/skills-contract.sh` after), plumbing fixes into this
script. Record what failed and what was changed in the report file. If Haiku
proves too weak to follow the full skill (plausible — the skill is long),
re-run once with `EVAL_MODEL=claude-sonnet-5`; if Sonnet passes and Haiku
does not, encode that floor honestly: change the default `MODEL=` line to
`claude-sonnet-5` with a comment naming the measured reason, and note it in
`tests/README.md` (Step 4).

- [ ] **Step 3: Write the probe log**

`tests/eval/super-plan-insession.md`:

```markdown
# In-session probe of super-plan

The eval tier proves the planner prompt headless: lint-clean output, overlap
resistance, forks surfaced as assumptions. What it cannot exercise — the two
approval gates and the batched AskUserQuestion round — happens only with a
real user in a real session, and is recorded here, honestly, when it happens.

Procedure: plan the next real feature with `super-plan`; record the date,
the lint result on first presentation, how many question batches were
needed, and how the plan fared in execution (did the waves run without
contract amendments?).

## Probe log

| Date | Feature | Lint on first presentation | Question batches | Execution outcome |
|---|---|---|---|---|
```

- [ ] **Step 4: Update tests/README.md**

After the `**wave-runner (simulated)**` paragraph, add:

```markdown
**plan linter** — `tests/plan-lint.test.sh` mutates the canonical clean plan
fixture one defect at a time and asserts the shipped `plan-lint.mjs` names
each error class; warnings are asserted non-fatal. Requires `node`.
```

In the evaluation paragraph area (after the sentence about the drift check
answering NOTHING), append to the same paragraph:

```markdown
The super-plan tier asks the inverse planning questions: a request that
tempts same-wave file overlap must still produce a lint-clean plan, and a
request hiding a product fork must surface it under "Assumptions (would
ask)" rather than resolve it silently.
```

- [ ] **Step 5: Full suite both ways**

Run: `./tests/run.sh` — all offline tiers green.
Run: `./tests/run.sh --live` — supervisor, drift, wave and super-plan tiers;
report each honestly.

- [ ] **Step 6: Commit**

```bash
git add tests/eval/super-plan.sh tests/eval/super-plan-insession.md tests/README.md
git commit -m "super-plan eval tier: overlap temptation and silent-fork traps, plus the probe log"
```

---

## Self-review notes

- Spec coverage: §1 skill structure → Task 3; §2 format (header/json/prose,
  wave-level supervisor, drift-hook compatibility) → Tasks 2–3; §3 linter →
  Task 1; §4 code tests → Tasks 1–3; §5 skill eval + probe log → Task 4.
- The linter's overlap approximation (literal prefix) is documented in both
  the spec and the script comment; the eval does not depend on glob
  subtleties beyond it.
- Task 2's expected-string indirection ("mirror case 4") is deliberate: the
  hook's dry-run proceed string lives in that file, and copying it here
  risks drift; the implementer reads it in place.
- `contains` in P1 greps `unittest` because the fixture's only real test
  command is `python3 -m unittest …`; a planner that invents `pytest` fails
  the check — that is intended (research quality, not just format).
