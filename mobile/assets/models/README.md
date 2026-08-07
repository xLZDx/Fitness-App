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

## v2 — in progress (2026-08-07)

Not shipped. `equipment_v1.tflite` above is still what the app loads.

**Why v2 exists**: B1 measured v1 against 30 real gym photos
(`core/plans/B1_RECOGNITION_MEASUREMENT_2026-08-07.md`). Its three most
confident answers were all wrong, and all three were machines it has no class
for — an abduction machine as `treadmill` 0.892, a Nautilus shoulder press as
`leg_press` 0.897. Ten classes serving a 69-machine catalogue cannot do
otherwise, and no confidence threshold repairs it.

**What changed**

| | v1 | v2 |
|---|---|---|
| classes | 10, typed by hand in 3 places | generated from `equipment.json` |
| "not mine" | impossible | `none`, a real trained class |
| corpus | 1741 web-crawled catalogue photos | 55,466 crops from CC BY 4.0 Roboflow datasets |
| framing | whole machine, clean background | bounding-box crops — the machine fills the frame |
| test set | a slice of the same crawl | the operator's own 30 gym photos, never trained on |

**Pipeline** (still outside the repo, `D:\tools\equipment-model\`):

`classes.py` → `fetch_roboflow.py` → `train_v2.py` → `eval_on_gym_photos.py`

- `classes.py` reads `equipment.json`, so the label set cannot drift from the
  app again. `bench` and `adjustable_bench` were the same object and are now
  one class.
- `fetch_roboflow.py` pulls only `CC BY 4.0` projects, writes `ATTRIBUTION.md`
  during the download (attribution is a licence condition, and nobody collects
  it afterwards), crops every bounding box, and mines background crops from the
  same photos for `none`. Class names it cannot map are COUNTED and PRINTED —
  that report is what found `chest fly machine` = our `pec_deck`, 1081 crops
  that were being silently dropped.
- `train_v2.py` MOVES classes under 150 images out of the training tree rather
  than filtering them in code, and prints them. That list is the gap, not a
  rounding error.

**Measured against the operator's 30 gym photos — the only real-world test**

18 of the 30 could be labelled with certainty (the machine's name is printed
on it); the other 12 are wide room shots with no single subject and are NOT
graded, because a one-label-per-image classifier cannot be scored on them.
Labels + evidence per frame: `D:\tools\equipment-model\gym_photos_truth.json`.

```
top-3 accuracy on 18 labelled photos: 5/18 (28%)
abstained ('none'):                   10/30 (33%)
top-1 confidence:  min 0.294  median 0.736  max 0.998
```

What v2 fixed and what it did not:

- **Fixed**: the abduction machine that v1 called `treadmill` at 0.892 now
  returns `none` at 0.808. The abdominal machine likewise. Abstention exists
  and works — v1 had no way to say "not mine" at all.
- **Not fixed**: 28% top-3 is not a product. The Nautilus shoulder press is
  `seated_dip_machine`; two treadmill frames are `lat_pulldown` and
  `hack_squat_machine`. The corpus is still catalogue-style crops and users
  still shoot from wherever they stand.
- **Still confidently wrong on the machine with no class**: the abdominal
  machine reads `treadmill` at 0.940 from one angle and `none` at 0.946 from
  another. Abstention is not yet stable under viewpoint.

**Corpus, second pass (v2.1)**

The first pull used a hand-written list of 5 datasets while the coverage
survey had found 36 — which is why `hip_abductor_adductor`, the machine in the
operator's own screenshot, had ZERO crops. The list is now generated:

`discover_roboflow.py` (search) -> `filter_datasets.py` (licence + class
relevance) -> `fetch_roboflow.py`. 112 CC BY 4.0 datasets found, 36 usable
after filtering, 49,574 images.

Two defects found and fixed while doing it, both caught BEFORE any download:

- `map_class` filed 41 datasets' worth of classes as `hip_abductor_adductor`.
  `norm()` strips non-letters, so YOLO's numeric class names (`'0'`, `'1'`)
  and decorative ones (`'=========='`) normalised to the EMPTY string — and
  `'' in k` is true for every k, so each matched the longest key in the index.
  Audited against the 5 datasets v2 was actually trained on: 0 mappings
  changed, so the shipped v2 corpus was NOT contaminated.
- `mine_negatives` took `none` crops from any photo without an annotated box.
  The expanded search reaches helmet, bus, cow-disease and hip-radiograph
  datasets; their backgrounds would all have been filed as "a gym with nothing
  in it". Negatives now come only from photos that contain a machine we
  recognise.

Class counts after the second pass: `hip_abductor_adductor` 0 -> 535,
`elliptical` 128 -> 460, `adjustable_bench` 119 -> 388, `punching_bag` -> 359,
`assisted_pullup_machine` -> 1058.

**Known gaps remaining**

- Still thin: `ab_crunch_machine` 31, `recumbent_bike` 31, `agility_ladder` 11,
  `tricep_extension_machine` 2, `rowing_machine` 2, `rotary_torso_machine` 1.
  `ab_crunch_machine` is the operator's ABDOMINAL machine — the one that reads
  `treadmill` at 0.940. It is the next gap that matters.
- `'Abdominal Bench'` (35 crops) deliberately unmapped: it is a decline sit-up
  bench, neither `ab_crunch_machine` nor `adjustable_bench`. A guess would
  poison whichever class received it.
- `'transformer'` (549), `'inversion_table'` (144), `'dumbell rack'` (158)
  unmapped on purpose — the first is a multi-station rig, the other two have no
  catalogue id, and inventing one files crops under a class with no page.

**The text anchor is the other half of this**

`core/plans/B5b_TEXT_ANCHOR_2026-08-07.md`. On the same 18 labelled frames the
machine's own printed name identifies 18; this classifier identifies 5. The
two compose: the anchor is near-certain when text is in frame and silent
otherwise, which is the opposite failure mode to a softmax that always
answers.

**Do not train on the operator's 30 photos.** They are the only real-world
sample in the project. Spending them on training buys a slightly better model
and destroys the ability to know whether it is better.

## Improving v2

Biggest wins, in order: real gym photos at user angles (the current corpus is
catalogue imagery), more `leg_press` / `lat_pulldown` / `kettlebell` samples,
and hard-negative mining for the bench/leg-press confusion.
