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

The catalog the user sees is **1,887 vendor exercises + 186 legacy**, all
licensed, all animation.

---

## Still open — your call, not mine

1. **The public bucket is still up.** `traidingbot-b4061-videos-eu`, 677
   unlicensed clips, `allUsers` can read. Nothing in the new build points at it,
   but builds already installed (1.0.0+14) do — pulling it breaks their clips.
   Needs your word; see the proposal in chat.

2. **325 hidden legacy exercises.** Many are probably recoverable: the exact
   and subset passes only ever compared names, and the 13 replacements above
   prove how badly that reads. A proper pass over the remaining 268 (82 fuzzy,
   186 no-match) against the vendor's 2,540 clips is its own gate.

3. **The machine header photograph.** `equipmentHeroImageProvider` still draws
   `imageUrls.first` then `frames.first` — photographs from free-exercise-db.
   They are public-domain, so this is not a licence question; it is whether
   "only animation" covers the machine header too. Not mine to decide.
