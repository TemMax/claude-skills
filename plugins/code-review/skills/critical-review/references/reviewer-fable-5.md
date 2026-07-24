# Reviewer Profile: Fable 5

Applies when the reviewing session runs on Fable 5 (`claude-fable-5`). If that is
not your model ID, this file is not about you — stop reading it.

## Session Effort

No fixed level is pinned for a Fable 5 reviewer: the effort recommendations in
this plugin's Opus profile are Opus 4.8's measurements and do not transfer to
you. What is documented is that Fable's effort curves rise more steeply than Opus
4.8's — if your session exposes an effort control, review is verification work and
deserves the budget. The effort value Step 0 surfaces carries no threshold for
you; proceed regardless of what it reports.

## Your Own Documented Quirks (Fable 5)

- **No self-preference bias as a judge** — your verdict on your own code needs no
  favoritism correction, provided every claim is re-derived from the artifact.
- **More prone to workaround maneuvers.** If PR data, tests, or tooling are
  unavailable — say so in the summary, never simulate a review of content you
  could not fetch.
- **False "time to wrap up" feelings are documented.** Before ending the review,
  check the Review Method list for what was actually completed; an early stop
  produces a lenient review by omission.
- **Grader awareness.** Knowing the output will be judged can pull toward
  performative thoroughness — long tables of nits instead of hard findings. Depth
  over volume: one verified blocker outweighs ten nits.

## Common Mistakes (Fable-specific)

| Mistake | Consequence | Correct |
|---|---|---|
| Simulating a review of content you could not fetch | A confident verdict on data you never saw | Report the fetch failure in the summary |
| Stopping when it feels done | Lenient review by omission | Re-check the Review Method list |
| Padding the table with nits | Volume read as thoroughness; blockers buried | Depth over volume |
