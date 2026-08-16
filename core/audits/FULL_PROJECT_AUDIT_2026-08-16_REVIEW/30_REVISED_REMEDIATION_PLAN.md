# 30 - Revised remediation plan

Built from the eight root causes in `16_ROOT_CAUSE_MAP.csv`, not from the 33 findings. Five gates
close twenty-one findings between them.

**Not started.** Awaiting `REMEDIATION-GO`. Each gate is independently verifiable and independently
revertible; take them one at a time, in this order.

---

## G-A (P0) - The user must see the refusal the app already produces

**Root cause RC3.** Smallest gate, highest value, touches no safety logic - only how existing
decisions surface. Do this first precisely because it cannot break the eligibility layer.

| Step | File | Change |
|---|---|---|
| A1 | `workouts_page.dart:1281-1291` | Catch `ProgrammeNotViable` before the generic handler; render `EligibilityNotice` with the review-profile action. **No retry action.** |
| A2 | `par_q.dart:123-126`, `app_*.arb` | Branch refusal copy on `kBlockingQuestions`; chest pain gets urgent-evaluation wording |
| A3 | `app_en.arb:212`, `app_ru.arb` | Remove the "keep your plan safe" subtitle above the free-text health fields; it contradicts `healthStepIntro` two steps later |
| A4 | `safety_disclosure.dart` | Render `safetyFilterCoverage` from `catalogSafetyCoverageProvider` - written, translated, computed, currently shown nowhere |
| A5 | 6 surfaces | Render `SafetyDisclosure` wherever an exercise list is served, not only on the equipment detail page |

**Closes:** N01, F017, F018, F019, F020.
**Acceptance:** blocked screening + tap `strength_base` renders `EligibilityNotice`, no retry action,
no "service unavailable" string. The tagged/total figure appears on every list surface. Mutation:
restore the generic handler, the test goes red.
**Risk:** low. No decision path changes.

---

## G-B (P0) - Route every exercise surface through the layer that already exists

**Root cause RC1.** One pattern, six call sites. The eligibility layer is correct; these surfaces
simply do not call it.

| Step | File | Change |
|---|---|---|
| B1 | `programme_providers.dart:199-206` | Read `safetyContextProvider` **above** the spec branch; refuse on `!allowsAnyTraining`; pass `eligibleExercises(safeCatalogue, safety)` into the fallback |
| B2 | `workout_player_page.dart:798-800` | Picker reads `eligibleExercises(catalog, safety)`, not `safeCatalogProvider`. This one is terminal - the tap logs the exercise, so there is no downstream re-screen to save it |
| B3 | `equipment_detail_page.dart:31,322` | Add the `allowsAnyTraining` gate the Train tab already uses |
| B4 | `equipment_detail_page.dart:110-118`, `scanner_page.dart:1422` | Hide the AI coach entry when `!allowsAnyTraining`, matching `exercise_page.dart:83-88` |
| B5 | `workouts_page.dart:164-200` | Route the non-"For you" chips through `eligibleExercises` |
| B6 | `equipment_providers.dart:481-482` | Widen the `ai::` exclusion to `injuries.isNotEmpty \|\| flags.restrictions.isNotEmpty` |

**Closes:** F015 (partly), F020, F023, N02, N04.
**Acceptance:** one test per surface asserting a restriction-only profile is served no row carrying
the restricted region tag. B2 additionally asserts the logged session contains no such row.
**Risk:** medium - this is the safety layer's call sites. Each step lands separately with its own
mutation.

---

## G-C (P0) - Stop rendering invented exercises

**Root cause RC2.**

Suppress `uses[]` in `machine_describer.dart:165-177` unless every line matches the catalogue or an
equipment alias; otherwise render name and summary only. The codebase already reached this
conclusion for AI-generated exercises (`equipment_providers.dart:481-482`, *"They cannot be screened
at all"*) and never applied it here.

**Closes:** F016. **Acceptance:** a stub returning an invented movement renders no `uses` block.
**Risk:** low.

---

## G-D (P0) - Close the client-writable server state

**Root cause RC6.** Three clauses in `firestore.rules:12-17`: exclude `usage`, exclude `receipts`,
and deny a `health` key on `profile/main`. **Closes:** F005, F006, N03.
**Acceptance:** three rules-emulator tests, each asserting denial. The CI job already exists.
**Risk:** low, and the blast radius is a rules deploy - verify against the emulator before shipping.

---

## G-E (P1) - Give the default programme a spec and delete the fallback

**Root cause RC4.** Add a `ProgrammeSpec` for `from_answers` (and for `shred_endurance` and
`shoulders_arms`) so `programmeSpecFor` never returns null, then delete `buildProgrammeSchedule` and
`_fillDay`. This removes the alphabetical filler, the three-of-four day repetition and the last
unscreened enrolment path in one change rather than patching each.

**Closes:** F015 (fully), F021, F022. **Acceptance:** enrol with goal=strength and assert
`movementRoleOf` covers at least four primary strength roles across a week; assert pairwise session
overlap of at most one exercise.
**Risk:** medium-high - it is a real generator change and needs the strength reviewer, not only a
test.

---

## BLOCKED - these need you, not engineering

**D1 - the untagged 360.** The severity is contested 1-1 between two independent readers. The
mechanism is not in doubt; whether it is a blocker is a clinical question. **Ask a clinician to
adjudicate a stratified sample of the 360 untagged rows.** Meanwhile G-A/A4 makes the gap visible,
which is the honest interim regardless of the answer. Do **not** flip `exercise_filter.dart:38` to
fail-closed before that answer: withholding 19.1% of the catalogue from every injured user is a
large product change made on a contested premise.

**D2 - pregnancy.** The mechanism is clear and small: one self-reported question persisting a
boolean, routed to `wholePersonBlocks`, holding no medical category - which respects the recorded
decision at `cycle_phase.dart:56-64`. What needs you is the wording and whether the product is
willing to refuse this user at all. **Anyone reading the blocker as "store pregnancy status" will
implement the wrong fix.**

**D3 - "scan any gym machine".** 10 of 69 machines are recognisable. Either the claim changes or the
label set does.

**D4 - the collected-and-unused data (RC5).** 14 questionnaire fields and 12 health fields reach no
engine, the sensitive ones unencrypted in SharedPreferences. Consuming them is feature work;
deleting them is a product decision. Deleting is cheaper and reduces liability.

---

## Recommended order

**G-A, then G-D, then G-C, then G-B, then G-E.**

G-A first because it is the only gate that improves user safety without touching a decision path -
today the app makes correct refusals the user never sees. G-D next because it is three lines behind
an existing CI job. G-C is self-contained. G-B is the largest correctness win and the highest risk,
so it goes after the cheap wins are banked. G-E last because it is a generator rewrite needing domain
review.

D1 and D2 should be asked **now**, in parallel with G-A, because both have lead times measured in
days and neither blocks any gate above.
