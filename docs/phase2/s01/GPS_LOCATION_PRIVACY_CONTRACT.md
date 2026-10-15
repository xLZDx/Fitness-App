# GPS and location privacy contract (Phase 2, sprint S01 part a)

Status: DRAFT for GPT-PM review and operator approval. Date: 2026-10-15. Branch: `phase2/s01-contracts`.
Companion document: `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md` (one row per data class).
No code is changed by this document. No decision is taken here: D-16 and D-17 are written as options in section 9.

## 0. How to read this document

Every statement is tagged:

- **FACT** - verified in a file of this worktree; the path follows.
- **PROPOSED** - a requirement or default this contract introduces; it becomes binding only after approval. Nothing tagged PROPOSED exists in code.
- **UNVERIFIED** - could not be confirmed in this worktree (listed again in section 11).

Requirement ids are `GPS-PRIV-nnn`. Later sprints cite them in stories, tests and change records. "MUST" means the sprint that builds the feature fails its DoD without it. Source of the sprint and decision ids: `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` (S01 row, section 10 decision register, section 11 matrix).

## 1. Purpose and scope

Purpose: fix, before any location code exists, what location-related data the product may collect, where it may live, who may see it, how long it stays, and how it leaves the system (export, deletion, logs). Location history is the most sensitive data the app will hold (FACT, `docs/phase2/plan/01_PROJECT_REASSESSMENT_2026-10-15.md`, risk R-1 and section "riskiest assumption is GPS").

In scope: raw GPS samples, derived geometry, published routes, previews and thumbnails, caches, route photos, background location, heart-rate streams, friends/social graph, minors. Consumers: S02 (activity persistence), S04-D/S04 (permission and recorder), S05/S06 (EXPLORE, RIDE), S07 (route catalogue), S09 (publication protocol), S10 (sharing UI), S11 (offline), S25 (security and privacy review), S28 (deletion SLA).

Out of scope: tile and route-data licensing (S01 part b), UI baseline (S01 part c), body photos and nutrition (covered in the matrix only as existing-data baseline).

## 2. What exists today (baseline, all FACT)

| Topic | Evidence |
|---|---|
| No GPS recording, no route model, no maps | `docs/phase2/plan/01_PROJECT_REASSESSMENT_2026-10-15.md` ("Navigation today") |
| No location permission or location plugin: Android manifest declares CAMERA, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, WAKE_LOCK, VIBRATE and Health Connect permissions only; `pubspec.yaml` has `health`, `permission_handler`, `image_picker`, no geolocation package | `mobile/android/app/src/main/AndroidManifest.xml`, `mobile/pubspec.yaml` |
| Health Connect permissions declared: READ_STEPS, READ_ACTIVE_CALORIES_BURNED, READ_RESTING_HEART_RATE, READ_SLEEP, READ_HEART_RATE_VARIABILITY, READ_TOTAL_CALORIES_BURNED, READ_DISTANCE, WRITE_EXERCISE, WRITE_TOTAL_CALORIES_BURNED, WRITE_DISTANCE. No continuous heart-rate permission | `mobile/android/app/src/main/AndroidManifest.xml` |
| Firestore rules: owner-only wildcard `users/{uid}/{coll}/{document=**}` grants read and write to every subcollection not explicitly carved out. A new collection is therefore client-writable by default | `firestore.rules` lines 61-83 |
| Rules helper `isOrdinaryUser()` excludes the canary identity; all non-public grants use it | `firestore.rules` lines 58-60 |
| Only public-read collection is `donor_wall` (opt-in display name) | `firestore.rules` lines 249-252 |
| There is NO `storage.rules` file and `firebase.json` has no `storage` section, only `firestore`, `hosting`, `functions`, `emulators` | `firebase.json`; glob for `storage.rules` returned nothing |
| Server-side Storage use today: only the licensed video bucket via `getStorage().bucket(LICENSED_BUCKET)` | `functions/src/video_urls.ts` lines 40, 175-176 |
| Account deletion: `sweepAccountData` runs `recursiveDelete` on `users/{uid}`, `donor_wall/{uid}`, `coach_listings/{uid}` then `sweepSharedRecords`; durable retry record `accountDeletionRetries/{uid}` is written before the Auth user is deleted; a scheduled reconciler retries | `functions/src/index.ts` lines 2372-2379, 2381-2389 and its docs |
| Account deletion does NOT clean Cloud Storage; the source comment says whoever adds a storage backend must add its cleanup in the same change | `functions/src/index.ts` lines 2073-2077 |
| Account export: callable `exportAccountData`, reads only `request.auth.uid`, daily quota, per-collection cap 2000 rows, serialized budget 8 MiB, response hard cap about 9.5 MiB, reports `truncated` sections, states that progress-photo bytes are not included | `functions/src/account_export.ts` lines 52-58, 235-248, 364-388 |
| Collection lifecycle classification (DELETE / EXPORT / BOTH / EXEMPT) and client access classification are kept in one policy file with CI checkers named in its `_comment` | `scripts/ci/data_lifecycle_policy.json` |
| Progress photos are AES-GCM encrypted on device, key in local storage, never uploaded; export lists metadata only | `mobile/lib/features/progress_photos/data/aes_photo_cipher.dart`, `photo_key_store.dart`; `functions/src/account_export.ts` lines 26-33; `public/privacy.html` line 76 |
| Health answers are stripped on the device before profile upload; rules independently refuse a profile write carrying them | `firestore.rules` lines 165-211 |
| Age is a birth YEAR only. `ageBandFor(null)` and an unknown age return `AgeBand.adult`. The minor band applies while the person might still be 17 | `mobile/lib/features/safety/data/age_policy.dart` lines 27-76 |
| Privacy text: account requires age 16 or more; data kept while the account exists; no separate retention timer; deletion "erases every document under your account"; export covers profile, health answers, workout history, schedule, photo details | `public/privacy.html` lines 91-100 |
| Debug telemetry collection `debug_sessions`: create-only, key allowlist, at most 500 events, event contents not shape-checked; exported and deleted per user | `firestore.rules` lines 295-306; `scripts/ci/data_lifecycle_policy.json` |
| Body scan cloud code (`functions/src/body_scan`, `mobile/lib/features/body_scan`) is listed in `docs/EXPERIMENTS.md` but is NOT present in this worktree | `docs/EXPERIMENTS.md` line 9; glob of `**/body_scan*/**` returned nothing - UNVERIFIED here |

Consequence of the baseline: nothing in this contract is implemented; every location requirement is new work, and the three existing safeguards that matter most (owner-only wildcard, deletion cascade, export function) each have a gap for location data (new collections default to client-writable; deletion does not reach Storage; export is capped at about 8 MiB).

## 3. Data classes and definitions

| Id | Class | Definition |
|---|---|---|
| C1 | Raw GPS samples | Timestamped latitude, longitude, accuracy, optional altitude/speed/bearing as received from the location provider during a recording |
| C2 | Derived geometry (private) | Smoothed track, distance, elevation profile, splits, bounding box computed from C1 and stored with the activity |
| C3 | Published routes | A route entity visible beyond the owner (unlisted, friends, public) |
| C4 | Previews and thumbnails | Rendered images or simplified polylines of C2 or C3 used in lists, cards, share images |
| C5 | Caches | Any derived or fetched copy kept for speed or offline: route cache, map tile cache, previews cache, geocoding results |
| C6 | Route photos | Photos attached to a route or activity, which may carry EXIF including GPS coordinates |
| C7 | Background location | Location delivered while the app is not in the foreground (foreground service or background permission) |
| C8 | Heart-rate streams | Timestamped heart-rate series from a sensor or health platform during an activity |
| C9 | Friends and social graph | Follow/friend edges, groups, membership, buddy requests |
| C10 | Minors | Cross-cutting rules for users under 18 or of unknown age |

## 4. Principles

- GPS-PRIV-001 (MUST, PROPOSED) Private by default. Every new activity, route, photo and preview is visible only to its owner until the owner takes an explicit publish or share action. No flag, onboarding default or experiment may change this default.
- GPS-PRIV-002 (MUST, PROPOSED) Purpose limitation. Location is collected only while the user is recording an activity or has explicitly invoked a location feature (for example "Find nearby"). It is never collected at launch, during onboarding, or passively.
- GPS-PRIV-003 (MUST, PROPOSED) Least data. Sample rate, precision and fields are the minimum the calculators need (decided in S04-D); precision is not increased for diagnostics.
- GPS-PRIV-004 (MUST, PROPOSED) Every class in section 3 has a row in `DATA_LIFECYCLE_MATRIX.md` and in `scripts/ci/data_lifecycle_policy.json` before its first line of code merges.

## 5. Permission and consent flow

Flow (PROPOSED; screen design belongs to S04-D, which MUST implement these rules):

1. Foreground location is requested only at the moment of the first "Start GPS" or "Find nearby" tap, with a one-line reason shown first. (The same rule is stated in `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md`, line 52, FACT.)
2. Background location is requested only after foreground is granted, only when a recording is active or about to start, and only on platforms where continuous recording needs it. Foreground-service recording is preferred over background permission wherever the platform allows it.
3. Denial of either permission leaves the app fully usable: manual entry, history, no-GPS walk.
4. Consent is recorded per purpose in the Consent centre (rows: GPS, background location, health import, route visibility; the centre itself is specified in `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` line 76, FACT as a plan).

Requirements:

- GPS-PRIV-005 (MUST, PROPOSED) No location permission prompt appears at app launch, on first run before a location feature is chosen, or in onboarding.
- GPS-PRIV-006 (MUST, PROPOSED) Foreground location is requested before background location; the pre-prompt explains in plain words what is recorded, where it is stored and who can see it.
- GPS-PRIV-007 (MUST, PROPOSED) Background location is used only while a recording is active (including paused-by-auto-pause). When the recording ends or is discarded, background collection stops within the same user action. A persistent system notification is shown during background collection.
- GPS-PRIV-008 (MUST, PROPOSED) Revoking a permission (in the app or in system settings) stops collection immediately. A recording in progress is saved up to the moment of revocation and marked "permission revoked"; the user is offered keep, export or delete for that data. The app never re-requests in a loop.
- GPS-PRIV-009 (MUST, PROPOSED) Consent is stored as a record per purpose with timestamp, text version and current state; withdrawing consent is as short as granting it (one switch in the Consent centre) and offers export and delete links for the affected class.
- GPS-PRIV-010 (MUST, PROPOSED) Location privacy text is approved by the operator or counsel before any route can be made visible beyond the owner (roadmap section 7 lists legal review before S09; risk R-1 in `01_PROJECT_REASSESSMENT`, FACT).
- GPS-PRIV-011 (MUST, PROPOSED) The Android manifest and store data-safety forms declare background location only if the final design uses the background permission; the declared set equals the used set (checked in S25).

## 6. Requirements per data class

Retention values marked "per D-16" are open (section 9).

### C1 Raw GPS samples

- Collected: only during a recording (GPS-PRIV-002). Local: crash-safe journal on the device until synced or discarded (PROPOSED, S04). Cloud: PROPOSED private compressed object per activity (roadmap S02: "streams as compressed private objects", FACT as a plan), not a Firestore document and never in a collection readable by anyone but the owner.
- GPS-PRIV-012 (MUST, PROPOSED) Raw samples are never readable by any user other than the owner and never appear in any published, unlisted, friends or public artefact.
- GPS-PRIV-013 (MUST, PROPOSED) Until D-16 is decided and recorded in `core/DECISION_LOG.md`, raw samples stay on the device only; no upload code path is enabled (flag OFF).
- GPS-PRIV-014 (MUST, PROPOSED) The local journal is deleted after a confirmed sync, or on discard, or on sign-out/account deletion. A journal left by a crash is offered for recovery and then follows the same rule.
- GPS-PRIV-015 (MUST, PROPOSED) Retention for cloud raw samples follows the D-16 outcome and is enforced by a mechanism, not a document (object lifecycle rule or scheduled deletion), with a test.
- Export: GPX and FIT (roadmap S02/S06, FACT as plan) containing the full raw series. Deleted: with the activity and with the account.

### C2 Derived geometry (private)

- GPS-PRIV-016 (MUST, PROPOSED) Derived geometry lives and dies with its activity: same owner-only access, same retention, deleted in the same operation as the activity and the account.
- GPS-PRIV-017 (MUST, PROPOSED) Derived geometry is recomputable from C1 and is not treated as a safe, anonymised substitute: it carries the same sensitivity as C1.

### C3 Published routes

- GPS-PRIV-018 (MUST, PROPOSED) Visibility is a server-held enum private / unlisted / friends / public, defaulting to private, changed only by an authenticated owner action. Enforcement is server-side (S09), not only in the client.
- GPS-PRIV-019 (MUST, PROPOSED) Publishing requires a preview of the exact geometry that will be visible (after privacy zones and trimming) and an explicit confirm. Unpublish and delete-shared-copy are available from the same screen.
- GPS-PRIV-020 (MUST, PROPOSED) A published route is a separate derived artefact. The raw samples (C1) are never copied into it. It stores only trimmed, simplified geometry.
- GPS-PRIV-021 (MUST, PROPOSED) Trimming is not treated as sufficient protection. Before publication the server runs a re-identification check (for example a start or end remaining within a configurable distance of a repeated location, or a rare route shape) and refuses or asks for more trimming (roadmap S09, FACT as plan: "trimming alone is not treated as protection").
- GPS-PRIV-022 (MUST, PROPOSED) Unlisted links use unguessable identifiers (at least 128 bits of randomness) and are revocable.
- GPS-PRIV-023 (MUST, PROPOSED) Every published artefact stores a back-reference to its source activity so deletion or unpublish can find every copy (derived-artefact registry, S09).
- GPS-PRIV-024 (MUST, PROPOSED) Report and takedown records exist for published routes; a takedown hides the route for everyone except the owner and moderators (S09).

### C4 Previews and thumbnails

- GPS-PRIV-025 (MUST, PROPOSED) A preview is generated only from geometry already filtered for the target visibility (privacy zones and trimming applied). A preview of a private activity inherits private visibility.
- GPS-PRIV-026 (MUST, PROPOSED) Previews are registered in the derived-artefact registry (GPS-PRIV-023) and deleted or detached whenever their source is deleted, unpublished or re-trimmed. A preview is never kept after its source is gone.
- GPS-PRIV-027 (MUST, PROPOSED) A preview or share image never embeds location metadata (no EXIF/XMP GPS) and never contains street-level base map detail inside a privacy zone.

### C5 Caches

- GPS-PRIV-028 (MUST, PROPOSED) Every cache (route cache, preview cache, tile cache, geocoding results) has a documented maximum size and age, and is cleared on sign-out and on account deletion.
- GPS-PRIV-029 (MUST, PROPOSED) A cache never holds data the owner has deleted or that is outside the viewer's visibility; unpublishing or deleting evicts local caches on the owner's devices on next sync, and the server-side cache (if any) is purged by the same deletion operation.
- GPS-PRIV-030 (MUST, PROPOSED) Map tiles are cached only as the provider licence allows; no bulk pre-fetch from a provider that forbids it (S01 part b and S11, FACT in roadmap: OSM community tile policy forbids offline pre-fetching).

### C6 Route photos with EXIF

- GPS-PRIV-031 (MUST, PROPOSED) EXIF, XMP and any GPS metadata are stripped on the device before an upload and again verified server-side on receipt; an upload still carrying GPS tags is rejected, not silently stored (roadmap S09, FACT as plan).
- GPS-PRIV-032 (MUST, PROPOSED) Original unstripped files are never uploaded. Photos are private by default and follow the visibility of their route; making a photo public requires its own explicit confirmation.
- GPS-PRIV-033 (MUST, PROPOSED) Route photos are stored in a private Storage path under the owner's id, covered by `storage.rules` (GPS-PRIV-064), deleted with the route, activity and account, and listed in the export (metadata and the stripped images).
- Note (FACT): existing progress photos are a different class: encrypted on device and never uploaded (`mobile/lib/features/progress_photos/data/aes_photo_cipher.dart`). Route photos do not reuse that promise; the privacy text MUST say they are uploaded.

### C7 Background location

- GPS-PRIV-034 (MUST, PROPOSED) Background location is a collection mode of C1, not a separate store: samples collected in the background have the same classification, retention and deletion as C1.
- GPS-PRIV-035 (MUST, PROPOSED) No location is collected in the background when no recording is active, on boot (`RECEIVE_BOOT_COMPLETED` is declared today for notifications, FACT in the manifest), or after sign-out. A test or static check asserts that no location listener is registered outside a recording session.

### C8 Heart-rate streams

- GPS-PRIV-036 (MUST, PROPOSED) Heart-rate streams are health data: consent per source and per datatype, device-only by default, uploaded only after D-16 and only with that consent, never shown in a published, unlisted or friends artefact, and never included in a public preview or share image.
- GPS-PRIV-037 (MUST, PROPOSED) Platform reads (Health Connect, HealthKit) are read-only and use the minimum granular permission; a new datatype means a new manifest permission, a new consent row and a new matrix entry. Today only resting heart rate and HRV reads are declared (FACT, manifest).
- GPS-PRIV-038 (MUST, PROPOSED) Heart-rate retention, export and deletion mirror C1 (same activity cascade), except that D-16 may set a different retention period for each (section 9).

### C9 Friends and social graph

- GPS-PRIV-039 (MUST, PROPOSED) Social features are opt-in. Edges are visible only to the two parties (and group members for groups). There is no public follower list and no search by location.
- GPS-PRIV-040 (MUST, PROPOSED) Friends visibility of a route is only enabled for users who passed the age rule (GPS-PRIV-043). Leaving a group or removing a friend takes effect for all future reads immediately.
- GPS-PRIV-041 (MUST, PROPOSED) Account deletion removes the user's edges and group memberships, and replaces the user id in records that are not theirs alone with a tombstone value, following the existing pattern (`DELETED_UID = "deleted_user"`, FACT, `functions/src/index.ts` lines 2080-2087).

### C10 Minors

- GPS-PRIV-042 (MUST, PROPOSED) A user under 18 or of unknown age has no public sharing: public and unlisted visibility are unavailable and every publish endpoint refuses (this is the register default of D-17; the final rule is in section 9). Private recording and local use are allowed.
- GPS-PRIV-043 (MUST, PROPOSED) The sharing gate uses its own function "known adult", not `ageBandFor`. Reason (FACT): `ageBandFor(null)` returns `AgeBand.adult` for an unknown age (`age_policy.dart` line 27 and 52-57), which is right for training heuristics and wrong for sharing; reusing it would let an unknown-age user publish.
- GPS-PRIV-044 (MUST, PROPOSED) The age used by the gate is server-held. The profile document is client-writable (the profile rule only checks the health block, FACT `firestore.rules` lines 194-211), so a client-asserted birth year cannot be trusted by a publish endpoint. S09 MUST read an age field written only by the server or verified by a server function; how that field is obtained is part of D-17.
- Note (FACT): the age data available today is a birth year, and the app resolves the 17/18 boundary on the cautious side; the privacy text sets a minimum account age of 16 (`public/privacy.html` line 99). Users aged 16 and 17 can therefore hold accounts and are minors for this contract.

## 7. Safeguards

- GPS-PRIV-045 (MUST, PROPOSED) Privacy zones (home, work, user-defined) and default start/end trimming apply to every artefact that leaves the owner-only scope (C3, C4, C6 captions, share images). Zones are enabled by default for EXPLORE and RIDE (roadmap S05 DoD, FACT as plan). Zones are applied when deriving the shared artefact, never by editing C1.
- GPS-PRIV-046 (MUST, PROPOSED) Default trim radius and the zone editor are defined in S04-D/S10-D; the value is not fixed in this contract (UNVERIFIED parameter, to be set from a design decision, not invented here).
- GPS-PRIV-047 (MUST, PROPOSED) Zone definitions are themselves location data: stored with the owner only, included in export, deleted with the account, never logged with coordinates.
- The safeguard set also includes, by reference and without new ids: EXIF stripping (GPS-PRIV-031), the re-identification check (GPS-PRIV-021) and the minors rules (GPS-PRIV-042 to GPS-PRIV-044).

## 8. Logging, export, deletion

### Logging

Existing practice (FACT): server log events carry a stable event name and the uid, with an error string (`functions/src/account_export.ts` lines 391-408 using `EXPORT_ACCOUNT_FAILED`).

- GPS-PRIV-048 (MUST, PROPOSED) Logs, metrics, analytics, crash reports and error strings never contain coordinates, geohashes, route geometry, place names, heart-rate values, or photo contents. Allowed: counts, durations, sample counts, byte sizes, activity or route ids, permission state, error codes.
- GPS-PRIV-049 (MUST, PROPOSED) Error strings forwarded to logs are sanitised: an exception message that interpolates a sample or geometry is mapped to a bare code first (precedent: `accountDeletionRetries` stores only a bare error code, FACT, `scripts/ci/data_lifecycle_policy.json`).
- GPS-PRIV-050 (MUST, PROPOSED) The `debug_sessions` telemetry path (FACT: events are not shape-checked beyond count) MUST NOT receive location or heart-rate values; the debug telemetry redaction in `mobile/lib/core/diagnostics/debug_telemetry.dart` is extended and tested for this before any GPS code ships.

### Export

- GPS-PRIV-051 (MUST, PROPOSED) Every class held on the server or the device is exportable on request: C1 and C8 as GPX/FIT or JSON, C2, C3 metadata, C6 stripped images, zone definitions, consent records.
- GPS-PRIV-052 (MUST, PROPOSED) Streams are not placed inside the `exportAccountData` response, which is bounded to about 8 MiB (FACT, `functions/src/account_export.ts` lines 54-58). The export lists them and delivers them through a separate bounded mechanism (for example short-lived download links to private objects). The exact mechanism is chosen in S02.
- GPS-PRIV-053 (MUST, PROPOSED) An incomplete export says so in the file, as `truncated` and `notes` do today (FACT); device-only data excluded from a server export is named in the notes (precedent: progress photo note, FACT).

### Deletion

- GPS-PRIV-054 (MUST, PROPOSED) Deleting an activity deletes in one operation: C1 object, C2, every derived artefact in the registry (previews, published route, shared photos), local journal and caches on the owner's devices (on next sync), and tombstones any friend-visible reference.
- GPS-PRIV-055 (MUST, PROPOSED) Account deletion extends `sweepAccountData` (FACT: `functions/src/index.ts` line 2372) with Storage object removal for C1, C6, C8 and derived artefacts, in the same change that introduces the Storage path, as the existing source comment requires (FACT, lines 2073-2077). The step is idempotent and covered by the existing reconciler (`accountDeletionRetries`).
- GPS-PRIV-056 (MUST, PROPOSED) Published copies are either deleted or detached (owner reference removed and the route anonymised) per the matrix; the default is delete. Detach is allowed only for a route another user has already built a dependency on and only if no coordinates inside a privacy zone remain. The choice per class is fixed in `DATA_LIFECYCLE_MATRIX.md`.
- GPS-PRIV-057 (SHOULD, PROPOSED) A deletion SLA for location data is published and monitored (owner S28). The number is not set here.

## 9. Open decisions (written as options; no decision is taken)

### D-16 Retention of GPS and heart-rate streams

Roadmap context (FACT, `03_ROADMAP` section 10): "design default two years is open"; default if not decided: "Device-only until decided"; blocks S02.

| Option | What it means | Consequence |
|---|---|---|
| A. Device-only (register default) | Raw samples and HR stay on the phone. Cloud holds summary and derived geometry only. | Lowest privacy risk and no cloud cost; loses streams on device loss or reinstall; no multi-device history of full tracks; contradicts the S02 plan item "streams as compressed private objects" (S02 would implement a different scope); deletion and export are simpler. |
| B. Cloud, fixed 24 months | Streams uploaded as private objects and removed by lifecycle rule 24 months after the activity date. | Matches the "design default two years" note; needs an object lifecycle mechanism and tests; users lose old raw tracks unless exported; a fixed period needs a privacy-text change (today: "no separate retention timer", FACT `public/privacy.html` line 91). |
| C. Cloud, user-controlled | Streams uploaded as private objects; retained until the user deletes them or the account; the user can set an automatic expiry (for example 90 days, 1 year, 2 years, never). | Best fit for portability and multi-device; highest stored volume and exposure if an account is compromised; requires a visible setting and a default that must be chosen; privacy text change needed. |
| D. Split | GPS streams cloud per option B or C; heart-rate streams device-only (or shorter retention) because they are health data. | Lower sensitivity for HR; two policies to explain and test; HR features that need history (trends) are limited. |

Recommended default (PROPOSED, not a decision): keep option A as the binding default until the operator answers; when the operator decides, recommended target is option D with GPS as in option C and a default expiry shown to the user. Reason: GPS streams are needed for route reuse and device change, HR is health data that the app already treats as device-only unless consented. If D-16 is never answered, option A applies and S02 scope reduces accordingly.

### D-17 Minors, sharing and public routes

Roadmap context (FACT): default if not decided "Under-18 and unknown age: no public sharing"; blocks the contract, S09 and S10.

| Option | What it means | Consequence |
|---|---|---|
| A. No public sharing for under 18 or unknown age; friends and private allowed | Public and unlisted unavailable below the gate; friends visibility allowed for known minors with a mutual-accept edge. | Keeps community features for 16-17 year olds; friends visibility of a minor's location is still a safety exposure and needs mutual-accept and parental-guidance copy. |
| B. No sharing of any kind for under 18 or unknown age (private only) | The gate blocks public, unlisted and friends. | Strongest protection and simplest test matrix; removes social features for the 16-17 group; likely cuts engagement for the youngest allowed account holders. |
| C. Block GPS recording for under 18 | No location features at all for minors. | Maximum protection; large product loss; contradicts the privacy text which allows accounts from 16 and the existing minor training heuristics (`age_policy.dart`). |
| D. Age source (independent choice combined with A, B or C) | D1: keep birth year, self-declared, copied to a server-held field at onboarding. D2: collect full birth date and verify server-side where available. D3: require a parent or guardian consent flow for 16-17. | D1 is cheapest and can be falsified by the user, so unknown or inconsistent age must stay in the blocked group. D2 improves the 17/18 boundary and needs a new personal-data field and privacy text. D3 adds legal and support load and may need counsel. |

Recommended default (PROPOSED, not a decision): option A with age source D1 and "unknown means blocked", because it equals the register default, needs no new personal data, and still allows private recording and friends-only sharing between mutually accepted users; revisit D2 before public beta (G-C). Because the age signal under D1 is self-declared, S09 treats the minor rule as a risk-reducing control, not proof of age; the privacy text must not promise age verification.

## 10. Security-rules requirements as testable acceptance criteria

Each criterion names the test type; tests are written by the named test agents in the sprint that creates the collection or path (`functions/src/__rules__/firestore_rules.test.ts` and `functions/src/__rules__/data_access_policy.test.ts` are the existing rules-test homes, FACT).

- GPS-PRIV-058 (MUST, PROPOSED) Every new collection or Storage path holding class C1-C9 data has its own explicit block in `firestore.rules` or `storage.rules`. None relies on the `users/{uid}/{coll}/{document=**}` wildcard. AC: a rules test creates a document in each new location-bearing subcollection as the owner and as another user; the other user is denied for read and write; for server-authored collections the owner is denied write (pattern of `recognised_models`, FACT lines 362-365).
- GPS-PRIV-059 (MUST, PROPOSED) Raw sample objects and derived geometry for private activities are not readable by anyone but the owner. AC: rules test with owner, another signed-in user, signed-out user, canary token; only the owner reads.
- GPS-PRIV-060 (MUST, PROPOSED) Visibility, owner id, source activity id, moderation state and derived-artefact fields are server-authored. AC: an owner attempt to write or change any of them directly is denied; the same change through the publish callable succeeds.
- GPS-PRIV-061 (MUST, PROPOSED) Any client-writable document in these areas has a key allowlist and size bounds (precedent `debug_sessions`, FACT). AC: a write with an unknown key, an oversized array or a wrong type is refused.
- GPS-PRIV-062 (MUST, PROPOSED) The only publicly readable location artefacts are published-route documents whose state is public, and previews of them. AC: an unauthenticated read succeeds only for a public route and returns trimmed geometry; unlisted routes are readable only through the unguessable id; private, friends-only (for a non-friend), taken-down and minor-owned routes return denied.
- GPS-PRIV-063 (MUST, PROPOSED) The minors rule is enforced on the server write path. AC: a publish call by an account with unknown age, or an under-18 account, with public or unlisted visibility is refused; the same call with a known-adult account succeeds; a profile-only client edit of `birthYear` does not unlock publishing.
- GPS-PRIV-064 (MUST, PROPOSED) `storage.rules` exists, is referenced from `firebase.json`, denies everything by default and grants owner-only paths per class. AC: today there is neither file nor config entry (FACT, section 2); a rules test for Storage (emulator) covers owner read/write, cross-user denial, and size and content-type bounds on photo upload.
- GPS-PRIV-065 (MUST, PROPOSED) Every new collection and Storage path has an entry in `scripts/ci/data_lifecycle_policy.json` with delete and export classification and a `clientAccess` row, and the existing coverage checkers pass. AC: the checkers named in the file's `_comment` fail when an entry is missing (existing behaviour, FACT).
- GPS-PRIV-066 (MUST, PROPOSED) Deletion cascade is proven end to end. AC: an emulator test seeds an activity with C1, C2, C4, C6, a published route and an unlisted link, deletes the activity, and asserts none of them remains readable or listed; a second test does the same for account deletion including Storage objects and the retry/reconcile path.
- GPS-PRIV-067 (MUST, PROPOSED) Export parity. AC: a test seeds one record of each exportable class and asserts it appears in the export or in the declared separate delivery, and that an over-cap case is reported in `truncated`/`notes` rather than silently dropped.
- GPS-PRIV-068 (MUST, PROPOSED) Log hygiene. AC: a test (or log-capture check) runs record, publish, delete and export flows with seeded sentinel coordinates and heart-rate values and asserts that no captured log line, error string or telemetry event contains them.
- GPS-PRIV-069 (MUST, PROPOSED) EXIF. AC: an upload fixture with GPS EXIF is stored without any GPS tag; a fixture that cannot be stripped is rejected; the stored object is re-read and checked for metadata.
- GPS-PRIV-070 (MUST, PROPOSED) Canary and non-ordinary tokens get no access to location data. AC: rules test with the canary token on every new location path returns denied (the `isOrdinaryUser()` pattern, FACT).

## 11. Requirement index and what could not be verified

Requirements: GPS-PRIV-001 to GPS-PRIV-070 (70). All are PROPOSED. Sections: principles 001-004, consent 005-011, classes 012-044 (C1 012-015; C2 016-017; C3 018-024; C4 025-027; C5 028-030; C6 031-033; C7 034-035; C8 036-038; C9 039-041; C10 042-044), safeguards 045-047, logging 048-050, export 051-053, deletion 054-057, rules ACs 058-070.

Not verified in this worktree (UNVERIFIED):

- The body scan cloud code and its Storage bucket setup (`functions/src/body_scan`, `mobile/lib/features/body_scan`) are listed in `docs/EXPERIMENTS.md` but absent here; the matrix row for body photos relies on the roadmap matrix and on the privacy text.
- Whether `PersonalInfo.birthYear` is written to the cloud profile and whether any server-held age field exists; only the client age policy and the profile rule were read.
- The exact Firebase production Storage configuration (no `storage.rules` here); whether a default bucket with default rules exists in the cloud project cannot be seen from the repository.
- The daily export quota value and the heart-rate fields of `WorkoutSession` (not read).
- Platform store requirements for background location (Android foreground-service types, Play declarations, iOS) were not checked against official sources; GPS-PRIV-007 and 011 state the intent only.
- Legal basis, jurisdiction-specific age of consent and the operator's legal position: not assessed.
