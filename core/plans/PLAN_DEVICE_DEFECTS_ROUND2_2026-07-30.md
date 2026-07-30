# Device-defect round 2 — five operator reports (2026-07-30)

Second round of on-device feedback, after the nine defects fixed in
`PLAN_DEVICE_DEFECTS_2026-07-30.md`. All six gates below are **built, tested and
committed locally**. Nothing is pushed — that needs a separate `push`.

## What was asked

1. Translate the exercise instruction text into Russian.
2. Stop opening the system camera for recognition; keep capture inside the app.
3. In live mode the camera window is a black square — it must always show what
   the camera sees.
4. Make the muscle map look like a real anatomical chart (two reference images
   supplied).
5. Search for the most detailed sources of "which muscles work on which machine
   + animation + instructions".

## Gates as built

| Gate | Commit | What landed |
|---|---|---|
| A | `c920395` | 66 exercises / 301 steps in Russian via a text-only overlay; one shared answer for "what language is the user reading" |
| A2 | (see log) | 51 more ARB keys incl. interpolated strings; About page; three l10n-pipeline bugs fixed |
| B1 | `099dc40` | In-app `takePicture()`; reactive camera-ready preview; camera leak + latch + watchdog |
| E | `c0cabd5` | Attribution surface — a precondition for shipping C |
| C | `8ed19eb` | Real anatomical artwork, recoloured per muscle |
| D | (this) | Premise refuted by measurement; improved the two-frame cadence instead |

## Decisions worth not re-deriving

### The exercise translation is an overlay, not a second catalogue

`assets/data/exercises.ru.json` carries only `title` + `steps`, keyed by exercise
id, patched over the untouched English base. Structure — ids, muscles,
contraindications, frames, difficulty — always comes from the base, enforced by
`ExerciseItem.withText`, so a translation cannot add, drop or re-tag an exercise.
`summary` is derived from step one because that holds for all 66 in the base; a
test pins that invariant on the English data so a future catalogue rebuild fails
loudly instead of leaving Russian summaries in English.

Overlay loading is isolated in its own `try`/`catch` block. Every exercise screen
resolves through one repository, so letting a malformed translation throw would
take the catalogue down in *both* languages to deliver a translation.

### Language resolution has exactly one answer

`AppLanguage.system` has no code of its own. Deriving content language from
`language == AppLanguage.ru` would ship a half-translated screen: on a device set
to, say, French, Flutter resolves the interface to `ru` (first in
`supportedLocales`) while that check answers "not Russian". `resolvedLocaleCode`
does what Flutter does, and both `MaterialApp.locale` and the catalogue read it.

`equipmentRepositoryProvider` watches only that code. Watching the whole
`AppSettings` would re-read the bundled catalogue through nine derived providers
on a theme tap.

### The black square was a missing subscription, not a rendering bug

`LiveEquipmentPreview` watched a plain `Provider` whose value never changes and
read `cameraController` as a one-shot field. That field flips part-way through an
async `start()` — invisible to the widget tree. The widget was also `const`, so
even a parent rebuild could not reach it (`Element.updateChild` short-circuits on
an identical const widget). The service now publishes
`ValueListenable<CameraController?>`; the preview watches it *and* the
controller's own `CameraValue`, because "a controller exists" and "it is
initialized" are separate transitions.

### Capture pauses the analysis stream around the shot

Whether `takePicture()` may run concurrently with `startImageStream` is plugin-
and device-dependent. Nothing here needs that to be true, so the stream stops for
the duration of the shot.

### Gate B was cut down from the original plan

The first draft consolidated onto one camera owner and removed `mobile_scanner`.
Agent review found that would: (a) not achieve single ownership without an
unstated service refactor, since the service builds its own controller; (b) make
QR — the cheap default path — pay for NV21 repacking and ML inference it pays
nothing for today, through a code path that has already caused one on-device
incident; (c) trade a shipped native iOS barcode path for one with no iOS mileage
here. **B2 (shared camera session, folding QR in, always-on preview) remains
unbuilt and needs its own GO**, and it needs a structural fix for camera release
first: `/equipment/:id` renders above the shell, so this page is never disposed
and `autoDispose` cannot fire.

### `flutter_body_atlas` cannot be installed here

It requires Dart SDK `>=3.10.8`; this project is on 3.6.0. `flutter pub add`
fails version solving. Upgrading Flutter to get a muscle chart is not a trade
worth making, so the CC BY 4.0 artwork is vendored into `assets/anatomy/`
instead — which also drops three transitive dependencies and any exposure to a
pre-1.0 package being abandoned. Verified against the SHA256 pub.dev publishes
before extraction.

### Highlighting rewrites SVG fills, and that is safe for a specific reason

Every muscle path in the artwork ships `fill="#BDBDBD"`; every non-muscle part
(body underlayer, hands, face) ships `#E0E0E0`. An element's role is therefore
readable without walking the group structure. A test pins that property, because
if an asset update broke it the chart would start tinting faces as muscles.

### `lower_back` is declared undrawable rather than approximated

It means the erector spinae and this artwork does not draw them. Colouring a
nearby muscle would teach the user something false about their own body, so the
chart names such muscles in text underneath instead.

## Gate D: the premise was wrong, and here is the evidence

The plan said to pull animated Everkinetic GIFs from Wikimedia Commons under
CC-BY-SA 3.0. Measured before building:

* `Category:Everkinetic` on Commons: **0 files**.
* `insource:Everkinetic` in the File namespace: 530 hits, some `.gif`.
* Downloaded `Standing-biceps-curl-1.gif` and `Hack-squats-2.gif` and counted
  image-descriptor blocks: **1 frame each**. The `-1` / `-2` suffix is the
  position number, exactly like our `_0.jpg` / `_1.jpg`. Same origin, same
  content, no motion.
* Upstream free-exercise-db: **all 873 exercises have exactly 2 images**. The
  `[:2]` slice in `build_catalog.py` was never dropping anything.

So swapping our JPEGs for those GIFs would add a share-alike obligation and
~300 KB for zero animation. Other candidates, from the same search:

| Source | Verdict |
|---|---|
| Gym Visual | Real animation, **commercial licence required** |
| hasaneyldrm exercises-dataset | Text MIT (10 languages incl. Russian); media is © Gym Visual |
| FitnessDB exercise-animation-dataset | URL **404s** — the "commercial use OK" claim is unverifiable, discarded |
| WorkoutX API | GIFs need a paid plan; network dependency conflicts with offline-first demos |

**Two frames is the ceiling of every free source.** What shipped instead is a
cadence that makes two frames read as a repetition: hold the start position, move
with an eased curve, hold the end position, reverse. The old player cross-faded at
a constant rate on a periodic `Timer`, which reads as a dissolve between two
photographs precisely because neither position is ever *held*.

## Open, and for the operator to decide

* **Buying a Gym Visual licence** is the only route to animation of the quality
  in the reference images. That is a money decision, deliberately not made here.
* **B2** — shared camera session / QR consolidation. Needs its own GO and the
  route-release fix described above.
* **9 strings are still English** because they sit in files with no
  `BuildContext` (seed repositories, `suggestion_builder` reasons,
  `form_classifier` cues) or in an interpolation the extractor cannot prove safe.
  Each needs a per-site design — an enum resolved in the widget layer, or a
  language-aware constructor like `AssetEquipmentRepository`'s. Listed in
  `scripts/l10n/strings_spec.json` under `interpolated`.
* **No on-device run.** Everything here is verified by the 634-test host suite
  and `flutter analyze`; the camera work in particular can only be confirmed on
  hardware. A release build was not produced.
* Pre-existing, unrelated: three `unnecessary_type_check` warnings and one
  `unnecessary_brace_in_string_interps` info in files this round did not touch.

## Test-harness notes worth keeping

* `rootBundle` futures do **not** complete inside `testWidgets`' fake async —
  asset-dependent widget tests need `tester.runAsync`.
* Using `runAsync` in a file that pumps the real `AppTheme` lets `google_fonts`
  fire a real HTTP font fetch, failing the test for unrelated reasons.
* An `AspectRatio` inside an `Expanded` gets a tight width and cannot shrink to
  fit a short box — the ratio has to sit around the whole group.
* Source-level guard tests earn their place here: two boot-breaking l10n mistakes
  had each been made twice, and one of them silently reapplied itself because a
  manual revert left the Russian string in `ru.json`.
