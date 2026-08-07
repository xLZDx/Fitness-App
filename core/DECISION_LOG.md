# Decision log — Fitness App

Append-only. One entry per decision, piece of evidence, or refusal that a
future session (or a human) would otherwise have to re-derive from scratch.

Times are local (Europe/Chisinau) / UTC. Newest at the bottom, so the file
reads forward.

Not here: what the code does (read the code), what changed in a commit (read
`git log` — every commit carries its own plan block), the plans themselves
(`core/plans/`). Here: **why**, and **what was ruled out**.

---

## 2026-08-07 20:00–23:00 local / 17:00–20:00 UTC — B5 measured, B5b added

### Evidence — v2 measured against the operator's own 30 gym photos

`top-3 5/18 (28%)` on the 18 frames that could be labelled with certainty;
`abstained 10/30`. Raw per-frame output and labels:
`D:\tools\equipment-model\gym_photos_truth.json`, evidence for each label
recorded inline in that file.

Rules out: shipping v2 as the answer to "распознавание должно быть
безупречным". It fixed abstention — the abduction machine that v1 called
`treadmill` at 0.892 now returns `none` — and did not fix identification.

Only 18 of 30 frames are gradeable. The other 12 are wide room shots with no
single subject; grading them would have manufactured whatever accuracy I
chose. Stated rather than quietly averaged over 30.

### Decision — the truth labels come from the machine's own printed name

Operator: *«это только для теста, люди будут в произвольном виде все это
фоткать и нужен другой якорь если надо»*.

Correct, and it turned into a feature rather than a caveat. Counting what I
had actually done to label the photos: the printed name identified 18 frames,
the classifier 5. Three times the signal.

Rejected: relying on the decal as a REQUIREMENT. On 12 of 30 frames there is
no legible text at all. The anchor is additive and silent by default.

### Decision — the anchor returns a LIST, not a single answer

Found while writing it: photo `20260730_134401` is a Nautilus Instinct cable
station whose decal lists six exercises. "Longest phrase wins" answered
`shoulder_press_machine` at 0.92 — a confident wrong answer, the exact defect
the gate exists to remove.

Rejected: picking the first/longest and lowering the confidence. A ranked list
already exists everywhere else in this pipeline, and the honest output for "the
text names two machines" is two candidates.

>=3 distinct machines on one placard is a cable station, and saying so is
worth more than listing its exercises. 2 is genuinely ambiguous and is handed
to the classifier.

### Evidence — `map_class` was filing 41 datasets into one class

`norm()` strips non-letters, so YOLO's numeric class names (`'0'`, `'1'`) and
decorative ones (`'=========='`) became the EMPTY string, and `'' in k` is
true for every k — each matched the longest key in the index,
`hipabductoradductor`.

Audited against the 5 datasets v2 was actually trained on: **0 mappings
changed**, so the shipped v2 corpus was not contaminated. Caught before any
download of the expanded set.

### Decision — negatives only from photos containing a machine we recognise

`mine_negatives` took `none` crops from any photo with no annotated box there.
The expanded search reaches helmet, bus, cow-disease and hip-radiograph
datasets. `none` is the class that decides whether the app may say "I don't
know"; filling it with radiographs is worse than not having it.

### Decision — dataset list generated, not hand-written

The hand-written list of 5 is why `hip_abductor_adductor` — the machine in the
operator's own screenshot — had zero crops while the survey said 36 datasets
existed. `discover_roboflow.py` + `filter_datasets.py` regenerate it from the
live API, so the list and the survey cannot disagree again.

### Decision — notification permission moved out of `main()`

It was requested during startup, before the first frame. On Android 13+ a
denial is close to permanent (the system stops re-asking). Now requested in
`scheduleReminder`, where the user has just asked to be reminded of something.

`init()` keeps the warm-up and no longer prompts; `MockNotificationService`
counts prompts so a test can assert launch raises none.

### Decision — `tflite_flutter` removed

Zero imports (`grep -rn "package:tflite_flutter" lib/ test/`), shipping 7.2 MB
of native code per ABI. The bundled model is still TFLite and is loaded by ML
Kit's own interpreter, which is why nothing broke.

Rejected: keeping it "in case". A dependency with no call site is not
insurance, it is weight.

### Finding, NOT fixed — Wear pairing will fail on a release install

`wear/build.gradle.kts` declares no `signingConfig`, so its release build is
debug-signed while the phone's release APK is signed with the upload key. The
Wearable Data Layer pairs on applicationId **and signing key**; the ids match
(`com.fitnessapp.fitness_app.sptr` on both sides) and the Data Layer path
matches (`/workout_state`), so this is the remaining condition.

Not changed here: signing configuration is the "especially explicit GO" class
per `~/.claude/CLAUDE.md`, and this was never part of the rename.

### Self-correction — I claimed the read phrase is shown to the user; it is not

Written in the first draft of `B5b_TEXT_ANCHOR_2026-08-07.md`: «Прочитано на
тренажёре: ABDOMINAL — опознание, которое пользователь может проверить».

Checked before leaving it: `grep -rn "labelHint" lib/` returns only the four
places that WRITE the field. No widget reads it. The claim was false and the
doc is corrected.

First response: named as uncovered rather than silently added or dropped.
**Then built**, in the next turn, once `70d8fd0` was pushed and there was room
for it — `scannerReadOnMachine` in ru + en, rendered in `_Matches`.

Decision inside that: a new `MatchSource` field on `VisualMatch` rather than
rendering `labelHint` whenever it is non-null. The classifier fills the same
field with its own internal label (`treadmill`, `bench`), and captioning that
"read on the machine" is a straight lie. Nothing in the value distinguishes
them, so the source has to be carried explicitly. Default is
`MatchSource.classifier`, so every existing call site keeps its meaning and
only the anchor opts in.

### Verified from data — B3 needs no code change

1887 exercise rows, 2539 image references, **all** pointing at
`assets/posters/`. No remote URLs, no `assets/exercises/`. The catalogue
cannot serve a photo of a person. The operator's screenshots came from a
build predating `88d0759`.

---

## 2026-08-07 23:00–23:30 local / 20:00–20:30 UTC — release build, and a number I got wrong

### Evidence — the release build was broken by the text-anchor dependency

`:app:minifyReleaseWithR8`, "Compilation failed to complete", BUILD FAILED in
5m 41s. Named by R8 itself in
`mobile/build/app/outputs/mapping/release/missing_rules.txt:3-10`: eight
classes, `Options` and `Options$Builder` for chinese / devanagari / japanese /
korean.

The plugin's single `initialize()` can build a recogniser for any of five
scripts; we bundle only latin. R8 treats the dangling reference as a hard
error. Fixed in `2a930c0` with the eight rules copied verbatim.

**Rules out: "the tests are green, therefore the app ships."** 1586 passing
tests say nothing about what minification does to an APK. This defect was
introduced with the dependency in `cda4503` and no test could have seen it —
only a real release build could, which is exactly why the rule requires one.

Rejected: adding the other four ML Kit script artifacts. That grows the APK for
writing systems no decal in the catalogue uses.

Kept deliberately: the older `-dontwarn org.tensorflow.lite.gpu.**`, even
though `tflite_flutter` was removed the same day. `google_mlkit_image_labeling`
embeds TFLite itself and whether the reference survived is unverified. A
needless `-dontwarn` costs nothing; a missing one costs a six-minute build.

### Self-correction — my source-diversity numbers were invented, and wrong

Claimed earlier today, in prose, with no script behind it: *"18 of 54 classes
come from <=2 sources"* and *"`hip_abductor_adductor`'s 535 crops all come from
ONE dataset"*.

Measured (`D:\tools\equipment-model\source_diversity.py`, snapshot in
`diversity_before.json`):

| claimed | measured |
|---|---|
| 18 of 54 classes thin | **6 of 37** have <=2 sources |
| `hip_abductor_adductor` = 1 source | **3 sources**, 66% from the largest |
| — | **0 of 37** classes come from a single source |

Both numbers were worse than reality, which is not the safe direction to be
wrong in either: it would have justified a large indiscriminate download to
fix a problem that is six specific classes wide.

The real concentration, and the actual target for round 2:
`exercise_bike` 97% · `stability_ball` 95% · `calf_raise_machine` 92% ·
`stair_climber` 86% · `captains_chair` 81% · `resistance_bands` 80%.

Root cause of the error: the figure was arithmetic done in my head over a
partial listing and then repeated as if measured. The fix is the script, not
more care — a number quoted twice needs to be reproducible by someone else.

Still true and still the biggest gap: `ab_crunch_machine` — the operator's own
ABDOMINAL machine — has 31 crops and lives in `dataset_v2_thin/`, so it does
not appear in the table at all.

### Decision — round 2 fetches the weak classes, not everything found

Discovery returned 184 datasets / 237,479 images / 72 new. Downloading all of
it is the kitchen-sink move the trading project already proved wrong: more
columns, not more independent hypotheses.

The corrected measurement says the deficit is six dominated classes plus
`ab_crunch_machine`, so round 2 pulls only datasets that cover those, and
prefers sources that are NOT already the dominant one for that class. Adding
5,000 more crops from `gym-equipment-t6kck` raises the count and lowers the
diversity.

`diversity_before.json` exists so the claim "diversity improved" can be checked
against a before, rather than asserted.

### Evidence — the classifier has a ceiling that data cannot raise

`select_targets.py` run against round 1: of the catalogue's 69 machines, **42
are weak** (no data, under 300 crops, <=2 sources, or >=80% from one source),
and **23 of those no Roboflow dataset can fix at all** — `captains_chair`,
`stability_ball`, `stair_climber`, `preacher_curl_bench`,
`multi_hip_machine`, `rotary_torso_machine`, plus most small kit (TRX,
skipping rope, yoga blocks, gymnastic rings, tyre).

This is a supply fact, not a training one: labelled photographs of those
machines are not publicly available. No amount of downloading, epochs or
architecture changes it. The classifier tops out somewhere near 46 of 69.

The printed name does not care how rare a machine is — `MULTI HIP` on a decal
reads exactly like `TREADMILL`. Today's 18-of-18 vs 5-of-18 stops being a
coincidence and becomes the expected consequence.

Caveat kept deliberately: the "23" is measured against round 1's 36 datasets.
Round 2 found 184 candidates and may close some. It cannot close the small kit.

### Decision — v2.1 is NOT embedded, despite "beating" the bar

37 classes (was 29), same 30 photos, same truth file:
`top-3 6/18 (33%)` against v2's `5/18 (28%)`, abstention `15/30 (50%)` against
`10/30`.

The stated bar was "do not embed unless it beats 28%". It beats it by **one
photograph**. At n=18 that is indistinguishable from re-running the same
training with a different seed, and it was bought with a doubling of "I don't
know" — half the operator's frames now get no answer at all.

Rejected: shipping it because the number moved in the right direction. That is
exactly the "beautiful result" the kill-first rule exists to stop.

The app therefore still ships `equipment_v1.tflite` (2026-07-29). The build
delivered tonight has the NEW text anchor and the OLD classifier, and the
operator was told so before testing — otherwise a v1-grade wrong answer would
read as the anchor being broken.

### Self-correction — my own script destroyed the model needed to check that

`train_v2.py` wrote to a fixed path, so the 37-class run landed on top of the
29-class one. The paired comparison — which specific photos changed answer
between v2 and v2.1 — is now impossible; only the two aggregate numbers
survive, and two numbers cannot show whether they moved together or in
opposite directions on different frames.

An hour of CPU to reproduce, and the loss was silent: nothing failed, the file
was simply replaced.

Fixed: each run now writes `out_v2/<classes>c_<UTC stamp>/`, with the stable
`out_v2/equipment_v2.tflite` kept as a copy of the newest so every existing
command keeps working. Named by class count rather than a version number
because the count is what actually differs between runs and needs no
hand-maintained counter — a hand-maintained one is how this collision
happened. v2.1 was moved into `out_v2/37c_20260807_2035/` after the fact.

### Refusal — `D:\tools\equipment-model` is not under version control

`git rev-parse` → `fatal: not a git repository`. The entire pipeline that
produces the model the app ships — `classes.py`, `fetch_roboflow.py`,
`train_v2.py`, `eval_on_gym_photos.py` and tonight's two additions — has no
history and no backup. Two real bugs were fixed in those files today with
nothing to roll back to.

Not fixed here: `git init` in the operator's tools directory is new scope,
outside the "build + А+Б+В" GO. Raised for a decision instead — either version
it in place, or move the scripts (not the datasets) into the app repo.

### Verified — the shipped APK really contains latin OCR

`-dontwarn` suppresses a warning; it does not prove the wanted class survived
minification. Checked inside the delivered APK rather than inferred from a
green build: `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` (10.8 MB),
`.../Latn_ctc/optical/lstm_model.fb` (302 KB),
`.../rpn_text_detector_...mbv2_v1.tflite` (333 KB).

So if the anchor misbehaves on the device, minification is ruled out as the
cause before the search starts.

Cost, recorded because it argues against itself: OCR adds ~11 MB of native
code plus ~1.4 MB of models — more than the 7.2 MB per ABI reclaimed by
dropping `tflite_flutter` the same day.

### Evidence — the round-2 filter run was a total failure that looked like a result

All 184 lookups failed. The script printed a tidy report ending
`classes covered by the usable set (0)`, wrote `datasets_usable_round2.json`
containing `[]`, and **exited 0**. It was reported to the operator as a
finished job before being checked.

Cause, isolated by running the identical request under three interpreters:

```
D:\tools\ml-train-env\Scripts\python.exe        HTTP 200, 58 classes
...\Programs\Python\Python311\python.exe        HTTP 200, 58 classes
D:\test 2\oracle-pdm-loader\.venv\...\python    SSL: CERTIFICATE_VERIFY_FAILED
                                                "Basic Constraints of CA cert
                                                 not marked critical"
```

`python` on PATH resolved to an **unrelated project's venv** whose CA bundle
rejects the Roboflow certificate. `curl` against the same URL answered fine,
which is why "the network is down" was never the explanation. The 28-minute
runtime was 184 x 3 attempts x the retry sleeps — it was counting timeouts,
not working.

Two distinct defects, and the second is the dangerous one:

1. Nothing pins the interpreter, so `python` means whatever PATH says that day.
2. `except Exception: pass` in `meta()` collapsed "the API never answered" into
   the same `None` as "this project does not exist", which the report renders
   as `no metadata` — indistinguishable from a legitimate negative result.

Fixed: `meta()` now returns `(data, error)`; a 404 is a real answer and stays
an ordinary drop, everything else is recorded as a failure. If more than a
fifth of lookups fail the run prints a `RUN FAILED` banner naming the error
kinds, says the selection is not a result, points at a known-good interpreter,
and **returns 1**.

Proven in both directions rather than asserted — same input, same script:
broken interpreter → `RUN FAILED: 5/5`, exit 1; good interpreter → two real
KEEPs, exit 0.

The same probe re-confirmed the morning's `map_class` fix on the exact dataset
that motivated it: `hip-osteo-ylkzl` (hip radiographs), whose class names are
`'=============================='` and a Roboflow export blurb, now maps
`0/4` and is dropped. Before `_MIN_NAME`, both normalised to the empty string
and matched `hip_abductor_adductor`.

Deleted, not left in place: the `[]` output file the failed run wrote. An
empty result file beside a green-looking log is exactly what a fresh session
picks up as data.

The round-2 fetch itself was NOT re-run — the operator postponed the
recognition track to 2026-08-08.
