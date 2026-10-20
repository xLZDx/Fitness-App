# B3 — People Photographs in Exercise Cards: Original Diagnosis DISPROVEN (English Translation)

**Original:** [B3 corrected media investigation](B3_MEDIA_DIAGNOSIS_2026-08-07.md), Git source blob `0ea49a190a776e272c0fc68a0dd60d4f8e8f5f1c`.  
**Date:** August 7, 2026.  
**Most important historical correction:** **The file's first revision (commit `0046129`) reached the wrong diagnosis. This is the corrected account.**

The report investigates a screenshot showing a real person's photograph in the exercise-media area. It is a source-linked historical investigation, **not** an assertion that modern Fitness App releases have the same image or that the device was inspected again during translation.

## Original assertion and why it was wrong

The initial analysis said photographs of people were being read from Free Exercise DB `frames` / `imageUrls` fields and were still live behavior. It inferred that from a comment at `lib/features/equipment/workout_player_page.dart:157-160`.

**The comment actually described code that had already been REMOVED:**

> The two photograph fallbacks that used to sit here **are gone**: `frames` and `imageUrls` are both stills of a man in a gym…

The original author misread a description of **removed fallback code** as evidence of current behavior. The record explicitly describes this as a citation/provenance failure: the excerpt was accurate, but its meaning had been reversed.

## What the source really established

**At that checkpoint, the current source code no longer selected those human photographs, but the operator's installed APK was older than the fix.**

The comparison was:

| Catalogue/source | Earlier state before August 3 | Source at August 7 |
| --- | --- | --- |
| Exercise rows | **511** | **1,887** |
| Media roots | `assets/exercises/...` **417** references; `https:` **284**; `assets/...` **549** | Only `assets/posters/...` |
| Source | `f9d5913:mobile/assets/data/exercises.json` | `exercises_vendor.json` |

The legacy `assets/exercises/` directory consisted of **132 files, 8.1 MB** of demo photographs noted at `mobile/pubspec.yaml:123-126` and deleted on **August 4, 2026**.

The actual behavior fix arrived in commit **`88d0759` (August 3)**, captioned in the source as **"feat(H1): the catalog shows animation or it shows nothing"**.

The author then **opened the actual current poster** `assets/posters/men/ea_iso_lateral_shoulder_press_alternate_arms.jpg`: it showed a **3D anatomical figure on white**, not a living man. The operator's screenshot `Screenshot_20260806_133411.jpg` instead showed a dark photograph of a man lifting a barbell. The current catalogue no longer had a source for that picture.

Across all catalogue posters, the source counted **2,979 files**, sizes **1.9–11.3 KB**, median **4.4 KB**. The author acknowledged that inferring "not a real photograph" solely from file size had been **a hypothesis until one actual image was opened**. The verified single-example inspection supported the corrected conclusion, but the report explicitly says the order of reasoning should have been **inspect first, infer second**.

## Consequence for gate B3

**B3 required no additional code fix based on this corrected analysis.** It required rebuilding and reinstalling the APK containing the prior fix.

The screenshot date (**August 6**) was three days after the source fix, but the **installed build date did not match the screenshot date**. The source cites the global `Screenshot Timestamps` rule: a screenshot freezes what the installed build displayed, not what the latest repository source would render.

**Verify with a newly built/installed APK; do not diagnose live source exclusively from old screenshots.**

This was a historical recommendation, not a new request to build or install software through this translation.

## What this correction did NOT resolve

- **Bug 1 — treadmill recognition remained:** B1 evaluated the real checked-in `.tflite`, **not** an obsolete operator APK. Thresholds **0.05/0.10** accepted all **30/30** images, and the model gave **0.892** confidence to an unrepresented class. See [B1 English measurement](B1_RECOGNITION_MEASUREMENT_2026-08-07.en.md). Partially mitigated in `6d63e98`; actual remedy targeted **B5**.
- **Bug 3 — male users receiving female animation clips remained:** `playableVideoFor` in `equipment_models.dart:178` used the source fallback `video[body] ?? video['men'] ?? video.values.first`. The operator decided to **leave that behavior unchanged** at this checkpoint.
- **B6 debug instrumentation remained important:** It would have shown the actual APK/build version in logs, avoiding a lengthy investigation triggered by confusing an old device build with current source.

## Next actions described in the original source

1. Rebuild an APK at that historical code HEAD, install it on the phone, and repeat the scenario associated with `Screenshot_20260806_134541.jpg`.
2. **If human photographs remained:** Reopen diagnosis B3. Examine live fallback paths in `_EquipmentThumb` (`equipment_detail_page.dart:207-251`) and `_ExerciseCard` (near line 253); both had gradient placeholders and remaining active branches.
3. **If the human photographs disappeared:** Close B3 as **"already fixed earlier, confirmed on new build"**.

These were conditional verification actions; this translation did **not** execute them or assert either outcome occurred.

## Historical gate status in the source

- **B1 DONE:** Measurement recorded in `B1_RECOGNITION_MEASUREMENT_2026-08-07.md`.
- **B2 DONE:** Commit `6d63e98`.
- **B3:** No additional code needed; awaited rebuilt APK confirmation.
- **B4:** Retained as-is by owner decision.
- **B5 / B6:** Not yet started.
- Nothing had been pushed after `d5bc578` at the source checkpoint.

## Fidelity and safety boundary

The original B3 **mistaken assertion is not repeated as truth**, and the corrected explanation, commit IDs, poster file, counts, unclosed bugs, old-versus-current-build distinction and conditional B3 closure are all preserved.

No original report, source media, actual user/gym photographs, copyright-sensitive assets, Flutter code, build, emulator, phone, test suite, or runtime configuration was modified.

**Disposition: SOURCE-BOUND ENGLISH TRANSLATION OF THE CORRECTED B3 INVESTIGATION — no current build or reviewer signoff.**
