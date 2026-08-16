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
| `RU summary != steps[0]`, while EN holds the invariant on all 1887 | ~~127~~ **0 — repaired 2026-08-16 (C2)** |
| `equipmentLabel` is the literal string `"None"` while `equipmentId` names a real machine | ~~78~~ **0 — repaired 2026-08-16 (C3)** |

**Caveat without which the first row misleads.** Identical steps do not prove a wrong description.
The largest cluster is `Barbell Deadlift` / `(front POV)` / `(side POV)` / `360 Degrees` — one
exercise shot from four angles, where the text is correct and the **cards** are redundant. Read the
83 as "redundant or wrong", never as "wrong".

The 127 RU rows were a different matter: EN held `summary == steps[0]` on 1887 of 1887 and RU broke
it on 127. That was a defect, not an ambiguity, and it is **closed** — all 127 differed only in the
phrasing of the same instruction, with `steps[0]` carrying the newer wording.

### 1.4 Known-wrong cards — **all five closed 2026-08-16 (C1)**

| id | Defect |
|---|---|
| `ea_major_groups_muscle_body` | a single step, a generic standing cue, no real exercise behind it. **WITHHELD** — `assets/data/exercises_quarantine.json`, filtered in `AssetEquipmentRepository`, the single load path for every surface. Row kept so the audit's 1,887-id cross-reference stays exact |
| `ea_cable_wrist_extension` | asserts a flexor/extensor strength parity that does not exist, plus an unhedged causal medical claim. **FIXED** both locales |
| `ea_puppy_pose` | "the lower back is not involved" is backwards for this pose. **FIXED** both locales |
| `ea_sissy_squat_bodyweight` | implies any knee adapts eventually. **FIXED** both locales |
| `ea_criss_cross_bow_tie_pose` | the RU title describes a seated crossed-**legs** hip opener; the exercise is a shoulder stretch with the arms crossed behind the back, and the card's own RU steps say so. **FIXED** — RU title now names the arms |

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
- ~~78 rows say "no equipment" on the card for an exercise that names a machine~~ — **repaired 2026-08-16 (C3)**,
  derived from the registry. Measured populations: **503 NO_EQUIPMENT / 1384 KNOWN_EQUIPMENT /
  0 UNKNOWN_EQUIPMENT**. A permanent invariant test now holds all three apart.
- ~~**New, found during C3:** the exercise card renders `equipmentLabel` verbatim, so a Russian
  user reads the machine name in English~~ — **fixed 2026-08-16.** `ExerciseQuickStats` now
  resolves the name through `equipmentByIdProvider`, the same lookup the machine pages use, so
  there is no second mapping to keep in step. Three fallbacks, each a different fact: no
  `equipmentId` keeps the vendor's own words ("Yoga Mat", "Wall"), an unresolvable id keeps the
  stale English label rather than claiming bodyweight, and no label at all reads Bodyweight.
  3 tests, 4 mutations.

### 1.8 Persistence risk, inherited — **closed 2026-08-16 (G6)**

The CSVs every audit figure rests on used to live outside the repository, in the operator's
`Downloads`. The whole delivered package — 5 CSVs, 3 summaries and the review page — is now under
`core/audit/full_catalog_1887_2026-08-15/`, imported byte-for-byte with a `MANIFEST.csv`
carrying a SHA-256 and a row count per file. `tools/evidence/validate_csv_evidence.py` re-hashes
them, and every documented count was verified against the live catalogue at import: 609 findings
over 519 cards, 224 Gate E findings over 199 cards, 1887 verified rows of which 403 carry a
`purpose`, and the audit's 1887 ids match the shipped catalogue exactly in both directions.

---

## 2. Safety and claims — the remainder of the 2026-08-15/16 mission

| # | Item | Status |
|---|---|---|
| **S1** | `mobile/lib/features/insurance/` — dead code designing the sharing of adherence-derived eligibility with a carrier, recorded in Gate J as prohibited by a 15 April 2026 Play policy | **Closed 2026-08-16.** Deleted under an explicit operator GO after the shell safety gate blocked the first attempt |
| ~~**S2**~~ | **R5** — the device-local claim was absolute in the policy while the code was conditional | **Closed 2026-08-16 (G4), without the production query.** Reading the code settles it: `DeviceHealthProfileRepository.save` calls `stripSensitive` before writing, so the current app *cannot* send a health block — the present-tense claim is true. A pre-2026-08-06 document may still carry one; `_resolve` clears it on the owner's next read and `deleteAccount`'s `recursiveDelete` removes it with the account. Only a never-reopened account keeps a copy, which is the population the absolute sentence was silently speaking for. Both locales now name that case and the one action that resolves it |
| **S3** | **R8 / R9 / R11** from Gate J | **Closed 2026-08-16 (G5).** Source recovered to `core/audit/gate_j_regulatory_review_2026-08-15/`. R8 (deletion pseudonymises `coach_bookings` / `equipment_reports` without saying so) **FIXED** — policy sentence in both locales, plus a test that reads `index.ts` so a fourth shared collection fails. R9 (About page implies a clinical review programme) **FIXED** in both locales. R11 (stale comment says photos are unencrypted) **FIXED** in both copies |
| **S3a** | **R3** — no explicit Art. 9(2)(a) consent event for special-category health data | **DECISION_REQUIRED.** MAJOR, and it had been dropped from Gate J's deferral list entirely — recovered 2026-08-16. FACT: no consent control exists in `step_health.dart`. The reviewer's own unresolved item requires the Art. 9 basis be settled with counsel before the control is designed |
| **S3b** | **R10** — Crashlytics enabled in release with no in-app opt-out | **DECISION_REQUIRED.** Disclosed, with an Art. 21 route by email; the reviewer's own verdict is "no change strictly required". Also never recorded before 2026-08-16 |
| **S3c** | **R12** — BMI bands render "Obese range" | **NOT A DEFECT.** The reviewer filed it as a boundary observation: the app states BMI cannot tell muscle from fat and `body_metrics.dart:29` confirms nothing consumes it. Recorded so it is not rediscovered as new |
| **S4** | The 2026-08-16 review round left 9 test files and 4 programme claims unexamined | not cleared, not examined |
| **S5** | Deleting `recovery_block.dart` and retracting the body-comp paywall line removed what `NEXT_TICKETS.md` calls the MK.6/MK.7 "foundations" | deliberate — there was no functionality behind either — but picking those up now starts from zero |

---

## 3. Bugs and open plan items

### Verified against code on 2026-08-16

| # | Item | Evidence |
|---|---|---|
| **B1** | ~~**H4** — exercise tiles on the programme card are nameless to a screen reader~~ **STALE, and the conclusion was backwards.** The evidence line was true — there is no `Semantics` in `exercise_thumb.dart` — but the programme card supplies its own `Semantics(label: title)` at `workouts_page.dart:1169`, and the other five call sites put the tile beside a `Text` with the title, where a label would make the name be read twice. The change actually missing was the opposite: `excludeFromSemantics`, so the picture stops contributing an unnamed graphic node. **Done 2026-08-16**, 3 tests, 2 mutations |
| **B2** | ~~`purpose` is rendered on the exercise card only~~ **Half stale, and the real defect was worse. Closed 2026-08-16.** The player already showed it — `workout_player_page.dart:282` renders `ExerciseStepsCard`, the same widget that draws the purpose block on the detail page. What was real: the list row's subtitle was `exercise.summary`, and `summary` is byte-identical to `steps[0]` by an invariant enforced on all 1,887 rows — so the subtitle was the first **instruction**, shown on the one screen where the user has not chosen yet. `exerciseSubtitle` now prefers `purpose`, keeping both fallbacks for the 1,484 rows without one. 5 tests, 4 mutations |
| **B3** | **There is no iOS scaffold at all** — `mobile/ios/` does not exist | `ls` |

### From plan files, NOT re-verified on device

| # | Item | Source |
|---|---|---|
| **B4** | **B4** silhouette — third attempt; "closed only after the operator looks at it" | `PLAN_BUGS_2026-08-13.md` |
| **B5** | **B6** video speed control — code done, unverified on device | same |
| **B6** | **H2** template ranking ignores equipment and injuries (they affect selection INSIDE a programme, not card order) | same |
| **B7** | **H5** 89 rows with a contradictory muscle group — **NOT_REPRODUCED, and the source definition does not exist anywhere.** Four definitions tried on 2026-08-16: `primaryMuscles ⊄ muscles` → **0**; `primaryMuscles` set with `muscles` empty → **0**; `muscles` set with `primaryMuscles` empty → **269**; both empty → **182**. A fifth, `vendorGroup` sharing no muscle with its own body area, gives **28** under a mapping this session invented, which is not a reproduction either. No fix is proposed, because fixing an unreproducible count means inventing the defect to match it |
| **B8** | **R11f-2** photo export conflicts with the recorded decision that photos never leave the phone — **decision not taken** | `PLAN_REDESIGN_REMAINDER_2026-08-12.md` |
| **B9** | **R11f-3** photo reminder — notification-scheduler territory | same |
| **B10** | **F3** screen-by-screen parity check against the Figma prototype | same |
| **B11** | **A2** empty `notificationsRule` on budget `projects/988522745882`; **A3** photo capture order (needs a phone); **A4** live Stripe API version (key blocked by the environment classifier); **A5** Paywall HELD on pricing | `PLAN_BUGS_2026-08-13.md` block A |

---

## 4. Platform and release

| # | Item |
|---|---|
| **P1** | **iOS does not exist.** No scaffold, no `Info.plist`, no entitlements. `mobile/IOS_PERMISSIONS_TODO.md` lists what is needed |
| **P2** | ~~The release build has never been run~~ **Closed 2026-08-16 (G2)** — see `core/RELEASE_BUILD_2026-08-16.md`. The debug APK measures **292.6 MB** (306,805,723 bytes), not 380 |
| **P3** | Wear OS smoke test never run on an emulator |
| **P4** | 5 Stripe price IDs not created — annual / family / lifetime SKUs do not work |
| **P5** | `equipment_v1.tflite` not trained and not bundled — recognition runs cloud-only |
| **P6** | ~~Stripe Connect return URL is a placeholder domain~~ **STALE.** `RETURN_ORIGIN` (`index.ts:244`) is derived from `GCLOUD_PROJECT`, so a deploy returns the browser to whichever project it landed in; the placeholder survives only in the comment recording its removal. Both target pages exist: `public/coach/onboarding-done.html` and `onboarding-refresh.html` |
| ~~**P7**~~ | **Closed 2026-08-16.** The suite had never run in this worktree — `npm ci` had not been run, so `ts-jest` was missing and `jest` refused to start; every "full suite green" statement before today covered `mobile/` only. Of the six named, `stripeWebhook`, `createPortalSession` and `startCoachOnboarding` already had behavioural tests; **`optInDonorWall`, `optOutDonorWall` and `reportEquipment` appeared only in `scaling.test.ts`**, which pins scaling configuration and calls none of them. 14 behavioural tests added for those three, 7 mutations, all caught. Suite now **165 passing** |
| **P8** | ~~the photos page still uses the test-only XOR cipher~~ **STALE.** `progress_photos_providers.dart:153` builds `PhotoStore` over a real `AesPhotoCipher` keyed from `SecurePhotoKeyStore`, and `:195` binds `LocalProgressPhotosRepository` over it. `XorPhotoCipher` has **no** caller in `lib/` outside its own definition. Same stale claim as R11, corrected in two other places on 2026-08-16 |

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
| ~~**G2**~~ | ~~Run `flutter build apk --release` and `--split-per-abi`; record size and versions~~ | **Done 2026-08-16.** All three builds pass, real signing key verified against the debug one, not debuggable; AAB 128.8 MB, arm64 download 107.2 MB, both well inside Play's 500 MB limit. Recorded in `core/RELEASE_BUILD_2026-08-16.md` rather than `PRODUCTION_MANIFEST`, which is generated from live APIs. **Found one blocker: `targetSdk` 35 — see G7** |
| **G7** | Raise `targetSdk` to 36 and verify on an Android 16 device | Play requires API 36 for new apps from **31 Aug 2026**, 15 days out. One line in `android/app/build.gradle:126`; deliberately not changed blind, because API 36 enforces edge-to-edge and no layout here has run on Android 16 |
| **G3** | Create 5 Stripe price IDs, run `setup_stripe_secrets.ps1` | operator, ~10 min in the dashboard |
| ~~**G4**~~ | ~~Settle R5~~ | **Done 2026-08-16.** Neither branch was needed as written: the code answers the question a query was being asked for. Policy and code now agree, in both locales, with a control test so the fix cannot become "delete the strong claim". 3 tests, 4 mutations |
| ~~**G5**~~ | ~~Recover the R8/R9/R11 artefact, or close them as "no source exists"~~ | **Done 2026-08-16.** Recovered from the session transcript (the agent's own output file was 0 bytes), persisted and hashed. R8/R9/R11 all FIXED with mutation-tested regressions; R3/R10/R12 surfaced, three findings nobody had recorded at all — see S3a–S3c |
| ~~**G6**~~ | ~~Move the three audit CSVs from `Downloads` under `core/`~~ | **Done 2026-08-16.** 9 artifacts imported unmodified, hashes recorded, validator added and mutation-tested |

### P1 — catalogue content (the bulk; scale is an operator decision)

| Gate | Work | Size |
|---|---|---|
| ~~**C1**~~ | ~~Close the 5 known-wrong cards~~ | **Done 2026-08-16.** 1 withheld, 4 corrected in both locales via a new `correct_exercise_text.py` whose guard found the authored batches had already drifted from the shipped catalogue. 17 tests, 12 mutations |
| ~~**C2**~~ | ~~Fix the 127 `RU summary != steps[0]` rows; add the RU-side invariant test~~ | **Done 2026-08-16.** All 127 repaired deterministically from `steps[0]` by `tools/catalog/repair_ru_summary.py`; the invariant now runs over all 1,887 rows in **both** languages. The pre-existing test checked English only, and its own comment named the Russian divergence it was not checking |
| ~~**C3**~~ | ~~Resolve the 78 `equipmentLabel: "None"` rows that name a machine~~ | **Done 2026-08-16.** All 78 derived from the registry by `tools/catalog/repair_equipment_label.py`. The three states are kept apart — 503 NO_EQUIPMENT / 1384 KNOWN_EQUIPMENT / 0 UNKNOWN_EQUIPMENT — and an unresolvable id is a refusal, not a guess. Permanent invariant test, 4 mutations |
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
| **C14** | 4 machines with no exercises — `recumbent_bike`, `glute_kickback_machine`, `t_bar_row`, `rotary_torso_machine` (69 registry ids, remeasured 2026-08-16) | **Content still open** (link them, or hide the pages). **The defect behind them is fixed 2026-08-16:** opening one of those pages ran the AI fallback, so a Gemini call and a cache write happened per machine per language for text the generator builds with no clip (`ai_exercise_generator.dart:135-149`) and `withDemonstration` then dropped in full — and a generation failure reached `equipment_detail_page.dart:156` as "couldn't load exercises", turning an honest empty state into an error card about work nobody would have seen. `recommendedExercisesProvider` now reads the real catalogue. The page renders `equipmentNoCuratedYet` exactly as before. **Scope of the guarantee, corrected after review:** no *list or feed* can show a clipless exercise, but `exerciseResolutionProvider:472` applies no clip rule, so an `ai::` id already on the device still opens in the player as text with `ExerciseNoVideoFallback` — untouched here, and a population that shrinks rather than grows. 4 tests + 2 rewritten, 3 mutations |

### P2 — UI and accessibility

B4 silhouette (operator's eyes) · B6 speed control on device · H2 template ranking · F3 Figma parity.

Closed 2026-08-16: ~~surface `purpose` on the programme card and in the player~~ (B2 — the player
already did; the list row's subtitle was the first *instruction*, which is the sharper defect) ·
~~`semanticLabel` on `ExerciseThumb`~~ (B1 — the label was decoration a screen reader announced as an
image; `excludeFromSemantics` was the fix, and the recorded finding had it backwards).

### P3 — platform

iOS scaffold · Wear OS smoke test · the TFLite equipment model · **G7** (`targetSdk` 36 before the
31 Aug 2026 Play deadline, then edge-to-edge verified on an Android 16 device).

Closed 2026-08-16: ~~Cloud Function tests~~ (P7 — the suite had never run in this worktree at all;
`npm ci`, then 14 behavioural tests, 151 → 165) · ~~AES instead of XOR for photos~~ · ~~the Stripe
Connect return URL~~.

### P4 — operator decisions only

R11f-2 photo export (conflicts with "photos never leave the phone") · A5 Paywall pricing · the fate
of MK.4 and of MK.6/MK.7 · the scale of C7 (own pass versus a hire) · **the fate of AI exercise
generation** — since C14 it has no consumer in `lib/`, because what it produces has no clip and every
list applies the clip-only rule. Either it is deleted (generator, cache, `FirestoreGeneratedExerciseRepository`,
the `ai::` badge and the deep-link branch) or it waits for the day those machines have footage. Kept
for now: unrenderable is not the same as wrong, and deleting a capability is not a call to make while
measuring one.

---

## 7. What this document does NOT claim

- It does not claim the 1368 unread cards are fine. It claims nobody has looked.
- It does not claim the 33 Gate E action items are the complete defect set even within the 199 cards
  reviewed.
- It does not treat `DEDUP_CANDIDATE` or `LEGITIMATE_VARIANT` as wrong descriptions — those are
  catalogue-structure problems, tracked separately.
- Items **B4–B11** come from plan files and were **not re-verified on 2026-08-16**. Three
  neighbouring items in the same file proved stale, so check each against code before picking it up.
