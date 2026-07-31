# Video hosting

Putting the 677-file exercise library somewhere the app can fetch it, and
pointing the catalog at it.

Nothing here has been run. The library is **not uploaded** and the catalog still
points at `VIDEO_HOST_PLACEHOLDER`, so 343 exercises show their photographs.
That is deliberate: uploading is the first thing this app does that costs money
and puts content on the public internet, and the licence question below is open.

---

## The numbers, measured

| | |
|---|---|
| Files | 677 |
| Unique exercises | 359 (343 reach the catalog) |
| **Total size** | **0.686 GB** |
| Mean clip | 1.01 MB |
| Median clip | 0.59 MB |
| Largest clip | 22.9 MB |
| Wasted on byte-identical duplicates | 14.3 MB across 16 groups |

## The two options, priced from the vendors' own pages (2026-07-31)

| | Firebase Storage | Cloudflare R2 |
|---|---|---|
| Free storage | 5 GB | 10 GB-month |
| Free egress | 100 GB / month | **unlimited** |
| Free reads | 50K / month | 10M / month |
| Then, storage | $0.026 / GB | $0.015 / GB-month |
| Then, egress | $0.12 / GB | $0 |

At 0.686 GB and ~1 MB a clip, **both are free and stay free**: Firebase's
100 GB/month is about 100,000 plays. Egress pricing — the thing that usually
decides this — cannot bite at this size, so the deciding factor is effort, and
Firebase wins it: the project, the SDK and the auth are already there.

R2 becomes the right answer if the library grows an order of magnitude, which
is exactly what buying the 2000-video animation pack would do.

## Prerequisites

- A Firebase project with Storage enabled (`traidingbot-b4061` exists).
- `firebase` CLI authenticated, or the Google Cloud console.
- The drop at `D:/Downloads/Video`, unzipped, with its `girl-*/girl/` and
  `men-*/men/` trees intact.
- **A decision about the licence.** These clips came from a public Google Drive
  folder and carry no licence. They are a development scaffold. Publishing them
  on a host is distribution, which is a different act from having them on a
  laptop. See `reference_fitness_exercise_video_sources` in memory: the
  2000-clip pack at exerciseanimatic.com is the licensed replacement, and its
  own terms permit hosting and app use — but it has not been bought, and the
  questions about it have not been answered.

## Dependencies

Python 3 only, standard library. No project imports.

## Preflight

```bash
python scripts/catalog/preflight_video_hosting.py
```

Exits 0 and writes `data/preflight/video_hosting.json` only when every check
passes. Each check exists because of a specific way an upload goes wrong:

1. **Every advertised url has a file.** A missing one is a 404 the user reads
   as "video unavailable" on an exercise that looks fine in the catalog.
2. **Every file is advertised, or is a known exclusion.** An orphan is storage
   paid for and never served. Currently 24, all accounted for: 16 deliberate
   drops (byte-identical duplicates and unidentifiable names, see
   `data/staging/library/UNSURE.txt`) and 8 whose names collide across groups.
3. **Percent-encoding round-trips.** 637 of the 653 urls contain a space. If
   decoding does not return the real filename, the upload mirrors a tree the
   urls cannot address.
4. **No byte-identical duplicates.** 16 groups, 14.3 MB — small, but it is
   storage and bandwidth paid for twice.
5. **Total size against the free tier.**

### Known finding, not repaired

`girl/Weighted Leg Extension Crunch.mp4` exists under both `Abs` and `mix`
**with different content**. The builder keys an exercise by the file's stem, so
the second silently replaces the first and one real demonstration is discarded.
Deciding whether those are two exercises or one mislabelled clip needs someone
to watch both; guessing is how a catalog fills with confident errors. The
preflight reports it and does not fail on it — the exercise still ships with a
video.

## Launch

Upload preserving the tree, so the paths the catalog already advertises resolve:

```bash
# Firebase, from the drop root
firebase storage:upload "girl-*/girl"  --project traidingbot-b4061 --to exercises/girl
firebase storage:upload "men-*/men"    --project traidingbot-b4061 --to exercises/men
```

Then point the catalog at it — one command, reversible:

```bash
python scripts/catalog/set_video_host.py https://<bucket>.firebasestorage.app/exercises
python scripts/catalog/set_video_host.py --reset     # undo
```

## Monitor

Two tests are written to FAIL the moment a host exists. They are notes left for
whoever sets it, not regressions:

- `video_library_test.dart` — "the host is still a placeholder"
- `exercise_video_test.dart` — "the whole shipped catalog is unplayable right now"

When they fail: confirm `ExerciseItem.playableVideoFor` returns urls, confirm a
clip actually plays on a device, then rewrite both tests to describe the new
state. Do not delete them — replace the assertion, keep the reason.

Then watch the Firebase console's Storage → Usage tab for the first week.
Egress is the only number that can start costing money, and 100 GB/month is the
line.

## Cleanup

```bash
python scripts/catalog/set_video_host.py --reset
firebase storage:delete exercises --project traidingbot-b4061   # confirm first
```

Deleting the bucket contents is safe: the drop is on disk and the upload is a
plain directory copy.
