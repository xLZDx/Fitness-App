# Importing the purchased video bundle

Turning the Exercise Animatic Ultimate Bundle into the library the app serves.

**Status, 2026-08-02:** running. Bucket provisioned, functions deployed and
verified 11/11, transcode under way, 815 clips uploaded, catalog matched.

---

## What arrived

All downloads finished 2026-08-01. Six archives, not the three this document
was first written against:

| Archive | Size | Files | Use |
|---|---|---|---|
| `4K UHD 2160P.zip` | 42.0 GB | 2,578 mp4 | **the library** — operator's choice |
| `FULL HD 1080P.zip` | 11.2 GB | 2,576 mp4 | equal-quality source, 4x cheaper to read |
| `HD 720p LOWEST FILE SIZE.zip` | 2.6 GB | 2,576 mp4 | already our target shape |
| `ILLUSTRATIONS.zip` | 2.8 GB | 5,085 jpg | ~2 stills per exercise, mean 547 KB |
| `VERTICAL VIDEOS.zip` | 15.0 GB | 2,571 mp4 | 9:16 — wrong shape for our player |
| `1200+ GREEN SCREEN VIDEOS.zip` | 19.2 GB | 1,413 mp4 | fallback, needs keying |
| `OLDER CHARACTER VIDEOS … ALREADY AVAILABLE IN THE OTHER FOLDERS.zip` | 25 GB | — | **skip** — its own name says so |

2,578 clips matches the 2,579-row name list exactly, so the 4K archive is the
whole library. Twelve folders by muscle group; `Legs` alone is 575.

### Which source, settled by measurement

The 4K is 3840x2160 **60 fps**; the 1080p and 720p are already 30 fps, our
target. Encoding the same three clips from each, on a quiet disk:

```
source     per clip   output      SSIM vs the 4K-derived result
4K          5.6 s     0.235 MB    (reference)
1080p       4.0 s     0.229 MB    0.996 - 0.999
720p        3.9 s     0.283 MB    0.994 - 0.999
```

Re-encoding the vendor's 720p is *larger* than working from 4K, because it
spends bits reproducing the previous encoder's artefacts.

**Using the 4K, per the operator.** The measurement does not show 4K is
wasted — it shows the alternatives land within half a percent of it, at a cost
of about seventeen extra minutes across the whole library. If a re-run is ever
needed and time matters, `FULL HD 1080P.zip` is the drop-in: same names, same
tree, 11 GB instead of 42.

### The illustrations are not posters

5,085 stills at a mean of 547 KB. Bundled posters are ~8 KB each (653 of them
in 5.1 MB), so these are seventy times too large for the APK. They are a
full-screen asset if one is ever wanted; posters keep coming from the clips.

## What it costs to serve as delivered, and why we do not

Measured with `ffprobe` on the delivered files, not assumed:

```
vendor    3840x2160, 60 fps, ~26 Mbit/s, mean 16.7 MB   max 63.2 MB
ours      1920x1080, 30 fps, ~0.77 Mbit/s, mean 1.01 MB
```

The app shows these in a block about 350 logical points wide. Serving the
originals is ~42 GB of objects and 16 MB of phone data per five-second
demonstration, at $0.12/GB egress.

At **720p30 CRF 24** a sample clip goes 16.6 MB -> 0.25 MB. Frames extracted
from both were stacked side by side and are indistinguishable at display size.
Projected whole library: **~640 MB**, against the 686 MB already hosted.

## Coverage, from the real filenames

Not from the vendor's spreadsheet — from what is actually in the archive.

| | covered (exact / our name inside theirs) | + likely (≥66% of our words) |
|---|---|---|
| whole catalog, 511 | 243 (48%) | 79% |
| the 168 with no clip | 49 (29%) | 67% |

**Gender:** 1,802 unsuffixed (male) and 774 `_Female`. So the female half of
the catalog will stay roughly 40% covered, and the app's per-gender
demonstration will keep falling back to the male clip for most exercises.
That is a property of the purchase, not of the import.

**Upper bound on what stays missing: 18 of the 168**, across plyo box,
preacher curl bench, hip abductor/adductor, stair climber, glute kickback
machine, punching bag and T-bar row.

## Four things about the filenames that will bite

Found by listing the archive, and every one is an import bug waiting to happen.
All four are handled in `scripts/catalog/bundle_layout.py`, which is a separate
module from the encoder precisely so 25 tests can hold them without running
ffmpeg over forty gigabytes.

0. **The gender suffix is inconsistently cased.** 551 clips end `_Female`, 211
   end `_female`, one ends `_Male`, and one — `...Inverted Row on floor_female_1`
   — carries a version marker AFTER the gender. A case-sensitive match filed 211
   women's clips as men's; a rule anchored hard to the end of the name filed the
   twelfth. Both were caught before upload, both are the same failure the
   operator explicitly asked to avoid, and both now have tests.

   Final split: **1,800 men, 763 women.** (An earlier count of 1,764 / 775
   quoted to the operator was taken before canonicalisation and is wrong.)

1. **297 files have a leading or trailing space** — `superman .mp4`,
   `box jump  .mp4`. A space at the end of an object key is legal, invisible
   and unforgettable, and Windows cannot store such a name at all. 280 of them
   have no twin, so this is sloppy naming across one batch rather than a marker
   of anything.
2. **17 groups collide case-insensitively** — `Dead Bug.mp4` and
   `dead bug .mp4` are two files for one exercise. **Settled by looking**:
   a frame was pulled from all 34 and stacked in pairs
   (`core/bundle/duplicate_pairs_1.png`, `_2.png`). Every pair is the same
   movement rendered twice — an older character and machine set against a
   newer one. None of the 17 is two different exercises.

   The shape of it: all 17 have exactly one side carrying a trailing space,
   and in 13 of 17 that side is the larger file. So **keep the larger file
   and record the discarded name**; it is the longer render, and 13/17 with
   a visual check beats any rule derived from the filename.

   One pair deserves a second look before the rule is applied blindly:
   `calf raise on hack squat machine` shows two visibly different machines,
   not two renders of one.
3. **No stable ids.** The vendor says so outright and recommends assigning our
   own. We already have that mechanism — it is what built the current library.

Canonicalise on import: strip, collapse whitespace, casefold for matching,
keep the original name only in a mapping file.

## Preflight

Before spending hours of CPU:

```bash
python scripts/catalog/match_vendor_list.py            # whole catalog
python scripts/catalog/match_vendor_list.py --gap      # just the 168
python scripts/catalog/match_vendor_list.py --equipment
```

Check: the coverage numbers still match this document. If they have moved, the
catalog changed under the plan and the mapping needs rebuilding first.

Then a real dry run on 20 clips:

```bash
python scripts/catalog/transcode_bundle.py <src> <out> --limit 20 --jobs 4
```

Confirm mean output size is near 0.25 MB and every file plays
(`ffprobe` exits 0 — a truncated encode fails with "moov atom not found").

## Launch

**Do not extract the archive.** The transcoder reads members straight out of
the zip, one per worker, and deletes each copy after encoding — peak extra disk
is about seventy megabytes instead of forty-two gigabytes.

```bash
# 0. Preconditions: the private bucket and the signing grant.
python scripts/catalog/provision_video_bucket.py inspect   # read-only
python scripts/catalog/provision_video_bucket.py apply
firebase deploy --only functions:clipUrl,functions:clipUrls
python scripts/catalog/verify_clip_signing.py              # must be 11/11

# 1. Transcode straight from the archive. Re-runnable: finished clips are
#    skipped, and a killed run leaves .partial.mp4 files the next run deletes
#    rather than trusts.
python scripts/catalog/transcode_bundle.py "D:/Downloads/4K UHD 2160P.zip" \
    "D:/bundle/720" --jobs 16

# 2. Green-screen only for exercises the white library does not have:
python scripts/catalog/transcode_bundle.py "D:/bundle/green" "D:/bundle/720" --key

# 3. Upload to the PRIVATE bucket. Re-runnable, size-checked, skips in-flight
#    encodes, so it can be run while step 1 is still going.
python scripts/ops/upload_video_library.py --licensed

# 4. Point the catalog at the object keys and fill empty metadata fields.
python scripts/catalog/import_bundle_clips.py           # measure first
python scripts/catalog/import_bundle_clips.py --write

# 5. Posters from the new clips (same script as the current library)
python scripts/catalog/make_posters.py
```

### Measured throughput, on a quiet disk

Every earlier timing was taken while a hundred gigabytes was downloading and
was worthless. Re-measured with nothing else running:

| jobs | per clip | whole library |
|---|---|---|
| 4 | 3.10 s | 2h 12m |
| 10 | 2.54 s | 1h 49m |
| 16 | 2.40 s | **1h 43m** |

Past ten jobs the gain is small — x264 already multithreads, so the ceiling is
not the job count. Mean output 0.29 MB, so ~750 MB for 2,563 clips.

**Do not run the Dart suite during a transcode.** Sixteen ffmpeg jobs starve
the test runner and it dies with "Connection closed before test suite loaded",
which looks exactly like a real failure and is not.

## Monitor

- Output count climbs and mean size stays near 0.25 MB. A sudden jump means
  the scale filter stopped applying.
- No `.partial` files left behind at the end.
- `ffprobe` every output before uploading — one pass, cheap, and the only
  thing that catches a silently truncated encode.

## The licensing change this forced — DONE 2026-08-02

The vendor's written answer permits hosting and streaming **provided users
cannot reach the raw files**: *"users can only view them within your app and
are not given access to the raw files, public storage folders, or permanent
downloadable links."*

The old bucket does not satisfy that: `allUsers` hold `objectViewer` and every
URL is permanent and public. Fine for an unlicensed development scaffold, not
fine for purchased content. So the licensed library went somewhere else.

`traidingbot-b4061-videos-private`, EU, uniform bucket-level access, public
access prevention **enforced** — the licence condition is a property of the
bucket rather than a promise about how we configure it. Catalog entries for
licensed clips are object keys, not URLs, and the app exchanges each for a
15-minute signed URL through `clipUrl` / `clipUrls`. Signing goes through IAM
as the runtime service account, so no private key exists on disk.

Two things were asked rather than assumed, and both mattered:

- **Which account the functions run as.** It is the Compute Engine default
  (`…-compute@developer.gserviceaccount.com`), not the `@appspot` account the
  documentation implies. Granting the wrong one yields a bucket that answers
  nobody with an error that reads like a missing file.
- **Whether the chain actually works.** `verify_clip_signing.py` puts a real
  object in the real bucket, signs it through the deployed function as a real
  signed-in user, opens it, then tries every way a stranger would. 11/11:
  unsigned requests refused, signed URL opens and carries an expiry, anonymous
  callers get 401, traversal / absolute paths / a body that is not girl|men /
  a non-mp4 extension all rejected, batch cap enforced.

Note for anyone re-running this here: Norton Web/Mail Shield terminates TLS to
`cloudfunctions.net` and `run.app` with a CA whose Basic Constraints are not
marked critical, which OpenSSL rejects outright. The verifier detects that,
announces it, and falls back to an unverified transport. The round trips are
real; only this laptop's transport is trusted blindly.

## Cleanup

Keep the source archives until the imported library is verified end to end on
a phone. The vendor's Dropbox link expires and the files are erased after
**30 days** — so an archive copy on local disk plus one on private cloud is
the operator's own responsibility and cannot be recreated later.

## What the import actually bought

Measured against the real archive, not projected:

- **2,578 members → 2,563 objects.** 15 duplicate renders dropped, the loser of
  each recorded in `import_map.json`.
- **243 of the 511 catalog exercises** now point at a licensed clip, on an
  exact or subset name match. 49 of those had no clip at all before, so the
  silent-exercise count falls **168 → 119**.
- **82 more have a fuzzy candidate and none are applied.** Reading the list is
  why: "Barbell Bench Press - Medium Grip" scores 0.67 against "barbell bench
  close grip press", and "Single-Dumbbell Stiff-Leg Deadlift" scores 0.80
  against "deadlift dumbbell leg single". Different exercises. Showing one as a
  demonstration of the other teaches the wrong movement, so they go to
  `core/bundle_import_report.csv` for a human eye.
- **225 sets of tips filled**, and nothing else — steps and muscles were
  already present everywhere, and the importer never overwrites curated text.

**The bundle covers far more than the catalog holds.** 1,899 distinct movements
against our 511. Growing the catalog is the larger prize and a separate
decision: it needs Russian titles, equipment mapping and difficulty for each
new entry, and the vendor's own metadata is only 64-69% filled.

## What is still unknown

- Whether `calf raise on hack squat machine` is one exercise or two — the only
  one of the 17 pairs the frames did not settle. The larger render is kept and
  the plan reports it rather than silently choosing.
- Whether the green-screen archive adds anything the white library lacks.
