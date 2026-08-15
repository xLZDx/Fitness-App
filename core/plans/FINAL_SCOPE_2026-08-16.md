# Final scope — everything not done, or not finished

**Measured 2026-08-16 against `formcoach/gates-a-c` @ `36602a3`.**

Every figure below was produced by running over `mobile/assets/data/*.json` and reading code on that
date, not carried forward from an earlier document. Where a line comes from a plan file that was NOT
re-verified, it says so — three neighbouring items in that same file turned out to be stale, so the
distinction matters.

This file exists because a scope that lives only in a chat transcript is the same persistence risk
this project already realised once (see `core/DECISION_LOG.md`, the 2026-08-04 loss of 131
unpersisted findings).

---

## 0. Already done — the plans are stale

Verified against code before being excluded from the scope. These items in
`core/plans/PLAN_BUGS_2026-08-13.md` are closed and the file still lists them as open:

| Item | Evidence |
|---|---|
| **P1** compileSdk 35→36 | `mobile/android/app/build.gradle:87` — `compileSdk = 36` |
| **P2** debug and release share an `applicationId` | `:163` — `applicationIdSuffix ".debug"` |
| **A1** experimental labelling of scanner / Form Coach / posture | `ExperimentalBanner` wired on all three: `form_check_page.dart:368,395`, `posture_page.dart:146`, `scanner_page.dart:944` |
| **H6** no in-app progress-photo deletion | `progress_photos_page.dart:537` — `onLongPress` → `runPhotoDeleteFlow` |
| **H1** day title in history | closed by `8f26797` |
| **P3** `upper_back` tag | 265 rows tagged |

---

## 1. Exercise catalogue — the largest block

### 1.1 Text: what exists and what does not

| Field | EN | RU |
|---|---|---|
| `title` / `summary` / `steps` | **1887 / 1887** | **1887 / 1887** |
| **`purpose` ("why this matters") absent** | **1484 of 1887 (78.6%)** | same 1484 |
| `visual_status = NOT_VERIFIED` — nobody compared artwork against text | **1484** | — |
| rows with 3 steps instead of a breakdown | 124 | — |
| rows with a single step | 1 (`ea_major_groups_muscle_body`) | — |

403 rows are the authored, proofread part of the catalogue. **The other 1484 are raw vendor rows**
where nobody wrote a "why" and nobody checked that the picture matches the words.

### 1.2 Review coverage — the number that matters most

- **1368 of 1887 cards (72.5%) were never flagged by a detector and were never read card by card.**
  How many carry a wrong description is **unknown**, and no defensible estimate exists.
- **1128 of those 1368** additionally have no `purpose`.
- Of the 519 flagged cards, **320 were dismissed at gates A/B/C and never re-verified**. Those
  dismissals are precisely the classifications proven unreliable: the SPINE_CUE pass produced
  **29 false positives out of 29**.

Extrapolating the Gate E hit rate onto the unread 1368 is unsound in both directions. The 519 were
selected *because* detectors matched them, so they are not a random sample; and those detectors have
a demonstrated ~50% false-positive rate.

### 1.3 Structural signals that a description does not belong to its card

Measured 2026-08-16. These need no judgement call — they are facts about the data.

| Signal | Cards |
|---|---|
| Byte-identical `steps` shared by different exercises (EN) | **83** across 38 clusters |
| Same, RU | **71** across 33 clusters |
| Identical `summary` shared by different exercises (EN) | **355** across 140 clusters — **224 of them never flagged by any detector** |
| `RU summary != steps[0]`, while EN holds the invariant on all 1887 | **127** |
| `equipmentLabel` is the literal string `"None"` while `equipmentId` names a real machine | **78** |

**Caveat without which the first row misleads.** Identical steps do not prove a wrong description.
The largest cluster is `Barbell Deadlift` / `(front POV)` / `(side POV)` / `360 Degrees` — one
exercise shot from four angles, where the text is correct and the **cards** are redundant. Read the
83 as "redundant or wrong", never as "wrong".

The 127 RU rows are a different matter: EN holds `summary == steps[0]` on 1887 of 1887 and RU breaks
it on 127. That is a defect, not an ambiguity.

### 1.4 Known-wrong cards still open

| id | Defect |
|---|---|
| `ea_major_groups_muscle_body` | a single step, a generic standing cue, no real exercise behind it. Quarantine-or-delete decision |
| `ea_cable_wrist_extension` | asserts a flexor/extensor strength parity that does not exist, plus an unhedged causal medical claim |
| `ea_puppy_pose` | "the lower back is not involved" is backwards for this pose |
| `ea_sissy_squat_bodyweight` | implies any knee adapts eventually |
| `ea_criss_cross_bow_tie_pose` | the RU title describes a seated crossed-**legs** hip opener; the exercise is a shoulder stretch with the arms crossed behind the back, and the card's own RU steps say so |

### 1.5 Catalogue metadata

| Field | Empty / broken | Consequence |
|---|---|---|
| `primaryMuscles` | **451** | the volume-deficit ranker cannot see these rows as a priority |
| `muscles` | **182** | reach no muscle filter; sorted last by the planner |
| `equipmentId` | **503** | never filtered against the user's available equipment |
| `contraindications` | **360** | filtered out by no injury — the filter keeps any row with no tags |
| `difficulty` | **1877 of 1887 = `beginner`**, 8 advanced, 2 intermediate | **the gradation does not exist as data.** Any filter or selection by level is fiction |
| `movementRole` (derived) | **26 unclassified** (98.6% coverage) | those rows fill no programme slot |

### 1.6 Video and posters

| Fact | Count |
|---|---|
| Poster files present on disk | **2539, 0 missing** |
| Rows with a **men-only** clip | **1112 (58.9%)** |
| Rows with a **girl-only** clip | **123** |
| Rows with both | **652** |

A product gap, not a technical one. A woman sees a male model on 1112 of 1887 cards.
`ExerciseItem.bodyForGender` honestly falls back to whichever clip exists — the code does not lie,
the content is not there.

### 1.7 Equipment

- 69 machines in the registry, **4 with no exercise linked at all**: `glute_kickback_machine`,
  `recumbent_bike`, `rotary_torso_machine`, `t_bar_row`. Those machine pages are empty.
- 78 rows say "no equipment" on the card for an exercise that names a machine (see 1.3).

### 1.8 Persistence risk, inherited

The three CSVs every audit figure rests on (`SPTR_FULL_CATALOG_1887_*`) live **outside the
repository**, in the operator's `Downloads`. Same class of risk as the 2026-08-04 loss.

---

## 2. Safety and claims — the remainder of the 2026-08-15/16 mission

| # | Item | Status |
|---|---|---|
| **S1** | `mobile/lib/features/insurance/` — dead code designing the sharing of adherence-derived eligibility with a carrier, recorded in Gate J as prohibited by a 15 April 2026 Play policy | **Closed 2026-08-16.** Deleted under an explicit operator GO after the shell safety gate blocked the first attempt |
| **S2** | **R5** — the device-local claim is absolute in the policy, and `firestore_profile_repository.dart:74` still parses a populated legacy `health` block | **UNKNOWN.** `legal_text.py`'s own evidence header records that H1b cleared the 14 documents that had one and a read-only query returned zero. Re-running it needs production Firestore |
| **S3** | **R8 / R9 / R11** from Gate J | **UNKNOWN.** Deferred without recording what they are. Needs the original review artefact |
| **S4** | The 2026-08-16 review round left 9 test files and 4 programme claims unexamined | not cleared, not examined |
| **S5** | Deleting `recovery_block.dart` and retracting the body-comp paywall line removed what `NEXT_TICKETS.md` calls the MK.6/MK.7 "foundations" | deliberate — there was no functionality behind either — but picking those up now starts from zero |

---

## 3. Bugs and open plan items

### Verified against code on 2026-08-16

| # | Item | Evidence |
|---|---|---|
| **B1** | **H4** — `ExerciseThumb` carries no `Semantics`/`semanticLabel`. Exercise tiles on the programme card are nameless to a screen reader | no `Semantics` anywhere in `exercise_thumb.dart` |
| **B2** | `purpose` is rendered on the exercise card only (`exercise_reference.dart:892`). Neither the programme card nor the player shows it | single UI reader |
| **B3** | **There is no iOS scaffold at all** — `mobile/ios/` does not exist | `ls` |

### From plan files, NOT re-verified on device

| # | Item | Source |
|---|---|---|
| **B4** | **B4** silhouette — third attempt; "closed only after the operator looks at it" | `PLAN_BUGS_2026-08-13.md` |
| **B5** | **B6** video speed control — code done, unverified on device | same |
| **B6** | **H2** template ranking ignores equipment and injuries (they affect selection INSIDE a programme, not card order) | same |
| **B7** | **H5** 89 rows with a contradictory muscle group. My check "primary ∉ muscles" returned 0, so the original measurement used a different definition — **not reproduced** | same |
| **B8** | **R11f-2** photo export conflicts with the recorded decision that photos never leave the phone — **decision not taken** | `PLAN_REDESIGN_REMAINDER_2026-08-12.md` |
| **B9** | **R11f-3** photo reminder — notification-scheduler territory | same |
| **B10** | **F3** screen-by-screen parity check against the Figma prototype | same |
| **B11** | **A2** empty `notificationsRule` on budget `projects/988522745882`; **A3** photo capture order (needs a phone); **A4** live Stripe API version (key blocked by the environment classifier); **A5** Paywall HELD on pricing | `PLAN_BUGS_2026-08-13.md` block A |

---

## 4. Platform and release

| # | Item |
|---|---|
| **P1** | **iOS does not exist.** No scaffold, no `Info.plist`, no entitlements. `mobile/IOS_PERMISSIONS_TODO.md` lists what is needed |
| **P2** | The release build has never been run per the docs (`NEXT_TICKETS.md`: "release build untested"). The debug APK is 380 MB |
| **P3** | Wear OS smoke test never run on an emulator |
| **P4** | 5 Stripe price IDs not created — annual / family / lifetime SKUs do not work |
| **P5** | `equipment_v1.tflite` not trained and not bundled — recognition runs cloud-only |
| **P6** | Stripe Connect return URL is the placeholder `fitnessapp.example.com/coach/onboarding-done` |
| **P7** | Cloud Functions with no tests: `stripeWebhook`, `createPortalSession`, `optInDonorWall`, `optOutDonorWall`, `startCoachOnboarding`, `reportEquipment` |
| **P8** | `AesPhotoCipher` is implemented and tested; the photos page still uses the test-only XOR cipher |

---

## 5. Tier MK — foundations laid, none integrated

| MK | Exists | Missing | Estimate |
|---|---|---|---|
| MK.1 Live Form Coach with voice | voice grammar and form check, separately | a state machine listening to voice while the classifiers run | ~5d |
| MK.2 Goal photo → programme | the `GoalPhotoRequest` envelope | the Cloud Function calling Claude Vision | ~5d + ~$2/mo |
| MK.3 Cycle-aware | **shipped in Gate O** | an onboarding opt-in question | ~1d |
| MK.4 Insurance attestations | nothing — the model layer was deleted 2026-08-16 | picking this up means designing a prohibited data flow from scratch; the Play policy is the reason, not the effort | — |
| MK.5 White-label SDK | config + JWT envelope | the SDK package and partner SSO function | ~60d + a hire |
| MK.6 Body comp | the Navy formula | the photo-silhouette estimator; the paywall line is retracted | ~20d + a TFLite model |
| MK.7 Recovery as a workout | **the model was deleted as dead** | scheduling UI, and the model again | ~5d |

---

## 6. Plan

### P0 — release blockers

| Gate | Work | Acceptance |
|---|---|---|
| ~~**G1**~~ | ~~Delete `mobile/lib/features/insurance/` and its test~~ | **Done 2026-08-16.** No consumer existed in `lib/`; suite 2596 green after removal |
| **G2** | Run `flutter build apk --release` and `--split-per-abi`; record size and versions | the build passes; the size lands in `PRODUCTION_MANIFEST` |
| **G3** | Create 5 Stripe price IDs, run `setup_stripe_secrets.ps1` | operator, ~10 min in the dashboard |
| **G4** | Settle R5: either an evidential read-only Firestore query, or soften the absolute wording in `legal_text.py` | policy and code agree |
| **G5** | Recover the R8/R9/R11 artefact, or close them as "no source exists" | no UNKNOWN left hanging |
| **G6** | Move the three audit CSVs from `Downloads` under `core/` | the persistence risk is gone |

### P1 — catalogue content (the bulk; scale is an operator decision)

| Gate | Work | Size |
|---|---|---|
| **C1** | Close the 5 known-wrong cards (quarantine `ea_major_groups_muscle_body`, 4 text fixes) | ~1h |
| **C2** | Fix the 127 `RU summary != steps[0]` rows mechanically; add the RU-side invariant test | ~2h |
| **C3** | Resolve the 78 `equipmentLabel: "None"` rows that name a machine | ~2h |
| **C4** | Decide the 83/38 identical-steps clusters: one card with an angle switch, or leave them | product decision, then ~1d |
| **C5** | Read the 224 shared-`summary` cards no detector ever touched | ~2d |
| **C6** | Re-verify the 320 dismissed at gates A/B/C (those detectors are ~50% false-positive) | ~3d |
| **C7** | **The 1368 unread cards** — a full pass. This is the main body of work | ~10–15d, or a hire |
| **C8** | `purpose` for the remaining 1484 rows | ~15d assisted, but see C9 |
| **C9** | **Professional review of the 403 already-written `purpose` texts** — they were written by an assistant, not a trainer | external budget |
| **C10** | 1112 exercises with no female clip, 123 with no male one | shoot or licence |
| **C11** | A real `difficulty` gradation — 1877/1887 are `beginner`, the field is unusable | content |
| **C12** | 451 without `primaryMuscles`, 182 without `muscles`, 503 without `equipmentId`, 360 without an injury tag | tagging |
| **C13** | 26 rows `movementRoleOf` cannot classify | rules, or a manual tag |
| **C14** | 4 machines with no exercises | link them, or hide the pages |

### P2 — UI and accessibility

Surface `purpose` on the programme card and in the player · `semanticLabel` on `ExerciseThumb` ·
B4 silhouette (operator's eyes) · B6 speed control on device · H2 template ranking · F3 Figma parity.

### P3 — platform

iOS scaffold · Wear OS smoke test · the TFLite equipment model · Cloud Function tests · AES instead
of XOR for photos · the Stripe Connect return URL.

### P4 — operator decisions only

R11f-2 photo export (conflicts with "photos never leave the phone") · A5 Paywall pricing · the fate
of MK.4 and of MK.6/MK.7 · the scale of C7 (own pass versus a hire).

---

## 7. What this document does NOT claim

- It does not claim the 1368 unread cards are fine. It claims nobody has looked.
- It does not claim the 33 Gate E action items are the complete defect set even within the 199 cards
  reviewed.
- It does not treat `DEDUP_CANDIDATE` or `LEGITIMATE_VARIANT` as wrong descriptions — those are
  catalogue-structure problems, tracked separately.
- Items **B4–B11** come from plan files and were **not re-verified on 2026-08-16**. Three
  neighbouring items in the same file proved stale, so check each against code before picking it up.
