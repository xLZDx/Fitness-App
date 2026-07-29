# Bundled ML models

`equipment_v1.tflite` (4.3 MB) ships in this directory and is copied to the
app's documents dir on first launch by `core/assets/asset_bootstrap.dart`.
`MlKitVisualEquipmentService` loads it through ML Kit's `LocalLabelerOptions`,
which needs an absolute file path — assets are not addressable that way.

## equipment_v1 — what is actually in the file (trained 2026-07-29)

| Property | Value |
|---|---|
| Architecture | MobileNetV2 (ImageNet weights) + 10-way softmax head |
| Training | 10 epochs frozen backbone, then 6 epochs fine-tuning the top 40 layers |
| Input | float32 `[1, 224, 224, 3]`, raw 0-255 — preprocessing (`[-1,1]` scaling) is **inside** the graph, so metadata declares mean 0 / std 1 |
| Output | float32 `[1, 10]` softmax, label order below |
| Size | 4.3 MB (float16 quantised) |
| Data | 1741 web-crawled photos, deduped by pixel hash, 115-200 per class |

### Measured accuracy — held-out 15%, stratified, run against the exported `.tflite` (not the Keras model)

**top-1 = 0.617, top-3 = 0.835** (n=261)

| Label | n | top-1 | top-3 |
|---|---|---|---|
| squat_rack | 31 | 0.55 | 0.87 |
| barbell | 28 | 0.71 | 0.89 |
| dumbbell | 28 | 0.68 | 0.86 |
| kettlebell | 21 | 0.57 | 0.81 |
| cable_machine | 32 | 0.66 | 0.88 |
| bench | 42 | 0.67 | 0.81 |
| leg_press | 22 | 0.41 | 0.64 |
| lat_pulldown | 14 | 0.43 | 0.93 |
| rowing_machine | 18 | 0.61 | 0.89 |
| treadmill | 25 | 0.72 | 0.80 |

The Scan tab shows the **top 3** candidates, so top-3 is the number that
describes the user experience: roughly 5 of 6 photos put the right machine
on screen. `leg_press` is the weak class (top-3 0.64) — most confusable with
`bench` and `squat_rack` in crawled photos.

**This is a v1 trained on web images, not gym photos.** Real-world accuracy
will be lower than these numbers: crawled photos are catalogue-style (clean
background, full machine in frame) while users shoot at odd angles in
crowded gyms. Treat the table as an upper bound.

### A leak this pipeline already caught once

The first run reported 0.774 and it was **wrong**. `image_dataset_from_directory`
shuffles the file list using `seed` before slicing, so passing different
`shuffle` flags to the training and validation calls produced two different
orderings — a non-stratified split with train/val overlap. The give-away was
per-class holdout counts showing `0/0` for 8 of 10 classes. `train_export.py`
now passes `shuffle=True` to both subsets and **raises** if any class is
missing from the validation split. Never report a single aggregate accuracy
without the per-class breakdown next to it.

## Label set (order is contractual — index 0 first)

```
squat_rack
barbell
dumbbell
kettlebell
cable_machine
bench
leg_press
lat_pulldown
rowing_machine
treadmill
```

Model label → catalog `equipmentId` mapping lives in
`MlKitVisualEquipmentService._kLabelMap` (note `bench` → `bench_press`).
Adding a class means: retrain with the new label appended, add the row to
`_kLabelMap`, and add the equipment to `assets/data/`.

## Retraining

Pipeline lives outside the repo (it pulls a ~2 GB image corpus):
`D:\tools\equipment-model\` — `crawl_dataset.py` → `crawl_round2.py` →
`clean_dataset.py` → `train_export.py` → `attach_metadata.py`.
Python 3.11 venv at `D:\tools\ml-train-env`.

Two Windows-specific notes for whoever runs this next:

- `tflite-support` has no Windows wheels. The metadata writers still exist in
  `mediapipe.tasks.python.metadata`, but mediapipe 1.0.0 ships them without
  the `_pywrap_metadata_version` C extension; `attach_metadata.py` stubs that
  module (it only stamps a version string).
- If HTTPS interception is active (corporate proxy / Norton "Web Shield"),
  `pip` needs a CA bundle that includes the interceptor's root, otherwise
  every install fails with `CERTIFICATE_VERIFY_FAILED`.

## Improving v2

Biggest wins, in order: real gym photos at user angles (the current corpus is
catalogue imagery), more `leg_press` / `lat_pulldown` / `kettlebell` samples,
and hard-negative mining for the bench/leg-press confusion.
