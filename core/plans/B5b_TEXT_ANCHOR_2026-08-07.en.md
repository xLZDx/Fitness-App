# B5b — Second Machine-Recognition Anchor: Read Equipment Text (English Translation)

**Original:** [B5b machine-text anchor plan](B5b_TEXT_ANCHOR_2026-08-07.md), source Git blob `5a5acff8b439b9caf348af8eb820105daaa5912b`.  
**Date:** August 7, 2026.  
**Scope:** Historical, source-bound implementation and test rationale. It does **not** establish current detector accuracy, current ML Kit API behavior or permission to modify model or training data.

The owner's original response to labeling the 30 gym photos is translated as:

> "These photos are only for testing. People will photograph equipment from arbitrary viewpoints, and we need another way to identify it if necessary."

The exact Russian quote remains unchanged in the [original document](B5b_TEXT_ANCHOR_2026-08-07.md). The author treated it as a concrete need for another recognition feature, not a caveat to ignore.

## Measurement that motivated the text anchor

While labeling the operator's 30 photographs, the source author identified **18** machines **by words printed directly on equipment housings**, rather than by the silhouette or metal frame.

Examples of visible English labels: `ABDUCTION / ADDUCTION`, `PEC FLY / REAR DELT`, `ABDOMINAL`, `Leg Curl`, `SEATED ROW` and `SHOULDER`.

| Method, same 18 known images | Correct identifications |
| --- | ---: |
| 29-class v2 classifier, top-three predictions | **5** |
| Words printed on equipment | **18** |

The source proposed that vendors such as Nautilus, Star Trac, Precor, Technogym and Life Fitness commonly print exercise names on gym machines because the labels also help gym members.

**The number is a historical small-sample observation, not current field accuracy certification.**

## What the anchor is NOT

- It does **not** replace the image classifier.
- It is **not** required for every photo.
- **12 of the 30** images had no readable machine label — including general views of a gym.

The intended design is the opposite of closed-set softmax: **fire rarely and with a strong supporting text cue; otherwise remain silent**. The 10/29-class softmax still produces some prediction even for unknown machines.

## Where the logic belongs

- `mobile/lib/features/visual_equipment/data/machine_text_anchor.dart` — a pure, deterministic function operating on OCR text strings, independent of actual camera, plugin or device; its interesting edge cases are unit-testable.
- `mlkit_text_recogniser.dart` — only the bridge to ML Kit, with no duplicated matching rules.

Do not confuse a passing pure-function unit test with proof that a live scan actually calls the function.

## Three detection rules based on concrete failures

### 1. Brand names must not identify equipment

`NAUTILUS`, `INSPIRATION`, `STRENGTH` and `STAR TRAC` occur on many distinct machines. Without filtering, nearly any photo could be assigned whichever class appears first in the matching table.

### 2. Match whole words, not substrings

`row` must not match the inside of `arrow`, and `ab` must not match the substring within `abdominal`. Loose OCR substring matching can convert an unrelated piece of text into a confidently wrong machine classification.

### 3. A multi-station is not just one of its labeled exercises

A concrete source example was image `20260730_134401`: a Nautilus Instinct cable station with **six different exercise names** printed on one sticker. A naive "longest matching phrase wins" rule chose `shoulder_press_machine` with **0.92** confidence for what was really a **cable station**.

The revised behavior counted **distinct machine categories mentioned by OCR text**, not just the longest string:

| Distinct recognized machine categories in text | Intended result |
| --- | --- |
| **1** | High-confidence text anchor with maximum **0.92** |
| **2** | Two candidates, **0.55** each; the text is not forced to pick one |
| **3 or more** | `cable_machine` at **0.75**; multi-station rather than a single exercise machine |

One image of the **opposite side** of the same station mentioned six exercises but only **two** matched catalogue-known categories. The >=3 rule did not apply, and previous code wrongly selected `chest_press_machine`. Returning **two candidates** was a more honest representation of the evidence.

## Confidence never equals 1.0

The source imposed a **0.92 ceiling**, not certainty. OCR can misread text and a sticker can belong to a nearby machine. Do not fabricate a confidence value absent from actual model evidence.

The document compares this principle to removing unsupported confidence renormalization in `rankTopK`.

## User-visible source attribution

Historical mockup in English:

> **"Read on the machine: ABDUCTION ADDUCTION"**

The text appears under the machine name and displayed score **only when the source is actually printed text**. Users can independently compare it with the label on the physical machine.

### Why displaying `labelHint` alone would be false

The classifier **also** fills `labelHint` with internal labels such as `treadmill` or `bench`. Describing a classifier's internal token as **"read on the machine"** is a false provenance claim. A string's mere presence cannot distinguish the two origins.

The proposed/source implementation added `source` to `VisualMatch`, defaulting to `MatchSource.classifier`; only the text-anchor path sets `MatchSource.printedText`. The UI must test **the recorded provenance**, not merely whether a label hint exists.

**Historical correction within B5b:** An initial draft said the source label was already shown on screen. That was wrong: provenance was set but a source-code search for `labelHint` found only writes, not a rendering read. The UI omission was identified and corrected in the same gate, according to this source. Do not restore the disproven claim as truth.

## Tests recorded in the original

- `test/features/visual_equipment/machine_text_anchor_test.dart`: **21** cases. The original says test strings were transcribed from **actual owner gym photos**, not invented prompts.
- `test/features/visual_equipment/text_anchor_pipeline_test.dart`: **6** integration-style pipeline cases proving the text anchor runs **before** the classifier, prevents redundant classifier calls after unambiguous text, and passes the photo onward when OCR is unavailable, no text exists, no machine name matched, or several machines matched. Also check OCR errors do not break scanning.

The original deliberately required both **pure matching tests** and **actual provider-pipeline tests**: a pure function never invoked by production could pass its isolated tests forever.

## What this does not solve

The text anchor cannot identify machines from a general gym overview or the back of unlabeled equipment. Those frames still depend on the classifier, whose meaningful improvement was tracked under **B5**: more classes, realistic gym angles and an explicit unknown/negative class.

**The two anchors complement each other; neither replaces the other.**

## Integration/performance cost at the source checkpoint

The requested dependency was `google_mlkit_text_recognition`, configured for the Latin alphabet. The source noted that common gym equipment labels in its target market were printed in English even when app UI/owner language was Russian.

In the same source gate, unused `tflite_flutter` was removed from the APK: a search for `package:tflite_flutter` imports under `lib/` and `test/` found none. The unused dependency had bundled `libtensorflowlite_jni.so` (~**3.7 MB**) and `libtensorflowlite_gpu_jni.so` (~**3.5 MB**) **per architecture**. The application still consumed a TFLite model through ML Kit's own interpreter.

This is a historical build-composition observation, not a current dependency size guarantee.

## Translation and test-data boundary

The original operator quotations, **30 photo held-out TEST set**, machine labels, reference image IDs, the three distinct-machine decision rules (**0.92 / 0.55 / 0.75**), all file identifiers and B5/B5b split are preserved. No new camera image, source code, model training, OCR inference, device build, CI test, user data or push action occurred in this translation.

**Status: COMPLETE B5b ENGLISH SOURCE-LINKED COMPANION — reviewer semantic signoff and current-device validation pending.**
