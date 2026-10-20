# B1 — What the On-Device Equipment Model Did With Real Gym Photos (English Historical Translation)

**Original:** [B1 measured recognition results](B1_RECOGNITION_MEASUREMENT_2026-08-07.md), Git blob `36798e93ef805004c32a22fbab7755166dcbdc09`.  
**Checkpoint date:** August 7, 2026.  
**Status:** Historical measured evidence, **not a contemporary model evaluation**.

The source describes a run of the actual `mobile/assets/models/equipment_v1.tflite` file intended for the APK against **30 gym photos** supplied by the operator, captured on July 30 and August 6, 2026. The original photo folder and raw log paths are preserved in the original report; **the photos are a protected TEST set and MUST NOT be used for model training**.

Preprocessing followed `assets/models/README.md`: float32 tensor `[1,224,224,3]`, raw **0–255** input, with **[-1, 1] scaling inside the graph**. The original experiment used a scratchpad script `b1_measure.py` and raw predictions `b1_raw.json`.

## Main conclusion

**Raising the confidence threshold did not solve the problem. Some of the highest-confidence answers were the most clearly wrong.**

## Confidence thresholds filtered out none of the 30 test photos

```text
Random-chance reference for 10 classes          0.100
Accepted by photo threshold (0.10)              30/30 (100%)
Accepted by live threshold (0.05)               30/30 (100%)
Top-1 below random-chance probability           0/30
Top-1 confidence: min 0.215 / median 0.437 / max 0.897
```

Original source locations:

- Live `confidenceThreshold: 0.05` — `mobile/lib/features/visual_equipment/data/mlkit_live_equipment_service.dart:88`.
- Photo `confidenceThreshold: 0.10` — `mobile/lib/features/visual_equipment/data/mlkit_visual_equipment_service.dart:50`.
- `minConfidence = 0.10` — `mobile/lib/features/visual_equipment/data/visual_equipment_match.dart:29`.

The live threshold was **half** the 0.10 random-chance reference, and the photo threshold exactly equaled it. For a ten-class softmax, some class generally receives at least 0.10, so a simple 0.10 maximum-probability threshold could not implement a meaningful **"uncertain/none of the above"** state.

The **minimum** top-1 score over all 30 photos was **0.215**. A screenshot showed "treadmill" with ~**23% confidence**, which corresponded to this same low-confidence phenomenon.

## Labeled examples — confidently wrong

| Source image | Actual gym machine | Model prediction | Top-1 confidence |
| --- | --- | --- | ---: |
| `20260730_135634` | Precor Inspiration hip abduction/adduction machine | `treadmill` | **0.892** |
| `20260806_140007` | Nautilus Inspiration shoulder press | `leg_press` | **0.897** |
| `20260730_141736` | Precor Inspiration abdominal machine | `treadmill` | **0.742** |
| Screenshot `140916` | Leg-extension machine | `treadmill` | **0.23** |

None of these machines was among the model's ten classes:

`squat_rack`, `barbell`, `dumbbell`, `kettlebell`, `cable_machine`, `bench`, `leg_press`, `lat_pulldown`, `rowing_machine` and `treadmill`.

A hypothetical **0.85** threshold would reject **zero of the first three** problematic high-confidence examples. A wide gap between top-1/top-2 was not proof of correctness: for image `135634` the values were **0.892 versus 0.032**. The model was **confidently out of distribution**, without a learned "unknown" category.

## Distribution of predictions on the real-gym set

```text
leg_press      30%
barbell        20%
treadmill      17%
cable_machine  17%
dumbbell       10%
bench           3%
squat_rack      3%
```

"Treadmill" accounted for roughly one in six responses, but `leg_press` was the largest attractor at nearly one third. The operator noticed the treadmill symptom; the general defect was wider than one class label.

## Consequences for follow-up gates

**B2 needed to change.** Its original idea, "raise the confidence threshold," was invalidated by these measurements.

1. A ten-class model must **not** present its label as a **confident catalogue match** across 70+ distinct machines. At most it could say **"possibly this"** until validated.
2. An explicit **unknown / reject** mechanism was necessary. A naive maximum-score threshold would not create it; possible approaches included a trained negative/none-of-the-above class (B5) or a separate out-of-distribution signal.
3. A raw English classifier class name like `treadmill` in the Russian user interface was **a separate localization defect**, to fix independently of recognition accuracy.

**B5 was the substantive remediation track:** broaden machine classes and add background/negative examples; merely tuning a threshold cannot teach the model about the eleventh machine it has never learned.

## Limitations and protected data

- Only **four** images were given full semantic labels in the source table: the strongest obvious errors plus the operator screenshot. The **confidence-threshold** finding was measured on **all 30** and did **not** require labels. A complete labeled test set would still be required for B5.
- Only the **on-device** model was measured. The cloud Gemini route was **not** tested: its key was held server-side, outside this script.
- The screenshot's live mode represented the **on-device** route, not a new cloud result.
- The **30 operator photos are strictly TEST material**. Training on them would invalidate the held-out evidence. The translation does not copy, open, relabel or redistribute any image.

## Translation boundary

This English companion preserves the original prediction table, ten classes, exact 30-photo thresholds and B2/B5 decision implications. It does **not** claim the current Fitness App model still has ten classes, that its current OOD behavior matches v1, or that any training/evaluation was conducted in this translation session.

**Result:** Source-linked English historical measurement for independent semantic review, **not a production AI accuracy signoff or permission to retrain**.
