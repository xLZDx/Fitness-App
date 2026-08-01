# Importing the purchased video bundle

Turning the Exercise Animatic Ultimate Bundle into the library the app serves.

**Status, 2026-08-01:** archives arriving. Nothing imported yet. This runbook
exists before the work so the numbers below can be checked rather than
discovered halfway through a 2,500-file job.

---

## What arrived

| Archive | Size | Clips | Use |
|---|---|---|---|
| `4K UHD 2160P.zip` | 42.0 GB | 2,578 | **the library** |
| `1200+ GREEN SCREEN VIDEOS.zip` | 19.2 GB | 1,413 | fallback, needs keying |
| `OLDER CHARACTER VIDEOS … ALREADY AVAILABLE IN THE OTHER FOLDERS.zip` | 25 GB | — | **skip** — its own name says so |
| (one more still downloading) | | | check before starting |

2,578 clips matches the 2,579-row name list exactly, so the 4K archive is the
whole library. Twelve folders by muscle group; `Legs` alone is 575.

**Prefer a 1080p archive over the 4K one if one arrives.** The output target is
720p, so 4K only costs decode time — the result is identical.

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

## Three things about the filenames that will bite

Found by listing the archive, and all three are import bugs waiting to happen:

1. **297 files have a leading or trailing space** — `superman .mp4`,
   `box jump  .mp4`. A space at the end of an object key is legal, invisible
   and unforgettable. 280 of them have no twin, so this is sloppy naming
   across one batch rather than a marker of anything.
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

```bash
# 1. Extract the 4K archive (42 GB in, keep it until the import verifies)
# 2. Transcode. Re-runnable: finished clips are skipped, and a killed run
#    leaves .partial files that the next run deletes rather than trusting.
python scripts/catalog/transcode_bundle.py "D:/bundle/4k" "D:/bundle/720" --jobs 4

# 3. Green-screen only for exercises the white library does not have:
python scripts/catalog/transcode_bundle.py "D:/bundle/green" "D:/bundle/720" --key

# 4. Posters from the new clips (same script as the current library)
python scripts/catalog/make_posters.py

# 5. Upload + repoint
python scripts/ops/upload_video_library.py
python scripts/catalog/set_video_host.py <base-url>
```

**Throughput is not yet measured.** Every timing taken so far was on a machine
simultaneously downloading a hundred gigabytes, which makes them worthless.
Measure on a quiet disk with `--limit 20` and multiply.

## Monitor

- Output count climbs and mean size stays near 0.25 MB. A sudden jump means
  the scale filter stopped applying.
- No `.partial` files left behind at the end.
- `ffprobe` every output before uploading — one pass, cheap, and the only
  thing that catches a silently truncated encode.

## The licensing change this forces

The vendor's written answer permits hosting and streaming **provided users
cannot reach the raw files**: *"users can only view them within your app and
are not given access to the raw files, public storage folders, or permanent
downloadable links."*

The current bucket does not satisfy that. `allUsers` hold `objectViewer` and
every URL is permanent and public — which was fine for an unlicensed
development scaffold and is not fine for purchased content.

**Before any licensed clip is uploaded**, the bucket has to move to signed URLs
with an expiry, and the app has to fetch them through a Cloud Function rather
than embedding them in the catalog. That is a real piece of work and it is a
precondition, not a follow-up.

## Cleanup

Keep the source archives until the imported library is verified end to end on
a phone. The vendor's Dropbox link expires and the files are erased after
**30 days** — so an archive copy on local disk plus one on private cloud is
the operator's own responsibility and cannot be recreated later.

## What is still unknown

- Throughput on a quiet machine.
- Whether the last archive is 1080p horizontal (preferred source) or the 9:16
  vertical cut (wrong shape for our player).
- Whether `calf raise on hack squat machine` is one exercise or two — the
  only one of the 17 pairs the frames did not settle.
