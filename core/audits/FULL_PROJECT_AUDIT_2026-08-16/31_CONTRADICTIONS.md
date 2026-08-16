# 31 - Contradictions

Places where two sources in this repository disagree, and which one the evidence supports.

## 1. The TFLite model - scope says absent, the artefact says trained

`core/plans/FINAL_SCOPE_2026-08-16.md:190` (P5): *"equipment_v1.tflite not trained and not bundled -
recognition runs cloud-only."*

The file is present at 4,496,661 bytes, `mobile/assets/models/README.md` documents a 2026-07-29
training run (MobileNetV2 + 10-way head, float16, 1,741 crawled photos), reports top-1 0.617 /
top-3 0.835 on a stratified 15% holdout with a per-class table, and records a data leak that the
pipeline caught and fixed. `asset_bootstrap.dart:20` copies it to the documents directory and
`mlkit_live_equipment_service.dart:31` loads it.

**The scope row is CONTRADICTED.** The real gap is different and narrower: 10 label classes against
69 registry machines.

## 2. "Scan any gym machine" against a 10-class model

`core/business/PITCH_2026.md:15`: *"QR-scan any gym machine -> instant personalized workout that
respects your injuries, time budget, and goal."*

Recognition covers 10 of 69 registry machines. Injuries are genuinely screened. "Any machine" is
not supported by the artefact. **CONTRADICTED as written**, though the QR path may be a separate
mechanism from the model - that distinction is NOT_CHECKED here.

## 3. Level personalisation against a degenerate difficulty column

Onboarding collects a fitness tier and the product presents level as a personalisation axis.
1,877 of 1,887 catalogue rows carry `difficulty: beginner`. Any ranking or filter keyed on
difficulty is arithmetically inert. **The collection and the data contradict each other.**

## 4. Recovery against the questionnaire

The app asks for sleep hours and a 1-10 stress level. The recovery feature reads neither.

## 5. This audit contradicted itself twice, on record

- Dead providers: a file-count measure reported 15; an occurrence measure reported 7. The first was
  wrong (`aiCoachServiceProvider` is consumed four lines below its own declaration).
- Personalisation: `heightCm` and `weightCurrentKg` were first classed as reaching no engine. They
  reach `body_comp` (Navy formula) and `form_check/pose_silhouette`. The engine list was incomplete.

Both are recorded because the same shape of error - a grep treated as a fact - is exactly what this
audit exists to catch elsewhere.
