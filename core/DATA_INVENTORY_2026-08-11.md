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
| `activity.mode.v1.<uid>` | S03 mode state (per account, `modeStorageKeyFor` in `mobile/lib/features/modes/data/mode_store.dart`) | yes (prefix `activity.` and suffix `.<uid>`) | no |
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
| `<support>/activity_journal/<scopeId>/{journal,sources,quarantine}` | local activity journal (routes, heart rate, laps), one scope per account; ON by default since S03-0 (`ACTIVITY_LOCAL_JOURNAL`, `activity_flags.dart`); `activity_journal` is excluded from Android backup and device transfer in `backup_rules.xml` and both sections of `data_extraction_rules.xml` (`domain="file"`) | yes (the account's scope, by `ActivityAwareLocalDataWipe`) | local export only |
| `<temp>/` camera stills | **plaintext JPEG** of the shot just encrypted | **NO** (not in `local_data_wipe.dart`) | no |
| `<docs>/offline_videos/` | cached exercise clips (catalogue content) | no | n/a |
| `<docs>/<model asset path>` | ML model files unpacked by `AssetBootstrap` | no | n/a |
| `<temp>/` export file | the export itself | n/a | n/a |

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

## Body scan and nutrition coach additions (C25, 2026-10-15)

CSV rows carry gate `C25`. Deleted = `recursiveDelete(users/{uid})` or the
`sweepAccountData` Storage prefix delete (D-60). Exported = `exportAccountData`
(`functions/src/account_export.ts`), newest first, paged by the app (D-61).

| Store | Holds | Deleted | Exported |
|---|---|---|---|
| `users/{uid}/body_scans/*` | scan metadata, estimate, provider, `photosState`, weight, note | yes | yes, paged; no links, `photoLinksAvailable` only |
| `users/{uid}/body_scan_settings/main` | cloud consent, retention days, reminder | yes | yes |
| `users/{uid}/weight_entries/*` | daily body weight | yes | yes, paged |
| `users/{uid}/nutrition_plan/main` | plan targets | yes | yes |
| `users/{uid}/nutrition_plan_reviews/*` | weekly review decisions | yes | yes, paged |
| `users/{uid}/food_entries/*` | diary entries | yes | yes, paged |
| `users/{uid}/saved_foods/*` | saved foods | yes | yes, paged |
| `nutrition_cache/{key}` | public nutrition-database responses | n/a (no user data) | n/a, EXEMPT |
| `body_scan_purge_state/{id}` | purge cursor bookkeeping; transient `late_sweep_<hash>` records carry a uid for about 17 minutes under normal operation, retried every 5 minutes until deleted, no hard bound (server-only, deny-all to clients) | n/a (no user content; the uid-bearing record is deleted by the 5-minute late sweep) | n/a, EXEMPT |
| Storage `<project>-bodyscan-private` `users/{uid}/scans/*` | face-blurred scan JPEGs, default retention 0 (deleted after analysis, within 48 hours worst case) | yes, prefix delete | metadata only; 1-hour links via `manageBodyScanData.exportLinks` |
| Prefs `data_notice.v{N}.{uid}` | data notice acknowledgement | yes (device wipe) | no |
| Prefs `progress_photos.scan_reminder.v1.{uid}` | reminder toggle | yes (device wipe) | no |
| Prefs `profile.sensitive.{uid}` (`excludedFoods`) | device-only excluded foods | yes (device wipe) | yes, merged from the device by the client export |
| `<docs>/progress_photos/{uid}/scans/`, `.../meals/` | encrypted scan sidecars, meal thumbnails | yes (directory wipe) | no (stay on the device) |

Logging (D-67): the new quota actions are in `REDACTED_QUOTA_ACTIONS`, so
their quota log lines carry no uid; continuation export pages use the
`accountExportPage` counter. No analytics SDK receives photos or body metrics.
