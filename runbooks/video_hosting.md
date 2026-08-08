# Video hosting

Putting the 677-file exercise library somewhere the app can fetch it, and
pointing the catalog at it.

**Done, 2026-08-01.** 677 objects live in
`gs://traidingbot-b4061-videos-eu/exercises`, the catalog points at them,
and four clips were fetched anonymously — `206 Partial Content`, `video/mp4`,
including a filename carrying spaces and brackets. Range requests answer, which
is what a player needs to seek.

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

## What it costs, priced from the vendors' own pages

| | plain GCS bucket (chosen) | Firebase Storage | Cloudflare R2 |
|---|---|---|---|
| Free storage | 5 GB always-free | 5 GB | 10 GB-month |
| Free egress | none — see below | 100 GB / month | **unlimited** |
| Then, storage | $0.020 / GB | $0.026 / GB | $0.015 / GB-month |
| Then, egress | ~$0.12 / GB | $0.12 / GB | $0 |

0.686 GB of storage is free on all three. Egress is where they differ, and the
chosen option has the smallest allowance of all: GCS's always-free 1 GB/month
of egress applies to **North America only**, and this bucket is in
`europe-west1`. So every byte served is billed, at roughly $0.12/GB — about
twelve cents per thousand plays at this library's ~1 MB average.

That is deliberate and it is the correct trade. The bucket sits in Europe
because the phone is in Moldova: the first version put it in us-central1 to
match the project's Cloud Functions buckets, which was tidy and wrong —
functions are called by other Google services, video is fetched by a person
waiting for a clip to start. Measured from this machine, europe-west1 answered
in ~220 ms against ~350 ms from us-central1. Paying twelve cents a thousand to
remove a third of the start-up wait is not a close call.

R2 is the endgame if this ever carries real traffic, and moving is one
constant — which is exactly what buying the 2000-clip animation pack would
make worth doing.

## Prerequisites

- Firebase CLI logged in. Nothing else: `scripts/ops/firebase_api.py` mints an
  access token from the refresh token the CLI already stored. No `gcloud`, no
  browser, and no downloaded service-account key — a long-lived secret on disk
  for a job that does not need one.
- The drop at `D:/Downloads/Video`, unzipped, `girl-*/girl/` and `men-*/men/`
  trees intact.

## Why a plain bucket and not Firebase Storage

Firebase Storage's default bucket requires the project's **default resource
location**, and `traidingbot-b4061` has never had one — its `resources` block
holds a hosting site and nothing else. That setting is permanent: it decides
where Firestore and Storage data live for the life of the project, and Google
provides no way to change it. Settling that as a side effect of hosting some
demonstration clips would be deciding something much larger than the task.

A plain bucket needs no such choice, deletes in one command, and gives the app
what it actually needs: an HTTPS url a video player can open. The Firebase SDK,
security rules and console are all things public demonstration footage does not
use — so `storage.rules` was deleted rather than left in the repo pretending to
govern a bucket it has no authority over. Access is IAM: `allUsers` hold
`objectViewer`, which reads objects and cannot list, write or delete.

**The cost difference, stated rather than hidden.** The Firebase-managed bucket
would have given 100 GB/month of free egress. A plain bucket's always-free tier
is 1 GB/month from North America — about a thousand plays at this library's
~1 MB average. Past that the project is on Blaze and egress bills around
$0.12/GB, so the next thousand plays cost about twelve cents. If that ever
stops being the right trade, the answer was never Firebase: Cloudflare R2 has
free egress at any volume, and moving is one constant.

## Preflight

```bash
python scripts/catalog/preflight_video_hosting.py
```

Exits 0 and writes `data/preflight/video_hosting.json` only when every check
passes. Each exists because of a specific way an upload goes wrong:

1. **Every advertised url has a file.** A missing one is a 404 the user reads
   as "video unavailable" on an exercise that looks fine in the catalog.
2. **Every file is advertised, or is a known exclusion.** An orphan is storage
   paid for and never served. Currently 24, all accounted for: 16 deliberate
   drops (byte-identical duplicates, unidentifiable names — see
   `data/staging/library/UNSURE.txt`) and 8 whose names collide across groups.
3. **Percent-encoding round-trips.** 637 of the 653 urls contain a space.
4. **No byte-identical duplicates.** 16 groups, 14.3 MB.
5. **Total size against the free tier.** 0.686 GB.

### Known finding, not repaired

`girl/Weighted Leg Extension Crunch.mp4` exists under both `Abs` and `mix`
**with different content**. The builder keys an exercise by the file's stem, so
the second silently replaced the first and one real demonstration was
discarded. Deciding whether those are two exercises or one mislabelled clip
needs someone to watch both. Reported, not failed on — the exercise still ships
with a video.

## Launch

```bash
python scripts/ops/create_video_bucket.py     # idempotent
python scripts/ops/upload_video_library.py    # re-runnable, size-checked
python scripts/catalog/set_video_host.py     https://storage.googleapis.com/traidingbot-b4061-videos-eu/exercises
```

The upload compares every object's size before sending, so a second run after a
failure moves only what is missing rather than 0.69 GB again. Objects go up as
`video/mp4`: served as `application/octet-stream` some players download the
whole file before the first frame and others refuse it outright.

## Signing, in a project that has just been moved to

Every one of the catalog's 2,539 clip references is an object key now — zero
absolute urls remain (`assets/data/exercises_vendor.json`). So the whole video
feature hangs on one IAM binding, and the day it is missing **nothing plays at
all**, on every exercise, for every user.

That day was 2026-08-08. The phone said "Ссылка на ролик недоступна" on all of
them; the function log said:

```
E clipurl: {"object":"exercises/men/Calisthenics-Cardio-Plyo-Functional/180 Jump Turns.mp4",
 "error":"SigningError: Permission 'iam.serviceAccounts.signBlob' denied on resource"}
```

The bucket was fine and the object was there (`gcloud storage ls` found that
exact key). `getSignedUrl` never touches the object — it signs a string — so a
missing grant and a missing file are indistinguishable from the phone, which is
why the log is the only place this is legible.

The grant, on the **Compute Engine default** account and on itself (see the
`video_bundle_import.md` note: it is not the `@appspot` account the
documentation implies):

```bash
gcloud iam service-accounts add-iam-policy-binding \
  988522745882-compute@developer.gserviceaccount.com \
  --member="serviceAccount:988522745882-compute@developer.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project=fitness-app-korostelev
```

It takes effect within a minute or two and needs no redeploy and no new APK —
the failure is entirely server-side.

Verify with the checker that already exists rather than by opening the app:

```bash
python scripts/catalog/verify_clip_signing.py
```

**This step belongs to every project move.** `LICENSED_BUCKET` is derived from
`GCLOUD_PROJECT`, so the bucket follows a move on its own and this binding does
not — which is exactly how it got missed here.

## Monitor

Two tests were written to fail the day a host was chosen, as notes for whoever
chose it. Both fired on 2026-08-01 and have been rewritten to describe the new
state rather than deleted:

- `video_library_test.dart` — "the host is still a placeholder" is now "every
  url is on the real host".
- `exercise_video_test.dart` — "the whole shipped catalog is unplayable right
  now" is now "the shipped catalog is playable now".

Watch egress in the Cloud console's Storage → Monitoring for the first weeks.
It is the only number here that can start costing money, and 1 GB/month is the
line.

## Cleanup

```bash
python scripts/catalog/set_video_host.py --reset
# then delete the bucket in the console, or:
#   DELETE https://storage.googleapis.com/storage/v1/b/traidingbot-b4061-videos-eu
```

Safe: the drop is on disk and the upload is a plain directory copy.
