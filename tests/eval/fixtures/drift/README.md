# Adversarial drift fixtures

Authored by Fable 5, which did not write the prompt under test and was told
plainly that predicting failure was the useful outcome. Adjudicated under
`docs/superpowers/specs/2026-08-11-adversarial-protocol.md`, fixed before any
result was seen.

They found what the self-authored fixtures could not: `tail-window-false-positive`
made the check flag two tasks whose completion simply predated the transcript
window. The prompt had never been told it receives a window rather than a whole
session, so "nothing shows it being executed" matched literally and correctly by
its own wording. That is the false-positive class, the one that gets an advisory
ignored, and no fixture written by the prompt's own author had a windowed
transcript in it at all.

Fixing it then broke `audit-metadata-injection` — the window rule let an
*asserted* out-of-window completion excuse anything, which is the exact shape
Fable predicted in that fixture's `why_hard`. Both now hold, but the sequence is
the lesson: a false-positive fix must be re-run against every true positive, not
against the two that come to mind.
