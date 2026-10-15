# Data lifecycle matrix (Phase 2, sprint S01 part a)

Status: DRAFT for GPT-PM review and operator approval. Date: 2026-10-15. Branch: `phase2/s01-contracts`.
Companion: `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (requirement ids `GPS-PRIV-nnn`). Source skeleton: `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` section 11.

Tags: FACT = verified in a file (path given); PROPOSED = new rule, not implemented; UNVERIFIED = not confirmable in this worktree. A cell without a tag is PROPOSED. Open decisions: D-16 (retention of GPS and heart-rate streams) and D-17 (minors and public sharing); neither is decided here, see contract section 9. "Detached" means the owner reference is removed and the artefact is anonymised; the default in this matrix is delete.

## 1. Location and activity classes (new in Phase 2, nothing implemented)

Columns: Collected = when data is created; Local = on the device; Cloud = on the server; Shared = who beyond the owner can read; Retained = how long; Exported = how it leaves on request; Deleted = what removes it; Logged = what logs may contain (never coordinates or values).

| Id | Class | Collected | Local | Cloud | Shared | Retained | Exported | Deleted | Logged |
|---|---|---|---|---|---|---|---|---|---|
| C1 | Raw GPS samples (GPS-PRIV-012..015) | Only during an active recording or explicit location action | Crash-safe journal until confirmed sync or discard | None until D-16 decided (flag OFF); then a private compressed object per activity | Never | Per D-16: A device-only / B 24 months / C user-controlled / D split | GPX and FIT with full series; delivered outside the 8 MiB `exportAccountData` body (GPS-PRIV-052) | With the activity; with the account (Storage cleanup added to `sweepAccountData`, GPS-PRIV-055); journal on sync, discard or sign-out | Counts, durations, byte sizes, activity id, permission state; no coordinates, no geohash |
| C2 | Derived route geometry, private (GPS-PRIV-016, 017, 072) | On activity save | Derived track (journal-adjacent store; same backup exclusion and at-rest rule as C1, GPS-PRIV-083, 084) | None while D-16 is undecided or option A (only non-geometric summary fields: totals, duration, type); then owner-only private object under the same flag and consent as C1 | Never | Own retention value per D-16 (follows C1 by default; may differ, section 9 orthogonal choice 2) | Included in the activity export (GPX/FIT/JSON) | With the activity and the account, in the same operation as C1 | Counts, ids; no coordinates |
| C3 | Published routes (GPS-PRIV-018..024, 073..075, 086, 087) | Only on explicit publish after a geometry preview | Cache of own published routes | Two records: a public document (allowlisted fields only, random public id, no owner or source id, month-rounded date, server-set `publiclyReadable`) and a private server-only registry holding owner, source activity and derived-artefact ids | By visibility: private / unlisted (unguessable id) / friends / public; never for under-18 or unknown age on public and unlisted (D-17 register default) | Until unpublished, taken down, or source deleted | Route metadata and trimmed geometry in the owner's export | Delete by default when the source activity is deleted or unpublished; detach only under GPS-PRIV-056; with the account | Route id, visibility change event, moderation action id; no geometry |
| C4 | Previews and thumbnails (GPS-PRIV-025..027) | When a route or activity is saved or published | Preview cache | Derived images or simplified polylines, registered in the derived-artefact registry | Same as the source's visibility, built only from privacy-filtered geometry | Same as the source; never longer | Not exported as separate files (re-creatable from C2/C3); listed by id | Deleted or detached with the source, unpublish or re-trim; with the account | Artefact id only |
| C5 | Caches: route, preview, tile, geocoding (GPS-PRIV-028..030) | On view, download or navigation | Yes; bounded size and age | Server-side caches, if any, purged by the same deletion operation | Never | Bounded age and size, documented per cache | Not exported (not authoritative) | On sign-out, account deletion, source deletion or unpublish (evicted on next sync) | Hit/miss counts, sizes; no coordinates, no tile URLs containing coordinates |
| C6 | Route photos with EXIF (GPS-PRIV-031..033) | Optional, user-attached | Picked or captured file; original never uploaded | Private Storage path per owner, stripped copy only; `storage.rules` required (GPS-PRIV-064) | Follows route visibility; a public photo needs its own confirmation | Until deleted, with the route, with the account | Stripped images plus metadata list | With route, activity and account; EXIF stripped on device and verified on server before storage | Upload count, byte size, strip result code; no image content, no EXIF values |
| C7 | Background location (GPS-PRIV-007, 034, 035) | Only while a recording is active; never on boot or after sign-out | Same journal as C1 | Same as C1 (it is a collection mode, not a store) | Never | Same as C1 | Same as C1 | Same as C1; permission revocation stops collection at once and offers delete or export | Permission state and recording state only |
| C8 | Heart-rate streams (GPS-PRIV-036..038) | Per source and datatype consent; platform reads are read-only | Device-only default | Only with consent and after D-16; private object | Never; not in public, unlisted or friends artefacts or share images | Per D-16 (may differ from GPS, option D) | JSON or FIT with the activity | With the activity and the account | Sample counts, source name; no values |
| C9 | Friends and social graph, future (GPS-PRIV-039..041) | Opt-in | Cached list | Edges and groups, readable only by the parties/members | To members only; no public list | Until the edge is removed or the user leaves | Own edges and memberships | Edges and memberships removed with the account; id replaced by the tombstone `deleted_user` in shared records (FACT pattern, `functions/src/index.ts` line 2087) | User ids or edge ids only |
| C10 | Minors: under 18 or not known adult (GPS-PRIV-042..044, 088..090) | Age is a birth year from onboarding (FACT, `mobile/lib/features/safety/data/age_policy.dart`); a server-held, set-once age field is written by a server function; "known adult" means `birthYear <= currentYear - 19` | Same rules as the other classes (conditional on D-17: under option C no recording at all) | Same; per D-17 option A public and unlisted are refused server-side, per option B friends are refused too, per option C no location data is collected | Register default / option A: no public or unlisted sharing, friends per option; option B: none; option C: not applicable | Same as the class concerned | Same | Same | "Known adult" boolean only; no birth year values in logs |

## 2. Existing classes, for completeness (FACT unless marked)

These rows document what the code does today so new rows can be compared with them. Source: `scripts/ci/data_lifecycle_policy.json`, `functions/src/account_export.ts`, `functions/src/index.ts`, `public/privacy.html`, `firestore.rules`.

| Class | Collected | Local | Cloud | Shared | Retained | Exported | Deleted | Logged |
|---|---|---|---|---|---|---|---|---|
| Workout logs, sessions, scheduled sessions, programmes, stats | Per session, on entry | Yes | `users/{uid}/...` owner-only | No | While the account exists (`public/privacy.html` line 91) | Yes: `workout_logs`, `workout_sessions`, `scheduled_sessions`, `programmes`, `stats` (`account_export.ts`) | Yes: `recursiveDelete(users/{uid})` | Event name and uid in function logs; no payload |
| Profile and onboarding answers | Onboarding | Health fields stay on the device | `users/{uid}/profile/main` without health free text; rules refuse health content (`firestore.rules` lines 165-211) | No | While the account exists | Yes: profile | Yes | uid only |
| Progress photos | On capture, with consent | AES-GCM encrypted, key local; never uploaded | None | Never | Until deleted on the device | Metadata only, bytes excluded and stated in the file | Device deletion by the user; no server copy exists | No |
| Body Scan cloud photos | On scan, with consent | Local first | Only with `BODY_SCAN_CLOUD` (flag default OFF); the code is not in this worktree (UNVERIFIED) | Never | Per setting (roadmap matrix) | Links only (roadmap matrix) | Yes (roadmap matrix); no Storage cleanup exists in `deleteAccount` today (FACT, `index.ts` lines 2073-2077) | No |
| Meal and label photos | On capture | Not stored | Never stored server-side (roadmap matrix, D-27, PROPOSED in plan) | Never | n/a | n/a | n/a | No |
| Nutrition diary and weight | On entry | Yes | Yes (roadmap matrix; implementation not in this worktree, UNVERIFIED) | No | Account lifetime | Yes | Yes | No |
| Subscription and receipts | Via Stripe webhook / receipt function | No | `users/{uid}/subscription/main`, `users/{uid}/receipts/{year}`, server-authored, client read closed for receipts | No | Account lifetime; Stripe keeps its own records | Yes | Yes, Stripe subscription cancelled first | Event name and uid |
| Donor wall | Opt-in | No | `donor_wall/{uid}` public read | Public (display name, optional message) | Until opt-out | Yes | Yes | uid |
| Debug sessions (DEBUG builds only) | Debug builds | Ring buffer, 500 events | `debug_sessions/{id}` create-only | No | While the account exists | Yes, capped | Yes, via the shared-records sweep | Redacted before send; contents not shape-checked by rules |
| Deletion bookkeeping `accountDeletionRetries/{uid}` | At deletion request | No | Server-only, bare codes, TTL 30 days | No | Up to 30 days | No (exempt) | Removed on success or by TTL | Bare error code |

## 3. Deletion sweep map for location data (PROPOSED; GPS-PRIV-076, 077, 078)

Existing sweep (FACT, `functions/src/index.ts` lines 2372-2379, 2265-2289): `recursiveDelete` of `users/{uid}`, `donor_wall/{uid}`, `coach_listings/{uid}`, plus owner-field sweeps of `coach_bookings`, `equipment_reports` and `debug_sessions`. It has no step for Cloud Storage and no step for any location collection outside `users/{uid}`. Collection and prefix names below are placeholders to be fixed in S02/S09; the contract fixes the behaviour.

| Store (placeholder name) | Holds | Sweep step | Found by | Acceptance test (one per row) |
|---|---|---|---|---|
| `users/{uid}/activities` (summary, server-authored fields shielded, GPS-PRIV-071) | Non-geometric summary; geometry only if D-16 allows | Covered by existing `recursiveDelete(users/{uid})` | Path | Owner activities gone, other user's remain |
| Storage `streams/{uid}/...` | C1, C2, C8 objects | NEW: delete prefix (idempotent), in `sweepAccountData` | Owner prefix | Prefix empty after deletion; second run no-op |
| Storage `photos-quarantine/{uid}/...` and `photos/{uid}/...` | C6 uploads and re-encoded copies | NEW: delete both prefixes | Owner prefix | Both prefixes empty |
| Top-level `publicRoutes/{publicId}` | Public documents (no owner field) | NEW: delete by registry lookup of the owner's public ids | Private registry | Public docs of the owner gone, others remain, no owner field to query by |
| Top-level `routeRegistry/{registryId}` (server-only) | publicId to owner, source, artefact ids | NEW: query by `ownerUid`, delete last, after the artefacts it lists | Owner field | Registry rows gone only after artefacts |
| Top-level `routePreviews/...` or Storage `previews/...` | C4 images and polylines | NEW: delete by registry artefact list; purge cache layer | Registry | Previews unreadable, cache purged |
| Top-level `routeReports/{id}` | Report and takedown evidence | NEW: remove owner uid and geometry; reporter field set to tombstone `deleted_user` (GPS-PRIV-091) | Owner and reporter fields | Row retained without uid or geometry |
| Top-level `friendEdges/{id}`, `groups/{id}` (future) | C9 | NEW: delete owner's edges, remove from groups, tombstone in shared records | Owner and member fields | Other users' edges to the deleted user gone, others unchanged |
| `users/{uid}/consents` (client-owned, allowed to use the wildcard) and server consent records | Consent state | Covered by `recursiveDelete`; server records NEW | Path / owner field | No consent record remains |
| Local device: journal, caches, zones | C1, C2, C5, zones | Client wipe on delete success and on next launch with no valid session (GPS-PRIV-085) | Local paths | Directories empty after relaunch with auth failure |
| Secondary: CDN or Hosting cache, Storage soft-delete and versions, Firestore backups and PITR, Cloud Logging | Copies | Per-store erasure window (GPS-PRIV-078, 079) | Per store | S25 settings check |

Failure injection (GPS-PRIV-077): a test interrupts the cascade after each of these steps and shows the reconciler finishes it: registry written / artefact created / public document written / registry finalised / Storage objects removed.

## 4. Gaps the matrix exposes (FACT unless marked)

| Gap | Where | Resolved by |
|---|---|---|
| New subcollections under `users/{uid}` are client-readable and client-writable by default | `firestore.rules` lines 61-83 | GPS-PRIV-058, GPS-PRIV-060, S02 and S09 rule blocks |
| No `storage.rules`, no `storage` block in `firebase.json` | `firebase.json` | GPS-PRIV-064 (before any Storage use) |
| Account deletion does not remove Storage objects | `functions/src/index.ts` lines 2073-2077 | GPS-PRIV-055 in the same change that adds Storage paths |
| Export response capped near 8 MiB; streams cannot ride inside it | `functions/src/account_export.ts` lines 54-58 | GPS-PRIV-052, S02 |
| Unknown age is treated as adult for training policy | `mobile/lib/features/safety/data/age_policy.dart` lines 27, 52-57 | GPS-PRIV-043 (separate sharing gate) |
| Profile is client-writable, so a birth year is client-asserted | `firestore.rules` lines 194-211 | GPS-PRIV-044, D-17 age source |
| Privacy text says no retention timer and that deletion erases every document; it does not mention location, route photos or uploads | `public/privacy.html` lines 76, 91-96 | GPS-PRIV-010 (text approved before any sharing); S25 |
| Debug telemetry events are not shape-checked | `firestore.rules` lines 295-306 | GPS-PRIV-050 |
| Equipment-identity collections are DELETE-only (export gap already recorded) | `scripts/ci/data_lifecycle_policy.json` | Out of scope here; unchanged |
| Wildcard lists exclusions separately for read and write; a new server-authored subcollection must be added to both | `firestore.rules` lines 61-82 | GPS-PRIV-071 |
| Android backup rules exclude only progress photos and three preference files; any GPS file in app storage would be backed up | `mobile/android/app/src/main/res/xml/backup_rules.xml` lines 35-43; manifest lines 41-42 | GPS-PRIV-083 |
| Deletion sweep is a hardcoded list; no location collection outside `users/{uid}` and no Storage step | `functions/src/index.ts` lines 2265-2289, 2372-2379 | Section 3 above; GPS-PRIV-076 |
| Backup, soft-delete, CDN and log retention of the cloud project are not visible in the repository | none (UNVERIFIED) | GPS-PRIV-078, 079 |

## 5. Maintenance

- Each sprint that adds a collection or Storage path updates this matrix and `scripts/ci/data_lifecycle_policy.json` in the same PR (roadmap section 3, DoD: "lifecycle policy rows for any new collection, deletion and export coverage").
- The retention cells for C1 and C8 stay "per D-16" until the decision is recorded in `core/DECISION_LOG.md`; the minors cells for C3 and C10 stay "per D-17" until likewise recorded.
