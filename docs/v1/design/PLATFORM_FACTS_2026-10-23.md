# Platform facts the v1 design leans on

Date: 2026-10-23. Worktree base: master c945e9f8, branch docs/v1-platform-facts.
Scope: items 4 of section 2 of `PRE_IMPLEMENTATION_CONDITIONS_2026-10-22.md` and the UNKNOWN items of `OFFLINE_COMMAND_PROTOCOL.md` (v1.5.10).
Method: read-only only. gcloud list/describe/get-iam-policy/logging read, git, grep, node, installed library source, vendor docs. Nothing was deployed, set, created or changed. No secret values were read (secret names only).
Project: `fitness-app-korostelev`, database `(default)`, location `eur3`.
Status values: VERIFIED / NOT VERIFIABLE FROM HERE / CONTRADICTED. CONTRADICTED means the current project state differs from what the protocol's deploy gate or text assumes; it is a gap to close by a reversible configuration change, not a design flaw by itself.

## Summary table

| # | Fact | Status |
|---|------|--------|
| F1 | Trigger SDK versions; `before.createTime` / `before.updateTime` exposed | VERIFIED |
| F2 | 2nd gen Firestore trigger retry flag and 24 h window | VERIFIED (docs); no Firestore trigger is deployed today |
| F3a | Firestore TTL available on the project database | VERIFIED |
| F3b | TTL configurable on the `workout_command_receipts` subcollection group | NOT VERIFIABLE FROM HERE |
| F4 | Point-in-time recovery enabled (protocol P3 gate, 8.3 item 12 (d), (e)) | CONTRADICTED (disabled; 1 h retention) |
| F5a | Data-write audit logs enabled for Firestore | CONTRADICTED (no `auditConfigs`; nothing logged) |
| F5b | `_Required` / `_Default` log bucket retention | VERIFIED (400 d / 30 d) |
| F5c | Audit entries carry document path and commit time for client SDK writes | NOT VERIFIABLE FROM HERE |
| F6 | Secret store and rotation for the HMAC seal key | VERIFIED |
| F7a | `waitForPendingWrites` exists in the pinned `cloud_firestore` | VERIFIED |
| F7b | `waitForPendingWrites` behaviour offline / with an old-build stub | NOT VERIFIABLE FROM HERE |
| F8a | Minimum-version gate exists | VERIFIED ABSENT (nothing exists) |
| F8b | Device registry exists | VERIFIED ABSENT (nothing exists) |
| F9 | `deleteAccount` can host a begin-deletion step | VERIFIED (with required changes listed below) |
| F10 | Audit logs list client SDK writes and can be exported with 30-day retention | NOT VERIFIABLE FROM HERE |

Counts: VERIFIED 9, NOT VERIFIABLE 4, CONTRADICTED 2 (15 rows).

## F1. Trigger SDK and `before.createTime`

Pinned versions.
- `functions/package.json`: `"firebase-functions": "^6.0.0"`, `"firebase-admin": "^13.10.0"`, engines `"node": "22"`. These are ranges; the pin is the lock file.
- `functions/package-lock.json:8099-8101` firebase-functions 6.6.0; `:8004-8006` firebase-admin 13.10.0; `:2333-2334` @google-cloud/firestore 7.11.6.
- The worktree has no `node_modules`; the main checkout `D:\Repo\Fitness_App\functions\node_modules` matches the lock (command: `node -e "...require('./<pkg>/package.json').version"` printed `firebase-functions 6.6.0`, `firebase-admin 13.10.0`, `@google-cloud/firestore 7.11.6`).

Types (installed library).
- `node_modules/firebase-functions/lib/v2/providers/firestore.d.ts:59` `onDocumentWritten` handler gets `FirestoreEvent<Change<DocumentSnapshot> | undefined>`; `:119` `onDocumentUpdated` gets `Change<QueryDocumentSnapshot>`.
- `node_modules/@google-cloud/firestore/types/firestore.d.ts:1609` and `:1615`: `DocumentSnapshot.createTime?` and `updateTime?` (optional, undefined when the document does not exist, so `before` of a create has none); `:1669` and `:1675`: `QueryDocumentSnapshot.createTime` and `updateTime` are required.
- Implementation: `node_modules/firebase-functions/lib/common/providers/firestore.js:67-76` `createBeforeSnapshotFromProtobuf` builds `before` from `oldValue` through `firestoreInstance.snapshot_(...)`; `:100-108` the JSON path sets the read time from `oldValue.createTime || oldValue.updateTime`. `:44-45` shows createTime/updateTime are carried in the decoded protobuf document.
- Result: VERIFIED that the type surface and the construction path expose `before.createTime` and `before.updateTime` (and `after.*`). NOT observed with a live event, because no Firestore trigger is deployed (see F2); the deploy check named in protocol 8.3 item 12 (a) (equality of audit commit time and `after.updateTime`) is still required.

## F2. Trigger retry behaviour and window (2nd gen)

- Library: `node_modules/firebase-functions/lib/v2/options.d.ts:155` `retry?: boolean | Expression<boolean> | ResetValue` is available on the 2nd gen options.
- Docs, https://firebase.google.com/docs/functions/retries: "Setting `true` ... configures a function to retry on failure"; "For 2nd gen functions, this retry window expires after 24 hours" (1st gen: 7 days); exponential backoff "between 10 and 600 seconds"; the backoff policy applies to newly created functions at first deploy.
- Project state: `gcloud functions list` shows every function as GEN_2; `grep -rn "onDocument" functions/src` (non-test) finds no Firestore trigger, only `onSchedule`/`onCall`. `eventarc.googleapis.com`, `cloudfunctions.googleapis.com` and `run.googleapis.com` are enabled (`gcloud services list --enabled`).
- Result: VERIFIED (docs plus library). Retry window is 24 hours, which is exactly the protocol invariant "retry window and message retention at most 24 hours" (8.3 item 2). The invariant has to be checked at deploy for each trigger (retry flag set on the new function).

## F3. Firestore TTL

F3a, VERIFIED. Command `gcloud firestore fields ttls list` printed:
```
name: projects/fitness-app-korostelev/databases/(default)/collectionGroups/accountDeletionRetries/fields/expireAt
ttlConfig:
  state: ACTIVE
```
Declared in `firestore.indexes.json:44-46` (`fieldOverrides`, collectionGroup `accountDeletionRetries`, `fieldPath expireAt`, `ttl true`). Only that one collection group has TTL.

F3b, NOT VERIFIABLE FROM HERE. Docs (https://docs.cloud.google.com/firestore/native/docs/ttl): "A TTL policy designates a given field as the expiration time for documents in a given collection group"; "Data is typically deleted within 24 hours after its expiration date"; expired documents remain visible to queries until deleted; "Deleting a document through TTL does not delete subcollections under that document"; "Deletion through TTL calls all active snapshot listeners and triggers ... Firestore triggers". The existing policy is on a top-level collection; there is no example on a subcollection group, and the docs page does not state it. Creating a policy to test it is a write and was not done. Operator command in the open-items section.
Design note: TTL deletes fire triggers (so a trigger on a TTL'd collection must tolerate DELETE events), and deletion is "typically within 24 hours", not on `expireAt`; the 24 h fence expiry in protocol 8.7 is therefore "at least 24 h".

## F4. Point-in-time recovery and backups

`gcloud firestore databases describe` (relevant lines):
```
pointInTimeRecoveryEnablement: POINT_IN_TIME_RECOVERY_DISABLED
versionRetentionPeriod: 3600s
earliestVersionTime: '2026-10-23T11:58:48.246133Z'
deleteProtectionState: DELETE_PROTECTION_DISABLED
locationId: eur3 / type: FIRESTORE_NATIVE / databaseEdition: STANDARD
```
`gcloud firestore backups schedules list --database="(default)"` printed `Listed 0 items.` (no scheduled backups).
Docs (https://docs.cloud.google.com/firestore/native/docs/use-pitr): retention "is one hour when PITR is disabled and seven days when PITR is enabled"; reads accept "a microsecond precision timestamp within the past hour or a whole minute timestamp beyond the past hour"; Java and Node server libraries need a read-only transaction to read at a time; Android, iOS and Web SDKs cannot do PITR reads.
Result: CONTRADICTED against protocol 8.3 item 12 (d) and (e): the deploy gate P3 requires PITR enabled, and (d) assumes minute-granular versions for 7 days. Today only the last hour is readable (microsecond exact). Enabling it is a reversible configuration change that was not made.

## F5. Data-write audit logs and log retention

F5a, CONTRADICTED. `gcloud projects get-iam-policy fitness-app-korostelev --format=json`, auditConfigs part: the key is absent (script printed `"NO auditConfigs key"`). No `datastore.googleapis.com` / `firestore.googleapis.com` DATA_WRITE config exists. Docs (https://docs.cloud.google.com/logging/docs/audit): "Except for BigQuery, Data Access audit logs are disabled by default." Corroboration: `gcloud logging read 'protoPayload.serviceName="firestore.googleapis.com" AND logName:"cloudaudit.googleapis.com%2Fdata_access"' --limit=3 --freshness=30d` returned no entries. Sinks (`gcloud logging sinks list`): only `_Required` and `_Default`; no user sink.

F5b, VERIFIED. `gcloud logging buckets list`:
```
global _Default  RETENTION_DAYS 30   LIFECYCLE ACTIVE
global _Required RETENTION_DAYS 400  LOCKED True
```
Data Access logs, when enabled, are stored in `_Default` (30 days) unless routed elsewhere (logging audit docs above). So 30 days is available without a custom sink, but at the exact boundary the protocol asks for as a minimum ("at least 30 days").

F5c, NOT VERIFIABLE FROM HERE. Firestore audit docs (https://docs.cloud.google.com/firestore/native/docs/audit-logging) list DATA_WRITE methods `BatchWrite`, `Commit`, `CreateDocument`, `DeleteDocument`, `UpdateDocument`, `Write`, and mention `AuthenticationInfo` (with `thirdPartyPrincipal` for Firebase Auth tokens), `requestMetadata.callerIp`, `metadata.processing_duration`. The page does not mention `resourceName`, request/response content (the `writes` list) or commit time, and does not address client SDK traffic explicitly. Whether a client SDK `Commit` or `Write` stream entry carries the document paths, the write list and a commit time, and in which shapes, can only be proven by enabling the logs and capturing real entries (see F10).

## F6. Secret store for the HMAC seal key

- `gcloud services list --enabled` contains `secretmanager.googleapis.com` (VERIFIED).
- `gcloud secrets list --format="value(name)"` (names only): CANARY_WEB_API_KEY, STRIPE_PRICE_CELEBRITY, STRIPE_PRICE_CELEBRITY_ANNUAL, STRIPE_PRICE_CELEBRITY_LIFETIME, STRIPE_PRICE_STANDARD, STRIPE_PRICE_STANDARD_ANNUAL, STRIPE_PRICE_STANDARD_FAMILY2, STRIPE_PRICE_STANDARD_FAMILY4, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, ai-gateway-kill-switch. No seal-key secret exists yet; one must be created.
- Code already uses it: `functions/package.json` depends on `@google-cloud/secret-manager ^5.6.0`; `deleteAccount` declares `secrets: [STRIPE_SECRET_KEY]` (`functions/src/index.ts:2549`).
- Rotation, docs (https://docs.cloud.google.com/secret-manager/docs/secret-rotation): rotation schedule or period can be set, Secret Manager publishes a `SECRET_ROTATE` message to Pub/Sub, and "you must configure a Pub/Sub subscriber"; the service does not create the new version itself. Secrets hold multiple versions, which fits the protocol's `kid` model (verification accepts every non-retired kid). Rotation of the seal key is therefore a manual or subscriber-driven procedure, not automatic.

## F7. `waitForPendingWrites` in the pinned `cloud_firestore`

- `mobile/pubspec.yaml:46` `cloud_firestore: ^6.3.0`; `mobile/pubspec.lock:172-178` hosted package (version 6.3.0 per the pub cache directory name and its `pubspec.yaml` line 7 `version: 6.3.0`).
- F7a, VERIFIED: `C:\Users\koros\AppData\Local\Pub\Cache\hosted\pub.dev\cloud_firestore-6.3.0\lib\src\firestore.dart:322` `Future<void> waitForPendingWrites() { return _delegate.waitForPendingWrites(); }`; the doc comment at `:319-321` says to call it again after additional writes and that outstanding calls are rejected on user change.
- F7b, NOT VERIFIABLE FROM HERE: its offline behaviour (it waits for server acknowledgement, so it cannot complete offline), its behaviour with writes made by an old build's SDK instance, and ordered acknowledgement for the marker fallback require a device or emulator test. The package source only delegates.

## F8. Minimum-version gate and device registry

F8a, VERIFIED ABSENT. Search `grep -rniE "minAppVersion|min_app_version|minVersion|forceUpdate|force_update|remote_config|remoteConfig|package_info|appVersion|versionGate|update.?required" mobile/lib mobile/pubspec.yaml functions/src firestore.rules`: the only hits are informational: `mobile/lib/core/diagnostics/debug_telemetry.dart:42-67` (appVersion/buildNumber reported in telemetry), `mobile/lib/main.dart:393` and `mobile/lib/features/scanner/history/scan_history_providers.dart:33` (`String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0')`), `functions/src/nutrition_config.ts:12-34` (a User-Agent version), `functions/src/release_guard.ts:619` (the string "remoteconfig" as a firebase.json section name), and `mobile/lib/core/health/platform_health_service.dart:97` (Health Connect provider update). No `firebase_remote_config`, `package_info_plus` or similar dependency in `mobile/pubspec.yaml`; `firebase.json` has no `remoteconfig` section. The app has no minimum-version gate, matching protocol P1 ("no verified gate").

F8b, VERIFIED ABSENT. `grep -rniE "deviceInstallId|device_install|registerDevice|device_registry|fcmToken" mobile/lib functions/src firestore.rules` finds `deviceInstallId` only as a field of the local offline queue (`mobile/lib/features/workouts/offline/sender.dart:31,42,137,149,303`, `command_queue_store*.dart`, `command_record.dart`, `canonical.dart`) and the server side that already echoes it (`functions/src/account_export.ts:282,301`, `functions/src/workout_commands/apply.ts`). No device collection exists in `firestore.rules`, `functions/src` or the client; `sync_markers` and `deleted_accounts` collections do not exist either (`deleted_accounts` appears only in a comment, `functions/src/index.ts:169`). So the protocol's `drainedDevices`, "every device seen in the last 90 days" and `sync_markers/{deviceInstallId}` have no existing registry to read from; "devices seen" must be built.

Note: `functions/src/index.ts:160-175` records an earlier decision against a `deleted_accounts/{uid}` tombstone (data minimisation: "retaining a uid specifically about a person who asked to be forgotten"). Protocol 8.7 introduces exactly such a document, with a 24 h `expireAt` after completion. The two decisions need to be reconciled in the design (the retention until TTL is the mitigation, but the comment's premise should be updated).

## F9. Can `deleteAccount` host a begin-deletion step (O-02)?

Current flow, `functions/src/index.ts`, callable `deleteAccount` at line 2547 (`onCall`, `RARE`, own service account, secret STRIPE_SECRET_KEY):
- 2550-2555 auth check and App Check note.
- Step 1, 2557-2625: reads `users/{uid}/subscription/main` (2573), cancels every Stripe subscription immediately (retrieve, cancel if not `canceled`); failure throws `internal` and aborts before anything else.
- Step 1b, 2627-2641: `revokeRefreshTokens(uid)`, non-fatal.
- Step 1c, 2643-2662: `writeActivityAccountFence` writes top-level `activity_account_state/{uid}` (server-only; blocks activity callables); failure aborts.
- Step 2, 2664-2692: `sweepAccountData(uid)` (recursiveDelete of `users/{uid}` and the extra collections); failure throws, safe to repeat.
- Step 2b, 2694-2715: `recordAccountDeletionIntent(uid)` (defined 2494) writes `accountDeletionRetries/{uid}` (TTL field `expireAt` = now + 30 d); failure aborts before the Auth user is deleted.
- Step 3, 2717-2739: `admin.auth().deleteUser(uid)`, irreversible; `auth/user-not-found` tolerated.
- Step 3b 2741, Step 4 2755-2790: `authDeletedAt`, final idempotent sweep, record cleared or left for `reconcileAccountDeletions` (defined 2824, every 15 min via `onSchedule`).
- Client: `mobile/lib/features/account_deletion/state/account_deletion_providers.dart:63-94` calls `deleteAccount()` once (`cloud_functions_account_deletion_service.dart:28-34`, `httpsCallable('deleteAccount')`) and, on success, wipes local data and signs out (`:149-169`). There is no begin call, no cancel point and no `FENCED` local state.

What a begin step would have to change (design facts, nothing changed):
1. Split the callable: a begin phase with only reversible pre-checks plus the one commit, and a completion phase. Today the first step already performs the irreversible Stripe cancellation (2573-2625) before any fence; protocol 8.7 wants payment-provider pre-checks first and cancellation only after the commit, so the Stripe cancel moves behind the begin commit (or the pre-check becomes a read-only look at subscription state).
2. Add the one transaction: create `deleted_accounts/{uid}` (`expireAt: null`) and set `migrationState = DELETING` in `users/{uid}/workout_command_policy/current` (the document exists in `functions/src/workout_commands/apply.ts:74`). The existing activity fence (1c) is a separate non-transactional write and cannot serve as that fence; it can stay as is, or be written in the same transaction.
3. Move token revocation (today 1b, before the fence, non-fatal) to after the commit and make it retried until success.
4. Make the begin call idempotent with a client `deletionRequestId` and answers `ALREADY_DELETING` / `NOT_STARTED`; today `deleteAccount` is idempotent as a whole but has no answer codes.
5. Make the completion job set `expireAt = completion + 24 h` on the fence (needs a TTL policy on `deleted_accounts`, none exists, see F3) and extend `sweepAccountData` and the reconciler to treat the fence as part of the deletion inventory.
6. Client: add the begin call, the local `FENCED` checkpoint with `beginAttempted`, and the cancel/"verifying" UI; `account_deletion_providers.dart` must stop treating a single call as the whole flow.
7. Firestore rules: every client-write match must carry the fence check (protocol 8.7); none does today.
Conclusion: the existing durable-intent pattern (`accountDeletionRetries`, reconciler) shows the callable can host forward-only recovery; a dedicated begin step is feasible but changes the ordering of Steps 1, 1b and 1c.

## F10. Do data-write audit logs list client SDK writes, with 30-day retention?

Proven:
- Docs list `Commit`, `BatchWrite`, `Write`, `CreateDocument`, `UpdateDocument`, `DeleteDocument` as DATA_WRITE methods and say requests authenticated with Firebase Auth produce audit logs with the token in `thirdPartyPrincipal` (Firestore audit-logging page above).
- Data Access logs go to `_Default` with 30-day retention by default; `_Required` keeps 400 days but holds only Admin Activity and System Event logs (F5b).
Not proven:
- That client SDK writes in this project appear in practice, with the document path, the write list and a commit time (F5c). The docs page does not mention these fields.
- That DATA_WRITE is enabled: it is not (F5a); nothing has been logged in the last 30 days.
- That an export sink with at least 30 days exists: none exists; only the default sinks.
- The extra volume/cost of DATA_WRITE for every client write (not measured).
Result: NOT VERIFIABLE FROM HERE. Protocol 8.3 item 12 (e) already says the legacy path stays closed (no `DRAIN`) if this is not verified; that remains the correct reading.

## Consequences for the design

| Fact | Does the protocol assumption hold? |
|------|------------------------------------|
| F1 | Holds. `before.createTime` and `before.updateTime` exist in the pinned libraries. Keep the deploy check that compares audit commit time with `after.updateTime`. |
| F2 | Holds. Retry flag exists; window is 24 h, equal to the stated invariant. No Firestore trigger is deployed, so the invariant must be checked at the first deploy. The retry backoff docs apply only at first deploy of a function. |
| F3a | Holds. TTL is available and in use (`accountDeletionRetries`). |
| F3b | Unproven. Keep the protocol fallback (scheduled sweep) until a policy on `workout_command_receipts`, `workout_legacy_events` and `deleted_accounts` is confirmed. TTL deletes fire triggers and run up to about 24 h late, so receipt and fence expiry times are lower bounds. |
| F4 | Does NOT hold today. PITR is off; only the last hour is readable. The watchdog's one-hour exact-read window (protocol 12 (d)) still works, but the 7-day minute-granular fallback does not exist until PITR is enabled. Deploy gate P3 cannot pass yet. No backup schedules exist. |
| F5a | Does NOT hold today. No DATA_WRITE audit config; the authoritative inventory does not exist yet. |
| F5b | Holds at the boundary. `_Default` 30 days meets "at least 30 days"; a custom sink bucket with longer retention gives margin. |
| F5c / F10 | Unproven. `DRAIN` stays blocked (protocol 8.3 item 12 (e)) until captured real entries show the required fields. |
| F6 | Holds. Secret Manager is enabled and in use; a seal-key secret must be created; multiple versions fit the `kid` model; rotation is subscriber-driven, not automatic. |
| F7a | Holds. The method exists in 6.3.0. |
| F7b | Unproven. Keep the marker-document fallback and the rule "no verified flush, no `DRAIN`". |
| F8a | Assumption (none exists) holds; the minimum-version gate is a rollout deliverable (P1), including a remote source and a client check. |
| F8b | Assumption holds; the device registry ("devices seen in the last 90 days", `drainedDevices`) does not exist and must be built before the cutover criterion (b) can be evaluated. |
| F9 | Feasible. Needs the reorder in the list above; the earlier "no deletion tombstone" decision at `functions/src/index.ts:160-175` must be reconciled with the fence document. |

## Open items that need the operator or the console

1. Enable PITR (reversible). Console: Firestore > Disaster recovery > Edit > "Enable point-in-time recovery". Or: `gcloud firestore databases update --database="(default)" --enable-pitr` (command name to confirm with `--help` before running). Then re-read `gcloud firestore databases describe` and expect `POINT_IN_TIME_RECOVERY_ENABLED` and `versionRetentionPeriod: 604800s`. Cost: storage for 7 days of versions.
2. Enable Data Access DATA_WRITE for Firestore. Console: IAM and Admin > Audit Logs > "Cloud Firestore API" (and "Cloud Datastore API" if listed) > check "Data Write". Or add an `auditConfigs` entry with `service: datastore.googleapis.com` and `logType: DATA_WRITE` (the service name used by Firestore audit entries; confirm in the Audit Logs page). Then perform one test client write and read the entry with `gcloud logging read 'logName:"cloudaudit.googleapis.com%2Fdata_access" AND protoPayload.serviceName="firestore.googleapis.com"' --limit=5 --format=json`, to capture the real shape (path, `writes`, commit time, batch and stream forms) for F5c and F10.
3. Create a log sink only if more than 30 days or a separate store is wanted: Logging > Log Router > Create sink (destination: a log bucket with chosen retention, filter on the data_access log of Firestore).
4. TTL on subcollection groups: run a non-production check or a deliberate policy creation: `gcloud firestore fields ttls update expireAt --collection-group=workout_command_receipts --enable-ttl`, then `gcloud firestore fields ttls list` (state CREATING, then ACTIVE). Console path: Firestore > Time-to-live > Create policy. Also needed for `workout_legacy_events` and `deleted_accounts`. Or decide to use the scheduled-sweep fallback.
5. Seal-key secret: create it in Secret Manager (console: Security > Secret Manager > Create secret) and decide the rotation owner (Pub/Sub subscriber or manual).
6. Device test of `waitForPendingWrites`: offline, online-after-offline, and with an old-build stub; needs a physical device or emulator run (F7b).
7. Deploy check of the first Firestore trigger: after the first deploy, confirm `gcloud functions describe <name> --gen2 --region=<region> --format="value(eventTrigger.retryPolicy)"` shows `RETRY_POLICY_RETRY`, and that the delivered event has `before.updateTime` equal to the audit commit time (F1, F2). The region of the functions was not determined here (a describe in us-central1 returned 404).
8. Decision on the `deleted_accounts` tombstone versus the earlier data-minimisation comment (F9, F8b note).
