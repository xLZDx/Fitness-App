# The legacy catalog was still serving unlicensed footage — audit and repair

2026-08-03. Written because the operator asked that findings be kept so he can
check them later: *"а находки сохрани чтобы потом показать мне если что то
будет не так"*.

CSV twin: `core/CLIP_LICENCE_AUDIT_2026-08-03.csv`.
Per-exercise verdicts: `core/subset_verdicts.csv`.

---

## What was found

The catalog's clips came from two different places and only one of them is
licensed.

`traidingbot-b4061-videos-eu` holds 677 clips and grants
`roles/storage.objectViewer` to `allUsers` — world-readable, permanent URLs.
My own commit `e233eb0`, written before the animation pack was bought, says
what they are:

> these clips came from a public Drive folder and carry none [no licence].
> They are a development scaffold; the 2000-clip pack whose terms DO permit
> hosting has not been bought.

The pack was bought and imported afterwards (`526dfcf`). The scaffold was never
taken back out.

### This was written down two days ago and then dropped

`core/VIDEO_SOURCES_RESEARCH_2026-08-01.md` §3, under a heading that reads
*"This is the most important thing in this report and it was not in the
original question"*:

> Buying a licensed source for 168 while 343 unlicensed clips remain in
> `traidingbot-b4061-videos-eu` leaves the app **exactly as unshippable as it
> is today** — the exposure is per-file […] the correct scope is: buy once,
> then **re-point all 511 rows** at licensed assets and purge the old bucket
> contents.

The pack was then bought, the import was run against exact name matches only,
and the re-pointing of the other 369 rows never happened. So this audit is not
a discovery — it is the same finding, verified this time against the bucket's
IAM policy and the catalog rather than against a memory note, and acted on.

### A claim of mine that was too kind to itself

Commit `526dfcf` says *"142 exercises play licensed clips"*. True, and it hid
the more useful fact. The importer fills one body at a time and nothing ever
checked the other, so:

| | count |
|---|---|
| fully licensed | 41 |
| **mixed — one body licensed, the other scaffold** | **101** |
| fully scaffold | 223 |
| no clip at all | 146 |
| **total serving unlicensed footage** | **324** |

### The posters were the same problem, one layer down

`ExerciseItem.poster` documents itself: *"Cut from the clip itself, so the
poster IS the video's first frame"*. So 528 bundled stills were frames of
unlicensed animation, shipped inside the APK.

---

## The 48 subset candidates, judged

These had been waiting for an eye since `526dfcf`. Judged by what the clips
show, not by their filenames, per the operator's standing rule: compare by
meaning, and on any doubt pull a frame from both clips and find out what the
thing actually is.

| verdict | n | meaning |
|---|---|---|
| accept | 31 | the name-matcher's pick was right |
| **replace** | **13** | a DIFFERENT vendor clip is the correct one |
| reject | 4 | no clip in the library is this exercise |

**The 13 replacements are the reason this could not be applied blind.** The
matcher chose by word overlap, and in every one of these the right clip was
sitting in the same library:

| exercise | matcher chose | actually correct |
|---|---|---|
| Push-Up | Archer push up | **Normal Push-up** |
| Pullups | Kipping Pull Up | **pull up normal grip** |
| Military Press | military press bodyweight | **Barbell Standing Military Press** |
| Lying Leg Curls | bodyweight lying leg curl | **lying leg curl machine** |
| Barbell Shrug | Barbell Silverback Shrug | **barbell shrugs** |
| Dumbbell Shrug | Dumbbell Silverback Shrug | **dumbbell shrugs** |
| Front Plank | Unilateral Front Plank | **plank on elbows** |
| Dumbbell Fly | Dumbbell floor Fly | **dumbbell fly flat bench** |
| Dumbbell Lunge | Dumbbell Curtsy Lunge | **Dumbbell Lunge Alternating on the spot** |
| Dumbbell Deadlift | Dumbbell Staggered Deadlift | **Dumbbell close Legs Deadlift** |
| Kettlebell Deadlift | Kettlebell Staggered Deadlift | **Single Kettlebell Deadlift** |
| 45-Degree Hyperextension | 45 degree twisting hyperextension | **45 degree hyperextension arms to chest** |
| Leg Press | Horizontal Leg Press | **leg press machine normal stance** |

Frames settled four of these where the names could not:

- **Barbell Shrug.** "Silverback" is a **bent-over** shrug — the frame shows a
  hinged torso and a bar at knee height. Nothing like a standing shrug.
- **Leg Press.** What we were *already showing* was a Smith machine with
  someone on the floor pressing the bar. The vendor's is a 45° sled.
- **Close-Grip Dumbbell Press.** The candidate is a **sit-up** while pressing
  overhead; ours is a press lying on a bench. Rejected — the library has no
  dumbbell close-grip bench press.
- **Dumbbell Incline Hammer Press.** The candidate is a **shoulder** press;
  ours is an incline chest press. Rejected — no incline hammer chest press
  exists in the library.

The other two rejections: **Recumbent Bike** (the library has no recumbent or
upright stationary bike at all, only air/assault bikes) and **Reverse-Grip
Pull-Up** (the candidate was a lat *pulldown*; no plain supinated pull-up
exists, only close-grip and narrow-parallel).

---

## What was done

1. `scripts/catalog/relicense_legacy_catalog.py` — applies the 48 verdicts,
   then removes every remaining `http` clip reference.
2. `scripts/catalog/sweep_orphan_posters.py` — drops poster references with no
   clip behind them and deletes the stills, across both catalogs (they share
   `assets/posters/`).

| | before | after |
|---|---|---|
| legacy entries with a licensed clip | 142 (101 only half) | **186** |
| legacy entries serving unlicensed footage | 324 | **0** |
| legacy entries hidden by H1 (no clip) | 146 | 325 |
| poster stills on disk | 3,256 | 2,758 |
| APK weight from posters | 15.2 MB | 12.3 MB |

(Those two figures move again in round two below: 186 → 337 and 325 → 174.)

---

## Round two — every remaining exercise re-matched, by meaning

`scripts/catalog/match_legacy_semantic.py`. The importer's name matching is what
put `Archer push up` behind "Push-Up", so this shortlists 30 candidates by name
and then asks the model which one IS the exercise, given our title AND our own
instructions — the steps describe the movement, which a filename cannot.

`none` is always an offered answer and the prompt says so twice, because a model
asked to choose from a list will choose from the list.

The importer's `disqualifying()` guard still runs, but here it **flags rather
than rejects**. It was written against a heuristic with no idea what an exercise
was, and against a reasoned answer it produces false alarms — it blocked
`Calf Press On The Leg Press Machine → Calf raise leg press machine` for adding
the movement "raise", and `Narrow Stance Leg Press → leg press machine close
stance` for adding the equipment "machine", when a leg press IS a machine. A
guard hit means the two judgements disagree, which is where to look at a frame.

| | n |
|---|---|
| matched | 151 |
| no clip in the library is this exercise | 162 |
| flagged by the guard, judged by hand | 90 → 79 accepted, 9 rejected, 2 overridden |

The 9 I rejected on review: Rocky Pull-Ups (alternates front and behind the
neck), Stride Jump Crossover, Smith Incline Shoulder **Raise** (matched to a
press), Rocking Standing Calf Raise, Reverse Band Box Squat and Box Squat with
Chains (accommodating resistance is absent), Reverse-Grip Pull-Up (the candidate
is wide grip), Bench Sprint (matched to step-ups), Cable Standing Lift.

Two overrides: "Row Intervals" and "Steady Row" had been matched to a **seated
row machine**. They are ergometer cardio, and the library has
`Gym Rowing Machine Fast/Normal Speed`.

Result: **186 → 337 of 511 legacy exercises play a licensed clip.** Per-exercise
in `core/legacy_match_proposals.csv`.

## The machine header is the clip's poster now

Operator: *"фото должно быть превью ролика"*. `equipmentHeroImageProvider` read
`imageUrls` then `frames` — photographs from free-exercise-db. Properly
licensed, so never a legal problem; it was the last place in the app still
showing a photograph while everything else showed a 3D render. It now reads the
poster, which is cut from the clip itself, and a machine with no clip gets no
header rather than a stand-in. 5 tests.

## The scaffold bucket is off

Operator: *"отключаем а не удаляем"*. The `allUsers` binding is removed from
`traidingbot-b4061-videos-eu`; the 677 objects are untouched. Verified: an
anonymous GET on a clip returns **HTTP 403**.
`scripts/catalog/set_scaffold_bucket_public.py --on` restores it in one command
— which matters for one reason: a build already on a phone (1.0.0+14) still
holds the old catalog and its clips stopped loading the moment this ran.

## Still open — your call, not mine

1. **174 legacy exercises still have no clip.** 162 because no clip in the
   purchased library is that exercise (sleds, chains, harnesses, recumbent
   bikes, Rocky pull-ups), 12 because a model batch failed twice and was
   skipped rather than guessed at. Re-running the matcher picks the 12 up.

2. **The 677 objects still exist**, just unreachable. Deleting them is a
   separate decision and is not reversible.

3. **`frames` and `imageUrls` are still in the catalog** — 66 and 94 entries.
   Nothing reads them any more. Removing them is a data cleanup worth doing
   when something else touches that file.
