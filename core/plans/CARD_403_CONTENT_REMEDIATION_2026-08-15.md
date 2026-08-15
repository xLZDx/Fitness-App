# Card — 403-exercise content remediation (B3 set)

**Status:** done (all three rounds closed); pending commit together with the
companion full-catalog card, `CARD_FULL_CATALOG_AUDIT_2026-08-15.md`
**Scope:** the 403 `exercises_vendor.json` rows that carry a B3-authored `purpose` field
**Trigger:** external professional audit (ACE/NASM-lens, 2026-08-15) of the
`H3_PURPOSE_REVIEW_2026-08-15.html` page — 15 P0 / 48 P1 / 97 P2 / 243 PASS

## What was checked

Every P0 finding was cross-checked against the real `purpose`/`steps` text in
`mobile/assets/data/exercises_vendor.json` before any edit (Empiricism over Poetry —
no fix applied on the audit's word alone). One own pattern-scan pass was run
across all 403 `purpose` texts and all 403 `steps` blocks for the same
classes of issue the audit named, to catch instances the audit itself missed.

## Fixes applied (agreed with the audit)

- **23 `purpose` texts rewritten** — 13 of the 15 P0 items, plus 8 more
  surfaced by the own-pattern scan (absolute/superlative claims: "the
  safest", "completely safe", "costs nothing", "the most effective", "the
  best"). **Correction (2026-08-15, after a second-round external re-audit):**
  this card previously and incorrectly said "all 15 P0 items" — verified
  against the live file, `ea_single_kettlebell_sled_push` and
  `ea_double_kettlebell_sled_push` never received a Purpose rewrite (see
  "Disagreed with the audit" below for why: the naming P0 finding on those
  two was rejected outright, not fixed).
- **1 real Purpose/Steps contradiction fixed**: `ea_headstand` said "never on
  the head" while its own Steps put the crown of the head on the floor.
- **60 `steps` rewritten** (scoped strictly to the 403 set) — "flat back" /
  "back flat" cueing replaced with "neutral spine" language throughout,
  excluding the 4 cards where "flat back" correctly means "back resting flat
  against a support surface" (bench/pad), not a hip-hinge cue.
- **1 more Steps fix, added after the second-round external re-audit**:
  `ea_box_sled_push` Step 1 said "Load the sled and grip the high handles or
  the frame" — wrong equipment word for a card titled/postered as a box push.
  Changed to "Load the box and grip the high handles or the frame". This was
  the one real P0 the re-audit found that the first pass missed (the
  "Sled"-naming convention itself is still correct and unchanged — see
  disagreement below; this was a genuine steps-text/poster mismatch, a
  different issue from the naming question).
- **Regression found + fixed by `flutter test`, own bug, not from the
  audit**: `exercise_translations_test.dart`'s `summary is always the first
  step` invariant caught that `summary` must equal `steps[0]` verbatim
  (`test/features/equipment/exercise_translations_test.dart:106-119` — the
  Russian overlay derives its summary the same way, so a desync here would
  silently break the Russian side too). 7 rows had their `steps[0]` rewritten
  by this pass (`ea_box_sled_push`'s box-vs-sled fix, plus 6 flat-back→
  neutral-spine rewrites that happened to land on step one) without updating
  `summary` to match: `ea_kettlebell_rear_delt_row`,
  `ea_kettlebell_silverback_shrug`, `ea_kettlebell_single_arm_rear_delt_fly`,
  `ea_plate_internally_rotated_rear_delt_fly`, `ea_plate_pinch_grip_row`,
  `ea_plate_rear_delt_fly`. Resynced `summary` to the new `steps[0]` for all
  7; `flutter test test/features/equipment/ test/assets/bundled_assets_test.dart`
  now passes clean (317/317).

Full diff reviewed line-by-line before regenerating the review page — see
`git diff mobile/assets/data/exercises_vendor.json` on this commit.

## Disagreed with the audit (left unchanged, on purpose)

- **Kettlebell/box "Sled Push" titles** (`ea_single_kettlebell_sled_push`,
  `ea_double_kettlebell_sled_push`, `ea_box_sled_push`) — audit read these as a
  title/equipment mismatch. Checked `equipmentId`/`equipmentLabel`: these are
  legitimate compound names (tool + movement pattern) consistent with every
  other "Sled"-labelled exercise in the catalog that substitutes kettlebells,
  weight plates, or a punching bag for an actual sled — the kettlebell card's
  own purpose text already says "when there is no proper sled." Not renamed.
- Four "always/never/impossible" purpose-text hits from the own pattern scan
  (`ea_kettlebell_single_arm_curl`, `ea_kettlebell_single_leg_glute_bridge`,
  `ea_multi_hip_adduction`, `ea_seated_single_leg_toe_touch_hamstring_stretch`)
  — figurative/logical use ("a two-handed curl always hides the difference"),
  not medical or safety claims. Left as-is.
- `ea_kettlebell_curl`'s "grip training you get for free" — idiom for
  "incidental benefit," not a zero-risk claim. Left as-is.
- `ea_frog_jumps`'s "landing noise is the best indicator" and `ea_puppy_pose`'s
  "best shape... if the lower back does not tolerate a deep fold" — both
  already conditionally hedged, defensible coaching heuristics. Left as-is.

## Out of scope for this card (flagged, not touched)

- `ea_box_sled_push` has `equipmentId: plyo_box` but `equipmentLabel: Sled` —
  a pre-existing vendor taxonomy quirk shared with several other cards
  (`weight_plates`/`punching_bag`/`weighted_sled` all label as "Sled" too).
  Changing `equipmentId` risks the H2 equipment-fit ranking feature; left
  alone. Worth a dedicated look if the equipment taxonomy itself ever gets
  audited.
- ~~Russian text (`exercises_vendor.ru.json`) not re-verified against the
  corrected English wording~~ — **closed 2026-08-15**, and it turned out to be
  the single most serious gap in the whole exercise, not a tidy-up. Both
  external audits reviewed the English review page, so neither could ever see
  it; Codex found it. The Russian side was still telling users an exercise was
  «полностью безопасно» after the English had stopped. 441 Russian rows
  re-derived from the corrected English — see
  `CARD_FULL_CATALOG_AUDIT_2026-08-15.md` → "Codex round 1".
- ~~The 48 P1 / 97 P2 findings beyond what the own pattern-scan already
  independently surfaced were not individually walked one by one~~ —
  **closed 2026-08-15** by the third-round full-catalog pass: the re-audit's
  carried-forward 52 P1 / 82 P2 arrived as the `PRIOR_REAUDIT` issue class
  (135 issue rows / 89 unique IDs after removing those already covered by
  another fix) and every one was individually dispositioned. See
  `CARD_FULL_CATALOG_AUDIT_2026-08-15.md` → "PRIOR_REAUDIT".

## Artifact

`core/plans/H3_PURPOSE_REVIEW_2026-08-15_REV2.html` — same 403-card review
page, regenerated from the corrected data, each rewritten card tagged
**Revised**.

## Second-round external re-audit (2026-08-15, of the REV2 output)

An external re-audit verified this card's own numbers (79 cards changed = 23
Purpose + 60 Steps; 60/64 flat-back hits fixed correctly, 4 legitimately
retained) and caught the "all 15 P0" documentation overclaim corrected above.
It found **1 remaining P0** (`ea_box_sled_push`, fixed above), plus **52 P1**
and **82 P2** items not yet dispositioned. It reaffirms the same "Sled"-naming
disagreement as correct (not a defect). Full-1484-row catalog audit still
needs the actual local JSON file, which the external tool did not have.

## Third round — closed out by the full-catalog pass (2026-08-15)

The operator then supplied a real full-catalog audit package
(`SPTR_FULL_CATALOG_1887_AUDIT_PACKAGE_2026-08-15.zip`), which *did* have the
local JSON, covering all 1887 rows. It carries this card's remaining 52 P1 /
82 P2 forward as its `PRIOR_REAUDIT` issue class (135 issue rows), alongside
its own whole-catalog pattern findings.

All 89 unique `PRIOR_REAUDIT` IDs not already covered by another fix in that
pass were individually dispositioned: **57 fixed (59 edits), 32 rejected with
a cited reason** (already-adequately-hedged text, the finding's own stated
exception applying, or the ask being a schema field this text-only pass will
not fabricate). The remaining P1/P2 items from this card are therefore closed
— not by pattern-scan inference, but one at a time against the real file text.

Full detail, including the false-positive classes measured in the audit's own
detection and the fix/reject breakdown, is in the companion card:
`core/plans/CARD_FULL_CATALOG_AUDIT_2026-08-15.md`.

## Next

1. **Done.** `flutter test test/features/equipment/ test/assets/bundled_assets_test.dart`
   — the full set of tests that actually reference `exercises_vendor.json` —
   passes clean (317/317) after the summary/steps[0] resync above. Two
   earlier full-suite (`flutter test`, no path filter) runs each showed
   exactly 1 failure, but in `blur_budget_test.dart` /
   `floating_sheet_test.dart` / `glass_card_test.dart` /
   `glass_nav_bar_test.dart` / `widget_test.dart` — none of which reference
   `exercises_vendor.json` (grepped, confirmed absent) — and the specific
   failing test differed between the two runs. Read as pre-existing,
   order-dependent full-suite flakiness unrelated to this text-only content
   edit, not a regression from this work; not investigated further here.
2. Commit (`fix(content): remediate B3 purpose/steps text per external audit`)
   with the usual plan-block + DECISION_LOG entry. **This card's work goes in
   one commit together with the full-catalog pass** — the two are one
   continuous edit stream on the same file, and splitting the diff after the
   fact would produce two commits neither of which passes the tests alone.
3. ~~Operator reviews REV2 page~~ — superseded: the full-catalog pass produced
   `core/plans/FULL_CATALOG_REVIEW_2026-08-15_REV2.html`, which covers all
   1887 rows (this card's 403 included) and reflects every fix from both
   passes, `ea_box_sled_push` among them.
4. ~~52 P1 / 82 P2 items~~ — **done**, see "Third round" above.
5. Still open: GO for H3 (`purpose` text for the 1484 rows that lack one).
