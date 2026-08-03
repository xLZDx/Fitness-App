# Hybrid catalog gates — state, 2026-08-03

Written mid-run so a fresh session resumes without re-deriving anything. The
operator's decision: keep our 511 with all their metadata, add the vendor's
1,899 alongside, make the legacy half switchable off, and show no photographs
anywhere.

Standing instruction on matching, given 2026-08-03 and not yet exercised:
**compare by meaning and content, not string equality. On any doubt, pull a
frame from both clips, look up what the exercise actually is, then decide — and
keep the findings so the operator can check them later.**

---

## H1 — done, committed `88d0759`

An exercise the app cannot play is an exercise the app does not show.

- `withDemonstration` in `exercise_filter.dart`, applied at `allExercisesProvider`
  and `recommendedExercisesProvider` — the two providers every list reads.
- Player shows a clip or the honest "no video" card. Both photograph branches
  removed; `ExerciseDemo` deleted as dead code.
- Legacy catalog 511 → 365 shown. The 146 are hidden, **not deleted**.
  (365 → 186 later the same day, when the unlicensed scaffold came out — see
  the licence-audit section below.)
- 1002 tests, 0 failures.

**Do not "fix" the 146 by cutting them.** Measured: 52 have a vendor candidate
I declined, and of the 94 with no candidate, a direct search of the archive
finds most under different phrasing (`Alternating Renegade Row` ↔ `dumbbell
renegade row`, `Barbell Hack Squat` ↔ `hack squat machine`, `90/90 Hamstring` ↔
`90 to 90 stretch`). Genuinely absent from the vendor: chains, harness sled
drags, Rocky pull-ups, kettlebell press, treadmill incline walk. A handful.

## H2 — in progress

Built and on disk:

- `scripts/catalog/build_vendor_catalog.py` → `mobile/assets/data/exercises_vendor.json`,
  1,899 entries, 2.56 MB. Every one has a clip. 640 have both bodies.
  1,715 carry a muscle tag; 184 deliberately carry none (Calisthenics,
  Powerlifting, Stretching, Yoga name no muscle honestly).
- `AssetEquipmentRepository` loads both catalogs through one `_loadCatalog`,
  same translation-overlay contract for each.
- `includeLegacy` flag on the repository — **H3's switch already exists at the
  data layer**; what is missing is the setting and the UI that flips it.
- `ExerciseItem.equipmentLabel` + `needsEquipment`. The vendor has no machine
  ids, so all 1,899 had `equipmentId == null` and the "at home" filter — which
  selected on exactly that — offered barbell squats as bodyweight work. The
  filter now asks `needsEquipment`.

Running when this was written:

- `translate_vendor_catalog.py` → `exercises_vendor.ru.json`. Gemini 2.5 Flash
  on Vertex, borrowed Firebase CLI token, no key on disk. Resumable: rerun the
  same command to continue. Rejects any batch that changes the step count.
- `make_vendor_posters.py` → ~2,498 stills at 5.3 KB, about 13 MB added to a
  241 MB APK.

Known outstanding in H2:

1. Two clips are missing from `D:/bundle/720` — the `..._1` / `..._female_1`
   pair. The transcode ran before the gender-suffix fix, so the girl copy sits
   under the men's key. Re-run `transcode_bundle.py` (it resumes) and re-cut
   those two posters.
2. Tests for the two-catalog load, the `includeLegacy` switch and
   `needsEquipment`.
3. Upload is done — all 2,563 objects are already in
   `traidingbot-b4061-videos-private`, verified 0 missing.

## H3 — switch to drop the legacy 511

Data layer done (`includeLegacy`). Needs a setting, a provider override and a
Settings row. With it off the catalog is 1,899, all animated, all vendor.

## H4 — Russian

Operator: mandatory, translate now, hide nothing. Running. Titles read like a
gym rather than a dictionary (`Скручивания на 3/4`, `Чатуранга на трёх точках
опоры`).

## H5 — the scanner, rewritten. DONE (data + flow + screen)

Operator's own framing, which replaced mine:

- In the catalog → show the catalog straight away.
- Not in the catalog → explain what the machine is and what can be done on it,
  and **save a machine card** so we can add a clip and details later.
- Record what people photograph and what the AI identified.
- Where we have no content, point the user at an outside video meanwhile.
- The card is **visible to the user**, marked "контент готовится" — not a
  silent bug report for us.

Not "find the nearest match among our 52 machines" — that was my reading and it
was wrong.

**The card** — `data/machine_card.dart`, 14 tests. One machine is one card (the
id normalises case and punctuation, Cyrillic survives); `uses` is plain text,
never exercise ids, because there are no clips for these and inventing entries
walks back into H1's rule; status defaults to `preparing`.

**The second question** — `data/machine_describer.dart`, 20 tests. Asked only
when recognition returned nothing, about the same photo, and it offers no list
to choose from: the classifier's 48-machine list exists so the model cannot
invent a page we do not have, and here there is no page by definition. The
model is given an explicit `isGymEquipment: false` and it is believed, or the
answer to a photo of a dog is a confident description of a rowing machine.
Failure is quiet — the user has already been told the machine is not in the
catalog, and a second error where a result used to be helps nobody.

`firebaseCloudAsk` in `gemini_equipment_service.dart` is now shared by both
questions. Not tidiness: the "thinking disabled" setting is what took a photo
from 25-31s to 2-5s, and a second copy of that config is a second place for
that regression to come back.

**The store** — `data/machine_card_repository.dart` (+ Firestore twin), 20
tests. Merge rule in one place, as `RecognitionDedup` already is, so the two
backends cannot disagree. Two rules carry weight: a second shot within five
minutes does not raise the count (the count decides what gets filmed first, and
re-shooting a blurry frame is one encounter), and a status already decided —
`inCatalog`, `declined` — survives a new photo instead of putting a shipped
machine back under «готовится».

Stored at `users/{uid}/machine_cards/{id}`, which the existing
`match /users/{uid}/{coll}/{document=**}` rule already covers — no rules
change. A shared world-writable collection would have served us more directly
and bought nothing: the same numbers come out of a collection-group read with
the Admin SDK. `photoPath` is not written: it is a path in one device's cache,
meaningless anywhere else, and the only version worth storing is the image
itself — which is a decision about the user's pictures leaving their phone, not
a detail of a write.

**The screen** — `widgets/machine_card_view.dart` + `_PreparingSection` in the
scanner, 10 flow tests. Photo, name, «контент готовится», what it is, what you
can do on it, and a YouTube search for it. Kept out of the "мои тренажёры" row
of chips: those lead to exercises and these do not yet, so mixing them makes a
chip a coin flip between a workout and a dead end.

1085 tests, 0 failures. `flutter analyze`: 6 issues, all in files this gate did
not touch.

Not done here, and worth naming: `_attempted` in the scanner is widget state
that duplicates what the controller already knows. It works; it is the kind of
duplication that goes wrong later.

## After H5 — the licence audit that the 48 turned into

Reviewing the 48 subset candidates surfaced something bigger than the 48:
**324 of the 511 legacy entries were still serving clips from the unlicensed
Drive scaffold**, over a bucket that grants `objectViewer` to `allUsers`. 101
of them were half-converted — one body licensed, the other not — which is why
`526dfcf`'s "142 exercises play licensed clips" was true and still misleading.

Full write-up, with the frame-by-frame reasoning for each of the 48:
`core/CLIP_LICENCE_AUDIT_2026-08-03.md` (+ CSV twin, + `core/subset_verdicts.csv`).

Shipped with it: `relicense_legacy_catalog.py`, `sweep_orphan_posters.py`,
`match_legacy_semantic.py`, `set_scaffold_bucket_public.py`.

Then the operator's four answers, all done the same day:

1. **Bucket off, not deleted.** `allUsers` binding removed; anonymous GET on a
   clip returns 403; the 677 objects are untouched and `--on` restores it.
2. **Match everything.** Every remaining exercise re-asked by MEANING, not by
   filename — 151 recovered. Legacy catalog 142 → 186 → **337 of 511**, and
   0 unlicensed at every step.
3. **The header is the clip's poster**, not a free-exercise-db photograph.
4. Pushed.

498 poster stills were deleted along the way (2.9 MB) because a poster is cut
from its clip, so a still of an unlicensed clip is unlicensed footage in the
APK.

## Not touched, waiting on the operator

- 48 subset candidates in `core/bundle_import_report.csv`. Applying them is
  `import_bundle_clips.py --write --include-subset`.
- 8.1 MB of bundled photographs are unreachable since H1 but still shipped.
  Deleting them means stripping `frames` from the legacy catalog, which the
  machine header image still reads.
- H1-H5 are on `origin/master`, head `92675ca` (pushed 2026-08-03 16:12 local
  (Europe/Chisinau) / 13:12 UTC). SHA-explicit, because the checkout is shared
  with other agent processes.
