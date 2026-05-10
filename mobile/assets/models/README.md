# Bundled ML models

Drop the TFLite model file `equipment_v1.tflite` here once the visual-
recognition model is trained. The Flutter side
(`MlKitVisualEquipmentService`) loads it via ML Kit's
`LocalLabelerOptions`, expecting the file to be available at runtime
under the app's documents directory (the bootstrap copies it from
assets on first launch — see `core/asset_bootstrap.dart`).

## Generating a v1 model (free workaround)

Until we train a custom dataset, two free off-the-shelf options work
as drop-in replacements:

1. **Teachable Machine** (https://teachablemachine.withgoogle.com/) —
   record 30 photos of each of the 10 equipment classes listed in
   `MlKitVisualEquipmentService._kLabelMap`, hit Export → TFLite,
   download `model.tflite` and rename to `equipment_v1.tflite`.

2. **MobileNetV2 imagenet starter** with our 10-class fine-tune. Use
   the Google "Image Classification with TFLite Model Maker" notebook:
   https://www.tensorflow.org/lite/models/modify/model_maker/image_classification

The label set our service expects (one label per line, in this order):

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

The label index 0 must correspond to the first row, etc. — ML Kit
expects the model's softmax output to be aligned to a `labels.txt`
file, but with a single-class-per-output TFLite model we don't need
to ship one separately because we map by string in
`_kLabelMap`.

## Why no model in git?

A trained model is 4–15 MB binary. Keeping it out of git keeps clones
fast; the `asset_bootstrap` falls back to the on-device mock when the
file is missing so the app still ships without a hard dependency on
the model.
