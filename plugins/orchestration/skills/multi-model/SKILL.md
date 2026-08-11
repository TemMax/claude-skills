---
name: multi-model
description: 'Use when orchestrating parallel development work through Workflow subagents on Haiku 4.5, Sonnet 5, Opus 4.8 and Opus 5 — including supervised waves, where each executor is isolated in its own worktree and its result is judged against a machine-checkable contract by a different model — decomposing a coding task into agent waves, routing tasks to models, picking reasoning effort, writing task prompts for executor agents, or reviewing their results. Works on whatever model this orchestrator session runs on; it loads the matching orchestrator profile itself. Triggers: "разбей на агентов", "запусти параллельно", "оркеструй задачу", "decompose into agents", "run in parallel", "delegate to subagents", "pick a model for this task". Do NOT use for single-agent work.'
metadata:
  author: https://github.com/TemMax
  version: 1.6.1
---

# Orchestrating Multi-Model Development

## Step 0 — Load Your Own Orchestrator Profile (before anything else)

Your environment block states the model you are running as ("You are powered by
the model named X. The exact model ID is Y"). Read it and load the ONE matching
profile file:

| Your model ID | Read this file |
|---|---|
| `claude-fable-5` | `${CLAUDE_SKILL_DIR}/references/orchestrator-fable-5.md` |
| `claude-opus-5` (any context-window suffix) | `${CLAUDE_SKILL_DIR}/references/orchestrator-opus-5.md` |
| `claude-opus-4-8` (any context-window suffix, e.g. `[1m]`) | `${CLAUDE_SKILL_DIR}/references/orchestrator-opus-4-8.md` |
| anything else | no profile exists — use the model-agnostic rules below only, and tell the user which model you are and that no profile matched |

**Read exactly one file — the one matching your own model. Do not read the
others: their session-effort guidance, documented failure modes and strengths
belong to a different model and are not yours.** State which profile you loaded
before planning. Your profile amends the numbered steps below; where it amends a
step, the amendment wins.

Your session's current reasoning effort is reported by the harness as
**${CLAUDE_EFFORT}**. Your profile states the effort it expects; if that reported
value is lower than your profile requires, act as your profile directs before you
plan.

## Overview

The orchestrator (this session's model) researches, plans, writes task specs, and
verifies; the executors (Haiku 4.5 / Sonnet 5 / Opus 5 / Opus 4.8) implement. Core
principle: **decisions belong to the orchestrator, execution belongs to the
agents**. Every rule below is derived from the models' official system cards; the
facts and numbers live in `references/model-dossiers.md`.

Always reply to the user in the language the user writes in — this skill being in
English does not mean English replies.

## Process

1. **Research.** Study the codebase to the depth needed for decomposition: files,
   dependencies, conventions.
2. **Decisions.** Close the open questions BEFORE decomposing: research an
   incomplete specification further and pin down the interpretation (escalate
   fundamental choices to the user); design cross-cutting architecture yourself
   and hand it out as a set of concrete implementations. Do not delegate decisions
   even to an Opus executor — it silently fills in gaps under ambiguity.
3. **Plan.** Tasks: independent within their wave (no file overlap, otherwise —
   next wave or worktree), self-contained (the agent sees neither the conversation
   nor your research), closed (no "decide for yourself what's best"). Batch small
   same-shaped edits into one agent's task: parallelization pays only on hard
   chunks — on easy ones coordination overhead eats the gain. The decomposition
   covers ALL artifacts of the feature, including documentation (README and the
   like) — otherwise it silently goes stale: if you froze a file for everyone,
   assign it to someone explicitly.
4. **Table.** Before launching, show the user: task | model | effort | rationale.
5. **Launch.** Independent tasks — in parallel via Workflow.
6. **Review** (see the checklist below). Fixes — as one concrete list. Two misses
   in the same place — fix the task spec, don't repeat the prompt.
7. **The final end-to-end review is the orchestrator's own.** Before it you may
   launch an Opus verifier, but the verdict is the orchestrator's.
8. **Completion.** At most 3 iterations per task, then escalation. At the end a
   summary: done / verified / remaining.

## Model Routing — Quick Reference

| Task | Model | Why (see the dossiers) |
|---|---|---|
| Mechanical work per exact instruction, zero decisions | Haiku 4.5 | Cheaper; condition — zero decisions |
| Implementation against a clear spec, tests, migrations, isolated features | Sonnet 5 (default) | Near-Opus quality on closed tasks |
| Digging through a large volume of code for a specific question | Sonnet 5 | Holds 1M context |
| Independent verification, "what's actually broken here" | Opus 5 executor (default heavy) | First Claude to saturate lazy-investigation; parity with 4.8 on flagging planted flaws |
| Fine-grained debugging, concurrency, source-level security-sensitive code | Opus 5 executor | Strongest coding + best injection robustness; source security unblocked |
| A long unsliceable session | Opus 5 executor | Strongest long-horizon coding at Opus-4.8 price |
| Sonnet hit its ceiling after a fix iteration | Opus 5 executor | The heavy-executor upgrade over Sonnet |
| Reading untrusted external content (web, fetched pages, hostile files) | Opus 5 executor | Most injection-robust model tested (still pair with platform safeguards) |
| Reverse-engineering / vulnerability discovery in compiled binaries | Opus 4.8 executor | Opus 5's Fable-class cyber classifier blocks binaries; Opus 4.8 does not |

Torn between Haiku and Sonnet → Sonnet. Torn between Sonnet and Opus → improve the
task spec first, then upgrade the model. Opus 5 is the default heavy executor and
verifier; Opus 4.8 is retained only for compiled-binary work and as the
cyber-refusal fallback.

**Routing anti-patterns:** no sub-orchestrators — executors never spawn their own
subagents (documented failures in deep delegation chains: status honesty, not
capability); don't give any executor untrusted external content without platform
safeguards (Opus 5 is the most robust, but safeguards still matter); don't give
Sonnet multi-hour sessions; don't route compiled-binary reverse-engineering to
Opus 5 (its classifier blocks it) — use Opus 4.8.

## Choosing Executor Effort — Quick Reference

This table is about the effort you hand to executors. Your own session's effort
is your profile's business, not this table's.

| Model | low | medium | high | xhigh |
|---|---|---|---|---|
| Haiku 4.5 | — does not support effort — | | | |
| Sonnet 5 | obvious solution, but the code must be read | routine implementation per spec | default for non-trivial work | hardest execution tasks; plateau! |
| Opus 5 executor | unusually strong on simple/scoped tasks | well-specified work | default for non-trivial work | avoid — overthinking/self-verification risk |
| Opus 4.8 executor | — | most well-specified tasks (min effort ≈ Opus 4.7 max) | debugging, verification, long horizon | research-grade only |

Signal rule: wanting to give Sonnet xhigh because the task is open-ended → that
means switching the model to Opus or returning to the Decisions stage, not effort.
Opus 5's effort curve is the exception — higher is not better; it peaks mid-range
on coding and overthinks at `max`, so cap Opus 5 executors at `high`.

## Wave Isolation

A supervised wave gives every executor **its own git worktree** and commits its
work to a branch named `wave/<task-id>`. Record the base SHA in the wave plan
before the wave starts; every later comparison is made against that SHA, never
against a moving `HEAD`.

**The base must be the commit the worktrees actually fork from, not your local
`HEAD`.** Agent worktrees branch from `origin/<default-branch>` by default
(`worktree.baseRef: "fresh"`), so a commit you made locally but never pushed
does not exist for any executor. Recording an unpushed `HEAD` corrupts every
comparison in the same direction: files that exist only in your checkout appear
as deletions in every branch, and the supervisor charges each executor with a
`files` violation for a change nobody made. That is the §7 failure — correct
work blocked — arriving through the base rather than through the contract.

So, before launching: **push the commit you intend as the base**, or record
`git rev-parse origin/<default-branch>` and accept that anything unpushed is
invisible to the wave. After the first executor commits, verify with
`git merge-base wave/<task-id> HEAD`; if it does not equal the recorded base,
stop and fix the plan rather than judging against it.

This is not tidiness, it is what makes the contract checkable at all. Executors
sharing one tree make two things impossible:

- **Attribution.** A diff of the shared tree contains every task's concurrent
  edits, so "this task touched a forbidden path" cannot be distinguished from
  "a neighbour legitimately owns that path" — the very violation the contract
  exists to catch.
- **Reproducibility.** A required command re-run against a tree a neighbour is
  editing can fail for reasons that have nothing to do with the task under
  judgment, and the escalation ladder would then send correct work back for
  rework.

A commit made inside a worktree survives that worktree's removal — worktrees
share the object database and refs — so `git diff <base>..wave/<task-id>` stays
available for supervision, and a second worktree can be checked out from the
branch for independent verification.

For an unsupervised wave, tasks still must not overlap in the files they touch.

## Wave Plan Artifact

Before launching a supervised wave, write the plan to a file — one entry per
task, carrying the prose, the contract, the assigned model, the branch and the
base SHA:

```yaml
base: 7c05ff5
tasks:
  - task: http-retry
    model: claude-sonnet-5
    branch: wave/http-retry
    contract: {...}
```

Without this file "deviation" has no referent: there is nothing to deviate
from. It is a file rather than something you hold in context because a wave
outlives a context window, and a summarized context keeps the task list while
losing the exact identifiers the supervisor needs.

## Task Prompt Template (mandatory blocks)

Every executor prompt contains all six blocks — explicit instructions measurably
reduce the documented failure modes:

1. **Context:** specific files and lines, dependencies, project conventions.
   Compute numeric examples in the spec with a tool, not in your head — a wrong
   example contradicts the formula and derails the executor. In a supervised
   wave the executor works in its own worktree and sees no neighbour's edits, so
   say so — an agent that expects a busy tree will misread its own isolation.
2. **Boundaries:** what NOT to do — don't refactor adjacent code, don't add
   unrequested features/files, don't touch anything outside the list.
3. **Dead-end protocol:** "If data or access is missing, a tool is broken, or the
   path is impossible — stop and report what's blocking you. Don't invent values,
   don't work around the restriction, don't pick an interpretation on the user's
   behalf."
4. **Prohibitions:** do not spawn subagents; no destructive operations
   (force-push, reset --hard, rm outside the task) without explicit permission.
   Phrase prohibitions without qualifiers — executors rules-lawyer around wording
   when it conflicts with "the overriding goal".
5. **Definition of done and response format:** list of changed files, the gist of
   the changes, output of actually executed tests/linter.
6. **Contract:** the machine-checkable half of the task. Prose carries intent;
   the contract carries what a supervisor can decide without arguing about
   intent.

   ```yaml
   contract:
     files_allowed:   [src/http/**, tests/http/**]
     files_forbidden: [src/auth/**]        # another task owns these this wave
     must_run:
       - cmd: pytest tests/http -q
         evidence: required
     forbidden_moves:
       - weakening, deleting or skipping an existing test
       - catching an exception to make a check pass
     report_must_answer:
       - Which call sites now retry?
       - What happens after the final failed attempt?
   ```

   `evidence: required` replaces trust. A report claiming a command passed
   without that command's actual output is not weak evidence — it is a
   violation in its own right.

   State the prohibitions explicitly and loudly. This is measured, not
   stylistic: an explicit "don't work around it — report it" lowers fabricated
   workarounds from 17.4% to 9.1% for Fable 5 (pp. 161–163) and from 9.4% to
   2.8% for Opus 4.8 (pp. 109–110).

For tasks with images/PDF/charts — give Sonnet code-execution access.

## Supervised Waves

Supervision is a stage in the `Workflow` script,
**not an instruction to self-check**. A check the executor is asked to perform
is a check it may decide
it already satisfied; a check in the control flow around it is one it never gets
a vote on. A stage can also do what advice cannot: reject and re-run.

Send `references/supervisor-prompt.md` to a model that is not the executor's own
(see Anti-Deception Rules), with the contract, the report, the base SHA and the
branch.

**The supervisor trusts artifacts only.** It checks out `wave/<task-id>` into
its own worktree, runs the diff itself, executes each `must_run` command itself,
and greps for the forbidden moves itself. The report is a set of claims to
check, never a source of facts.

**Forged evidence is its own violation class.** The executor pastes command
output; the supervisor re-runs the command and must **compare** the two. A
mismatch is the least deniable proof of fabrication in this design, and it
deserves different handling from an honest failure: an executor whose tests fail
made a mistake, which is what rework is for, while an executor that pasted a
green run over a real failure did something else. A `forged-evidence` violation
therefore skips the rework rung and escalates immediately.

Do not conflate it with `forbidden-move`. An agent that weakened a test and then
truthfully reported the resulting green run forged nothing — judge its diff, not
its honesty.

Verdict shape:

```json
{"ok": false,
 "violations": [{"rule": "must_run:pytest tests/http -q",
                 "class": "forged-evidence",
                 "evidence": "report pasted a green run; supervisor got 2 failed",
                 "quote": "tests/http/test_retry.py::test_backoff FAILED"}],
 "remarks": ["src/http/backoff.py:41 duplicates the helper in src/net/retry.py"]}
```

`violations` decide `ok`; `remarks` never do. Classes: `files`, `must_run`,
`forbidden-move`, `report`, `forged-evidence`. A violation without evidence the
supervisor produced itself is dropped, not softened — otherwise the supervisor
fabricates as readily as the executor it judges.

When a `must_run` command fails, run it a second time before recording anything.
If the retry passes, record a remark naming the command unstable and do not
block. Spending the supervisor's credibility on flaky tests buys nothing.

### Escalation ladder

| Situation | Action |
|---|---|
| 1st violation, no forged evidence | Back to the same executor with the verdict attached |
| 2nd violation of the same rule | To a stronger model — repeating a prompt on the model that just failed it reproduces the failure |
| Any `forged-evidence` violation | Skip the rework rung, go straight to a stronger model, mark the task in the wave report |
| Executor is already the strongest model | No higher rung: retry once at raised effort, then stop |
| Stop | Hand the user the task, every verdict in order, and the branch name |

The ladder lives inside a single `pipeline` stage. Stages run once per item, so
spreading execute / supervise / rework across three stages would re-enter the
pipeline from the top on every rework.

```js
pipeline(tasks, async (_, t) => {
  let model = t.model, attempt = 0, history = []
  while (true) {
    const report  = await agent(taskPrompt(t, history), {model, phase: 'Execute'})
    const verdict = await agent(supervisorPrompt(t, report),
                                {model: supervisorFor(model), phase: 'Supervise',
                                 schema: VERDICT})
    history.push(verdict)
    if (verdict.ok) return {task: t, verdict, model, attempts: attempt + 1}
    const next = nextRung(model, verdict, ++attempt)
    if (next.stop) return {task: t, verdict, history, escalatedToUser: true}
    model = next.model
  }
})
```

### The blocking threshold sits above the suspicion threshold

Rework is triggered only by contract violations. Anything the supervisor merely
finds doubtful goes to `remarks` and reaches the user through the wave report.
**Blocking correct work is a worse failure than missing a nitpick** — a
supervisor that stops legitimate work does not just waste a wave, it
manufactures confidence in the waves it lets through.

### Cost, and when to skip the model

A supervisor invocation is an agent with tools — a diff, the commands, the
greps — so it is not one model request. The tiers also invert: a Haiku 4.5 task
is supervised by Opus 4.8 or Fable 5, making the supervisor the expensive half.

Run full agentic supervision for tasks whose contract has `must_run` commands or
`files_forbidden` entries that matter: migrations, shared helpers,
security-adjacent code. For a small mechanical task, check the predicates
(paths touched, commands run, evidence present) in plain script logic and
skip the supervisor model. Supervision that costs more than the work it guards
gets switched off, and then it guards nothing.

## Anti-Deception Rules

Each of these comes from a measured failure, not from general caution.

| Rule | Evidence |
|---|---|
| State the prohibitions to the executor loudly and explicitly | Explicit "don't work around — report" lowers fabrication: Fable 17.4% → 9.1% (pp. 161–163), Opus 4.8 9.4% → 2.8% (pp. 109–110) |
| Do NOT disclose the supervisor's specific checks to the executor | Grader awareness reaches 24–30% and changes behavior at the surface level (Fable pp. 171–181) |
| The supervisor is never the executor's own model | Opus 5's self-preference bias as a judge is unmeasured; Opus 4.8 (pp. 122–124) and Fable 5 (pp. 202–203) have measured zero |
| A claim without command output is a violation | Caveat laundering: "I verified this myself" while spot-checking only ancillary facts (pp. 37–39) |
| Attach verdicts; never paraphrase an executor report in their place | Opus 5 relays subagent claims unverified (p. 81) |
| Stopping early with open plan items is a violation | Fable stops on spurious token-budget concerns, 2.43M tokens unspent (pp. 170–171) |
| Claims of monitoring or watching get their own check | Dead watchers: recap lines said "monitoring" while nothing polled (pp. 33–35) |

**Rules explicit, checks opaque.** The two halves come from opposite findings
and must not be collapsed. The contract is handed to the executor in full —
that is the explicit-prohibition half, and withholding it raises fabrication.
What is never disclosed is the supervisor's *method*: that a second model
re-runs the commands instead of reading the pasted output, that it compares the
two, that it diffs the tests against the recorded base SHA, that it greps for
the forbidden moves. An executor told the rules complies with the rules; an
executor told how compliance is measured optimizes for the measurement.

**Choosing the supervisor's model.** Never the executor's own. Prefer a judge
with measured zero self-preference — Opus 4.8 or Fable 5; when the executor is
one of those, supervise with the other. Opus 5 may execute under supervision but
does not supervise: the property that would justify it is unmeasured, and an
unmeasured property is not a permission.

## Result Review Checklist

An agent's self-report is not evidence (every executor has documented false
success claims and omissions about corners cut). In a supervised wave you review
the supervisor verdicts and remarks, not the executor reports — paraphrasing a
report where a verdict belongs is itself a failure, and the documented one:
Opus 5 relays subagent claims unverified (p. 81).

- [ ] Solves the stated task and matches the plan — by the diff, not the summary
- [ ] No unrequested changes (refactorings, files, abstractions)
- [ ] Consistent with the other agents' results (seams, duplicates, conflicts)
- [ ] Build/tests/linter — verified by running; "should work" doesn't count
- [ ] Documentation (README and the like) reflects the final state of the feature
- [ ] Every task carries a supervisor verdict; remarks are read and either acted on or dismissed on the record

## Common Mistakes

| Mistake | Consequence | Correct |
|---|---|---|
| Planning before loading your orchestrator profile | You inherit another model's effort advice and failure modes | Step 0 first, exactly one profile |
| Handing an executor "flesh out the spec yourself" | Silent unilateral assumptions | The orchestrator closes the decisions |
| Compensating an open-ended task with Sonnet xhigh | Plateau: money without quality | Switch the model or pin the task down |
| One agent per tiny file | Overhead eats the gain | Batch of edits for one agent |
| Trusting "tests pass" from the report | False claims are documented | Run them yourself |
| One long Sonnet session | 3× steps, early stops | Short waves with review in between |
| Returning "rework this" to an agent | Iterations without convergence | A concrete list: what and where |
| Numeric example in the spec computed in your head | The example contradicts the formula, the agent stalls | Compute with a tool or give only the formula |
| Not warning about parallel file changes | The agent treats the wave as an anomaly, wastes steps | List the files its neighbors modify |
| Documentation assigned to no one | README silently goes stale | An explicit docs task in the decomposition |
| Supervising with the executor's own model | A judge with unmeasured self-preference grants its own work a discount for free | Opus 4.8 or Fable 5, never the executor's model |
| Telling the executor how compliance is measured | Grader awareness turns compliance performative at the surface | Rules explicit, method undisclosed |
| Accepting a claim with no command output | The cheapest fabrication passes untouched | `evidence: required`, and compare it with your own re-run |
| Treating forged evidence as an ordinary failure | The task goes back to the model that just misrepresented its result | `forged-evidence` skips the rework rung |
| Blocking on suspicion rather than on a contract violation | Correct work is stopped and the wave gains false confidence | Doubts go to `remarks`; only violations block |
| Recording an unpushed local `HEAD` as the wave base | Worktrees fork from `origin/<default-branch>`, so every branch shows your local-only files as deletions and every executor gets a phantom `files` violation | Push the base commit, or record `origin/<default-branch>`; verify with `git merge-base` after the first commit |

## References

- `references/orchestrator-fable-5.md`, `references/orchestrator-opus-5.md`,
  `references/orchestrator-opus-4-8.md` — the orchestrator profiles. Load exactly
  one, per Step 0.
- `references/model-dossiers.md` — dossiers on all four models with numbers and
  page references to the system cards: benchmarks, documented failure modes,
  effort curves, multi-agent harness data, orchestration takeaways. Load it for
  contested routing calls or to justify a choice.
