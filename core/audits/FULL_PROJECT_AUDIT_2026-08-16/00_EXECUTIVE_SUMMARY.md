# 00 - Executive summary

**Full forensic audit of SPTR, 2026-08-16, against `formcoach/gates-a-c` @ `f965302`.**

27 findings: **3 BLOCKER, 3 CRITICAL, 7 HIGH, 10 MEDIUM, 1 LOW, 3 INFO.**
Verdict: **NOT_RELEASE_READY.**

## The three that stop a release

1. **The injury filter fails open.** `exercise_filter.dart:38` returns "not contraindicated" for any
   exercise carrying no tags. 360 of 1,887 rows carry none, so **19.1% of the catalogue cannot be
   withheld from anyone, by any injury, on any surface** - while the interface says the list was
   screened. The movement-restriction loop at `eligibility.dart:282` fails the same way.

2. **No pregnancy path exists.** Not asked, not inferred, not filtered, not warned. Two tests use
   "pregnancy" specifically as an *invalid* value. Not holding the status is a deliberate and
   defensible privacy decision (`cycle_phase.dart:56-64`); declining to generate a plan is a
   different decision that was never taken.

3. **The questionnaire-built programme skips the safety gate and is an alphabetical filler.**
   `programme_providers.dart:199-206` calls a scheduler that has no `SafetyContext` parameter at all,
   so a user refused training by PAR-Q+ can still enrol and receive 24 sessions. And `_fillDay` walks
   consecutive indices of an id-sorted pool, so a 45-minute session is four alphabetically adjacent
   rows - day 0 is two yoga poses, a sit-up and a jump, for any goal.

Two independent reviewers with non-overlapping briefs found (3) separately. That is the strongest
signal in this audit.

## What is genuinely well built

- **No health data reaches any model.** All three prompt builders carry subject name, language and
  image bytes only. The refusal is written down, reasoned, and told to the user. This is the best
  decision in the product.
- The person-level PAR-Q+ gate is fail-closed, refuses rather than returning an empty list, and names
  the question responsible with a route back.
- The dangerous cycle-phase logic - a 1.10 intensity factor and "PR attempts welcome" - **was already
  removed by this project** before the audit arrived.
- CI genuinely tests Firestore rules against an emulator and runs an account-deletion e2e with
  multi-account isolation. No job uses `continue-on-error`.
- The ML model is real: trained 2026-07-29, documented per-class metrics, and a data leak the
  pipeline caught and fixed. The scope document claiming it is "not trained and not bundled" is
  contradicted by the artefact.

## The catalogue, measured rather than quoted

1,887 rows. Zero duplicate ids. Full EN/RU parity. `summary == steps[0]` holds in both languages on
every row. Zero broken equipment references. Zero missing posters.

And: 503 rows with no `equipmentId`, 360 with no contraindication tag, 1,484 with no `purpose`, and
`difficulty` is **1,877 `beginner` out of 1,887** - which makes every level-based filter and ranking
arithmetically inert.

## What this audit could not do

Whether a clip depicts the exercise attached to it, whether the technique text is coaching-sound,
whether recognition works in a real gym, and how the timer and player behave in the background are
all UNAVAILABLE to a static audit. They are the core of the product. `32_UNVERIFIED_CLAIMS.md` lists
17 such areas with what would close each.

## This audit corrected itself twice

A file-count measure reported 15 dead providers; the correct answer is 7. Two body-metric fields were
wrongly classed as unused. Both are recorded in `31_CONTRADICTIONS.md` rather than quietly fixed,
because a grep treated as a fact is exactly the failure this audit exists to catch elsewhere.
