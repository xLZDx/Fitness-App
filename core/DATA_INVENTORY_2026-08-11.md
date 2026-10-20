# Data inventory — every store keyed to a user (2026-08-11)

Gate **A0** of `core/plans/PLAN_AUDIT_2026-08-11_REMEDIATION.md`. It exists
because A1 (deletion) and A3 (export) were each about to derive this list
separately, and a divergence between those two lists is exactly how a product
ends up promising "we erase everything" while exporting less than it stores.

CSV twin: `core/DATA_INVENTORY_2026-08-11.csv`.

**Method.** Enumerated from three independent directions and merged, rather
than from memory: `firestore.rules` `match` blocks; every `db.doc(`/
`db.collection(` in `functions/src/index.ts`; every `collection('…')` in
`mobile/lib/`; and every `SharedPreferences` key constant plus every
`getApplicationDocumentsDirectory` / `getTemporaryDirectory` call site in
`mobile/lib/`.

**Baseline as of `3cc8126`.** "Deleted" = removed by `deleteAccount`
(`functions/src/index.ts:1287-1345`) plus the client action
(`account_deletion_providers.dart`). "Exported" = present in
`buildExport` (`mobile/lib/features/data_export/data_export.dart:33-86`).

## Server — Firestore

| Path | Holds | Deleted | Exported |
|---|---|---|---|
| `users/{uid}/profile/main` | profile, goals, **injuries** | yes | yes |
| `users/{uid}/workout_logs/*` | workout history | yes | yes |
| `users/{uid}/workout_sessions/*` | open + completed sessions, sets, difficulty | yes | **no** |
| `users/{uid}/scheduled_sessions/*` | schedule | yes | yes |
| `users/{uid}/programmes/*` | enrolled programmes | yes | yes |
| `users/{uid}/subscription/main` | tier, Stripe customer + subscription ids | yes | **no** |
| `users/{uid}/machine_cards/*` | saved machines + user notes | yes | **no** |
| `users/{uid}/recognised_equipment/*` | recognition history | yes | **no** |
| `users/{uid}/generated_exercises/*` | AI-generated exercises | yes | **no** |
| `users/{uid}/stats/workouts` | aggregate counters | yes | **no** |
| `donor_wall/{uid}` | publicly readable donor entry | yes | **no** |
| `coach_listings/{uid}` | coach profile | yes | **no** |
| `coach_bookings/{id}` | `clientUid` + `coachUid`, times, price, payment intent | **NO** | **no** |
| `equipment_reports/{id}` | `reporterUid`, gym, fault, note | **NO** | **no** |
| `debug_sessions/{id}` | `uid`, device telemetry | **NO** | **no** |
| `accountDeletionRetries/{uid}` | deletion bookkeeping only: uid, status, attempts, timestamps, bare error code (no profile, email or payload) | removed by the reconciler on success, else by TTL | n/a (no user content) |
| `gyms/*`, `equipment/*`, `exercises/*` | shared reference data, no user key | n/a | n/a |

Three orphans, and they are not symmetrical: `coach_bookings` names the deleted
user in **either** of two fields, so a sweep that only matches `clientUid`
leaves a coach's own bookings behind. `debug_sessions` is create-only by its
own rule (`firestore.rules:82-87`: `allow update, delete: if false`) — the
client cannot delete it even for itself, so this one can only be swept
server-side.

### Deletion reconciliation records (`accountDeletionRetries/{uid}`)

`deleteAccount` ends with a final sweep after the Auth user is deleted (a
Stripe webhook can write subscription data for the uid while the deletion
runs). Once the Auth user is gone the user can no longer retry, so the
function writes a durable **intent record** after the first sweep and BEFORE
deleting the Auth user. A crash, timeout or kill at any later point therefore
still leaves a record for the reconciler. If the record cannot be written, the
Auth user is not deleted and the call fails with an internal error (the user
is still signed in and can repeat it). A clean final sweep deletes the record
(best effort; a failed delete is harmless because the reconciler sweeps and
removes it). The response carries `finalCleanup`: `complete`, or `scheduled`
when the final sweep failed and the reconciler will finish the job.

- **Contents:** `uid` (document id), `status` (`pending` | `failed_terminal`),
  `attempts` (0 at creation, 1 after a failed final sweep), `createdAt`,
  `nextAttemptAt`, `expireAt`, and `lastErrorCode` once a sweep has failed (bare
  code, never an error message). No profile, email, Stripe id or payload.
- **Who can read or write:** nobody from a client (`firestore.rules`:
  `allow read, write: if false`); the Admin SDK only, i.e. `deleteAccount` and
  the scheduled `reconcileAccountDeletions` (service account
  `fn-account-delete`). Operators read it through the Firebase console.
- **Retry:** `reconcileAccountDeletions` runs every 15 minutes, takes up to 50
  due `pending` records and re-runs the same sweep `deleteAccount` uses, with no
  user authentication (it only reads Auth to confirm the account is really gone;
  a record whose Auth user still exists, i.e. an aborted deletion, is dropped
  without sweeping). It CLAIMS each record before sweeping: `attempts` + 1 and
  `nextAttemptAt` pushed out (15 min doubling, capped at 6 h) are written first,
  so a sweep that hangs, times out or kills the instance still used up an
  attempt and a poison record cannot starve the queue or silently outlive its
  TTL. Success deletes the record (no uid is retained) and logs
  `account_deletion_reconciled`; failure logs a warning and stays `pending`. No
  new record is started after 240 s of the 300 s timeout.
- **Terminal state:** at 12 attempts the record becomes `failed_terminal` and
  the ERROR event `account_deletion_reconcile_exhausted` is logged (a record
  already at 12 attempts, left by a crash on the last attempt, is terminated
  without another sweep). `delete_account_final_sweep_failed` (ERROR, early
  signal) and `account_deletion_reconcile_run_failed` (ERROR, the due query
  itself failed) are logged too. The alert definitions are source-controlled in
  `functions/src/monitoring/alert_definitions.ts` (not deployed by this repo);
  creating the live policy and attaching a notification channel remains the
  separate operator step recorded in `functions/src/monitoring/README.md`
  (DECISION FA-D1).
- **Retention:** every record carries `expireAt` = `createdAt` + 30 days;
  a Firestore TTL policy on `accountDeletionRetries.expireAt`
  (`firestore.indexes.json` `fieldOverrides`) deletes it. TTL deletion is
  asynchronous and can lag by up to a day.
- **Operator action on `failed_terminal`:** the uid is the document id. Find the
  cause from the logs (`delete_account_final_sweep_failed`,
  `account_deletion_reconcile_attempt_failed`), fix it (permissions, index,
  outage), then set `status` back to `pending`, `attempts` to 0 and
  `nextAttemptAt` to now; the next run sweeps it and deletes the record. If the
  data was removed by hand, delete the record. If nothing is done the TTL
  removes the record and the uid with it, so a failure must be acted on within
  30 days.

## Device — SharedPreferences

| Key | Holds | Wiped on delete | Exported |
|---|---|---|---|
| `profile.sensitive.<uid>` | **health/injury blob**, JSON, plaintext | yes (exact key) | via profile, partially |
| `profile.sensitive.corrupt.<uid>` | raw copy of an unreadable health blob (plaintext) | yes | no |
| `training_context.v1.<uid>` | training-context answer | yes | no |
| `progress_photos.consent.v1.<uid>` | photo consent record | yes | no |
| `progress_photos.scan_reminder.v1.<uid>` | scan reminder toggle | yes | no |
| `progress_photos.key.v1` | pre-A2-sec install-wide AES key, base64, **not uid-scoped** (legacy; the current key is in the Keystore, see Files) | yes, only when the legacy owner marker is unset or this uid | no (correctly) |
| legacy photo migration marker (`kLegacyPhotoMigrationMarker`) | names the account that adopted the legacy photos | yes, only when it names this uid | no |
| `account_deletion.pending_wipe_uids` | uids whose device wipe is still pending (uids only) | removed per uid once that wipe completes | no |
| `settings.tier_override` | debug entitlement | yes | **no** |
| `moment.*` (`first_launch_at`, `launch_count`, `injury_filter_uses`, `shown.*`) | in-app moment counters | yes (prefix) | **no** |
| `settings.language`, `settings.theme_mode`, `settings.notifications_enabled` | device preferences | **NO, kept on purpose** (`DeviceLocalDataWipe.kept`) | **no** |

Source of truth for the "Wiped" column: `DeviceLocalDataWipe.wipe(uid)` in
`mobile/lib/features/account_deletion/data/local_data_wipe.dart`. It removes
the exact per-uid keys above (never a `profile.sensitive.` prefix, which would
erase another account's blob on a shared phone), runs every step even when one
fails, and throws `LocalWipeIncomplete` naming what remains. An interrupted
deletion is finished on a later launch from the pending-wipe set.

**Backup and device transfer.** The whole SharedPreferences file
(`FlutterSharedPreferences.xml`) is excluded from Android Auto Backup (Google
Drive) and from device-to-device transfer, together with the
`flutter_secure_storage` files `FlutterSecureStorage.xml` and
`FlutterSecureKeyStorage.xml`: `<exclude domain="sharedpref" .../>` in
`mobile/android/app/src/main/res/xml/backup_rules.xml` (Android 11 and below)
and in both the `cloud-backup` and `device-transfer` sections of
`data_extraction_rules.xml` (Android 12+); both are referenced from
`AndroidManifest.xml`. Android cannot exclude single keys, so the plaintext
health/injury blobs stay device-local at the cost of every key in the table
above. Consequence: on a new or restored device the user is asked the profile
and training-context questions again, and language, theme and notification
preferences are not restored either.

## Device — files

| Path | Holds | Wiped on delete | Exported |
|---|---|---|---|
| `<docs>/progress_photos/<uid>/` | AES-GCM envelopes + metadata index for that account | yes (whole per-uid directory) | metadata only |
| `<docs>/progress_photos/` loose `index.json` / `*.bin` | pre-A2-sec legacy files no account adopted | yes, same condition as the legacy key | no |
| Android Keystore entry `key.v2` (via `SecurePhotoKeyStore`) | the current AES key for photos and scans | yes (`SecurePhotoKeyStore.forget(uid)`, best-effort) | no (correctly) |
| `<docs>/coach_recordings/<uid>/` | developer coach recordings: joint angles + timestamps only (debug and profile builds) | yes | no |
| `<docs>/progress_photos/<uid>/scans/<id>.scan` | Guided body-scan record: photo ids and pose landmarks (body-shape data), one AES-GCM envelope per scan, **no plaintext index**; same key as the photos | yes (whole per-uid directory) | no |
| `<docs>/scan_history/<uid>/<scanId>/` (`record.json`, `photo.jpg`) | the on-phone scan history (operator order 2026-10-14): per scan the resized JPEG that was sent to the recogniser, timestamp, source (camera/gallery/live), the model's raw reply, every candidate with its confidence and the user's optional OK/NOT OK rating, which machine was opened or chosen by hand, whether the cloud or the on-device fallback answered, app build/git sha. **Plaintext, app-private, never uploaded** (a stated limit: not encrypted at rest, because the operator must be able to export it readable). Capped at the newest 500 scans or 1 GiB, whichever first, **per account** (each uid has its own cap, so two accounts on one phone can each hold that much; the cap is not a device-wide limit); "Clear history" deletes it | yes (`DeviceLocalDataWipe`, whole per-uid directory, serialised through the live store so a scan still being saved cannot recreate it afterwards) | only by the user's own export action (one JSON + `photos/`, handed to the share sheet); not in the account export function |
| `<temp>/scan_history_export/` (`scan_history.json`, `photos/*.jpg`) | the export copy made for the share sheet: **plaintext** photos and JSON, in the app's temp storage (not in the per-uid folder). Deleted right after the share call returns (success or failure), by "Clear history", by the next export, and by the account wipe. A stated limit: on Android the share target reads the file after the call returns, so a very large export may be cut short for the receiving app; the user can export again | yes (`DeviceLocalDataWipe` deletes the folder; "Clear history" too) | this IS the export |
| `<temp>/` camera stills | **plaintext JPEG** of the shot just encrypted | **NO** (not in `local_data_wipe.dart`) | no |
| `<docs>/offline_videos/` | cached exercise clips (catalogue content) | no | n/a |
| `<docs>/<model asset path>` | ML model files unpacked by `AssetBootstrap` | no | n/a |
| `<temp>/` export file | the export itself | n/a | n/a |

Scan history and backup: `<docs>/scan_history/` is excluded from Android Auto Backup and from device-to-device transfer (`<exclude domain="root" path="app_flutter/scan_history" />` in `backup_rules.xml` and in both sections of `data_extraction_rules.xml`), so it exists only on the phone that scanned. `scripts/ci/data_lifecycle_policy.json` classifies Firestore collections only and flags any name it cannot discover in rules or source as stale, so this device-only class is recorded here and pinned by `mobile/test/android/backup_rules_test.dart` (exclusion names, wipe path, this entry) rather than by a policy row.

Scan reminder toggle: pref `progress_photos.scan_reminder.v1.<uid>` (bool, per account), erased by the local wipe; photos and landmarks never leave the device.

The photo directory is shared across accounts, and so is its key. Sign out of
account A, sign in as account B on the same device, and B's photo grid reads
A's envelopes with A's key. That is the concrete mechanism behind the audit's
"следующий аккаунт может получить данные предыдущего", and it is a **local**
defect that no amount of server-side deletion fixes.

## What this fixes in the two dependent gates

**A1 must therefore:** sweep `coach_bookings` on both uid fields,
`equipment_reports` on `reporterUid`, and `debug_sessions` on `uid`, all
server-side; and on the client, `clear(uid)` the sensitive store, delete the
whole `<docs>/progress_photos/` directory (directory-level, so it survives
A2's restructure), drop the photo key, and reset the `settings.*`/`moment.*`
keys that describe a person rather than a device.

**A3 must therefore add:** workout sessions, subscription (minus secrets),
machine cards, recognition history, generated exercises, stats, donor entry,
coach listing, coach bookings, equipment reports, debug telemetry — plus a
recorded decision on photo bytes, which today are excluded by a comment in
`data_export.dart:13-22` that the privacy policy does not repeat.
