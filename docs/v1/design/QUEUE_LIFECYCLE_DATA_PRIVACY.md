# Durable command queue: data class, lifecycle and privacy contract

Status: DESIGN PROPOSAL, 2026-10-22. Nothing here is implemented. Closes the document-level part of review finding B-03 (queue lifecycle is not in the data and lifecycle contracts) from `docs/v1/package-amendments/PACKAGE_RECONCILIATION_2026-10-22.md`. It elaborates, and does not change, the 14 binding criteria of `docs/v1/LOCAL_QUEUE_DECISION.md` (cited below as LQ-n). Acceptance rows FU-AC-102 to FU-AC-105 stay as written in `docs/v1/package-amendments/ACCEPTANCE_AMENDMENTS.csv`; this file adds rows from FU-AC-120.

Reader: the package author reissuing the registers, and the engineer who will implement the queue. Package documents named below are under `FitnessUp_v1_Rebaseline_2026-10-20/docs/` (external deliverable, not in this repository). App paths are relative to `D:\Repo\Fitness_App`.

Claim labels: FACT (verified in a file, path cited), DECISION (made by this document within the limits of LQ-n; reversible by the operator), UNKNOWN (not verified or not decided; section 11 lists them).

## 0. Why the package contradicts the decision today

- FACT: `11_SECURITY_PRIVACY.md` section 3 says Option A applies to touch and voice and that an unsent capture may remain "only in the active UI, without durable queuing".
- FACT: `04_CORE_TDD.md` section 6 table row NOT_SENT_OFFLINE is "Active UI unsaved capture only; no rest or saved claim"; the paragraph after the table says the recovery handle "is not a stored unsent payload or an offline operation queue"; section 7 says "No durable manual-draft replacement is introduced".
- FACT: `05_DATA_MODEL.md` has no local command store entity, and its section 6 retention table has no row for unsent device data. The only device-local data classes are LocationEvidence and GeofencePreference.
- DECISION: the queue is a first-class, UID-scoped, device-local data class with its own row in every lifecycle path (sign-out, deletion, export, backup, restore, logs). The rest of this file defines it.

## 1. Data class definition

### 1.1 Name and scope
DECISION: entity `LocalCommandQueue` (working name `PendingWorkoutCommand` for one record). Authority: the device holds the record until the server acknowledges it; the server remains authoritative for committed workout facts (LQ-8). A queue record is never a canonical workout fact in history, progress, coach replies or server export until committed (FU-AC-099).

### 1.2 Fields of one record
DECISION (all fields are required unless marked optional; derived from LQ-2, LQ-4, LQ-6, LQ-9):

| Field | Content | Note |
|---|---|---|
| uid | owner Firebase UID | partition key, see section 2 |
| operationId | client-generated ID, scoped to uid and session | immutable across retries (LQ-4) |
| commandType | CompleteSet, AddEligibleExercise or SetDifficulty | closed enum; unknown type is preserved read-only, never sent |
| sessionId | workout session ID | |
| logicalSetId | session, exercise, set index | CompleteSet only (LQ-4) |
| sequence | per-UID, per-session monotonic integer assigned at the atomic commit | delivery order (LQ-6) |
| dependsOn | operationId of the predecessor, optional | AddEligibleExercise dependency (LQ-6) |
| payload | typed workout values: reps, load in integer grams, difficulty enum, exercise catalogue ID, target values | exactly what the server command needs; no free text |
| payloadHash | hash of the canonical payload bytes | detects local corruption; hash version stored |
| acceptedAt | device clock, UTC | used for the 25 and 30 day thresholds and display only, never as proof of order |
| state | PENDING, SENDING (fenced), UNKNOWN_EFFECT, CONFLICT, HELD_BY_PREDECESSOR | `synced` is not a stored state: an acknowledged record is deleted from the queue only after the acknowledgement is itself durably recorded (section 1.5) |
| attempts, lastAttemptAt, lastErrorClass | retry bookkeeping; error class is an enum, never server text with payload | |
| schemaVersion | integer | unknown future versions are preserved and never rewritten |

Fields that must NOT be stored: display name, email, auth tokens, ID tokens, App Check tokens, location, photos, audio, transcripts, free text typed or spoken by the user, health flags, allergens, injury answers. FACT: protected health fields are device-only by `11_SECURITY_PRIVACY.md` section 2 and are held under `profile.sensitive.<uid>` in `mobile/lib/features/account_deletion/data/local_data_wipe.dart`; the queue must never copy from them. A payload that would need such a field is refused at admission as a design error, not stored.

Privacy classification: DECISION: the payload is workout data (personal data, health-adjacent, not special-category protected fields by the package's own classification) and is handled like `WorkoutSession` data, not like the protected onboarding flags.

### 1.3 Storage location
DECISION: a single app-private store inside the application documents directory, partitioned by UID (one logical store or one file per UID; the engine is an implementation choice, section 11). It is not placed in `SharedPreferences`.
- FACT: `FlutterSharedPreferences.xml` is a plaintext file excluded from backup, holds the health blob, and is read in whole (`mobile/android/app/src/main/res/xml/backup_rules.xml` comments). Putting up to 500 commands there would make a size-bounded, whole-file read-modify-write path the durability mechanism, which LQ-2 (one atomic unit) does not allow.
- FACT: `pubspec.yaml` has no SQLite or embedded database dependency (grep of `mobile/pubspec.yaml` for sqflite, drift, isar, hive, sqlite returned nothing); `path_provider` and `flutter_secure_storage` are present. The choice of engine is therefore a new dependency decision (UNKNOWN U1).
- Required engine property, DECISION: a single transaction commits command, operationId and payload together (LQ-2); a crash leaves the whole record or nothing; the store reports a commit failure to the caller before the UI shows "pending sync".

### 1.4 Encryption at rest
DECISION: no app-level encryption key for the queue in v1. Protection is the OS app sandbox plus OS device encryption plus backup exclusion (section 1.6).
Rationale:
1. FACT: the progress-photo envelope key lives in the Keystore and the existing comments record that a key lost or not restored leaves "undecryptable files the user cannot delete" (`data_extraction_rules.xml` comment; `photo_key_store.dart` handles "present but unreadable" as a distinct failure). An unreadable queue would turn a Keystore reset into silent loss of unacknowledged commands, which LQ-3 forbids. An app-level key adds a new way to lose data and no new protection against the stated threat (another app or backup extraction), because the sandbox and backup exclusion already cover those.
2. The payload contains no direct identifiers (section 1.2); the UID is the only identifier.
3. Residual risk, stated: a rooted device or a forensic image of an unlocked device can read the queue. Accepted for workout values.
If the operator or the privacy review requires encryption at rest, the condition is that a key-loss path preserves the commands (for example export of plaintext before any key reset) and that FU-AC-093 is re-run (UNKNOWN U2).

### 1.5 Acknowledgement and removal
DECISION: a record leaves the queue only by (a) a server acknowledgement that matches operationId and payloadHash, recorded durably before deletion of the record, (b) a user-confirmed discard (section 3), (c) account deletion (section 4). Never by age, size, app update, schema migration or low storage (LQ-3). A conflict acknowledgement moves the record to CONFLICT; it is not removed (LQ-5, LQ-9).

### 1.6 Backup and cloud restore
FACT: the manifest sets both `android:fullBackupContent="@xml/backup_rules"` and `android:dataExtractionRules="@xml/data_extraction_rules"` (`mobile/android/app/src/main/AndroidManifest.xml:41-42`); `allowBackup` is not set, so Android Auto Backup is on by default (comment in `backup_rules.xml` line 35-36). The files exclude exactly: `app_flutter/progress_photos`, `FlutterSharedPreferences.xml`, `FlutterSecureStorage.xml`, `FlutterSecureKeyStorage.xml`, in `cloud-backup` and `device-transfer`. The documents directory resolves to `app_flutter` (comment in `backup_rules.xml`). Everything else is backed up. `mobile/test/android/backup_rules_test.dart` asserts the four exclusions and that the two XML files exist.
FACT: no iOS exclusion flag exists in the repository (grep for isExcludedFromBackup / NSURLIsExcludedFromBackupKey in `mobile` returned nothing).

DECISION: the queue is explicitly EXCLUDED from Android cloud backup and device-to-device transfer, and from iCloud/iTunes backup. Reasons:
1. A restored copy would put the same operationIds and sessions on a second install while the original still sends them: two senders for one logical set (LQ-5), and a restore after the commands were acknowledged would replay acknowledged commands against receipts that may have expired (LQ-7).
2. The operationId is bound to a session on a particular device; a restored queue on a new device has no writer-epoch standing (`04_CORE_TDD.md` section 5 writer fencing).
3. It keeps the photo-consent precedent: do not let a user-visible promise ("kept on this device") be false on one route.
Consequences (user is told, section 8): a user who restores or changes phones loses unsent commands that were never synced. This is the price of not creating duplicates; export is the user's way to carry them (section 5).

Required changes, DECISION: add the queue directory/file path to both `backup_rules.xml` and `data_extraction_rules.xml` (cloud-backup and device-transfer sections) in the same change that creates the store; extend `backup_rules_test.dart` to assert the new path in all three sections (FU-AC-120). On iOS set the exclude-from-backup attribute on the store location and test it (UNKNOWN U3: no iOS build evidence in this review).
The queue path must be a dedicated directory name so a single `exclude` rule covers it, unlike `FlutterSharedPreferences.xml` which is whole-file.

## 2. UID scoping and access rules

DECISION:
1. Every read, write, send and count takes an explicit uid argument. No API reads "the current queue" without a uid. The uid used for a send is the uid stored in the record, never the currently signed-in uid.
2. A sender may send a record only when the Firebase Auth user equals the record's uid at the moment of sending and the token used was minted for that uid. If they differ the record is skipped, not failed, and not modified.
3. The UI and any code running for account B can read only B's partition and cannot enumerate other partitions. The count shown on B's sign-out sheet is B's count only. The only cross-UID listing is a uid-only list used by the interrupted-wipe sweep (section 4.3), which returns UIDs and counts, never payloads. FACT: the existing pending-wipe marker holds "uids only, never health data" (`local_data_wipe.dart:45-60`); the same restraint applies.
4. Shared-device rule: account switching A to B to A. A's partition is untouched while B is signed in; no send of A's records happens under B; on A's return the sender resumes with the same operationIds. B's own partition is created lazily and is empty at first use (LQ-11, FU-AC-102).
5. Partition keys use the opaque UID in a directory name only after the same validation the wipe code applies (`_looksLikeUid`: non-empty, not `.` or `..`, no `/` or `\`; `local_data_wipe.dart:153-158`).
6. Cap scope: the 500 command cap (LQ-3) applies per UID. A global device cap is not set (UNKNOWN U4: confirm that several accounts on one phone are an accepted case for storage size).
7. An unreadable or corrupt partition is preserved and reported ("could not read saved sets"), never recreated empty. FACT precedent: unreadable health blobs are quarantined, not overwritten (`mobile/lib/features/profile/data/local_sensitive_store.dart:62-108`).

Failing scenario for FU-AC-102 (concrete): A queues 3 sets offline and signs out choosing "keep"; B signs in on the same phone, goes online, and the sender runs. Expected: 0 requests carrying A's operationIds, B's queue count 0, B cannot see A's count. Then A signs in: 3 records still PENDING with unchanged operationId and payloadHash, sent under A's token. Failure if any record is sent while B is signed in, deleted, or re-keyed.

## 3. Sign-out

### 3.1 Current behavior
FACT: the profile screen signs out in one tap with no sheet: `mobile/lib/features/profile/profile_page.dart:276-278` calls `ref.read(authActionProvider.notifier).signOut()`; `mobile/lib/features/auth/state/auth_providers.dart:55-58` forwards to the repository. FACT: no `waitForPendingWrites`, `clearPersistence` or `persistenceEnabled` appears anywhere under `mobile/lib` (grep returned nothing); Firestore SDK offline persistence is therefore at defaults.
UNKNOWN U5: the "cannot-check" sheet referred to in LQ-12 and `04_CORE_TDD.md` section 6 ("Preserve S04 cannot-check/wipe guards") was not found in the committed app: no cannot-check string exists in `mobile/lib/l10n/app_en.arb` for sign-out (matches are only for subscription plan and machine health checks), and `11_SECURITY_PRIVACY.md` says the S04 pre-unbind registry exists in a "local integration working file". The new variant is specified here independent of that sheet's code; if the sheet lands, the pending-commands variant is a sibling state of it, not a replacement.

### 3.2 Sheet states
DECISION. The sheet appears when the signed-in UID has at least one record in any state, before any auth state changes. With zero records sign-out is the current immediate behavior.

| State | When | Content | Actions |
|---|---|---|---|
| S1 Choice | online, N records | "You have N workout entries saved only on this phone." and the count of those held or in conflict if any | Sync first (primary); Keep on this phone; Export, then remove from this phone; Cancel |
| S1-off Choice, offline | no network | same text plus "You are offline, so they cannot sync now." | Sync first disabled with that reason; the other three remain |
| S2 Syncing | after Sync first | progress "M of N sent", per-record result as they are acknowledged | Stop waiting (returns to S1 with current counts); Cancel sign-out |
| S3 Partial result | sync finished but K records remain (conflict, held, error, unknown effect) | "K entries could not sync. They are kept." with reasons by class | Keep on this phone; Export, then remove; Try again; Cancel |
| S4 Done | queue empty | "All entries are synced." then sign-out completes | none; sign-out proceeds |
| S5 Export | after Export, then remove | file is written first; success shows file name and entry count | Remove from this phone (enabled only after a verified export); Cancel |
| S5-fail | export failed | "Export failed. Nothing was removed." | Try again; Keep on this phone; Cancel |
| S6 Discard confirmation | the only path to discard without export | see 3.4 | Remove N entries permanently; Cancel |

Copy requirements, DECISION:
- Every state names the number of entries in plain words and says whether they are "saved only on this phone".
- "Keep on this phone" says: "They stay on this phone for this account only. Another account cannot see them. They are sent the next time you sign in to the same account. If you delete the app or change phones, they are lost."
- Never use "synced" for a record without a server acknowledgement (LQ-8).
- Offline copy must not imply server revocation took place. FACT: `04_CORE_TDD.md` section 6: "Offline logout cannot acknowledge server revocation. The UI must not imply that it did."
- A record in UNKNOWN_EFFECT is described as "may already be saved on the server".
- All strings go through `mobile/lib/l10n` (`app_en.arb` and the other locale files); copy is English in git.

### 3.3 Three outcomes (LQ-12)
1. Sync first: sender runs for this UID; sign-out proceeds only when the queue is empty or the user moves to S3.
2. Keep: partition remains; auth is released after fencing (3.5). The sender stops for that UID.
3. Export, then discard: export (section 5) completes and is verified (file exists, entry count equals the snapshot count), then the partition is cleared after the user taps Remove.

### 3.4 Discard without export (explicit confirmation)
DECISION: the S1 sheet has no direct "discard" button. Discard without export is reachable only through "Export, then remove" by declining the file step ("Remove without saving a file") which opens S6. S6 text: "Remove N entries permanently? They are not saved on any server and cannot be recovered." The button label contains the number: "Remove N entries". N is the live count read in the same transaction that performs the removal; if the count changed since the sheet was shown (a late acknowledgement), the sheet reloads and asks again. Entries in UNKNOWN_EFFECT are listed separately as "M may already be saved".

### 3.5 In-flight fencing
DECISION:
1. Entering any sign-out path sets a per-UID fence token `SIGNING_OUT` durably before anything else. The sender checks the fence before taking a record for SENDING and again immediately before writing to the network.
2. If a send is in flight, sign-out waits for one of: acknowledgement, a definitive failure, or cancellation of the call. Bounded wait (value frozen with the implementation, UNKNOWN U6); on timeout the record is set to UNKNOWN_EFFECT (not deleted, not re-keyed) and the UID binding is released only after the fence is durable.
3. The late response of a cancelled or timed-out send is applied to the record of its own uid only (state change or acknowledgement), never to the signed-in user. If the response says committed, the record becomes acknowledged under its own uid; if the user discarded, the late response changes nothing client-side and the server holds a committed set (stated in the S6 copy via "may already be saved").
4. The fence is cleared only by a new sign-in of the same uid (resume) or by discard/deletion.
Failing scenario for FU-AC-103: 5 records, record 3 in flight, user taps Sign out then Keep. Expected: no record sent after the fence token is written; record 3 ends as acknowledged or UNKNOWN_EFFECT with unchanged operationId; sign in as B within 1 s sends 0 of A's records; sign in as A resends only record 3 (if unknown) and 4, 5 with the original IDs and the server reports record 3 as same-ID-same-payload success. Failure: any request for A's operationId bearing B's token; a record lost; a record with a new operationId.

## 4. Account deletion

### 4.1 Current behavior
FACT: `mobile/lib/features/account_deletion/state/account_deletion_providers.dart:94-172` calls the `deleteAccount` Cloud Function first, and only after server confirmation records the uid in the pending-wipe marker (set of uids in SharedPreferences, key `account_deletion.pending_wipe_uids`), wipes device data, cancels notifications and signs out. The comments at lines 113-122 say the device wipe is deliberately after the server call so a failed deletion never wipes a still-live account. FACT: `DeviceLocalDataWipe.wipe` erases an exact list of preference keys, `progress_photos/<uid>/` and `coach_recordings/<uid>/`; it has no queue step (`local_data_wipe.dart:243-339`). FACT: `accountBeingDeletedUidProvider` lets in-flight writers abort (`account_deletion_providers.dart:24-29`) but it is set only after server confirmation.

### 4.2 Required ordering (LQ-13)
DECISION, with the deliberate difference from the existing health-data order stated in 4.4:
1. User confirms deletion on the existing page; if the queue is non-empty the page first shows the count and offers Export (section 5). Declining export is allowed (the account is being erased anyway).
2. Write durable checkpoint `DELETE_FENCING(uid)` (a uid-only record; section 4.3). From here the sender refuses all records of this uid and refuses new commands with a visible message.
3. Cancel in-flight sends; each is resolved to acknowledged or UNKNOWN_EFFECT; late responses are ignored client-side from here on.
4. Write checkpoint `DELETE_QUEUE_CLEARING`, clear the uid partition, verify it is empty, write `QUEUE_CLEARED`.
5. Call the `deleteAccount` Cloud Function. On success write `SERVER_DELETED`, then run the existing steps (marker add, `LocalDataWipe.wipe`, notification cancel, sign-out).
6. No resurrection by a late send: (a) the client cannot send because the queue is cleared and fenced; (b) a command already in flight before step 2 whose request reaches the server after deletion must be rejected by the server's deletion tombstone and generation fence. FACT: `11_SECURITY_PRIVACY.md` section 6 and `05_DATA_MODEL.md` section 8 require tombstones/generation fences so "late uploads, worker results or commands" cannot recreate erased state. UNKNOWN U7: that this fence is implemented for workout commands in the `deleteAccount` function (functions code was not inspected in this review); the acceptance test FU-AC-104 is the gate.

### 4.3 Deletion checkpoint and crash recovery
DECISION: the checkpoint is a uid-only record stored outside the queue partition, next to the existing pending-wipe marker, holding uid, stage enum, and timestamps; no payload. It is written with the same durability as queue commits.
Recovery on next launch, for every checkpoint found, regardless of who is signed in:
| Crash after | State found | Recovery |
|---|---|---|
| step 2 | DELETE_FENCING | queue stays fenced and unsendable; if the signed-in user is that uid, ask "Finish deleting your account?" with Continue and Cancel deletion; Cancel removes the checkpoint and the fence, queue intact |
| step 4 started | DELETE_QUEUE_CLEARING | complete the clear (idempotent); do not resume sending; continue to step 5 only if the user is signed in and confirms, else leave fenced |
| step 4 done | QUEUE_CLEARED | the same, now with an empty queue; call `deleteAccount` again |
| step 5 sent, response lost | QUEUE_CLEARED | call again; FACT: server `deleteAccount` is idempotent per the comment at `account_deletion_providers.dart:88-93` |
| step 5 succeeded | SERVER_DELETED | run the existing interrupted-wipe sweep (`finishInterruptedWipe`) and sign out |
Cancel deletion is possible only before step 4 started; after that the queue is gone and the user is told (4.4).

### 4.4 Difference from the current order, and why
FACT: the current order protects against wiping a live account's data when server deletion fails. DECISION: the queue is cleared before the server call because LQ-13 requires it and because the alternative (clear after) leaves a window where a pending command can be sent after the server data is gone. The cost: if the server deletion then fails, the account is live with an empty queue. Mitigation: the confirmation names the count, offers Export, and the failure message states that unsynced entries were already removed at the user's request. The health blob and photos keep the existing "after server confirmation" order (no change).
Contradiction record: this is the one place where the existing code comment (wipe only after the server call) and LQ-13 pull in different directions; resolved as above, scoped to the queue only.

### 4.5 Failing scenario for FU-AC-104
Delete during sync with 10 pending (3 in flight), kill the process after step 3, again after step 4, again after step 5 request; after each restart complete the flow. Expected: no server document under `workout_sessions` or the command admission/receipt collections for that uid exists after finalization; the queue partition is gone; the checkpoint is removed after wipe. Failure: any document reappears, or the queue is sent after the first restart.

## 5. Export

### 5.1 Current behavior
FACT: `DataExportAction.export` (`mobile/lib/features/data_export/data_export_providers.dart:32-137`) reads profile, workout history through `exportAll`, schedule, programmes and photo metadata with 30 s timeouts and a server callable, builds JSON via `buildExport` (`data_export.dart:34-110`, `exportFormatVersion: 1`, `notes`, `serverIncomplete`) and hands it to a sink. FACT: `workoutLogs` there comes from server-or-SDK-cache repositories, so it does not contain a queue.

### 5.2 Snapshot rules
DECISION:
1. The export reads the queue partition of the signed-in UID in one read transaction (a consistent snapshot) and includes every record in every state: PENDING, SENDING, UNKNOWN_EFFECT, CONFLICT, HELD_BY_PREDECESSOR (LQ-14).
2. It works offline: the queue snapshot has no network dependency and is always included. The server part stays best-effort as today (`serverIncomplete`). The export never fails because the network is down.
3. Records acknowledged between snapshot and file write are listed both ways without harm: the file states the snapshot time; each record carries its state at snapshot time.
4. Records that were exported are not removed unless the user chose Export, then remove (sign-out) or the export belongs to account deletion.

### 5.3 Format
DECISION: bump the top-level format to `exportFormatVersion: 2` (UNKNOWN U8: whether a reader of version 1 exists outside the app) and add:
```
"deviceOnlyCommands": {
  "snapshotAt": "<UTC ISO-8601>",
  "count": <int>,
  "commands": [ { "operationId", "commandType", "sessionId", "logicalSetId?",
                  "sequence", "state", "acceptedAt", "attempts", "lastErrorClass?",
                  "dependsOn?", "payload": { typed workout values } } ]
}
```
plus a note in `notes`: "These entries exist only on this phone and are not part of your synced history." The uid is already at `profile.uid`. Conflicted records carry the conflict class only, not server internals. Payload values use the same integer-gram load and difficulty enum names as the command contract (`05_DATA_MODEL.md` section 8).
A pending record must never be added to `workoutLogs` (that would double-count after sync; FU-AC-099).

### 5.4 Relation to server export
The server export remains the authority for committed data. DECISION: when both are present, an entry appearing in `deviceOnlyCommands` and as a committed set (acknowledgement between reads) is deduplicated by operationId in the importing reader, not by the exporter. The exporter always labels the origin. The server-side `workout_command_receipts` are not exported as workout facts; they are protocol metadata (`05_DATA_MODEL.md` section 8).

### 5.5 Failing scenario for FU-AC-105
Airplane mode, 15 pending and 2 conflicted records, run export. Expected: file contains `deviceOnlyCommands.count == 17`, each operationId present once, server note set to incomplete, no network call attempted for the queue part. Failure: export aborts offline, includes only 15, or the 15 appear in `workoutLogs` too.

## 6. Retention and limits (fail closed)

DECISION (values are the proposals of LQ-3, not new numbers):
| Threshold | Behavior |
|---|---|
| 400 pending records for a UID | visible warning "Your phone holds 400 unsent entries" with a link to sync/export |
| oldest pending is 25 days old | visible warning with the date of the oldest entry |
| 500 pending records | the 501st is refused before acceptance with a visible message and no pending state shown; all 500 remain; the user can sync, export, or explicitly discard |
| 30 days | aging warning (stronger copy); NOT an eviction deadline |

Rules:
- Count includes every state except acknowledged records. CONFLICT and HELD records count toward 500 because they are not removed automatically.
- Failing closed also covers storage errors: if a commit fails (disk full, I/O error) the command is reported "not saved" and the UI never shows pending (LQ-2).
- Age uses the device clock; a clock change cannot trigger any removal. A negative age (clock moved back) is treated as 0 and logged by class only.
- Receipt capacity must satisfy LQ-7: server receipt retention per user >= 500 + the retention window. FACT: the data model proposes 90 days for detailed admissions and receipts (`05_DATA_MODEL.md` section 6), and a record may stay on the device longer than 90 days (no eviction). DECISION: therefore a record older than the detail TTL must still be handled by the compact replay fence (`05_DATA_MODEL.md` section 8: "compact replay/deletion fences outlive detail TTL"); the server answers OUTCOME_EXPIRED for it, the client keeps it as CONFLICT with the copy "Too old to confirm automatically" and offers export, never auto-discard (FU-AC-094, FU-AC-098).
- Sign-out and app update never change counts.

## 7. Telemetry and logs

DECISION:
1. No payload content in any log, crash report, analytics event, error message or remote-config check: no reps, loads, exercise names, session IDs, operationIds, UID, command text or counts per exercise.
2. Allowed (enums and aggregates only): outcome class (accepted, refused_cap, refused_commit_failed, acknowledged, conflict, unknown_effect, held), queue size bucket (0, 1-10, 11-100, 101-399, 400-499, 500), oldest-age bucket (days: 0-6, 7-24, 25-29, 30+), attempts bucket, latency bucket, error class enum.
3. FACT: `firebase_crashlytics` is a dependency (`mobile/pubspec.yaml:94`); existing code already logs only `e.runtimeType` where the exception text would carry a uid-named path (`local_data_wipe.dart:305-309`). The queue follows this rule: log the exception type only; never `$e` of a record-carrying object; Crashlytics custom keys must not carry record fields.
4. The queue's `toString` and error messages are redacted by construction (no payload in `toString`), so an accidental `debugPrint(record)` prints nothing sensitive.
5. Server logs for received commands follow `17_RELEASE_OPERATIONS.md` ("Redact sensitive data from logs"); the unknown-command age and queue depth metrics listed there are fed by bucketed client signals only if consent for diagnostics permits (UNKNOWN U9).
Acceptance: FU-AC-122.

## 8. Restore, reinstall and new device

DECISION:
1. Queued commands never travel to another device: they are excluded from cloud backup and device transfer (section 1.6), not uploaded to a server, and not part of the passphrase backup file. FACT: the existing encrypted backup file (`mobile/lib/features/data_export/backup_envelope.dart`) is a carried profile/health backup with a user passphrase; it does not include the queue and will not.
2. On reinstall, restore or new phone, signing in shows an empty queue. If the app can detect that the previous install existed (it cannot reliably, UNKNOWN U10), no claim is made. The in-app text at Keep and in the sign-out sheet (3.2) is the user's notice; a short note is also added to the onboarding/settings data-and-backup page: "Entries not yet synced stay on this phone and are not included in backups or phone transfers. Sync or export them before changing phones."
3. Committed workout data is unaffected: it is on the server and appears after sign-in.
4. Server restore (`17_RELEASE_OPERATIONS.md` section 7): a restored server must not accept a replay of commands whose receipts were lost in the restore window as a fresh mutation. This is the existing "reapply deletions and closed epochs" obligation; the queue adds the case "device holds a record the restored server has no receipt for". Handling: the server treats it as a normal first delivery (it has no effect recorded); duplication risk is closed by the logical set ID rule (LQ-5), which is why that rule must be enforced on the committed session state, not only on receipts (UNKNOWN U11: confirm in the core design).

## 9. Voice transcripts and audio

DECISION: the queue stores no audio, no transcript, no recognition hypothesis and no recognized-text snippet. A voice "complete set" and a touch "complete set" produce the identical record (LQ-10): typed fields only, with no field recording the input modality (a modality field would be metadata about speech use and is not needed; UNKNOWN U12: whether product analytics wants it, answered by default as no).
- FACT: `VOICE_READY_PROMPT_DECISION.md`: "Audio and transcripts are not stored"; StartSet is not a queued command, records nothing.
- Ambiguous or low-confidence speech never enters the queue as a guess; only a confirmed typed command is accepted.
- Cancelling or invalidating a waiting context (route change, background, sign-out) leaves no queue entry.
Acceptance: FU-AC-123 (inspect the store and logs after a voice session for any audio or text field).

## 10. Changes required per document

Package (`FitnessUp_v1_Rebaseline_2026-10-20/docs/`), by the package author:
| File | Section | Change |
|---|---|---|
| `05_DATA_MODEL.md` | 2 entity dictionary | add `LocalCommandQueue` row (device-local, UID-partitioned, fields of 1.2) and `QueueLifecycleCheckpoint` (uid, stage) |
| `05_DATA_MODEL.md` | 6 retention table | add rows: queue (until acknowledged/exported/discarded, 400/500/25/30 thresholds); deletion checkpoint (until finalization) |
| `05_DATA_MODEL.md` | 7 migration | state that Firestore SDK pending writes and the new queue are two generations (see doc 14) and that the queue is excluded from backup |
| `04_CORE_TDD.md` | 6 outcome table and paragraph after it | replace NOT_SENT_OFFLINE; remove "not a stored unsent payload or an offline operation queue"; add local states and the logout paragraph pointing to sections 3 and 3.5 |
| `04_CORE_TDD.md` | 7 | remove "No durable manual-draft replacement"; replace with the queue and drain/preservation of SDK writes |
| `11_SECURITY_PRIVACY.md` | 2 data-flow table | add row "Queued workout commands" (device only, UID partitioned, excluded from backup, no payload in logs) |
| `11_SECURITY_PRIVACY.md` | 3 | replace the Option A paragraph; local acceptance precedes admission |
| `11_SECURITY_PRIVACY.md` | 6 | add the sign-out sheet outcomes, fencing and deletion order (4.2); the "UID-scoped encrypted gym photos remain intact" sentence gets a queue sibling |
| `11_SECURITY_PRIVACY.md` | 7 | add negative tests FU-AC-120 to FU-AC-125 to the pre-release list |
| `12_ACCEPTANCE_AND_TEST_STRATEGY.md` | register | add rows from `ACCEPTANCE_AMENDMENTS.csv` and the new rows below |
| `14_INTEGRATION_MIGRATION_RUNBOOK.md` | pending writes | two generations: legacy SDK writes and the queue; drain before cutover |
| `15_DECISIONS_AND_RISKS.md` | ADR-CMD-03 | supersede; add an ADR "Queue is a first-class UID data class, excluded from backup, unencrypted at app level" with the alternatives in 1.4 |
| `17_RELEASE_OPERATIONS.md` | section 7 restore, section on logs | add queue to restore notes (8.4) and to log redaction |
| `16_DOCUMENT_REGISTRY.md` | register | add this file |

Repository (`D:\Repo\Fitness_App` after implementation, by the implementer):
| File | Change |
|---|---|
| `mobile/android/app/src/main/res/xml/backup_rules.xml` | exclude the queue directory |
| `mobile/android/app/src/main/res/xml/data_extraction_rules.xml` | exclude it in cloud-backup and device-transfer |
| `mobile/test/android/backup_rules_test.dart` | assert the new path in all three sections |
| `mobile/lib/features/account_deletion/state/account_deletion_providers.dart` | new ordering and checkpoint (section 4) |
| `mobile/lib/features/account_deletion/data/local_data_wipe.dart` | add queue clear step and `queue` to `remaining`; keep best-effort contract |
| `mobile/lib/features/profile/profile_page.dart` | sign-out opens the pending-commands sheet when records exist |
| `mobile/lib/features/data_export/data_export.dart` and `data_export_providers.dart` | `deviceOnlyCommands`, format version 2 |
| `mobile/lib/l10n/app_en.arb` (and locale files) | sheet and warning strings |
| `docs/v1/package-amendments/ACCEPTANCE_AMENDMENTS.csv` and `SUPERSESSION.csv` | add FU-AC-120 to FU-AC-125 and the supersession of Option A rows, outside this document's scope |

### Acceptance obligations
Existing rows, with the concrete failing scenarios of sections 2, 3.5, 4.5, 5.5:
| Row | Failing scenario that must be caught |
|---|---|
| FU-AC-102 | sender uses the current user's token for another UID's record; partition deleted on switch; count of other UID visible |
| FU-AC-103 | request for A's operationId after the fence; record lost on timeout; a new operationId after resume; sheet with a direct discard button; S6 without the number |
| FU-AC-104 | any `workout_sessions` or receipt document reappearing after deletion with a send racing; queue sent after the first restart; deletion without checkpoint losing track after a kill |
| FU-AC-105 | offline export missing conflicted records; pending records also appearing in `workoutLogs` |

Proposed new rows (status NOT_RUN, priority P0 unless noted, same columns as the CSV):
| ID | Requirement/task | Scenario | Expected result |
|---|---|---|---|
| FU-AC-120 | FU-RQ-013 | Backup and transfer exclusion | The queue path is excluded in `backup_rules.xml`, in `data_extraction_rules.xml` cloud-backup and device-transfer, and flagged excluded on iOS; a restore or transfer to a second device yields an empty queue and the first device still sends once. Test: static assertion plus a device or emulator backup/restore run (extends `backup_rules_test.dart`). |
| FU-AC-121 | FU-RQ-049 | Deletion checkpoint crash recovery | Kill at each stage of section 4.3; after each restart no queue record is sent, the flow completes or is cancelled only before stage 4, and no marker or checkpoint remains after finalization. |
| FU-AC-122 | FU-RQ-013 | No payload in logs and telemetry | With a log capture and a Crashlytics test sink, run accept, sync, conflict, cap refusal, sign-out and deletion; no payload value, operationId, UID or exercise name appears in any captured line or key; bucketed fields only. |
| FU-AC-123 | FU-RQ-019 | No audio or transcript in the store | After 20 voice-initiated queued commands and 20 rejected utterances, the store and logs contain no audio, no transcript and no modality field; rejected utterances created 0 records. |
| FU-AC-124 | FU-RQ-049 | Export format and offline snapshot | Export schema validation of `deviceOnlyCommands` (fields of 5.3, `exportFormatVersion` 2), consistent snapshot while a send acknowledges a record mid-export, export works with the network off, and export never fails on a corrupt record (it is included as raw with a flag). |
| FU-AC-125 | FU-RQ-015 | Per-UID cap, warnings and old-record handling | 500 for UID A leaves UID B able to accept; a record older than the 90-day detail TTL is kept as CONFLICT with the "too old" copy, offered for export, and never removed by age; clock moved back by 40 days and forward by 40 days removes nothing. |
| FU-AC-126 (P1) | FU-RQ-013 | Sign-out sheet state coverage | Each state S1 to S6 is reachable and shows the exact count; offline disables Sync first with a reason; export failure keeps all records; discard needs S6 and the number in the button. Widget test with golden-free assertions on text and enabled state. |

## 11. UNKNOWNs
| ID | Question | Why it matters / default |
|---|---|---|
| U1 | Which storage engine implements the atomic local commit (new dependency)? | Needs a dependency review; must pass FU-AC-093; not decided here |
| U2 | Is app-level encryption required by the privacy review? | Default is no (1.4); a yes changes key-loss design |
| U3 | iOS exclusion and data protection class | no iOS evidence in this review |
| U4 | Is there a device-wide cap for many accounts on one phone? | default per UID only |
| U5 | The existing cannot-check sign-out sheet is not in the committed app | new sheet specified without its code |
| U6 | Bounded wait for an in-flight send during sign-out | value to freeze at implementation |
| U7 | Server `deleteAccount` tombstone/generation fence for workout commands | functions code not inspected; FU-AC-104 gates it |
| U8 | Readers of export format version 1 outside the app | decides whether bumping to 2 is safe |
| U9 | Whether diagnostics consent permits bucketed queue metrics | |
| U10 | Whether a reinstall can be detected to warn about lost entries | default: no claim |
| U11 | LQ-5 uniqueness enforced on committed session state, not receipts only (needed after receipt expiry or server restore) | belongs to the core design (B-02) |
| U12 | Whether product analytics wants an input-modality field | default: not stored |

Contradictions found with existing material (none with LQ-1 to LQ-14):
1. Existing deletion order (server first, wipe after) versus LQ-13 (clear queue before server delete): resolved in 4.4 for the queue only.
2. The package's `04_CORE_TDD.md` sections 6 and 7 and `11_SECURITY_PRIVACY.md` section 3 still state Option A (already recorded as B-01/B-03 in the reconciliation); not changed here.
3. LQ-12 calls the cannot-check sheet existing; it is not in the committed app (U5).
4. The 90-day detail TTL (`05_DATA_MODEL.md` section 6) is shorter than the unbounded queue age (LQ-3); handled in section 6 by OUTCOME_EXPIRED plus keep, which needs the compact fence to outlive detail records (already in the data model).
