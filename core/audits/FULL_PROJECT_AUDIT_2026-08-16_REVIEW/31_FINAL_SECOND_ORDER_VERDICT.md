# 31 - Second-order verdict

## On the first audit: SUBSTANTIALLY SOUND, WITH ONE OVERSTATEMENT

Every BLOCKER and CRITICAL reproduces at source. All 23 numeric claims reproduce exactly. No
re-tested finding collapsed into a false positive. One HIGH was overstated and is downgraded; one
MEDIUM has an unprovable denominator.

## On the product: NOT_RELEASE_READY - upheld, independently

The verdict is upheld, and it does not rest on the overstated finding. It rests on three defects that
were re-read at source in this review:

| Original blocker | Reproduced | Severity correct | Current status |
|---|---|---|---|
| Injury filter fails open on 360 untagged rows | **YES**, verbatim at `exercise_filter.dart:38` | **CONTESTED - see below** | Unchanged at HEAD `1453236` |
| No pregnancy path | **YES** - neither enum carries a value; only comments explaining the deliberate non-storage | **YES**, with a caveat below | Unchanged |
| Spec-less programme enrolment bypasses the whole-person gate | **YES** - the scheduler has no `SafetyContext` parameter at all | **YES** | Unchanged |

**Caveat on the pregnancy blocker.** The severity is right but the framing needs care: the product
made a deliberate, recorded decision not to hold a pregnancy status
(`cycle_phase.dart:56-64`), and that decision is defensible and should survive any fix. What is
missing is not storage - it is a refusal path. An ephemeral, non-persisted question routing to the
existing `wholePersonBlocks` mechanism satisfies both. Anyone reading the blocker as "start storing
pregnancy status" would be implementing the wrong fix.

## Per area

| Area | Status | Change from the first audit |
|---|---|---|
| Catalogue structural integrity | PASS | Independently reproduced, 23 of 23 |
| Health safety | **FAIL** | Upheld |
| Programmes | **FAIL** | Upheld |
| Personalisation | PASS_WITH_FINDINGS | **Raised from FAIL** - a working level signal exists in `fitness_model.dart` |
| AI Coach | PASS_WITH_FINDINGS | Upheld |
| Firestore security | PASS_WITH_FINDINGS | Upheld, not re-tested here |
| CI | PASS_WITH_FINDINGS | Upheld, not re-tested here |
| Documentation | PASS_WITH_FINDINGS | Upheld |
| Reproducibility | **PASS** | Every metric recomputed from the shipped assets |

## What this review could not do

The MEDIUM/LOW/INFO tail (16 findings) was not re-tested. The blinded adversary had not reported when
this verdict was written. Firestore rules, CI and the test suite were not independently re-attacked.
Everything the first audit marked UNAVAILABLE - clip-to-exercise correspondence, technique soundness,
real-gym recognition, background timer behaviour - remains UNAVAILABLE for the same reasons, and none
of it became testable by writing a second audit.

## Status

Second-order audit only. No source file changed. Remediation not started; awaiting `REMEDIATION-GO`.


## Correction: BLOCKER 1's severity is contested, not upheld

An earlier draft of this verdict said "BLOCKER upheld" for all three. That was written before the
blinded adversary reported, and it is wrong to leave standing.

The **mechanism** is REPRODUCED_VERIFIED twice over: `exercise_filter.dart:38` returns false on an
empty tag list, and 360 rows carry none. Nobody disputes that.

The **severity** is a 1-1 split between two independent readers. The blinded adversary measured the
same 1,527/1,887 (80.9%) coverage across all nine injury regions, listed the filter under "no
material issue found", and located the real risk one level up: whether the tags are clinically
correct at all, citing `safety_coverage_providers.dart:121` -
`const bool kSafetyTagsClinicallyReviewed = false` - a constant the first audit never surfaced.

Neither reader can break the tie, because it is a clinical question: are the 360 untagged rows
harmless for an injured user, or untagged because nobody looked? **Required next step: a clinician
adjudicates a stratified sample of the 360.** Until then the honest status is CONTESTED, and the
remediation task should be written as "make the unscreenable state visible" rather than "fix the
filter".

## Correction: BLOCKER 3's severity should be conditional

The blinded reviewer downgraded it to HIGH on evidence the first audit had and did not weigh -
sessions are re-screened at render (`session_screening_providers.dart:77`, `workouts_page.dart:1178`),
so rows are struck - and made the downgrade conditional on a device test it named. That is better
than either a flat BLOCKER or a flat downgrade. Adopted: **HIGH, escalating to BLOCKER if the
render-time chain does not fire on device.**

## Six findings the first audit missed

In `18_NEW_FINDINGS.csv`. The sharpest, verified at source: a safety refusal is rendered to the user
as *"The service is temporarily unavailable"* with a **Retry** button
(`workouts_page.dart:1281-1291`). The app's one honest refusal reaches the user as a network glitch.
