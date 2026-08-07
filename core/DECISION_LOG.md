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
