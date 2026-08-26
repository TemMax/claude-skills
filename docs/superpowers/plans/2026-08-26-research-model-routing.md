status: draft
base: pending

# Research Model Routing Implementation Plan

**Goal:** Research agents (read-only fan-out behind planning, decomposition and
reviews) get an explicit model routing table, so they stop inheriting the
session's model — on a Fable 5 seat that inheritance silently bills file
listings at the most expensive rate available.

**Why now:** Observed in a real ship run on Fable 5: super-plan's Research step
says "fan out read-only Explore agents" with no model named; the Agent tool
inherits the parent session's model when none is given; the Fable 5 orchestrator
profile amplifies with "spend the budget on research depth". Every research
subagent ran on Fable 5.

**Design (approved by the user in-session, 2026-08-26):**
1. A "Research Routing — Quick Reference" table in multi-model's SKILL.md:
   Haiku 4.5 for mechanical pattern search, Sonnet 5 (low/medium) for closed
   enumeration, Opus 5 (medium/high) for open research sub-questions,
   Opus 4.8 for reports trusted without re-verification or near-1M-context
   reasoning. Grounded in the dossiers (Opus 5 thorough-investigator p. 110 +
   recall-as-truth p. 87; Opus 4.8 DRACO/GraphWalks/honesty; Sonnet 5
   ProgramBench + fabricate-under-missing-info p. 71; Haiku mechanical only).
2. Mandatory research-prompt lines: evidence as `file:line`, `not found` is a
   valid answer, answering from memory is forbidden.
3. super-plan's Research step routes its fan-out through that table.
4. orchestrator-fable-5.md amendment: research depth is bought with routed
   cheaper agents, never with inherited Fable tokens.
5. Contract-test pins for the new load-bearing lines.
6. Version bump orchestration 2.2.0 → 2.3.0 (plugin.json + all three skill
   frontmatters — the structure tier requires agreement).

**Wave shape:** Wave 1 — three file-independent prose tasks (multi-model
SKILL.md; super-plan SKILL.md; orchestrator-fable-5.md). Wave 2 — one task
adding the contract pins and performing the whole version bump (it touches
files owned by wave-1 tasks, hence a separate wave; the pins can only go green
once wave 1 is merged). Version lines are deliberately NOT touched in wave 1 so
its worktrees keep the structure tier (version-agreement check) green.

```json wave-plan
{ "waves": [
  { "wave": 1,
    "supervisor": { "model": "opus", "effort": "high" },
    "tasks": [
      { "id": "mm-research-table",
        "branch": "wave/mm-research-table",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": ["plugins/orchestration/skills/multi-model/SKILL.md"],
          "files_forbidden": [],
          "must_run": [
            { "cmd": "bash tests/run.sh", "evidence": "required" },
            { "cmd": "grep -n 'Research Routing' plugins/orchestration/skills/multi-model/SKILL.md", "evidence": "required" }
          ],
          "forbidden_moves": [
            "changing the metadata.version line",
            "removing or weakening any existing section, table row or citation",
            "editing any file other than the one allowed"
          ],
          "report_must_answer": [
            "Where exactly does the new Research Routing section sit (between which two existing headings)?",
            "Did the full offline suite pass, with output shown?"
          ] } },
      { "id": "sp-research-step",
        "branch": "wave/sp-research-step",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": ["plugins/orchestration/skills/super-plan/SKILL.md"],
          "files_forbidden": [],
          "must_run": [
            { "cmd": "bash tests/run.sh", "evidence": "required" },
            { "cmd": "grep -n 'Research Routing' plugins/orchestration/skills/super-plan/SKILL.md", "evidence": "required" }
          ],
          "forbidden_moves": [
            "changing the metadata.version line",
            "removing or weakening any other Process step or section",
            "editing any file other than the one allowed"
          ],
          "report_must_answer": [
            "What does step 1 (Research) say now, quoted verbatim?",
            "Did the full offline suite pass, with output shown?"
          ] } },
      { "id": "fable-research-amendment",
        "branch": "wave/fable-research-amendment",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": ["plugins/orchestration/skills/multi-model/references/orchestrator-fable-5.md"],
          "files_forbidden": [],
          "must_run": [
            { "cmd": "bash tests/run.sh", "evidence": "required" },
            { "cmd": "grep -n 'Research Routing' plugins/orchestration/skills/multi-model/references/orchestrator-fable-5.md", "evidence": "required" }
          ],
          "forbidden_moves": [
            "removing or weakening any existing amendment, quirk or table row",
            "editing any file other than the one allowed"
          ],
          "report_must_answer": [
            "Which sections gained content (Amendments and Common Mistakes), quoted verbatim?",
            "Did the full offline suite pass, with output shown?"
          ] } } ] },
  { "wave": 2,
    "supervisor": { "model": "opus", "effort": "high" },
    "tasks": [
      { "id": "routing-pins-and-version",
        "branch": "wave/routing-pins-and-version",
        "executor": { "model": "sonnet", "effort": "medium" },
        "ladder": ["opus"],
        "contract": {
          "files_allowed": [
            "tests/skills-contract.sh",
            "plugins/orchestration/.claude-plugin/plugin.json",
            "plugins/orchestration/skills/multi-model/SKILL.md",
            "plugins/orchestration/skills/super-plan/SKILL.md",
            "plugins/orchestration/skills/ship/SKILL.md"
          ],
          "files_forbidden": [],
          "must_run": [
            { "cmd": "bash tests/run.sh", "evidence": "required" }
          ],
          "forbidden_moves": [
            "changing anything in the three SKILL.md files other than their metadata.version line",
            "removing or weakening any existing check in tests/skills-contract.sh",
            "changing anything in plugin.json other than the version field"
          ],
          "report_must_answer": [
            "Which new checks were added and does each one's grep pattern match the merged skill text?",
            "Do all four version fields now read 2.3.0?",
            "Did the full offline suite pass, with output shown?"
          ] } } ] }
] }
```

## Task mm-research-table

Add a "Research Routing — Quick Reference" section to
`plugins/orchestration/skills/multi-model/SKILL.md`, and point the Process
Research step at it. Do NOT touch the frontmatter `version:` line (a later
task owns the version bump).

**Edit 1 — Process step 1.** The file currently contains (under `## Process`):

```
1. **Research.** Study the codebase to the depth needed for decomposition: files,
   dependencies, conventions.
```

Replace those two lines with:

```
1. **Research.** Study the codebase to the depth needed for decomposition: files,
   dependencies, conventions. Any read-only fan-out goes through the Research
   Routing table below — research agents never inherit your model.
```

**Edit 2 — the new section.** The file currently has a section
`## Model Routing — Quick Reference` that ends with this paragraph, followed
directly by the `## Choosing Executor Effort — Quick Reference` heading:

```
**Routing anti-patterns:** no sub-orchestrators — executors never spawn their own
subagents (documented failures in deep delegation chains: status honesty, not
capability); don't give any executor untrusted external content without platform
safeguards (Opus 5 is the most robust, but safeguards still matter); don't give
Sonnet multi-hour sessions; don't route compiled-binary reverse-engineering to
Opus 5 (its classifier blocks it) — use Opus 4.8.
```

Insert the following new section between that paragraph and the
`## Choosing Executor Effort — Quick Reference` heading (blank line before and
after), verbatim:

```
## Research Routing — Quick Reference

The Model Routing table above routes work that changes things. Read-only
research agents — the fan-out behind planning, decomposition and reviews — are
routed here instead. An unrouted research agent inherits the session's model:
on a Fable 5 seat that silently bills file listings at the most expensive rate
available. Never spawn a research agent without naming its model.

| Research kind | Model | Why (see the dossiers) |
|---|---|---|
| Mechanical pattern search: occurrences of a known string or shape | Haiku 4.5 | Zero decisions; simple file searches are its documented lane |
| Closed enumeration: files, call sites, conventions, test commands that actually run | Sonnet 5, low/medium | Strong at digging through large code volumes (ProgramBench 76–86%, 1M context) and cheap; a closed question neutralizes its documented fabricate-when-information-is-missing failure (Sonnet 5 card, p. 71) |
| Open research sub-question: how a subsystem works, what depends on what, why it is shaped this way | Opus 5, medium/high | First Claude to saturate the lazy-investigation eval — a thorough investigator (p. 110); cap at high, its effort curve inverts |
| A report the orchestrator will trust without re-verification, or reasoning over a near-1M-token surface | Opus 4.8 | Honesty ceiling (0.00 misreported rate) and the best long-context reasoning in the comparison set (GraphWalks 1M 68.1); DRACO rises monotonically through max |

Torn between Haiku and Sonnet → Sonnet, as always. The session's own model is
never the answer here: research is gathering, not deciding — the decisions stay
in the orchestrator seat, and the seat is where expensive reasoning is worth
its price.

**Mandatory lines in every research agent's prompt** (the research counterpart
of the executor task template):

- every claim carries evidence as `file:line`, or as a command plus its output;
- `not found` is a valid and expected answer — never fill a gap with a guess
  (Sonnet 5 fabricates precisely when information is missing, p. 71);
- read the sources: answering from memory about library or system behavior is
  forbidden (Opus 5's documented recall-as-truth failure, p. 87).
```

**Verification.** Run `bash tests/run.sh` from the repository root — every
offline tier must be green (the new section adds citations, it must not touch
any pinned line). Show the suite output and
`grep -n 'Research Routing' plugins/orchestration/skills/multi-model/SKILL.md`
in the report. Commit with message
`multi-model: research routing table — gathering is never billed at the seat's price`.

## Task sp-research-step

Rewrite step 1 of the Process in
`plugins/orchestration/skills/super-plan/SKILL.md` to route research fan-out
through multi-model's new Research Routing table. Do NOT touch the frontmatter
`version:` line (a later task owns the version bump).

The file currently contains (under `## Process`):

```
1. **Research** to decomposition depth: files, dependencies, conventions,
   test commands that actually run. For a large surface, fan out read-only
   Explore agents; synthesis and every decision stay with you — do not
   delegate decisions, executors silently fill gaps under ambiguity.
```

Replace those four lines with:

```
1. **Research** to decomposition depth: files, dependencies, conventions,
   test commands that actually run. For a large surface, fan out read-only
   research agents routed by multi-model's Research Routing table
   (`../multi-model/SKILL.md`) — name a model on every spawn (an agent
   without one inherits the session's model, and a Fable 5 seat then pays
   Fable prices for file listings), and give each agent the table's
   mandatory research-prompt lines. Synthesis and every decision stay with
   you — do not delegate decisions, executors silently fill gaps under
   ambiguity.
```

**Verification.** Run `bash tests/run.sh` — all offline tiers green (the
existing super-plan contract pins grep for lines this edit must preserve:
`ONE batched AskUserQuestion`, `Assumptions (would ask)`, etc.). Show the
suite output and
`grep -n 'Research Routing' plugins/orchestration/skills/super-plan/SKILL.md`
in the report. Commit with message
`super-plan: research fan-out routes through multi-model's table`.

## Task fable-research-amendment

Amend `plugins/orchestration/skills/multi-model/references/orchestrator-fable-5.md`
so a Fable 5 orchestrator never buys "research depth" with its own inherited
tokens.

**Edit 1.** The file's `## Amendments to the Process` section currently opens
with:

```
## Amendments to the Process

- **Step 2 (Decisions).** Your safeguard classifiers block reverse-engineering of
```

Insert a new first bullet directly after the `## Amendments to the Process`
heading (keeping the existing bullets intact below it):

```
- **Step 1 (Research).** "Spend the budget on research depth" means the number
  and quality of routed research agents, never depth on your own tokens: an
  agent spawned without a named model inherits Fable 5. Route every research
  spawn through multi-model's Research Routing table (SKILL.md); your seat's
  budget goes to synthesis and decisions, not to gathering.
```

**Edit 2.** The `## Common Mistakes (Fable-specific)` table currently ends with:

```
| Trusting "time to wrap up" | Documented false stopping signal; work left open | Re-check the plan for what is actually closed |
```

Add one row after it:

```
| Spawning research agents without naming a model | They inherit Fable 5 — the priciest tokens buy file listings | Route every research spawn via multi-model's Research Routing table |
```

**Verification.** Run `bash tests/run.sh` — all offline tiers green. Show the
suite output and
`grep -n 'Research Routing' plugins/orchestration/skills/multi-model/references/orchestrator-fable-5.md`
in the report. Commit with message
`fable profile: research depth is bought with routed agents, not inherited tokens`.

## Task routing-pins-and-version

Two mechanical changes, exact content below. Runs after wave 1 is merged, so
the greps have text to match.

**Change 1 — contract pins.** In `tests/skills-contract.sh`, the file
currently contains:

```
section "multi-model: the lifecycle belongs to the orchestrator, not the user"
```

Insert the following block immediately BEFORE that line (blank line after the
new block):

```
section "multi-model: research fan-out is routed, never inherited"
check "the research routing table exists"      "grep -q 'Research Routing' $MM"
check "inheritance is named as the bug"        "grep -q 'never spawn a research agent without naming its model' $MM"
check "not-found is a valid answer"            "grep -q 'is a valid and expected answer' $MM"
check "answering from memory is forbidden"     "grep -q 'answering from memory' $MM"
check "super-plan routes research through it"  "grep -q 'Research Routing' $SP"
check "the fable profile routes research off-seat" \
  "grep -q 'Research Routing' plugins/orchestration/skills/multi-model/references/orchestrator-fable-5.md"
```

Note: `$SP` is defined further down in the file (after the multi-model
sections). Move the existing line `SP=plugins/orchestration/skills/super-plan/SKILL.md`
up so it sits together with the `CR=` and `MM=` definitions near the top of
the file (delete it from its old position; keep the `SH=` definition where it
is).

The `never spawn a research agent...` pattern matches the sentence "Never
spawn a research agent without naming its model." case-sensitively via its
lowercase-safe substring — use exactly the pattern given above (it matches
because grep finds the substring starting at "spawn"; the full pattern
includes "never" which appears capitalized in the skill). To be safe, verify
each pattern with a live grep before committing; if a pattern does not match
the merged text, adjust the PATTERN to the actual skill wording (never the
skill wording to the pattern), keeping the check's intent.

**Change 2 — version bump 2.2.0 → 2.3.0.** Exactly four one-line edits:

- `plugins/orchestration/.claude-plugin/plugin.json`: `"version": "2.2.0",` →
  `"version": "2.3.0",`
- `plugins/orchestration/skills/multi-model/SKILL.md` frontmatter:
  `  version: 2.2.0` → `  version: 2.3.0`
- `plugins/orchestration/skills/super-plan/SKILL.md` frontmatter: same edit
- `plugins/orchestration/skills/ship/SKILL.md` frontmatter: same edit

**Verification.** Run `bash tests/run.sh` — every tier green, including the
six new checks and the version-agreement check in the structure tier. Show
the full suite output in the report. Commit with message
`contract pins for research routing; orchestration 2.3.0`.
