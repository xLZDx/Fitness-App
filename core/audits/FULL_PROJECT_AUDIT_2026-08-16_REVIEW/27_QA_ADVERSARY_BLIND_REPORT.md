# 27 - Blinded adversary, stage A

Run with the repository and the invariants, and **explicitly denied** access to
`core/audits/FULL_PROJECT_AUDIT_2026-08-16/` and `core/DECISION_LOG.md`. It disclosed one incidental
exposure itself: `asset_equipment_repository.dart:71` and `exercises_quarantine.json` narrate an
audit finding as shipped code and data. That disclosure is exactly the behaviour the blinding was
meant to produce.

## The divergence that matters

**The blinded reviewer did not independently arrive at the first audit's headline BLOCKER.**

Both readers measured the same data and agree on every number: 1,527 of 1,887 rows tagged (80.9%),
360 untagged, nine distinct tags - `shoulder` 489, `hip` 404, `elbow` 371, `knee` 362, `lower_back`
313, `upper_back` 265, `ankle` 229, `wrist` 190, `neck` 117 - covering every one of the nine
`InjuryRegion` values. Independently recomputed again for this artefact: identical.

They part on what it means. The first audit read the untagged 360 as a fail-open hole and called it a
BLOCKER. The blinded reviewer, seeing 80.9% coverage across every injury region, listed the filter
under **"areas where I found no material issue"** and put the real risk elsewhere: *"I cannot verify
that any individual tag set is right, nor that the 360 untagged rows are genuinely safe for
everyone"* - and cited a constant the first audit never surfaced,
`safety_coverage_providers.dart:121`, `const bool kSafetyTagsClinicallyReviewed = false`.

Neither reader can settle it, because the tie-break is clinical: are the 360 untagged rows in fact
harmless for an injured user, or are they untagged because nobody looked? That is a question for a
clinician reviewing a stratified sample, not for either of us.

## Where the blinded reviewer went further

It also **downgraded the programme-enrolment blocker to HIGH** on evidence the first audit had but
did not weigh: sessions are re-screened at render (`session_screening_providers.dart:77`,
`workouts_page.dart:1178`), so the rows are struck. It then made that downgrade conditional and named
the test that decides it: *"If that chain does not fire on device, F1 becomes a BLOCKER."* That is
better reasoning than the first audit's flat BLOCKER, and better than an unqualified downgrade.

## What it found that the first audit did not

Six items, in `18_NEW_FINDINGS.csv`. The sharpest is **N01**, verified at source for this artefact:
a `ProgrammeNotViable` safety refusal is caught by a generic error handler and shown to the user as
*"The service is temporarily unavailable. Check your connection and try again."* with a **Retry**
button (`workouts_page.dart:1281-1291`, `app_en.arb:2118`). The app's one honest refusal reaches the
user as a network glitch, with an invitation to retry it forever.

## What it independently confirmed

PAR-Q+ genuinely fail-closed; no cross-user access in the rules; every callable deriving uid from
`request.auth`; Stripe webhook signature verification; account deletion enumerating subscriptions
from Stripe rather than a cached id; no health data in any of the three prompt builders; the Russian
catalogue being a text-only overlay that cannot re-tag an exercise; the quarantine applying at the
single load path.

Two independent readers agreeing on those, from different starting points, is much stronger evidence
than the first audit alone.
