# Card — full-catalog re-check (1887 exercises)

**Status:** work complete, tests green (2358/2358 Flutter, 36/36 catalog), Codex consensus
run to a final round. **Pending commit**, then a separate push-GO. Two named follow-up
gates remain, listed under "Next" — neither is optional-nice-to-have; item 3 is a
pre-release safety gate.
**Scope:** all 1887 rows in `mobile/assets/data/exercises_vendor.json`
**Trigger:** operator supplied a real external audit package,
`SPTR_FULL_CATALOG_1887_AUDIT_PACKAGE_2026-08-15.zip` (professional ACE/NASM-lens pattern
audit of the full catalog, not just the 403 B3 set) — this is Option 3 from this card's
original scope proposal ("a full professional re-audit of all 1887 cards"), supplied
pre-made rather than commissioned separately.

## What the audit found (measured, not guessed)

Extracted to `D:\Temp\claude\...\scratchpad\sptr_full_audit\`. Four files: a 4.1 MB
interactive HTML review, a 1887-row mismatch matrix CSV, a 609-row issue-level matrix CSV,
and a summary MD.

```
total catalog rows:            1887
has purpose (403 B3 set):       403
no purpose (H3 pending):       1484
P0 / P1 / P2 / PASS:      1 / 149 / 369 / 1368
flagged total:                  519 (609 individual issues -- some cards have 2+)
```

Pattern breakdown (issue-level, 609 total): `SPINE_CUE` 224, `PRIOR_REAUDIT` 135 (carries
forward the round-2 403-set audit's still-open 52 P1 / 82 P2), `DUPLICATE_STEPS` 91,
`FORCED_ROM` 66, `SUPERLATIVE_CLAIM` 23, `KNEE_TOE_RULE` 15, `VAGUE_HOLD` 10,
`POSTURE_CAUSAL` 10, `UPRIGHT_ROW` 9, `JOINT_LOCK` 6, `BEHIND_NECK` 5, `LOWER_ABS_TERM` 3,
`NECK_SPECIALIZED` 3, `MALFORMED_STEP` 2, `TOO_FEW_STEPS` 2, `MEDICAL_CLAIM` 2,
`EQUIPMENT_TEXT_CONFLICT` 1, `BOX_SLED_STEP_IMAGE` 1 (the last open P0), `ABSOLUTE_SAFETY` 1.

## What was checked before any edit (Empiricism over Poetry, same discipline as round 1+2)

Every issue class was cross-checked against the real `exercises_vendor.json` text before
any fix — not applied on the audit's word alone. This caught real false-positive classes in
the audit's own detection:

- **SPINE_CUE false positives (23 of 224)**: cards where "straight back" appears only as
  movement direction ("push your hips straight back", "extend your leg straight back"), not
  as a spine-posture cue. The audit's own regex apparently doesn't distinguish word order
  (`back straight` = posture cue, `straight back` as a bare directional phrase = false
  positive unless preceded by an article). Left unchanged.
- **SPINE_CUE under-detection**: extending the fix to the whole catalog (not just the
  audit's 224-row flag) surfaced **37 more** genuine spine-cue rows the audit missed
  entirely, plus **5 more surface-contact exclusions** (back pressed flat against
  floor/bench/wall — a different, correct cue, same exclusion class as the 4 already known
  from round 1).
- **FORCED_ROM false positives**: several flagged rows already said "as far as you can
  control" or "...comfortably" — already correctly qualified; only the genuinely unqualified
  "as far/high/deep/low as possible" (45 rows) and bare "as X as you can" with no qualifier
  (12 rows) needed a fix.
- **KNEE_TOE_RULE**: of 15 flagged, only 4 were genuinely restrictive ("knee must not go past
  your toes"); the other 11 use "knee tracking over your toes" as an alignment cue, which is
  the *correct* NASM-aligned phrasing, not a defect — the audit's keyword match doesn't
  distinguish prohibition from alignment cueing.
- **DUPLICATE_STEPS (91 flagged)**: clustered all 91 by exact-Steps-match across the whole
  catalog — every one is a legitimate multi-angle/POV video variant or naming-convention
  duplicate (e.g. "Barbell Deadlift" / "(front POV)" / "(side POV)" / "(360 Degrees)"), a
  standard pattern used consistently across the catalog's video library, not a content error.
  Rejected as a class. Found and fixed **3 real spelling typos** along the way (title-only:
  "Rotatio"→"Rotation" ×2, "Pres"→"Press" ×1), confirmed via a correctly-spelled sibling in
  the same duplicate cluster.
- **SUPERLATIVE_CLAIM (23 flagged)**: most already use qualified/relative language ("almost
  nothing else", "one of the most effective", named-alternative comparisons) — several are
  my own round-1 fixes being re-flagged by keyword match. Only 2 had a genuinely unqualified
  absolute ("nothing else does") needing softening.

## Fixes applied

**Gate A — mechanical, whole catalog, script + exact-old-text-match guard (abort-before-write
on any mismatch):**

- `SPINE_CUE`: 229 rows ("back straight"/"back flat"/"flat back"/noun-phrase "a straight
  back" → neutral-spine language), **10** exclusions (surface-contact meaning). The tenth,
  `ea_flat_knee_raise`, was missed on the first pass and caught by Codex round 3: the
  rewrite left step 3 saying "keeping the spine neutral" while step 2 says "Press your
  lower back gently into the floor and keep it there" and the purpose says keeping the
  lower back flat "is the whole point". A blanket substitution will always find a row where
  the phrase it replaces was the correct one; the exclusion list is never finished by
  construction, and the only reliable check is reading the neighbouring steps.
- `FORCED_ROM`: 57 rows ("as far/high/deep/low as possible" / bare "as you can" → "...as you
  can control").
- `VAGUE_HOLD`: 10 rows ("hold for a while" / "for few seconds" → "hold for a second",
  matching the catalog's own established convention).
- `JOINT_LOCK`: 6 rows ("locked"/"lock...straight" at elbow → "straight"/"extend fully").
- `KNEE_TOE_RULE`: 4 rows (the genuinely restrictive ones → "track over your toes", reusing
  exact phrasing already correct elsewhere in the catalog).
- `MALFORMED_STEP`: 2 rows — real data corruption (embedded "3. Hold..." numbering merged
  into a step string) split back into proper steps; also fixed the matching Russian overlay
  (`exercises_vendor.ru.json`), which had translated the merged text as one step and needed
  the same split to keep the EN/RU step-count invariant the test suite enforces.
- `EQUIPMENT_TEXT_CONFLICT`: 1 row (`ea_diagonal_chop_cable` — title/equipmentId say cable,
  Steps said "band"; fixed Steps to say cable).
- `ABSOLUTE_SAFETY`: 1 row (`ea_low_sled_push`, a residual claim the round-2 403-set audit
  had already flagged: "none of the joint impact of sprinting" → "less...impact...though the
  joints are still working hard under load").
- `MEDICAL_CLAIM`: 2 rows (rehab/injury framing softened to fitness-coaching scope).
- `LOWER_ABS_TERM`: 3 rows ("lower stomach/lower abs" as if a separate muscle compartment →
  described as hip-flexion-emphasis training instead).

**Judgment batch — small set, fixed directly:**

- `ea_hand_stand_hold`, `ea_gate_pose_rounding_spine_looking_up`: softened unqualified
  "nothing else does" claims.
- `ea_lying_neck_curls`, `ea_lying_neck_extension`: round-2 said the earlier "can help"
  softening didn't remove the causal-fix premise; reworded to drop it.
- `ea_plate_rear_delt_fly`, `ea_bow_pose`: softened "undo"/"strongest counter to" causal
  claims.
- `ea_crescent_moon_pose_quad_stretch`, `ea_dumbbell_shoulder_extension`: light touch on
  similar causal-adjacent phrasing.
- **Difficulty reclassification**: `ea_headstand` `beginner`→`advanced` (a head/forearm-balance
  inversion tagged beginner was a real safety-classification defect the round-2 audit named
  explicitly); `ea_lying_neck_curls`/`ea_lying_neck_extension` `beginner`→`intermediate`
  (direct loaded neck work is more specialized than typical beginner drills).

**PRIOR_REAUDIT (135 issue rows → 89 unique IDs not already covered by another fix above) —
dispatched to 4 parallel general-purpose agents**, each given the real current
`purpose`/`steps` text plus the specific finding from the round-2 action register
(`SPTR_H3_REV2_ACTION_REGISTER_2026-08-15.md`), instructed to propose exact old→new text
pairs or reject with a cited reason, following the same NASM/ACE standard established above.
**Every proposed fix was personally re-verified against the live file (exact-text-match,
abort-on-mismatch) before being applied** — same discipline as every other fix in this pass,
not agent output taken on trust. Result: **57 of 89 fixed (59 individual edits — 2 IDs had
2 edits each), 32 rejected** (already-adequately-hedged text, the finding's own stated
exception applying, or the ask being a schema/metadata field this text-only pass explicitly
does not fabricate — see "Deferred" below).

**Total this session: 449 English rows + 441 Russian rows changed** (the 403-set B3
remediation rounds 1+2 from earlier in this session, plus this full-catalog pass, plus the
Codex round-1 remediation below).

## Deferred — explicitly not done, and why

- **Structural/metadata asks.** Corrected 2026-08-15 after Codex round 1 caught this
  paragraph overclaiming — see "Codex round 1 → 4" above for the full correction.
  What is genuinely true: there is no `prerequisites`, `regressions` or
  wall-or-spotter/exit-guidance field on an exercise row, so those asks are a schema
  change and were **not** faked by writing an invented "prerequisite" sentence into
  `purpose`/`steps`. What was WRONG here: `difficulty` had been fixed on `ea_headstand`
  only, not on the other named movements (now fixed on 9 rows); and there IS a live
  safety-tag field, `contraindications`, which this paragraph wrongly said did not exist.
  Those tags are still not written by hand — they are rule-generated and a hand-written
  tag is retracted by the next tagger run — so the tag work is a named follow-up gate,
  not a deferred nicety.
- **H3** (writing `purpose` for the 1484 rows that don't have one): still on hold, per both
  this session's own recommendation and the round-2/round-3 audits' recommendation to close
  P0/P1 items first.
- **1484-row full professional content pass beyond the pattern-matched issue classes above**:
  the pattern audit covered specific, named issue classes (spine cueing, forced ROM, etc.)
  across all 1887 rows including the 1484 without `purpose`. It did not attempt a
  from-scratch professional review of every `title`/`steps` sentence on those 1484 rows the
  way the original 403-card pass did for `purpose` — that would effectively BE H3-scale work
  and is on hold with H3.

## Checks

- `flutter test test/features/equipment/ test/assets/bundled_assets_test.dart` — 317/317,
  clean, after every edit batch in this pass (re-run after each of: Gate A mechanical,
  judgment batch, PRIOR_REAUDIT batch, and the RU-overlay reformat fix below).
- **Real regression caught and fixed**: the MALFORMED_STEP split changed `steps[0]` for 7
  rows across the whole session without keeping `summary` in sync — caught each time by the
  `summary is always the first step` test invariant
  (`exercise_translations_test.dart:106-119`), fixed by resyncing `summary` to the new
  `steps[0]` in every case.
- **Formatting bug caught and fixed before commit**: my edit scripts wrote
  `exercises_vendor.ru.json` with `json.dump(..., indent=2)`, but the file's original
  formatting uses 1-space indentation — this reformatted the ENTIRE 27,000-line file on
  every write (a 54,000-line diff for a 2-record content change). Caught by comparing the
  diff at the **data level** (parsed JSON equality, not text diff) before commit, which
  confirmed only the 2 intended records actually changed; fixed by reloading from git HEAD
  and rewriting with `indent=1` to match the original file's style. Diff is now 6 lines for
  the 2 real edits.
- **Full unfiltered `flutter test` (2358 tests)** — passes clean, matching the last known-good
  baseline exactly. Confirms the two earlier full-suite runs that showed 1 failure each (in
  `blur_budget_test`/`floating_sheet_test`/`glass_card_test`/etc. — none of which reference
  `exercises_vendor.json`) were pre-existing, order-dependent flakiness unrelated to this
  content pass, not a regression it introduced.
- **Codex consensus review, round 1 — found 5 MAJOR + 1 NIT, all six confirmed
  against the real files, zero confabulations.** This is the most productive
  external review of the three rounds, and it caught a class of hole the two
  content audits structurally could not: they reviewed the English review page,
  so nothing in either of them could notice that the Russian overlay had not
  moved. Full disposition in "Codex round 1" below.
- After the round-1 remediation: full unfiltered `flutter test` **2358/2358**,
  `scripts/catalog/test_tag_contraindications.py` **36/36**.

## Codex round 1 — what it found and what was done

| # | Finding | Verdict | Action |
|---|---|---|---|
| 1 | Russian overlay still ships the claims removed from English | CONFIRMED | 459 Russian strings re-derived |
| 2 | `BEHIND_NECK` (5) never dispositioned | CONFIRMED | fixed |
| 3 | `UPRIGHT_ROW` (9) never dispositioned | CONFIRMED | fixed |
| 4 | `difficulty` still beginner; `contraindications` empty | CONFIRMED | difficulty fixed; tags deliberately not hand-written |
| 5 | `JOINT_LOCK` half-applied on Plate Overhead Shrug | CONFIRMED | fixed |
| 6 | lowercase steps + `stright` typo | CONFIRMED | fixed |

**1 — the Russian overlay.** Worse than the sample Codex gave. 433 English rows
had changed and exactly 2 Russian records had been touched.
`ea_low_sled_push` still read *"Тяжело для квадрицепса и полностью безопасно"* —
"completely safe", the single strongest claim this whole audit exists to remove
— and `ea_heavy_bag_sled_drag` still framed the movement as knee rehabilitation
with no clinician caveat. Russian-speaking users were being shown the
un-remediated copy while the English side was clean.

Measured gap: **468** out-of-sync Russian strings (403 changed step strings
across 380 ids, plus 65 changed purposes that have a Russian counterpart).
Re-derived by 6 parallel drafting agents, each shown `en_old` / `en_new` /
`ru_current` and told to make the minimal edit carrying the new meaning; every
result verified programmatically before applying (identity matched by
`(id, field, index)`, and the live Russian value had to still equal the
`ru_current` the agent was shown, or the whole apply aborts). **459 changed, 9
already correct.** Verified after: zero Russian purposes claim absolute safety;
the one remaining rehab mention now mirrors the English clinician caveat.

The overlay's own `summary` field is dead data — `asset_equipment_repository.dart:172`
derives summary from `steps.first` — so all 122 Russian summary values were
deliberately restored to their HEAD content instead of resynced, keeping the
diff to the 459 real changes.

**2 + 3 — the classes that were silently skipped.** `BEHIND_NECK` and
`UPRIGHT_ROW` were listed in this card's own pattern breakdown and then never
dispositioned in either direction, while the card claimed the pass was
complete. That is the more serious half of the finding: not that 14 cards were
unfixed, but that the card said otherwise. 22 substitutions applied, each
`old` verified as a unique verbatim match. Behind-neck cards now cue a
controlled comfortable range, name the front-of-body variant, and cue stopping
if the shoulder pinches; upright rows no longer impose a universal
shoulder-height cutoff or claim that exceeding it causes pain.

**4 — and where this card was wrong.** Codex was right that the "Deferred"
section below overclaimed twice. The `difficulty` fix had been applied to
`ea_headstand` only, not to the other movements named; and the claim that no
schema field existed for safety tags was false — `contraindications` exists and
is live (`exercise_filter.dart:38`: an empty list passes every injury screen).
Both corrected. Difficulty now fixed on 9 rows.

The tags were still **not** hand-written, and that is a considered refusal.
`contraindications` is not a hand-maintained field: `scripts/catalog/tag_contraindications.py`
produces it from deterministic word rules, and its `retract_stale_tags()`
removes any tag the current rules do not produce. Tested rather than assumed —
the 7 rows were hand-tagged, and
`test_tag_contraindications.py::test_the_rules_still_produce_what_the_catalog_carries`
went red immediately. Hand tags would have been silently retracted by the next
tagger run, leaving a catalog that looked screened and wasn't. The correct route
is a rule change plus the per-region hide-rate report that script's own
documentation requires — catalog-wide blast radius on the filter that decides
what an injured user is shown, so it is its own gate, not a footnote to a copy
pass. Reverted and named as follow-up.

**A real bug this surfaced.** One of the three title typos fixed earlier in this
pass — `Dumbbell Face Down Lying Shoulder Pres` → `Press` — made the existing
`shoulder_overhead` rule match (on its "shoulder press" phrase) a row it had never
matched. That exercise had
shipped never being screened for a shoulder injury **purely because of a
spelling mistake in its title**. The rules can only be as good as the text they
read, and a misspelt title fails open. Tagged through the canonical
`--region shoulder --write` path (1 row), with both ratchets raised in the same
change: `kSafetyCoverageFloor` 1524 → 1525 and `shoulder` 486 → 487, each
carrying a comment explaining why the number moved without a batch.

## Artifact

`core/plans/FULL_CATALOG_REVIEW_2026-08-15_REV2.html` — the full 1887-card interactive
review page (all rows, not just the 403 B3 set), with the 449 English rows changed this session
tagged **Revised**, filterable by Has-purpose/No-purpose and by muscle group. Supersedes
`FULL_CATALOG_REVIEW_2026-08-15.html` (kept on disk for before/after comparison).

## Codex round 2 — 4 AGREE, 2 REFINE, 1 DISAGREE, plus 4 new findings

Round 2 confirmed the JOINT_LOCK fix, the UPRIGHT_ROW rewrites, the capitalisation/typo
fix, and accepted the contraindications refusal reasoning — with the refinement that the
rule change stays a **mandatory pre-release safety gate** rather than being treated as
closed, which is right and is why it is item 3 under "Next". It DISAGREED on the Russian
parity being finished, and it was correct:

- **RU parity was incomplete, by construction.** The Russian payload was snapshotted
  before the `BEHIND_NECK`/`UPRIGHT_ROW`/`POSTURE_CAUSAL` English edits were applied, so
  those 26 later strings had no Russian counterpart. A self-inflicted ordering bug:
  derive-then-edit leaves the derivation stale, and nothing in the pipeline notices,
  because the step-count invariant that IS tested never moved. Re-derived after the fact.
- **Two behind-neck cards contradicted their own fallback.** Both offered "otherwise rest
  the bar across the front of your shoulders" in step 1 and then ordered the user to lower
  it *behind the neck* on the return. A user who took the safer option was told to
  undo it. Return cues now preserve whichever position was chosen. The other three
  behind-neck cards were already position-agnostic — Codex named exactly the two that
  weren't.
- **Four records this diff touched still positively cued locking** (`ea_kettlebell_windmill`,
  `ea_plate_overhead_walking_lunge` ×2, `ea_plate_thruster`, `ea_push_pull_front_handle_push`).
  Fixed. Note the scope line: the audit's `JOINT_LOCK` class was 6 rows, but the catalog
  carries ~30 more positive "lock the arms" cues in rows this pass never touched. Those are
  NOT fixed here — a catalog-wide lock-cue sweep is a separate pass, listed under "Next".
  Fixing only the rows already in the diff is the defensible line; silently extending to
  30 more would be unreviewed scope.
- **58 instances of an awkward Russian calque** («настолько … , насколько вы можете
  контролировать» — `контролировать` left without an object) introduced by this pass's own
  mechanical Russian edit. Rephrased per sentence rather than by another blanket
  substitution, which is what created the problem in the first place.
- Two NITs, both right: the rule that fired on the typo fix is `shoulder_overhead` (on its
  "shoulder press" phrase), not `shoulder_pressing` — corrected in all four places it was
  cited. And `DECISION_LOG.md` claimed the work was "committed" while `git status` showed
  it entirely unstaged — an entry written ahead of the action it describes, which a later
  reader has no way to detect. Corrected, with the lesson recorded in the log itself.

## Next

1. Operator reviews the REV2 page.
2. Push on a separate push-GO, after Codex's final round.
3. **Named follow-up gate — contraindication tags for the movements this pass
   reclassified as advanced.** `ea_hand_stand_hold`, `ea_crow_pose`,
   `ea_wild_thing_pose`, `ea_monkey_pose`, `ea_half_monkey_pose`, `ea_tyre_flip`,
   `ea_tyre_hammering` carry no injury tags and so pass every injury screen. The fix is a
   rule change in `scripts/catalog/tag_contraindications.py` plus the per-region hide-rate
   report, not a hand edit — see "Codex round 1 → 4". Note the rules currently miss
   `ea_hand_stand_hold` only because its title is spelled "Hand Stand" while the
   `shoulder_overhead` rule lists "handstand"; the same failure mode as the `Pres`/`Press`
   typo, and worth fixing as one piece of work. Codex round 2 refined this to a
   **mandatory pre-release gate**, not an optional follow-up: shipping movements
   reclassified as advanced while they pass every injury screen is the wrong order.
4. **Catalog-wide lock-cue sweep.** ~30 rows outside this diff still positively instruct
   locking a joint (`ea_air_swing_running`, `ea_dumbbell_push_press`,
   `ea_kettlebell_snatch`, `ea_landmine_hollow_hold`, and others). The audit's own
   `JOINT_LOCK` class named only 6; the rest were never flagged. Deliberately out of scope
   here — a mechanical sweep with per-row judgment, its own gate.
5. **A near-miss title sweep**, from the `Pres`/`Press` discovery: the tagger matches the
   vendor's free text, so a misspelt or unusually-spaced title fails open silently and no
   test can see it, because the rules and the catalog agree on the wrong answer.
6. Still on hold: H3 (`purpose` for the 1484 rows that lack one).
