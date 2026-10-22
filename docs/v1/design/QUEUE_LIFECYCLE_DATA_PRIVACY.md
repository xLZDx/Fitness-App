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
FACT (verified in the design worktree): the manifest sets both `android:fullBackupContent="@xml/backup_rules"` and `android:dataExtractionRules="@xml/data_extraction_rules"` (`mobile/android/app/src/main/AndroidManifest.xml:53-54`); `allowBackup` is not set, so Android Auto Backup is on by default. Each of `backup_rules.xml` (lines 59-69, `full-backup-content`) and `data_extraction_rules.xml` (lines 36-46 `cloud-backup`, lines 47-57 `device-transfer`) excludes exactly NINE entries: `root:app_flutter/progress_photos`, `root:app_flutter/scan_history`, `sharedpref:FlutterSharedPreferences.xml`, `sharedpref:FlutterSecureStorage.xml`, `sharedpref:FlutterSecureKeyStorage.xml`, and `file:journal`, `file:sources`, `file:quarantine`, `file:activity_journal`. The documents directory resolves to `app_flutter` and `domain="file"` is `getFilesDir()` (comments in `backup_rules.xml`). Everything else is backed up. `mobile/test/android/backup_rules_test.dart` asserts the exact nine-entry set in all three sections (`_expectExactly`, lines 66-78); `mobile/test/features/activity/repository/backup_exclusion_test.dart:142` asserts `kActivityBackupExcludedDirs` has length 4.
FACT: there is no exclusion for the `databases` domain, and grep of `mobile/lib` for `persistenceEnabled`, `clearPersistence` and `waitForPendingWrites` returned nothing. So the Firestore offline cache, including legacy SDK pending writes, is not excluded and, on Android, rides default Auto Backup if it is stored under the databases directory (UNKNOWN U13: the exact Firestore cache location and whether a restored cache is usable were not verified).
FACT: no iOS exclusion flag exists in the repository (grep for isExcludedFromBackup / NSURLIsExcludedFromBackupKey in `mobile` returned nothing).

DECISION: the queue is explicitly EXCLUDED from Android cloud backup and device-to-device transfer, and from iCloud/iTunes backup. Reasons:
1. A restored copy would put the same operationIds and sessions on a second install while the original still sends them: two senders for one logical set (LQ-5), and a restore after the commands were acknowledged would replay acknowledged commands against receipts that may have expired (LQ-7).
2. The operationId is bound to a session on a particular device; a restored queue on a new device has no writer-epoch standing (`04_CORE_TDD.md` section 5 writer fencing).
3. It keeps the photo-consent precedent: do not let a user-visible promise ("kept on this device") be false on one route.
Consequences (user is told, section 8): a user who restores or changes phones loses unsent commands that were never synced. This is the price of not creating duplicates; export is the user's way to carry them (section 5).

Required changes, DECISION:
1. Placement choice. Option (a), preferred: place the queue under the already excluded `activity_journal` tree or another already excluded directory. Then no XML line is needed, but the placement must be asserted by a test that walks the directory the real factory creates (the pattern the S04 test uses, per the `backup_rules.xml` comment), because a later move would silently break the promise. Option (b): a dedicated directory name with a new `exclude` line in all three sections. Either way the final exclusion set is asserted statically.
2. Extend `backup_rules_test.dart` so `_expectExactly` states the FINAL exclusion set (the nine current entries plus any new queue and Firestore-cache entries) in all three sections (`full-backup-content`, `cloud-backup`, `device-transfer`) (FU-AC-120).
3. Firestore cache and legacy pending writes, DECISION with consequences: add the Firestore cache location (`database` domain, exact path to be verified, U13) to the same exclusion work item, because the legacy pending writes are the first generation of the same class of unsent data and have the same duplicate-sender problem (a restored cache can resend writes the original install already sent). Consequence if instead it is left included: a restore or transfer can resurrect old unsent legacy writes on a new install. Consequence of excluding: a user who restores to a new phone loses the Firestore read cache (rebuilt from the server) and any legacy unsent writes, which is the same loss the queue accepts. The chosen default is to exclude; reversible by the operator.
4. On iOS set the exclude-from-backup attribute on the store location and test it (UNKNOWN U3: no iOS build evidence in this review).

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
FACT (corrects an earlier draft of this file, which wrongly said sign-out was a single tap): the profile sign-out tile calls the guard first: `mobile/lib/features/profile/profile_page.dart:287-291` runs `if (await confirmSignOutWithLocalData(context, ref)) { await ref.read(authActionProvider.notifier).signOut(); }`.
FACT: `mobile/lib/features/activity/state/sign_out_guard.dart` (header lines 1-35, body 63-426) is the existing guard. It is awaited by every user-initiated sign-out and returns true (sign out now) or false (stay signed in). Its states: `JournalNotEnabled` returns true with no prompt (line 71); `binding`, `gaveUp`, `failedToOpen` or an uncountable journal show the "cannot check" sheet with Try again (not for `failedToOpen`), Sign out anyway and Cancel (lines 80, 321-360); an open journal with activities or recordings shows the warning sheet (`showSignOutWarningSheet`, lines 232-287) with Export first, Sign out (keep) and Sign out and delete, where delete needs a second confirmation sheet (`showSignOutConfirmDeleteSheet`); a failing export or deletion shows the error sheet with Retry and keeps the user signed in (`_guarded`, lines 301-318). Export first writes files to a cache directory outside backup, shares them and deletes them in `finally` (lines 366-411, comment on line 401: a dismissed share sheet is not an error). The sheets live in `mobile/lib/features/activity/widgets/sign_out_warning_sheet.dart` (imported at line 56). Failures log a fixed message, a content-free code and the exception type (lines 33-34).
FACT: `mobile/lib/features/auth/state/auth_providers.dart:55-58` forwards `signOut` to the repository. FACT: no `waitForPendingWrites`, `clearPersistence` or `persistenceEnabled` appears anywhere under `mobile/lib` (grep returned nothing); Firestore SDK offline persistence is at defaults and its pending legacy writes are neither counted nor flushed at sign-out.
DECISION: the queue does not get a separate parallel sheet. Pending queue commands become a new first step inside `confirmSignOutWithLocalData`, so the user sees one coherent sequence (3.2). The `JournalNotEnabled` early `return true` (line 71) must not skip the queue step: the queue check runs before the journal availability is read.
U5 is resolved: the cannot-check sheet exists (it was designed for the activity journal, as LQ-12 says); what is new is the queue variant and its stricter rule.

### 3.2 One coherent sequence (queue plus journal)
DECISION. Order inside `confirmSignOutWithLocalData` for the departing UID:
1. Queue step first. Reason: queued commands can still be synced (an action the journal step cannot offer), and a user who syncs first may have nothing left to decide.
2. Existing journal step (unchanged states) second, only if the user did not cancel.
3. Commit phase last. Non-destructive actions (Sync first, Export) execute at once in their step. Destructive actions (Remove queue entries, journal "Sign out and delete") are only recorded as decisions and executed together in the commit phase after every prompt is answered. Cancel at any prompt returns false and nothing destructive has run. When both stores are being removed, one confirmation names both counts ("Remove N workout entries and A activities permanently?"). Failure in the commit phase shows the existing error sheet and keeps the user signed in; a partially executed commit is reported by what was removed, never as success.
4. `return true` only when: the queue is empty or was synced, or its remaining records were kept (Keep, for eligible accounts) or removed after the confirmed Remove path; and the journal step returned its own true.

Queue assessment rules, DECISION:
- The queue count and readability are read first. If the partition cannot be read or counted (store failed to open, corrupt, I/O error), the result is a queue "cannot check" sheet with Try again and Cancel only. "Sign out anyway" is FORBIDDEN for the queue: it would drop records silently (LQ-3). Only an explicit separate confirmation "Entries on this phone could not be read. Removing them deletes them permanently and their number is unknown." may remove an unreadable partition, and only from the Remove path with a preceding export attempt of the raw store file.
- The assessment also covers legacy Firestore SDK pending writes during the two-generation period (`04_CORE_TDD.md` section 7). UNKNOWN U16: the SDK exposes `waitForPendingWrites` (completes when acknowledged) but no count or enumeration, and it is unused today. DECISION: the guard runs a bounded wait; if it cannot confirm, the sheet says "older entries may not have synced" and the choices are the same as for queue records (Sync first, Keep where eligible, Cancel), with no claim of a count.

Acceptance (FU-AC-103, new FU-AC-126): widget test with N queue records plus M journal entries, for each combination (N>0 or 0, M>0 or 0, journal not enabled, journal cannot check, queue cannot check): exactly one coherent sequence, queue first; no path returns true while queue records would be dropped unless the Remove path was confirmed with the count; "Sign out anyway" is never available for the queue; Cancel at the journal step leaves the queue untouched.

### 3.3 Sheet states
DECISION. The queue step appears when the signed-in UID has at least one record in any state (or the partition cannot be read), before any auth state changes. With zero records and a readable partition the queue step is skipped.

| State | When | Content | Actions |
|---|---|---|---|
| S1 Choice | online, N records, account can sign in again (not anonymous) | "You have N workout entries saved only on this phone." and the count of those held or in conflict if any | Sync first (primary); Keep on this phone; Export, then remove from this phone; Cancel |
| S1-guest Choice | anonymous (guest) account | same text plus "This guest account cannot be signed in to again." | Sync first (primary); Link account first (opens the existing link flow, which keeps the uid, `profile_page.dart:260-279`); Export, then remove; Cancel. NO Keep (3.7) |
| S1-off Choice, offline | no network | same text plus "You are offline, so they cannot sync now." | Sync first disabled with that reason; the others remain (Keep only for non-guests) |
| S2 Syncing | after Sync first | progress "M of N sent", per-record result as they are acknowledged | Stop waiting (returns to S1 with current counts); Cancel sign-out |
| S3 Partial result | sync finished but K records remain (conflict, held, error, unknown effect) | "K entries could not sync. They are kept." with reasons by class | Keep (non-guests); Export, then remove; Try again; Cancel |
| S4 Done | queue empty | "All entries are synced." then the sequence continues to the journal step | none |
| S5 Export | after Export, then remove | the file is written and the OS share sheet opens; the sheet then shows an explicit question, see 3.5 | I saved the file with N entries (enables Remove); Share again; Cancel |
| S5-fail | export failed | "Export failed. Nothing was removed." | Try again; Keep (non-guests); Cancel |
| S6 Remove confirmation | the only path to removal | see 3.5 | Remove N entries permanently; Cancel |
| S7 Queue cannot be read | store/partition unreadable | "We could not read the entries saved on this phone." | Try again; Cancel. No "Sign out anyway" |

Copy requirements, DECISION:
- Every state names the number of entries in plain words and says whether they are "saved only on this phone".
- "Keep on this phone" (non-guest accounts only) says: "They stay on this phone for this account only. Another account cannot see them. They are sent the next time you sign in to the same account. If you delete the app or change phones, they are lost."
- Never use "synced" for a record without a server acknowledgement (LQ-8).
- Offline copy must not imply server revocation took place. FACT: `04_CORE_TDD.md` section 6: "Offline logout cannot acknowledge server revocation. The UI must not imply that it did."
- A record in UNKNOWN_EFFECT is described as "may already be saved on the server".
- All strings go through `mobile/lib/l10n` (`app_en.arb` and the other locale files); copy is English in git.

### 3.4 Three outcomes (LQ-12)
1. Sync first: the sender runs for this UID (pause lifted, 3.6); the queue step finishes when the queue is empty or the user moves to S3.
2. Keep (non-guest accounts only): the partition remains; the durable fence is set at commit (3.6). The sender stops for that UID.
3. Export, then remove: export (section 5) is produced, the user confirms (3.5), then exactly the exported records are removed in the commit phase.

### 3.5 Export then remove, and removal without export
FACT: the export sink cannot report whether the user saved anything. `ShareDataExportSink.deliver` (`mobile/lib/features/data_export/data_export_sink.dart:41-71`) writes a temp file, awaits `Share.shareXFiles`, and deletes the file in `finally`; the future completing says only that the sheet closed. The guard's own journal export has the same property (`sign_out_guard.dart:401`). Therefore "verified export" is not a property the app can claim.
DECISION:
1. "Verified" is replaced by what can be confirmed: (a) the file was written with N entries (the app knows this), and (b) an explicit user confirmation on the sheet after the share sheet closes: "I saved the file with N entries" (S5). A user-chosen file location (a save-to-files picker returning a URI) may replace (b) when such an export sink is added (UNKNOWN U17); until then (b) is required.
2. Dismissing the share sheet, or any share error, leaves Remove disabled. The user can Share again, Keep (non-guests), or use the separate removal-without-file confirmation S6.
3. Removal without any file: reachable only from S5 via "Remove without saving a file", opening S6. S6 text: "Remove N entries permanently? They are not saved on any server and cannot be recovered." The button contains the number: "Remove N entries". Entries in UNKNOWN_EFFECT are listed separately as "M may already be saved".
4. Removal is scoped to the snapshot: the removal transaction deletes only the operationIds present in the exported snapshot, and re-reads the live set in the same transaction. Records in the snapshot that were acknowledged meanwhile are simply gone. A record NOT in the snapshot (accepted after the export) survives; the sheet then returns to S1 stating "K entries were saved after the export and are still on this phone".
5. Once any sign-out path is committed (3.6 phase two), new command acceptance for that UID is refused with a visible message; that is what closes the snapshot-to-remove window for the commit itself.
Tests: dismiss the share sheet, Remove stays disabled; confirm "I saved" then Remove deletes exactly the snapshot IDs; a command accepted between snapshot and Remove survives Remove and is shown to the user; a share error keeps everything.

### 3.6 Two-phase fence and in-flight sends
DECISION (replaces the single `SIGNING_OUT` token, which had no release on Cancel and blocked Sync first):
1. Phase one, sheet open: when the queue step opens, only NEW sends are paused (in memory; a crash simply drops the pause). Acceptance of new commands continues. In-flight sends continue to a result.
2. Sync first lifts the pause: the sender runs normally for this UID while S2 is shown. Cancel at any point, or leaving the sheet, lifts the pause and the sender returns to its normal send interval.
3. Phase two, commit: the durable per-UID fence `SIGNING_OUT` is written only when the user commits to Keep, to Remove, or when S4 completes and the sequence reaches its commit phase. From then the sender refuses all records of the UID, and new command acceptance is refused (3.5 item 5). Cancel before this point never writes it; Cancel after it (a failed commit that keeps the user signed in) clears it.
4. If a send is in flight at phase two, sign-out waits for acknowledgement, a definitive failure or cancellation of the call, bounded (UNKNOWN U6); on timeout the record becomes UNKNOWN_EFFECT (kept, not re-keyed) and the UID binding is released only after the fence is durable.
5. The late response of a cancelled or timed-out send is applied to the record of its own uid only, never to the signed-in user. If it says committed the record becomes acknowledged under its own uid; if the user removed it, the late response changes nothing client-side and the server holds a committed set ("may already be saved" in S6).
6. Fence release: by Cancel or a failed commit (above), by relaunch while still signed in as the same UID (sign-out did not happen), by a new sign-in of the same UID, or by removal and deletion.
Tests (FU-AC-103): open the sheet, Cancel, log a set online: it is sent in the normal interval; open the sheet, choose Sync first: records are acknowledged (the pause does not block it); Keep with record 3 in flight, then B signs in: 0 of A's records are sent under B.
Failing scenario for FU-AC-103: 5 records, record 3 in flight, user taps Sign out then Keep. Expected: no record sent after the fence is written; record 3 ends acknowledged or UNKNOWN_EFFECT with unchanged operationId; sign in as B within 1 s sends 0 of A's records; sign in as A resends only record 3 (if unknown) and 4, 5 with the original IDs and the server reports record 3 as same-ID-same-payload success. Failure: any request for A's operationId bearing B's token; a record lost; a record with a new operationId; Cancel leaving a durable fence.

### 3.7 Guest (anonymous) accounts and orphaned partitions
FACT: for an anonymous user the only way to keep data is to link an account, which keeps the uid; ordinary sign-out "mints a fresh uid on the next sign-in and orphans all of it, permanently and silently, because an anonymous account has no credential to sign back into" (`mobile/lib/core/router/app_router.dart:117-126`; link tile for guests at `profile_page.dart:260-279`).
DECISION:
1. Keep is not offered for anonymous accounts, because the promised resume cannot happen. Their sheet is S1-guest: Sync first, Link account first, Export then remove, Cancel. Copy never says "next time you sign in".
2. Orphan rule, no auto-eviction: a partition whose UID cannot be signed in to (a former guest uid, any uid never seen again) is an orphan. At the next launch with any signed-in user the app lists orphans only as a count and age ("N entries from an account that can no longer sign in") on the data-and-backup settings page. No payload is shown. Offered actions: export or remove; both are gated by the OS device-credential check where available (UNKNOWN U15), because the signed-in user may not be the former owner of a shared phone. Orphan data is never sent.
3. If the server reports an account deleted (for example the auth refresh for that uid fails with user-not-found, or deletion is confirmed by another device), its partition is purged through the same wipe machinery at the next launch for which the failure is observed, with a notice to the user. This is an account-deletion consequence (LQ-13), not an age or size eviction. A deleted account whose uid is never observed again is covered by the orphan rule.
4. An orphan partition counts toward nothing but its own UID cap.

## 4. Account deletion

### 4.1 Current behavior
FACT: `mobile/lib/features/account_deletion/state/account_deletion_providers.dart:94-172` calls the `deleteAccount` Cloud Function first, and only after server confirmation records the uid in the pending-wipe marker (set of uids in SharedPreferences, key `account_deletion.pending_wipe_uids`), wipes device data, cancels notifications and signs out. The comments at lines 113-122 say the device wipe is deliberately after the server call so a failed deletion never wipes a still-live account. FACT: `DeviceLocalDataWipe.wipe` (`local_data_wipe.dart:281-407`) erases an exact list of preference keys, `progress_photos/<uid>/`, `coach_recordings/<uid>/` and the scan history; it has no queue step. The pending-wipe marker is `PrefsPendingWipeMarker`, key `account_deletion.pending_wipe_uids` (`local_data_wipe.dart:63-66`). FACT: the client has no re-authentication step: grep of `mobile/lib/features/account_deletion` for recent-login or reauth matched nothing, and the service only retries once with a forced token refresh on `unauthenticated` (`cloud_functions_account_deletion_service.dart`). Whether the server rejects with a recent-login error is UNKNOWN U18; Stripe cancellation failure is a documented failure mode (`account_deletion_providers.dart:80-86`). FACT: `accountBeingDeletedUidProvider` lets in-flight writers abort (`account_deletion_providers.dart:24-29`) but it is set only after server confirmation.

### 4.2 Required ordering (LQ-13)
DECISION. The queue must never be cleared while the account can still survive a failed deletion without the user having chosen that loss, so every separable failure point comes BEFORE the fence and the clear, and the server is asked to mark the account deletion-pending (reversible) before anything local is destroyed:
0. Pre-flight, before any fence (a failure here changes nothing): forced ID-token refresh (`getIdToken(true)`) and any re-authentication the platform requires (none exists in the client today, U18); network reachability; and, when the queue holds N>0 records, either an export or a second confirmation naming N ("N workout entries saved only on this phone will be removed with the account"). Declining export is allowed.
1. Write durable checkpoint `FENCED(uid)` (a uid-only record, 4.3). From here the sender refuses all records of the uid and new command acceptance is refused with a visible message. The queue is NOT touched.
2. Cancel in-flight sends; each resolves to acknowledged or UNKNOWN_EFFECT; late responses are ignored client-side from here on.
3. Ask the server to mark the account deletion-pending (a new reversible server operation, `beginAccountDeletion` as a working name; UNKNOWN U7). While pending, the server rejects every workout command for the uid, which closes the late-send window from the server side. If this call fails (offline, token, Stripe pre-check, recent-login), the fence and checkpoint are removed, the queue is intact, and the user sees the failure on the deletion page. Write `SERVER_PENDING`.
4. Write `QUEUE_CLEARING`, clear the uid partition, verify it is empty, write `QUEUE_CLEARED`.
5. Call the final `deleteAccount` Cloud Function (idempotent, `account_deletion_providers.dart:88-93`). On success write `SERVER_DELETED`, then run the existing steps (marker add, `LocalDataWipe.wipe`, notification cancel, sign-out). If the final call fails after step 4 (for example Stripe), the account stays deletion-pending, the user sees the existing error and Retry, and the message states that unsynced entries were already removed at their confirmed request; retry converges.
6. No resurrection by a late send: (a) the client cannot send (fenced, then cleared); (b) the server is deletion-pending from step 3 and then deleted, so a request already in flight reaches a server that rejects it; (c) the deletion tombstone and generation fence stop a command arriving after finalization. FACT: `11_SECURITY_PRIVACY.md` section 6 and `05_DATA_MODEL.md` section 8 require tombstones/generation fences so "late uploads, worker results or commands" cannot recreate erased state. UNKNOWN U7: neither the deletion-pending operation nor the fence for workout commands is confirmed in the `deleteAccount` function (functions code was not inspected). If the operator rejects a new server operation, the fallback is: skip step 3, keep the pre-flight and the N-naming confirmation, and accept that a failure of step 5 leaves a live account with an empty queue (stated in the copy); FU-AC-104 gates either variant.

### 4.3 Deletion checkpoint and crash recovery
DECISION: the checkpoint is a uid-only record stored outside the queue partition, next to the existing pending-wipe marker, holding uid, stage enum, and timestamps; no payload. It is written with the same durability as queue commits.
Recovery on next launch, for every checkpoint found, regardless of who is signed in:
| Crash after | State found | Recovery |
|---|---|---|
| step 1 or 2 | FENCED | queue untouched and unsendable; if the signed-in user is that uid, ask "Finish deleting your account?" with Continue and Cancel deletion; Cancel removes the checkpoint and the fence (and the server pending mark if set), queue intact |
| step 3 done | SERVER_PENDING | same question; Cancel asks the server to clear the pending mark first; if that cannot be confirmed the checkpoint stays and the fence stays |
| step 4 started | QUEUE_CLEARING | the user already confirmed deletion before the clear began: complete the clear (idempotent), do not resume sending, then continue to step 5 without a second confirmation |
| step 4 done, step 5 sent or not | QUEUE_CLEARED | call `deleteAccount` again (idempotent) without asking again |
| step 5 succeeded, crash before `SERVER_DELETED` is written | QUEUE_CLEARED (or earlier) | see below |
| `SERVER_DELETED` written | SERVER_DELETED | run `finishInterruptedWipe` and sign out |
Crash after the server deleted the user but before `SERVER_DELETED` is written, DECISION: on launch, for checkpoint stage QUEUE_CLEARED (and QUEUE_CLEARING, SERVER_PENDING once the user's confirmation is on record), resolve in this order. (1) If the cached Firebase user for that uid is still present (Auth keeps it until the token refresh fails), call `deleteAccount` again: an idempotent success or "account not found" is treated as `SERVER_DELETED`, with no second confirmation. (2) If there is no signed-in user and the auth layer reports the account as gone (user-not-found or equivalent; UNKNOWN U14 on the exact codes), treat it as `SERVER_DELETED`. (3) If there is no signed-in user and no evidence about the server, do NOT erase the health blob and photos (the account may be live); keep the checkpoint and the fence, and resume on the next sign-in of that uid. In cases (1) and (2) the uid is added to the pending-wipe marker (`PrefsPendingWipeMarker`) and `finishInterruptedWipe` runs the full wipe including the queue partition, then the checkpoint is removed. This closes the hole in which the marker is never written because `SERVER_DELETED` never was.
Test (FU-AC-121): kill after the server delete returns but before the `SERVER_DELETED` write; the next launch erases all uid-keyed device data (preferences, photos, scan history, queue) and the checkpoint. Second test: kill at QUEUE_CLEARED with no signed-in user and no server evidence: nothing but the already-cleared queue is erased, and the checkpoint survives.
Cancel deletion is possible only before step 4 started; after that the queue is gone and the user is told (4.4).

### 4.4 Difference from the current order, and why
FACT: the current order protects against wiping a live account's data when server deletion fails. DECISION: the queue is cleared before the final server deletion because LQ-13 requires that order and because clearing after leaves a window where a pending command can be sent after the server data is gone. A review found that clearing before any server success destroys the queue of an account that then survives a failed deletion. The resolution in 4.2 is to move every separable failure point (token, re-auth, reachability, confirmation naming N) before the fence, and to have the server mark deletion-pending first, so the clear happens only after the server has agreed deletion is in progress. Residual cost: a failure of the final `deleteAccount` (such as Stripe) after the clear leaves a deletion-pending account with an empty queue; the user confirmed that loss by name beforehand and the copy says so. The health blob and photos keep the existing "after server confirmation" order (no change).
Contradiction record: this is the one place where the existing code comment (wipe only after the server call) and LQ-13 pull in different directions; resolved as above, scoped to the queue only.

### 4.5 Failing scenario for FU-AC-104
Delete during sync with 10 pending (3 in flight), kill the process after step 2, again after step 3, again after step 4, again after the step 5 request; after each restart complete the flow. Expected: no server document under `workout_sessions` or the command admission/receipt collections for that uid exists after finalization; the queue partition is gone; the checkpoint is removed after wipe. Failure: any document reappears, or the queue is sent after the first restart.
Failure-before-clear tests: force `deleteAccount` (or `beginAccountDeletion`) to fail with a recent-login error, with a Stripe error, and offline: in each case the queue is intact with all operationIds, the fence and checkpoint are removed, sending resumes, and the user sees the failure on the deletion page. Force the final call to fail after step 4: the account remains deletion-pending, Retry converges, and no queue record is ever sent.

## 5. Export

### 5.1 Current behavior
FACT: `DataExportAction.export` (`mobile/lib/features/data_export/data_export_providers.dart:32-137`) reads profile, workout history through `exportAll`, schedule, programmes and photo metadata with 30 s timeouts and a server callable, builds JSON via `buildExportJson` (`data_export_providers.dart:134` calls `data_export.dart:120`, which wraps `buildExport` at `data_export.dart:34`; `exportFormatVersion: 1`, `notes`, `serverIncomplete`) and hands it to a sink (`ShareDataExportSink`, which cannot report whether the user saved the file; see 3.5). The format change in 5.3 is made in `buildExport` and threaded through `buildExportJson`. FACT: `workoutLogs` there comes from server-or-SDK-cache repositories, so it does not contain a queue.

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
3a. FACT: uncaught errors reach Crashlytics through `FlutterError.onError` and `PlatformDispatcher.instance.onError` (`mobile/lib/main.dart:427-450`); both pass the error through `sanitizeForGlobalHandler`, which today replaces only errors of recorder origin ("any other error is untouched", comment at lines 425-426). DECISION: the queue store must throw only a typed `QueueStoreException` carrying a fixed message and a class enum, never a path, UID, operationId or payload (file-system exceptions are caught at the store boundary and re-thrown in that form); in addition `sanitizeForGlobalHandler` is extended to recognize and redact any queue-origin error, so a missed wrapper still cannot leak. Test: inject a store failure whose raw exception text contains a path and an operationId; the Crashlytics test sink receives neither (FU-AC-122).
4. The queue's `toString` and error messages are redacted by construction (no payload in `toString`), so an accidental `debugPrint(record)` prints nothing sensitive.
5. Server logs for received commands follow `17_RELEASE_OPERATIONS.md` ("Redact sensitive data from logs"); the unknown-command age and queue depth metrics listed there are fed by bucketed client signals only if consent for diagnostics permits (UNKNOWN U9).
Acceptance: FU-AC-122.

## 8. Restore, reinstall and new device

DECISION:
1. Queued commands never travel to another device: they are excluded from cloud backup and device transfer (section 1.6), not uploaded to a server, and not part of the passphrase backup file. FACT: the existing encrypted backup file (`mobile/lib/features/data_export/backup_envelope.dart`) is a carried profile/health backup with a user passphrase; it does not include the queue and will not.
2. On reinstall, restore or new phone, signing in shows an empty queue. If the app can detect that the previous install existed (it cannot reliably, UNKNOWN U10), no claim is made. The in-app text at Keep and in the sign-out sheet (3.3) is the user's notice; a short note is also added to the onboarding/settings data-and-backup page: "Entries not yet synced stay on this phone and are not included in backups or phone transfers. Sync or export them before changing phones."
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
| `04_CORE_TDD.md` | 6 outcome table and paragraph after it | replace NOT_SENT_OFFLINE; remove "not a stored unsent payload or an offline operation queue"; add local states and the logout paragraph pointing to sections 3.2 to 3.7 of this file; also correct "Preserve S04 cannot-check/wipe guards" to name `sign_out_guard.dart` as the single flow the queue joins |
| `04_CORE_TDD.md` | 7 | remove "No durable manual-draft replacement"; replace with the queue and drain/preservation of SDK writes |
| `11_SECURITY_PRIVACY.md` | 2 data-flow table | add row "Queued workout commands" (device only, UID partitioned, excluded from backup, no payload in logs) |
| `11_SECURITY_PRIVACY.md` | 3 | replace the Option A paragraph; local acceptance precedes admission |
| `11_SECURITY_PRIVACY.md` | 6 | add the sign-out sheet outcomes, fencing and deletion order (4.2); the "UID-scoped encrypted gym photos remain intact" sentence gets a queue sibling |
| `11_SECURITY_PRIVACY.md` | 7 | add negative tests FU-AC-120 to FU-AC-126 to the pre-release list |
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
| `mobile/lib/features/activity/state/sign_out_guard.dart` (and `widgets/sign_out_warning_sheet.dart`) | add the queue step (and the queue cannot-check variant without "Sign out anyway") inside `confirmSignOutWithLocalData`, ahead of the `JournalNotEnabled` early return; commit phase for destructive actions |
| `mobile/lib/features/profile/profile_page.dart` | no change to the call at lines 287-291; guest accounts reach the Link account action from the new sheet |
| `mobile/lib/main.dart` (`sanitizeForGlobalHandler`) | redact queue-origin errors in the global handlers (lines 427-450) |
| `mobile/lib/features/account_deletion/data/cloud_functions_account_deletion_service.dart` | pre-flight token refresh and the `beginAccountDeletion` call (if adopted, U7) |
| `mobile/lib/features/data_export/data_export.dart` and `data_export_providers.dart` | `deviceOnlyCommands`, format version 2 |
| `mobile/lib/l10n/app_en.arb` (and locale files) | sheet and warning strings |
| `docs/v1/package-amendments/ACCEPTANCE_AMENDMENTS.csv` and `SUPERSESSION.csv` | add FU-AC-120 to FU-AC-127 and the supersession of Option A rows, outside this document's scope |

### Acceptance obligations
Existing rows, with the concrete failing scenarios of sections 2, 3.6, 4.5, 5.5:
| Row | Failing scenario that must be caught |
|---|---|
| FU-AC-102 | sender uses the current user's token for another UID's record; partition deleted on switch; count of other UID visible |
| FU-AC-103 | request for A's operationId after the fence; record lost on timeout; a new operationId after resume; sheet with a direct discard button; S6 without the number |
| FU-AC-104 | any `workout_sessions` or receipt document reappearing after deletion with a send racing; queue sent after the first restart; deletion without checkpoint losing track after a kill |
| FU-AC-105 | offline export missing conflicted records; pending records also appearing in `workoutLogs` |

Proposed new rows (status NOT_RUN, priority P0 unless noted, same columns as the CSV):
| ID | Requirement/task | Scenario | Expected result |
|---|---|---|---|
| FU-AC-120 | FU-RQ-013 | Backup and transfer exclusion | The final exclusion set (the nine current entries plus the queue location and the Firestore cache location, or the documented placement under an excluded directory) is asserted exactly in `full-backup-content`, `cloud-backup` and `device-transfer` by an extended `backup_rules_test.dart`; the queue is flagged excluded on iOS; a restore or transfer to a second device yields an empty queue and the first device still sends once. Test: static assertion plus a device or emulator backup/restore run. |
| FU-AC-121 | FU-RQ-049 | Deletion checkpoint crash recovery | Kill at each stage of section 4.3; after each restart no queue record is sent, the flow completes or is cancelled only before stage 4, and no marker or checkpoint remains after finalization. Includes: kill after the server delete but before the `SERVER_DELETED` write erases all uid-keyed device data on next launch; and `deleteAccount` failing (recent-login, Stripe, offline) leaves the queue intact. |
| FU-AC-122 | FU-RQ-013 | No payload in logs and telemetry | With a log capture and a Crashlytics test sink, run accept, sync, conflict, cap refusal, sign-out and deletion; no payload value, operationId, UID or exercise name appears in any captured line or key; bucketed fields only. |
| FU-AC-123 | FU-RQ-019 | No audio or transcript in the store | After 20 voice-initiated queued commands and 20 rejected utterances, the store and logs contain no audio, no transcript and no modality field; rejected utterances created 0 records. |
| FU-AC-124 | FU-RQ-049 | Export format and offline snapshot | Export schema validation of `deviceOnlyCommands` (fields of 5.3, `exportFormatVersion` 2), consistent snapshot while a send acknowledges a record mid-export, export works with the network off, and export never fails on a corrupt record (it is included as raw with a flag). |
| FU-AC-125 | FU-RQ-015 | Per-UID cap, warnings and old-record handling | 500 for UID A leaves UID B able to accept; a record older than the 90-day detail TTL is kept as CONFLICT with the "too old" copy, offered for export, and never removed by age; clock moved back by 40 days and forward by 40 days removes nothing. |
| FU-AC-126 | FU-RQ-013 | Sign-out guard sequence and sheet states | Widget test of `confirmSignOutWithLocalData` with N queue records plus M journal entries (including journal not enabled, journal cannot check, queue cannot be read): one coherent sequence, queue first; no path returns true with queue records dropped unless Remove was confirmed with the count; "Sign out anyway" never offered for the queue; Cancel anywhere leaves everything intact. Each state S1 to S7 is reachable and shows the exact count; offline disables Sync first with a reason; dismissing the share sheet keeps Remove disabled; a command accepted after the snapshot survives Remove; open sheet then Cancel then log a set online is sent in the normal interval; Sync first is acknowledged. |
| FU-AC-127 | FU-RQ-013 | Guest accounts and orphaned partitions | An anonymous account never sees Keep; Link account first keeps the uid and the queue; a partition of an unrecoverable uid is listed only as count and age, exported or removed only after the device-credential gate, never sent, never evicted by age; a partition of a server-deleted account is purged at the next observation with a notice. |

## 11. UNKNOWNs
| ID | Question | Why it matters / default |
|---|---|---|
| U1 | Which storage engine implements the atomic local commit (new dependency)? | Needs a dependency review; must pass FU-AC-093; not decided here |
| U2 | Is app-level encryption required by the privacy review? | Default is no (1.4); a yes changes key-loss design |
| U3 | iOS exclusion and data protection class | no iOS evidence in this review |
| U4 | Is there a device-wide cap for many accounts on one phone? | default per UID only |
| U5 | RESOLVED: the cannot-check sheet exists in `sign_out_guard.dart` (earlier draft was wrong) | queue joins that flow (3.1 to 3.2) |
| U13 | Exact Firestore offline-cache location and whether a restored cache is usable | decides the exclusion entry (1.6) |
| U14 | Which auth errors prove the account was deleted server-side | crash recovery case (2) in 4.3 |
| U15 | OS device-credential gating for orphan export/remove | 3.7 |
| U16 | Firestore SDK exposes no count or enumeration of legacy pending writes; only a bounded `waitForPendingWrites` | 3.2 |
| U17 | A save-to-files export sink returning a user-chosen location | would replace the "I saved the file" confirmation (3.5) |
| U18 | Whether the server requires recent login or fails deletion for other reasons; no client re-auth exists | pre-flight design in 4.2 |
| U6 | Bounded wait for an in-flight send during sign-out | value to freeze at implementation |
| U7 | Server `deleteAccount` tombstone/generation fence for workout commands, and the proposed reversible deletion-pending operation (`beginAccountDeletion`) | functions code not inspected; needs operator approval of a new server operation; FU-AC-104 gates either variant (4.2) |
| U8 | Readers of export format version 1 outside the app | decides whether bumping to 2 is safe |
| U9 | Whether diagnostics consent permits bucketed queue metrics | |
| U10 | Whether a reinstall can be detected to warn about lost entries | default: no claim |
| U11 | LQ-5 uniqueness enforced on committed session state, not receipts only (needed after receipt expiry or server restore) | belongs to the core design (B-02) |
| U12 | Whether product analytics wants an input-modality field | default: not stored |

Contradictions found with existing material (none with LQ-1 to LQ-14):
1. Existing deletion order (server first, wipe after) versus LQ-13 (clear queue before server delete): resolved in 4.4 for the queue only.
2. The package's `04_CORE_TDD.md` sections 6 and 7 and `11_SECURITY_PRIVACY.md` section 3 still state Option A (already recorded as B-01/B-03 in the reconciliation); not changed here.
3. LQ-12 calls the cannot-check sheet existing; it does exist (`sign_out_guard.dart`). The earlier draft of this file was wrong. Tension remaining: that sheet offers "Sign out anyway", LQ-3 forbids silent loss, so the queue variant forbids it (3.2).
4. The 90-day detail TTL (`05_DATA_MODEL.md` section 6) is shorter than the unbounded queue age (LQ-3); handled in section 6 by OUTCOME_EXPIRED plus keep, which needs the compact fence to outlive detail records (already in the data model).
