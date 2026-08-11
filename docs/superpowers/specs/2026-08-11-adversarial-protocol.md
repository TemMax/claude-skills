# Adversarial fixtures — adjudication protocol, fixed before the results arrive

Date: 2026-08-11
Committed before any fixture or verdict was seen.

## Why the fixtures come from elsewhere

Every evaluation fixture in this repository was written by the same session that
wrote the prompts under test. That is a structural limit, not a gap to be closed
by writing more of them: an author cannot fixture their own blind spot. The three
serious defects found on 2026-08-11 all came from outside that imagination — a
hash tool absent on another platform, a status key inside a documentation fence,
a wave-specific gate left in a generalised path.

So the adversarial fixtures are authored by Fable 5, which did not write the
prompts and whose card documents no self-preference bias as a judge (dossier,
pp. 202–203). Each adversary is told plainly that it owes the prompt nothing and
that predicting failure is the useful outcome.

## The bias this creates on my side

The adversary declares both the fixture and the verdict it believes correct. When
a run disagrees with that declaration, someone must decide who was wrong — and
that someone is the session that wrote the prompt. Opus 5's self-preference bias
as a judge is **unmeasured** (dossier: no equivalent of Opus 4.8's zero-bias
result), so I get no presumption of neutrality here. The temptation is obvious:
call the adversary's expectation mistaken and the prompt stays clean.

## Rules of adjudication

1. **A disagreement counts as a finding against our prompt by default.** The
   burden is on the prompt, not on the fixture.
2. **An adversary's expectation may be rejected only by quoting the line in our
   prompt that explicitly prescribes the other behaviour.** "That reading is more
   sensible" is not grounds. If the prompt does not say it, the prompt does not
   do it.
3. **Genuinely ambiguous fixtures go to an open-questions list, not into the
   suite.** An ambiguous test is worse than a missing one: it converts a coin
   flip into a green tick.
4. **A fixture that fails is recorded whether or not it is fixed.** Deciding a
   defect is not worth fixing is legitimate; quietly dropping the fixture that
   found it is not.
5. **No fixture is softened to make a prompt pass.** If the fixture is wrong,
   it is replaced or discarded with the reason written down — never trimmed
   until it goes green.

## What a good outcome looks like

Not "all adversarial fixtures pass". If four fixtures designed by an adversary to
defeat these prompts all pass on the first attempt, the most likely explanation
is that the adversary was too gentle, and the second most likely is that I framed
its task too narrowly. Finding nothing is a result about the experiment before it
is a result about the prompts.
