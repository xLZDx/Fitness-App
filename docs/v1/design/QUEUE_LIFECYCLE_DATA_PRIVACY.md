# Durable command queue: data class, lifecycle and privacy contract

Status: DESIGN PROPOSAL, 2026-10-22, revision 3 (conformed to `OFFLINE_COMMAND_PROTOCOL.md` v1.3). Nothing here is implemented. Closes the document-level part of review finding B-03 (queue lifecycle is not in the data and lifecycle contracts) from `docs/v1/package-amendments/PACKAGE_RECONCILIATION_2026-10-22.md`. It elaborates, and does not change, the 14 binding criteria of `docs/v1/LOCAL_QUEUE_DECISION.md` (cited below as LQ-n). Acceptance rows FU-AC-102 to FU-AC-105 stay as written in `docs/v1/package-amendments/ACCEPTANCE_AMENDMENTS.csv`; this file adds rows (section 10).

Single source of truth: sections 2 and 3 of `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (cited as PROTO n.n) are the ONE canonical command-record contract: record schema (PROTO 3.1), the seven states `ACCEPTED`, `SENDING`, `UNKNOWN_EFFECT`, `HELD`, `SYNCED`, `CONFLICTED`, `DISCARDED` (PROTO 3.2), transitions T1 to T16, `dependsOn` of at most 3 (PROTO 3.4), acknowledgement behaviour (PROTO 3.6), the old-command outcome table (PROTO 3.7) and the shared fixture `queue_protocol_fixture.json` (PROTO 3.10, FU-AC-125). This file defines NO schema, state, transition or aged-command outcome of its own; it only says how that record behaves at sign-out, deletion, export, backup, restore, logging and orphaning. Where a name below differs from the draft of the same file before revision 3, PROTO 3.11 holds the map (`PENDING` is `ACCEPTED`, `CONFLICT` is `CONFLICTED`, `HELD_BY_PREDECESSOR` is `HELD` with a reason, `OUTCOME_EXPIRED` is two codes in PROTO 3.7, "too old" does not exist).

Reader: the package author reissuing the registers, and the engineer who will implement the queue. Package documents named below are under `FitnessUp_v1_Rebaseline_2026-10-20/docs/` (external deliverable, not in this repository). App paths are relative to `D:\Repo\Fitness_App`; file facts were verified in the design worktree `D:\tmp\scratch_worktrees\v1design`.

Claim labels: FACT (verified in a file, path cited), DECISION (made by this document within the limits of LQ-n and PROTO; reversible by the operator), UNKNOWN (not verified or not decided; section 11 lists them).

## 0. Why the package contradicts the decision today

- FACT: `11_SECURITY_PRIVACY.md` section 3 says Option A applies to touch and voice and that an unsent capture may remain "only in the active UI, without durable queuing".
- FACT: `04_CORE_TDD.md` section 6 table row NOT_SENT_OFFLINE is "Active UI unsaved capture only; no rest or saved claim"; the paragraph after the table says the recovery handle "is not a stored unsent payload or an offline operation queue"; section 7 says "No durable manual-draft replacement is introduced".
- FACT: `05_DATA_MODEL.md` has no local command store entity, and its section 6 retention table has no row for unsent device data. The only device-local data classes are LocationEvidence and GeofencePreference.
- DECISION: the queue is a first-class, UID-scoped, device-local data class with its own row in every lifecycle path (sign-out, deletion, export, backup, restore, logs). The rest of this file defines those rows.

## 1. Data class definition

### 1.1 Name and scope
DECISION: entity `LocalCommandQueue`; one element is a command record exactly as PROTO 3.1. Authority: the device holds the record until the server acknowledges it; the server remains authoritative for committed workout facts (LQ-8). A record that is not `SYNCED` is never a canonical workout fact in history, progress, coach replies or server export (FU-AC-099, PROTO 3.8).

### 1.2 What is stored on the device, by privacy class
DECISION (classification only; field names and meanings are PROTO 3.1):

| Class | Elements | Handling |
|---|---|---|
| Pseudonymous identifiers | `uid`, `operationId` (contains the 8-character `uidTag`, PROTO 2.6), `sessionId`, `originDeviceInstallId` | allowed in the UID partition; never in logs or metric labels; in the export; deleted with the account |
| Workout payload | `canonicalBytes`, `payloadFields` (typed reps, integer-gram load, difficulty enum, catalogue exercise IDs, target values), `payloadHash`, `logicalSetId`, `exerciseId` | workout data, handled like `WorkoutSession` data; erased at acknowledgement (PROTO 3.6) |
| Ordering and diagnostics | `seq`, `dependsOn`, `sessionGeneration`, `acceptedEpoch`, `state`, `heldReason`, `conflictKind`, `conflictTerminal`, `maybeSent`, `attempts`, `lastAttemptLocalMs`, `lastResultCode`, `ackSummary`, `supersedes`, `intentKey`, `acceptedAtLocalWallMs`, `acceptedAtMonotonic` | no payload content; result codes are enum names |
| Separate local tables (PROTO 3.1) | `session_seq`, `set_context`, `effective_set` (holds `syncedValues`/`effectiveValues`, i.e. workout values), `intent_keys`, `session_sender_state`, `observed_generation`; plus `ageWarningRaisedAt` and `wallHigh` (PROTO 3.8) | the `effective_set` values are workout payload and are erased on removal, while its identity marker holds no workout value and is kept (PROTO 3.6, 1.7); the rest hold no workout values |
| Secrets in platform secure storage | the writer token (PROTO 8.1, 32 random bytes) keyed by (uid, sessionId); the `deviceInstallId` binding is stored outside backup (PROTO 9) | the token is NEVER a field of a record, NEVER in canonical bytes, NEVER in an export, a log, a crash report or a backup (PROTO 2.3, 8.1); see 1.6, 3, 4 |

Must NOT be stored in the queue or its tables: display name, email, auth tokens, ID tokens, App Check tokens, location, photos, audio, transcripts, recognition hypotheses, free text typed or spoken by the user, health flags, allergens, injury answers. FACT: protected health fields are device-only by `11_SECURITY_PRIVACY.md` section 2 and are held under `profile.sensitive.<uid>` (`mobile/lib/features/account_deletion/data/local_data_wipe.dart`); the queue never copies from them. A payload that would need such a field is refused at acceptance as a design error.

### 1.3 Storage location
DECISION: a single app-private store inside the application documents/support area, partitioned by UID (the engine is an implementation choice, U1). It is not placed in `SharedPreferences`.
- FACT: `FlutterSharedPreferences.xml` is a plaintext file excluded from backup and read in whole (`mobile/android/app/src/main/res/xml/backup_rules.xml` comments). A size-bounded whole-file read-modify-write path cannot be the durability mechanism, because LQ-2 and PROTO 3.3 require one atomic transaction.
- FACT: `mobile/pubspec.yaml` has no SQLite or embedded database dependency (grep for sqflite, drift, isar, hive, sqlite returned nothing); `path_provider` and `flutter_secure_storage` (line 96) are present. The engine is a new dependency decision (U1); PROTO 11.2 item 1 holds the same unknown.
- Required engine property (PROTO 3.1, 3.3): unique indexes, one transaction commits record, counters and tables or nothing, and a commit failure is reported before the UI shows "pending sync".

### 1.4 Encryption at rest
DECISION: no app-level encryption key for the queue in v1. Protection is the OS app sandbox plus OS device encryption plus backup exclusion (1.6).
1. FACT: the progress-photo envelope key lives in the Keystore and the existing comments record that a key lost or not restored leaves "undecryptable files the user cannot delete" (`mobile/android/app/src/main/res/xml/data_extraction_rules.xml` comment; `photo_key_store.dart` treats "present but unreadable" as a distinct failure). An unreadable queue would turn a Keystore reset into silent loss of unacknowledged commands, which LQ-3 forbids.
2. The payload has no direct identifier except the pseudonymous UID and `operationId`.
3. Residual risk, stated: a rooted device or a forensic image of an unlocked device can read the queue. Accepted for workout values. The writer token is different: it is a secret and stays in secure storage (1.2).
If the privacy review requires encryption at rest, the condition is a key-loss path that preserves the commands (export of plaintext before any key reset) and a re-run of FU-AC-093 (U2).

### 1.5 Acknowledgement, removal and DISCARDED
DECISION, on top of PROTO 3.6: a record leaves `ACCEPTED`/`SENDING`/`UNKNOWN_EFFECT`/`HELD`/`CONFLICTED` only by (a) a server answer of class C1 or C2 (PROTO 4.4) giving `SYNCED`, whose payload is erased in the same local transaction, with the stub kept 7 days (T16); (b) a user-confirmed removal giving `DISCARDED` (section 3.5, T5/T14, and T17 below); (c) account deletion (section 4), which removes the whole partition and is not a state transition. Never by age, size, app update, schema migration or low storage (LQ-3, PROTO 3.2). A `CONFLICTED` answer is kept (LQ-5, LQ-9).
T17 is defined in PROTO 3.2 (version 1.3.2): "any non-`SYNCED`, non-`DISCARDED` state, event user-confirmed removal of 3.5, to `DISCARDED`", with the per-source-state preconditions and the `discardSource` values; `canonicalBytes` and `payloadFields` are erased in the same transaction and the stub follows the 7-day rule (PROTO 3.6). This document only references it; it does not define a competing transition.

### 1.6 Backup and cloud restore
FACT: the manifest sets both `android:fullBackupContent="@xml/backup_rules"` and `android:dataExtractionRules="@xml/data_extraction_rules"` (`mobile/android/app/src/main/AndroidManifest.xml:53-54`); `allowBackup` is not set, so Android Auto Backup is on by default. Each of `backup_rules.xml` (lines 59-69, `full-backup-content`) and `data_extraction_rules.xml` (lines 36-46 `cloud-backup`, 47-57 `device-transfer`) excludes exactly NINE entries: `root:app_flutter/progress_photos`, `root:app_flutter/scan_history`, `sharedpref:FlutterSharedPreferences.xml`, `sharedpref:FlutterSecureStorage.xml`, `sharedpref:FlutterSecureKeyStorage.xml`, `file:journal`, `file:sources`, `file:quarantine`, `file:activity_journal`. The documents directory resolves to `app_flutter` and `domain="file"` is `getFilesDir()` (comments in `backup_rules.xml`). Everything else is backed up. `mobile/test/android/backup_rules_test.dart` asserts the exact nine-entry set in all three sections (`_expectExactly`, lines 66-78); `mobile/test/features/activity/repository/backup_exclusion_test.dart:142` asserts `kActivityBackupExcludedDirs` has length 4.
FACT: there is no exclusion for the `databases` domain, and grep of `mobile/lib` for `persistenceEnabled`, `clearPersistence` and `waitForPendingWrites` returned nothing. The Firestore offline cache, including legacy SDK pending writes, is not excluded and on Android may ride default Auto Backup (U13: the exact cache location and the usability of a restored cache were not verified).
FACT: no iOS exclusion flag exists in the repository (grep for isExcludedFromBackup / NSURLIsExcludedFromBackupKey in `mobile` returned nothing).

DECISION: the queue (all records and tables) AND the writer tokens are EXCLUDED from Android cloud backup and device-to-device transfer, and from iCloud/iTunes backup. This is the same decision as PROTO 3.9 and 9. Reasons:
1. A restored copy puts the same `operationId`s on a second install while the original still sends them (LQ-5), and a restored token would let a second install present the writer's secret (PROTO 8.1).
2. The queue is bound to a `deviceInstallId` stored outside backup; a restored queue on another install cannot be sent without review.
3. It keeps the photo-consent precedent: a user-visible promise ("kept on this device") must not be false on one route.
Writer tokens: FACT, the Android secure-storage files `FlutterSecureStorage.xml` and `FlutterSecureKeyStorage.xml` are already excluded in all three sections, so tokens kept through `flutter_secure_storage` are covered on Android; the final-set assertion below must keep them. iOS Keychain backup behaviour of the chosen storage options is UNKNOWN (U3, PROTO 11.2 item 1).
Defence in depth, DECISION: if a queue file nevertheless appears on an install whose `deviceInstallId` does not match, the protocol path applies unchanged: every non-terminal record becomes `CONFLICTED` (`RESTORED_REVIEW`, T15), nothing is sent automatically, any restored token is discarded, and each session needs an explicit takeover (PROTO 9, 8.1).
Consequence (the user is told, section 8): a user who changes phones loses unsent commands that were never synced. Export is the way to carry them (section 5).

Required changes, DECISION:
1. Placement. Option (a), preferred: place the queue under the already excluded `activity_journal` tree or another already excluded directory; no XML line is then needed, but a test must walk the directory the real factory creates (the pattern the S04 test uses, per the `backup_rules.xml` comment). Option (b): a dedicated directory name with a new `exclude` line in all three sections.
2. Extend `backup_rules_test.dart` so `_expectExactly` states the FINAL exclusion set (the nine current entries plus any queue and Firestore-cache entries) in `full-backup-content`, `cloud-backup` and `device-transfer` (FU-AC-120).
3. Firestore cache and legacy pending writes: add the Firestore cache location (`database` domain, exact path to verify, U13) to the same work item. Reason: legacy pending writes are the first generation of the same class of unsent data (the two-generation period of `04_CORE_TDD.md` section 7 and PROTO 8) and have the same duplicate-sender problem. Consequence if left included: a restore or transfer can resurrect old unsent legacy writes on a new install. Consequence of excluding: the new install loses the Firestore read cache (rebuilt from the server) and any legacy unsent writes, the same loss the queue accepts. Default: exclude; reversible by the operator.
4. On iOS set the exclude-from-backup attribute on the store location and test it (U3).

### 1.7 Which stores each lifecycle action touches
DECISION (one table so that no path forgets a store):

| Store | Sign-out Keep | Sign-out Remove | Account deletion | Orphan purge (3.7) | Export |
|---|---|---|---|---|---|
| command records (PROTO 3.1) | kept | `DISCARDED` for the exported snapshot IDs (T17/T5/T14) | whole partition deleted | whole partition deleted | non-`SYNCED`, non-`DISCARDED` records |
| `effective_set` identity markers | kept | kept (no workout value; stops a second APPEND for a set the server may hold) | deleted | deleted | no |
| `effective_set` values (`syncedValues`, `effectiveValues`) | kept | erased for the sets of removed records | deleted | deleted | not exported separately |
| `session_seq`, `set_context`, `observed_generation` | kept | kept (no workout values; protects `seq` continuity) | deleted | deleted | no |
| `intent_keys`, `session_sender_state`, `ageWarningRaisedAt` | kept | kept (opaque ids, expire after 30 days) | deleted | deleted | no |
| writer tokens in secure storage | kept | deleted for sessions whose records were all removed | all tokens of the uid deleted | all tokens of the uid deleted | never |
Removal keeps `session_seq` on purpose: reusing a `seq` after a discard would break the install-scoped guard (PROTO 2.1). `effective_set` follows the single split of PROTO 3.6 (round 2, M-01): the identity marker stays so that a later tap creates a CORRECT and never a second APPEND; the workout values are erased with the removed records, so nothing the user removed stays on the device. U20 is closed by that split.

## 2. UID scoping and access rules

DECISION:
1. Every read, write, send, count and token lookup takes an explicit uid argument. No API reads "the current queue" or "the current token" without a uid. The uid used for a send is the uid stored in the record, never the currently signed-in uid.
2. A sender may send a record only when the Firebase Auth user equals the record's uid at the moment of sending and the token used was minted for that uid, under the per-UID send lease of PROTO 3.9. If they differ the record is skipped, not failed, and not modified. (The server also rejects a mismatched `operationId`/uid pair, PROTO 4.3 I6.)
3. Code running for account B reads only B's partition and cannot enumerate other partitions. The count on B's sign-out sheet is B's count only. The only cross-UID access is internal and returns existence only (a yes/no and the uid) for the interrupted-wipe sweep and the orphan status (3.7); it never returns a count or payload to any UI. FACT: the existing pending-wipe marker holds "uids only, never health data" (`local_data_wipe.dart`, `PendingWipeMarker`, around lines 45-60).
4. Shared-device rule: A to B to A. A's partition is untouched while B is signed in; no send of A's records happens under B; on A's return the sender resumes with the same `operationId`s and the same stored bytes. B's partition is created lazily and is empty at first use (LQ-11, FU-AC-102).
5. Partition keys use the opaque UID in a directory name only after the validation the wipe code applies (`_looksLikeUid`: non-empty, not `.` or `..`, no `/` or `\`; `local_data_wipe.dart`, around line 155).
6. Cap scope: the 500 cap (LQ-3, PROTO 3.3) applies per UID. No device-wide cap is set (U4).
7. An unreadable or corrupt partition is preserved and reported, never recreated empty. FACT precedent: unreadable health blobs are quarantined, not overwritten (`mobile/lib/features/profile/data/local_sensitive_store.dart:62-108`).

Failing scenario for FU-AC-102: A has 3 `ACCEPTED` records, signs out choosing Keep; B signs in on the same phone and goes online while the sender runs. Expected: 0 requests carrying A's `operationId`s, B's queue count 0, B cannot read A's count, records or token. A signs in: 3 records still `ACCEPTED` with unchanged `operationId`, `payloadHash` and bytes, sent under A's token and A's writer proof. Failure if any record is sent while B is signed in, deleted, re-keyed, or readable by B. The orphan variant (A's partition left behind, B signed in) is in 3.7 and FU-AC-127.

## 3. Sign-out

### 3.1 Current behavior
FACT: the profile sign-out tile runs the guard first: `mobile/lib/features/profile/profile_page.dart:287-291` is `if (await confirmSignOutWithLocalData(context, ref)) { await ref.read(authActionProvider.notifier).signOut(); }`.
FACT: `mobile/lib/features/activity/state/sign_out_guard.dart` (header lines 1-35, body 63-426) is the existing guard, awaited by every user-initiated sign-out; it returns true (sign out now) or false (stay). `JournalNotEnabled` returns true with no prompt (line 71); `binding`, `gaveUp`, `failedToOpen` or an uncountable journal show the "cannot check" sheet with Try again (not for `failedToOpen`), Sign out anyway and Cancel (lines 80, 321-360); an open journal with activities or recordings shows the warning sheet (`showSignOutWarningSheet`, lines 232-287) with Export first, Sign out (keep) and Sign out and delete, where delete needs a second confirmation sheet (`showSignOutConfirmDeleteSheet`); a failing export or deletion shows the error sheet with Retry and keeps the user signed in (`_guarded`, lines 301-318). Export first writes files to a cache directory outside backup, shares them and deletes them in `finally` (lines 366-411; line 401: a dismissed share sheet is not an error). The sheets are in `mobile/lib/features/activity/widgets/sign_out_warning_sheet.dart` (imported at line 56). Failures log a fixed message, a content-free code and the exception type (lines 33-34).
FACT: `mobile/lib/features/auth/state/auth_providers.dart:55-58` forwards `signOut` to the repository. FACT: no `waitForPendingWrites`, `clearPersistence` or `persistenceEnabled` under `mobile/lib`; Firestore SDK persistence is at defaults and its pending legacy writes are neither counted nor flushed at sign-out.
DECISION: no parallel sheet. Pending queue records become a new first step inside `confirmSignOutWithLocalData`, one coherent sequence (3.2). The `JournalNotEnabled` early `return true` (line 71) must not skip the queue step: the queue check runs before the journal availability is read.

### 3.2 One coherent sequence (queue plus journal)
DECISION. Order inside `confirmSignOutWithLocalData` for the departing UID:
1. Queue step first. Reason: queued records can still be synced, which the journal step cannot offer, and a user who syncs first may have nothing left to decide.
2. Existing journal step (unchanged states) second, only if the user did not cancel.
3. Commit phase last. Non-destructive actions (Sync first, Export) execute in their step. Destructive actions (queue Remove, journal "Sign out and delete") are only recorded and executed together after every prompt is answered. Cancel at any prompt returns false and nothing destructive has run. When both stores are being removed one confirmation names both counts. A failure in the commit phase shows the existing error sheet and keeps the user signed in; a partial commit is reported by what was removed, never as success.
4. `return true` only when the queue has no `ACCEPTED`/`SENDING`/`UNKNOWN_EFFECT`/`HELD`/`CONFLICTED` record left unless Keep was chosen (non-guest) or the confirmed Remove path ran, and the journal step returned its own true.

Queue assessment, DECISION:
- Counts come from the record states of PROTO 3.2: "saved only on this phone" = `ACCEPTED` + `SENDING` + `UNKNOWN_EFFECT` + `HELD` + `CONFLICTED`; "could not sync" = `CONFLICTED` plus `HELD` with reason `PREDECESSOR_CONFLICTED`; "may already be saved" = `UNKNOWN_EFFECT`. `SYNCED` stubs and `DISCARDED` records are not counted.
- If the partition cannot be read or counted the result is the queue "cannot check" sheet S7 with Try again and Cancel only. "Sign out anyway" is FORBIDDEN for the queue: it would drop records silently (LQ-3). Only a separate explicit confirmation "Entries on this phone could not be read. Removing them deletes them permanently and their number is unknown." may remove an unreadable partition, and only on the Remove path after an attempted export of the raw store file.
- Legacy SDK pending writes during the two-generation period: U16, the SDK exposes `waitForPendingWrites` (completes when acknowledged) but no count or enumeration (`04_CORE_TDD.md` section 7; PROTO 8.5 uses the same mechanism with a marker-document fallback). The guard runs a bounded wait; if it cannot confirm, the sheet says "older entries may not have synced" and offers the same choices, with no count.
Acceptance (FU-AC-103, FU-AC-126): widget test with N queue records plus M journal entries for every combination (N>0 or 0, M>0 or 0, journal not enabled, journal cannot check, queue cannot be read): one coherent sequence, queue first; no path returns true with queue records dropped unless the Remove path was confirmed with the count; "Sign out anyway" is never available for the queue; Cancel at the journal step leaves the queue untouched.

### 3.3 Sheet states
DECISION. The queue step appears when the signed-in UID has at least one counted record (or the partition cannot be read), before any auth state changes. With zero counted records and a readable partition it is skipped.

| State | When | Content | Actions |
|---|---|---|---|
| S1 Choice | online, N counted records, account can sign in again (not anonymous) | "You have N workout entries saved only on this phone." plus how many could not sync and how many may already be saved | Sync first (primary); Keep on this phone; Export, then remove from this phone; Cancel |
| S1-guest | anonymous (guest) account | same text plus "This guest account cannot be signed in to again." | Sync first (primary); Link account first (existing link flow, keeps the uid, `profile_page.dart:260-279`); Export, then remove; Cancel. NO Keep (3.7) |
| S1-off | no network | same text plus "You are offline, so they cannot sync now." | Sync first disabled with that reason; the others remain (Keep only for non-guests) |
| S2 Syncing | after Sync first | "M of N sent", per-record result as records become `SYNCED` | Stop waiting (back to S1 with current counts); Cancel sign-out |
| S3 Partial result | sync finished, K counted records remain (`CONFLICTED`, `HELD`, session hold, `UNKNOWN_EFFECT`) | "K entries could not sync. They are kept." with reasons by class | Keep (non-guests); Export, then remove; Try again; Cancel |
| S4 Done | no counted record left | "All entries are synced." then the sequence continues to the journal step | none |
| S5 Export | after Export, then remove | file written, OS share sheet opened, then the question of 3.5 | I saved the file with N entries (enables Remove); Share again; Cancel |
| S5-fail | export failed | "Export failed. Nothing was removed." | Try again; Keep (non-guests); Cancel |
| S6 Remove confirmation | the only path to removal | see 3.5 | Remove N entries permanently; Cancel |
| S7 Queue cannot be read | store or partition unreadable | "We could not read the entries saved on this phone." | Try again; Cancel. No "Sign out anyway" |

Copy requirements, DECISION:
- Every state names the number of entries in plain words and says whether they are "saved only on this phone".
- "Keep on this phone" (non-guests only): "They stay on this phone for this account only. Another account cannot see them. They are sent the next time you sign in to the same account. If you delete the app or change phones, they are lost."
- "Synced" is shown only for `SYNCED` from a C1/C2 answer (LQ-8, PROTO 3.8); `SYNCED` with `superseded` shows "replaced by a newer change".
- Offline copy must not imply server revocation took place (FACT: `04_CORE_TDD.md` section 6: "Offline logout cannot acknowledge server revocation. The UI must not imply that it did.").
- `UNKNOWN_EFFECT` is described as "may already be saved on the server".
- All strings go through `mobile/lib/l10n` (`app_en.arb` and the other locale files).

### 3.4 Three outcomes (LQ-12)
1. Sync first: the sender runs for this UID (pause lifted, 3.6); the step finishes when no counted record is left or the user moves to S3.
2. Keep (non-guests only): records, tables and writer tokens remain; the durable fence is written at commit (3.6); the sender stops for that UID.
3. Export, then remove: export (section 5) is produced, the user confirms (3.5), then exactly the exported records are removed in the commit phase (1.7).

### 3.5 Export then remove, and removal without export
FACT: the export sink cannot report whether the user saved anything. `ShareDataExportSink.deliver` (`mobile/lib/features/data_export/data_export_sink.dart:41-71`) writes a temp file, awaits `Share.shareXFiles` and deletes the file in `finally`; the future completing says only that the sheet closed. The guard's journal export has the same property (`sign_out_guard.dart:401`). "Verified export" is therefore not a claim the app can make.
DECISION:
1. "Verified" is replaced by what can be confirmed: (a) the file was written with N entries, and (b) an explicit user confirmation after the share sheet closes: "I saved the file with N entries" (S5). A user-chosen file location (save-to-files picker returning a URI) may replace (b) when such a sink exists (U17).
2. Dismissing the share sheet, or any share error, leaves Remove disabled. The user can Share again, Keep (non-guests) or use the removal-without-file confirmation S6.
3. Removal without any file: only from S5 via "Remove without saving a file", opening S6. For entries that are only on this phone (`ACCEPTED`, `SENDING` with a proven cancelled send, `HELD`, `CONFLICTED`): "Remove N entries permanently? They are not saved on any server and cannot be recovered." Entries in `UNKNOWN_EFFECT` are listed separately with their own warning, because the server may already have applied them (PROTO 3.2 T17, one rule): "M entries may already be saved on the server. Removing them deletes only the copy on this phone, does not undo anything the server did, and the server result stays unknown." The sentence "not saved on any server" is never shown for them. The button contains the number: "Remove N entries". The stub keeps `maybeSent = true` and `serverStateUnknown = true`.
4. Removal is scoped to the snapshot: one local transaction moves to `DISCARDED` (erasing payload, 1.5) exactly the `operationId`s present in the exported snapshot, re-reading the live set in the same transaction. A snapshot record acknowledged meanwhile is already `SYNCED` and is left alone. A record NOT in the snapshot (accepted after the export) survives; the sheet returns to S1 stating "K entries were saved after the export and are still on this phone".
5. Once any sign-out path is committed (3.6 phase two), acceptance of new commands for that UID is refused with a visible message ("not saved"); this closes the snapshot-to-remove window.
Tests: dismiss the share sheet, Remove stays disabled; confirm "I saved" then Remove discards exactly the snapshot IDs; a command accepted between snapshot and Remove survives; a share error keeps everything.

### 3.6 Two-phase fence and in-flight sends
DECISION (uses the per-UID send lease of PROTO 3.9):
1. Phase one, sheet open: only NEW sends are paused (in memory; a crash drops the pause). Acceptance of new commands continues. In-flight sends continue to a result.
2. Sync first lifts the pause: the sender runs normally for this UID while S2 is shown. Cancel, or leaving the sheet, lifts the pause and sending returns to its normal interval.
3. Phase two, commit: the durable per-UID fence `SIGNING_OUT` is written, and the send lease is acquired exclusively (waiting for or cancelling the in-flight call), only when the user commits to Keep, to Remove, or when S4 completes and the sequence reaches its commit phase. From then the sender refuses all records of the UID and acceptance of new commands is refused (3.5 item 5). Cancel before this point never writes it; Cancel after it (a failed commit that keeps the user signed in) clears it and releases the lease.
4. If a send is in flight at phase two, sign-out waits for the answer, a definitive failure or cancellation of the call, bounded (U6); on timeout the record becomes or stays `UNKNOWN_EFFECT` (T10; kept, same bytes, same `operationId`) and the UID binding is released only after the fence is durable.
5. A late answer of a cancelled or timed-out send is applied to the record of its own uid only, never to the signed-in user. C1/C2 gives `SYNCED` under its own uid; if the user already removed the record the late answer changes nothing client-side and the server holds a committed set ("may already be saved" in S6).
6. Fence release: by Cancel or a failed commit, by relaunch while still signed in as the same UID (sign-out did not happen), by a new sign-in of the same UID, or by removal and deletion.
Tests (FU-AC-103): open the sheet, Cancel, log a set online: sent in the normal interval; open the sheet, choose Sync first: records reach `SYNCED`; Keep with record 3 `SENDING`, then B signs in: 0 of A's records sent under B.
Failing scenario for FU-AC-103: 5 records, record 3 in flight, user taps Sign out then Keep. Expected: nothing sent after the fence is written; record 3 ends `SYNCED` or `UNKNOWN_EFFECT` with unchanged `operationId`; B signing in within 1 s sends 0 of A's records; A signing in resends only record 3 (if unknown) and 4, 5 with the original bytes, and the server answers record 3 `ALREADY_COMMITTED`. Failure: any request for A's `operationId` bearing B's authentication; a record lost; a new `operationId`; Cancel leaving a durable fence.

### 3.7 Guest (anonymous) accounts and orphaned partitions
FACT: for an anonymous user the only way to keep data is to link an account, which keeps the uid; ordinary sign-out "mints a fresh uid on the next sign-in and orphans all of it, permanently and silently, because an anonymous account has no credential to sign back into" (`mobile/lib/core/router/app_router.dart:117-126`; link tile for guests at `profile_page.dart:260-279`).
DECISION:
1. Keep is not offered to anonymous accounts, because the promised resume cannot happen. Their sheet is S1-guest. The guard therefore forces a guest with counted records to choose Sync first, Link account first or Export-then-remove before sign-out; the guard itself never leaves a guest queue orphaned. Copy never says "next time you sign in".
2. An orphan is an isolated UID partition that the guard did not clear (forced sign-out such as `AUTH_REVOKED`, a crash between steps, a token revoked elsewhere, a former guest uid reached by another route). It is NOT the property of whoever is signed in next. The partition is preserved, isolated and never sent.
3. Maintenance status for any other account (B), non-identifying and at most: on the data-and-backup settings page, "This phone holds unsent data from another account." No uid, no count of commands, no age, no payload, no export, no remove, no preview. A signed-in B with the phone unlock credential gets nothing more: a device credential proves device access, not ownership of A's data. The existence flag is the only cross-UID output of the store (section 2 item 3).
4. Content access, export and deletion belong to the data owner only: (a) A signing in again (then A's normal sign-out sheet applies); (b) A's account-deletion flow (section 4), which clears A's partition; (c) the purge when the server reports A's account deleted, observed only while A's uid is authenticated or its cached user fails with an account-gone error (U14); (d) a defined authorized recovery capability (for example support-verified re-authentication of the same account), which is UNKNOWN U15 and not designed here. Otherwise the isolated partition stays.
5. An orphan partition counts toward nothing but its own UID cap. Its growth is bounded by 500 records per uid; a device with many orphaned guests keeps all of them (accepted, U4).
Tests (FU-AC-102 and FU-AC-127): A leaves an orphaned partition, B signs in; with B's account plus the phone unlock credential B can neither inspect nor export A's commands, sees no count, and the sender sends none; A signing in recovers the records; A's account deletion clears the partition; a server-reported deletion of A purges it when observed; with no signal the partition is preserved.

## 4. Account deletion

### 4.1 Current behavior
FACT: `mobile/lib/features/account_deletion/state/account_deletion_providers.dart:94-172` calls the `deleteAccount` Cloud Function first, and only after server confirmation records the uid in the pending-wipe marker (`PrefsPendingWipeMarker`, key `account_deletion.pending_wipe_uids`, `local_data_wipe.dart:63-66`), wipes device data, cancels notifications and signs out. The comments at lines 113-122 say the wipe is deliberately after the server call so a failed deletion never wipes a still-live account. FACT: `DeviceLocalDataWipe.wipe` (`local_data_wipe.dart:281-407`) erases an exact list of preference keys, `progress_photos/<uid>/`, `coach_recordings/<uid>/` and the scan history; it has no queue step and no writer-token step. FACT: the client has no re-authentication step: grep of `mobile/lib/features/account_deletion` for recent-login or reauth matched nothing, and the service retries once with a forced token refresh on `unauthenticated` (`cloud_functions_account_deletion_service.dart`). Whether the server rejects with a recent-login error is U18; Stripe cancellation failure is a documented failure mode (`account_deletion_providers.dart:80-86`). FACT: `accountBeingDeletedUidProvider` lets in-flight writers abort (`account_deletion_providers.dart:24-29`) but it is set only after server confirmation.

### 4.2 Required ordering (LQ-13, PROTO 8.7)
FACT: PROTO 8.7 already fixes the server order: deletion sets `migrationState = DELETING` first (all applies answer `ACCOUNT_DELETING`, a terminal state reachable from any state), then client sends are cancelled and the queue cleared, then server data (fence, receipts, typed documents, projections, tombstones, quarantine, counters) is deleted and the policy document last; a missing policy document refuses applies, so nothing is recreated.
DECISION, adapting the client side to that order. The queue is never cleared while the account can still survive a failed deletion without the user having chosen that loss, so every separable failure point comes BEFORE the fence, and the irreversible server marker comes BEFORE the clear:
0. Pre-flight, before any fence (failure changes nothing): forced ID-token refresh (`getIdToken(true)`) and any re-authentication the platform requires (none exists in the client, U18); network reachability; and, with N>0 counted records, an export or a second confirmation naming N ("N workout entries saved only on this phone will be removed with the account"). Declining export is allowed.
1. Write durable checkpoint `FENCED(uid)` (4.3). From here the sender refuses all records of the uid and new acceptance is refused with a visible message. Records are NOT touched.
2. Acquire the send lease exclusively, cancelling in-flight sends; each ends `SYNCED` or `UNKNOWN_EFFECT`; late answers are ignored client-side from here on.
3. Call the server begin-deletion step (working name `beginAccountDeletion`, U7), which does every separable server pre-check first (including the Stripe cancellation, so a Stripe failure leaves nothing changed) and only then sets `DELETING`. If the call fails, the fence and checkpoint are removed, records are intact, sending resumes and the user sees the failure. If it succeeds, deletion is committed and cannot be cancelled. Write `DELETING_ON_SERVER`.
4. Write `QUEUE_CLEARING`; delete the uid partition (records and all tables, 1.7) and the uid's writer tokens in secure storage; verify empty; write `QUEUE_CLEARED`. Any `ACCOUNT_DELETING` answer received for a record is T11 (record returns to `ACCEPTED`) and is then deleted with the partition.
5. Call the final `deleteAccount` (idempotent, `account_deletion_providers.dart:88-93`). On success write `SERVER_DELETED`, then the existing steps (marker add, `LocalDataWipe.wipe`, notification cancel, sign-out). If the final call fails after step 4 the account stays `DELETING`, the user sees the existing error and Retry, and the message says unsynced entries were removed at their confirmed request; retry converges.
6. No resurrection by a late send: (a) the client cannot send (fenced, then cleared); (b) the server answers `ACCOUNT_DELETING` from step 3, so a request already on the wire is refused; (c) the tombstone and generation fences stop a command arriving after finalization. FACT: `11_SECURITY_PRIVACY.md` section 6 and `05_DATA_MODEL.md` section 8 require such fences. U7: that the deployed `deleteAccount` implements the begin step and the workout-command fence is not verified (functions code not inspected; PROTO 11.2 item 5 is the same unknown). Fallback if the operator rejects a begin step: skip step 3, keep the pre-flight and the N-naming confirmation, and accept that a failure of step 5 leaves a live account with an empty queue (stated in the copy); FU-AC-104 gates either variant.

### 4.3 Deletion checkpoint and crash recovery
DECISION: the checkpoint is a uid-only record outside the queue partition, next to the existing pending-wipe marker, holding uid, stage and timestamps, no payload, with the same durability as queue commits. Recovery on launch, for every checkpoint found, regardless of who is signed in:

| Crash after | Stage found | Recovery |
|---|---|---|
| step 1 or 2 | `FENCED` | records untouched and unsendable; if the signed-in user is that uid, ask "Finish deleting your account?" with Continue and Cancel deletion; Cancel removes the checkpoint and fence, records intact. Cancel is possible only in this stage |
| step 3 | `DELETING_ON_SERVER` | deletion is committed: continue forward without asking again (the user confirmed before step 1) |
| step 4 started | `QUEUE_CLEARING` | complete the clear (idempotent), do not resume sending, continue to step 5 |
| step 4 done | `QUEUE_CLEARED` | call `deleteAccount` again (idempotent) without asking |
| step 5 succeeded, crash before `SERVER_DELETED` is written | any stage from `DELETING_ON_SERVER` on | see below |
| `SERVER_DELETED` written | `SERVER_DELETED` | run `finishInterruptedWipe` and sign out |

Crash after the server deleted the user but before `SERVER_DELETED` is written, DECISION: resolve in this order. (1) If the cached Firebase user for that uid is still present (Auth keeps it until its token refresh fails), call `deleteAccount` again: an idempotent success or "account not found" is `SERVER_DELETED`, with no second confirmation. (2) If no user is signed in and the auth layer reports the account gone (user-not-found or equivalent, U14), treat it as `SERVER_DELETED`. (3) If no user is signed in and there is no evidence about the server, do NOT erase the health blob and photos (the account may be live); keep the checkpoint and the fence and resume on the next sign-in of that uid. In (1) and (2) the uid is added to the pending-wipe marker and `finishInterruptedWipe` runs the full wipe (preferences, photos, scan history, the queue partition, the writer tokens), then the checkpoint is removed. This closes the hole in which the marker is never written because `SERVER_DELETED` never was.
Test (FU-AC-121): kill after the server delete returns but before the `SERVER_DELETED` write; the next launch erases all uid-keyed device data and the checkpoint. Second test: kill at `QUEUE_CLEARED` with no signed-in user and no server evidence: nothing beyond the already-cleared queue is erased and the checkpoint survives.

### 4.4 Difference from the current order, and why
FACT: the current order protects against wiping a live account's data when server deletion fails. DECISION: the queue is cleared before the final deletion because LQ-13 and PROTO 8.7 require that order and because clearing after leaves a window in which a record can be sent after the server data is gone. A review found that clearing before any server success destroys the queue of an account that then survives a failed deletion. The resolution in 4.2 puts every separable failure (token, re-authentication, reachability, confirmation naming N, server pre-checks including Stripe) before the fence and the irreversible `DELETING` marker, and clears only after it. Residual cost: a failure of the final `deleteAccount` after the clear leaves a `DELETING` account with an empty queue; the user confirmed that loss by name. The health blob and photos keep the existing "after server confirmation" order.
Contradiction record: the existing code comment (wipe only after the server call) and LQ-13 pull in different directions; resolved above, scoped to the queue and writer tokens only.

### 4.5 Failing scenario for FU-AC-104
Delete during sync with 10 counted records (3 `SENDING`); kill after step 2, after step 3, after step 4 and after the step 5 request; after each restart complete the flow. Expected: no document under `workout_sessions`, the typed documents, fences or receipts exists for that uid after finalization; the partition and the writer tokens are gone; the checkpoint is removed after the wipe. Failure: any document reappears, or a record is sent after the first restart.
Failure-before-clear tests: force `beginAccountDeletion` (or `deleteAccount` before the marker) to fail with a recent-login error, with a Stripe error, and offline: in each case all records are intact with their `operationId`s, the fence and checkpoint are removed, sending resumes and the user sees the failure. Force the final call to fail after step 4: the account remains `DELETING`, Retry converges, and no record is ever sent.

## 5. Export

### 5.1 Current behavior
FACT: `DataExportAction.export` (`mobile/lib/features/data_export/data_export_providers.dart:32-137`) reads profile, workout history through `exportAll`, schedule, programmes and photo metadata with 30 s timeouts and a server callable, builds JSON via `buildExportJson` (`data_export_providers.dart:134` calls `data_export.dart:120`, which wraps `buildExport` at `data_export.dart:34`; `exportFormatVersion: 1`, `notes`, `serverIncomplete`) and hands it to `ShareDataExportSink`, which cannot report whether the user saved the file (3.5). The format change in 5.3 is made in `buildExport` and threaded through `buildExportJson`. FACT: `workoutLogs` comes from server-or-SDK-cache repositories and contains no queue records.

### 5.2 Snapshot rules
DECISION:
1. The export reads the partition of the signed-in UID in one read transaction (a consistent snapshot) and includes every record whose state is `ACCEPTED`, `SENDING`, `UNKNOWN_EFFECT`, `HELD` or `CONFLICTED` (LQ-14). `SYNCED` stubs (payload erased, content on the server) and `DISCARDED` records are not exported as device-only commands.
2. It works offline: the queue snapshot has no network dependency and is always included. The server part stays best-effort (`serverIncomplete`). Export never fails because the network is down.
3. Records acknowledged between snapshot and file write are listed with their state at snapshot time; the file states `snapshotAt`.
4. Exported records are not removed unless the user chose Export, then remove (3.5) or the export belongs to account deletion.
5. A corrupt record is exported raw with a flag rather than failing the export.

### 5.3 Format
DECISION: bump the top-level format to `exportFormatVersion: 2` (U8: whether a reader of version 1 exists outside the app) and add a block whose entries use the field names of PROTO 3.1 verbatim, exactly the "golden export entry" owed by the shared fixture (PROTO 3.10):
```
"deviceOnlyCommands": {
  "snapshotAt": "<UTC ISO-8601>",
  "count": <int>,
  "commands": [ { <PROTO 3.1 record fields: uid, operationId, sessionId, exerciseId,
                   operation, sessionGeneration, acceptedEpoch, seq, dependsOn,
                   logicalSetId, payloadFields, payloadHash, state, heldReason?,
                   conflictKind?, conflictTerminal?, maybeSent, attempts,
                   lastResultCode, intentKey, supersedes, ...>} ]
}
```
plus a note: "These entries exist only on this phone and are not part of your synced history." Rules: states are the seven PROTO names; `dependsOn` is exported without loss or reordering; `operationId` is included (PROTO 2.6) and deleted with the account; the writer token is NEVER included and no other secret is a record field. Whether `canonicalBytes` is exported in addition to `payloadFields` follows the fixture's golden export entry (U21). A pending record is never added to `workoutLogs` (double count after sync, FU-AC-099).

### 5.4 Relation to server export
The server export remains the authority for committed data. DECISION: an entry present in `deviceOnlyCommands` and also as a committed set (acknowledged between reads) is deduplicated by `operationId` in the importing reader, not by the exporter, which always labels the origin. The server-side receipts and fence entries are protocol metadata and are not exported as workout facts.

### 5.5 Failing scenario for FU-AC-105
Airplane mode, 15 `ACCEPTED` and 2 `CONFLICTED` records, run export. Expected: `deviceOnlyCommands.count == 17`, each `operationId` once, server part marked incomplete, no network call for the queue part, no writer token anywhere in the file. Failure: export aborts offline, includes only 15, includes a `SYNCED` stub, or the 15 also appear in `workoutLogs`.

## 6. Retention and limits (fail closed)

DECISION (values are LQ-3; counting and warning mechanics are PROTO 3.3 and 3.8; the old-command outcome is PROTO 3.7 and is not restated):

| Threshold | Behavior |
|---|---|
| 400 counted records for a UID | warning "Your phone holds 400 unsent entries" with a link to sync/export, computed in the acceptance transaction |
| oldest non-`SYNCED` record is 25 days old | latched warning with the date of the oldest entry (PROTO 3.8: persisted wall high-water mark, monotonic age, latched in `ageWarningRaisedAt`; a clock change, reboot or restart cannot hide it) |
| 500 counted records | the 501st is refused before any record is created, with a visible message; all 500 remain; the user can sync, export or explicitly remove |
| 30 days | stronger aging copy only; NOT an eviction deadline. PROTO 3.8 names only the 25-day and 400-record warnings; the 30-day copy is a UI-only addition (U22) |
| any record held (session-level hold or `CONFLICTED` non-terminal) over 24 hours | persistent banner (PROTO 3.8) |

Rules:
- Counted states are `ACCEPTED`, `SENDING`, `UNKNOWN_EFFECT`, `HELD`, `CONFLICTED` (PROTO 3.3 step 1). `SYNCED` and `DISCARDED` are not counted.
- Failing closed also covers storage errors: if the commit fails (disk full, I/O error, or the writer token cannot be created in secure storage, PROTO 3.3) the command is reported "not saved" and the UI never shows pending (LQ-2).
- Age is a display and warning input only; no state change or removal depends on it. There is no "too old" conflict and no client or server age limit (PROTO 2.4, 3.7).
- Old commands, by PROTO 3.7 (restated by reference only): never sent at any age stays eligible and is applied once; sent with the answer lost is `ALREADY_COMMITTED` or `ALREADY_COMMITTED_DETAIL_EXPIRED`, both ending `SYNCED`; an earlier refusal replayed after expiry is `ALREADY_REJECTED` ending `CONFLICTED`; an unprovable one is `OUTCOME_UNKNOWN_REPLAY_CLOSED` ending `CONFLICTED`, never applied. Receipt capacity versus 500 (LQ-7) is PROTO 5 (compact fence kept for the life of the account).
- Sign-out and app update never change counts.

## 7. Telemetry and logs

DECISION:
1. No payload content and no identifier in any release log, crash report, analytics event, error message or remote-config check: no reps, loads, exercise names, `sessionId`, `operationId` (pseudonymous, PROTO 2.6: not above debug level, never a metric label), uid, writer token, `payloadHash`, or per-exercise counts.
2. Allowed (enums and aggregates only): outcome class (accepted, refused_cap, refused_commit_failed, refused_token_store_failed, acknowledged, conflicted, unknown_effect, held), state names of PROTO 3.2, `lastResultCode` enum names, queue size bucket (0, 1-10, 11-100, 101-399, 400-499, 500), oldest-age bucket (days 0-6, 7-24, 25-29, 30+), attempts bucket, latency bucket. These match the local counters PROTO 4.6 requires (oldest non-`SYNCED` age, count by `lastResultCode`).
3. FACT: `firebase_crashlytics` is a dependency (`mobile/pubspec.yaml:94`); existing code logs only `e.runtimeType` where the exception text would carry a uid-named path (`local_data_wipe.dart`, photo-directory catch). The queue follows this rule: exception type only; never `$e` of a record-carrying object; Crashlytics custom keys never carry record fields.
4. FACT: uncaught errors reach Crashlytics through `FlutterError.onError` and `PlatformDispatcher.instance.onError` (`mobile/lib/main.dart:427-450`); both pass the error through `sanitizeForGlobalHandler`, which today replaces only errors of recorder origin ("any other error is untouched", comment at lines 425-426). DECISION: the queue store throws only a typed `QueueStoreException` with a fixed message and a class enum, never a path, uid, `operationId` or payload (file-system exceptions are caught at the store boundary and re-thrown in that form), and `sanitizeForGlobalHandler` is extended to redact any queue-origin error so a missed wrapper still cannot leak. Test: inject a store failure whose raw text contains a path and an `operationId`; the Crashlytics test sink receives neither (FU-AC-122).
5. The queue's `toString` and error messages are redacted by construction, so an accidental `debugPrint(record)` prints nothing sensitive. The same holds for any object holding a writer token.
6. Server logs follow `17_RELEASE_OPERATIONS.md` ("Redact sensitive data from logs") and PROTO 4.6 (no UID or `operationId` in metric labels). Whether any client telemetry may leave the device is U9 and PROTO 11.2 item 10; this document requires only the local counters.
Acceptance: FU-AC-122.

## 8. Restore, reinstall and new device

DECISION:
1. Queued commands never travel to another device: they and the writer tokens are excluded from cloud backup and device transfer (1.6), are not uploaded, and are not part of the passphrase backup file. FACT: the existing encrypted backup file (`mobile/lib/features/data_export/backup_envelope.dart`) is a carried profile/health backup protected by a user passphrase; it does not include the queue and will not.
2. On reinstall, restore or a new phone, signing in shows an empty queue. If a queue file appears on a mismatched `deviceInstallId`, PROTO 9 and T15 apply (1.6). Whether the app can tell a clean reinstall from a restore is U10; no claim is made. The notice is the Keep text (3.3) and a note on the data-and-backup settings page: "Entries not yet synced stay on this phone and are not included in backups or phone transfers. Sync or export them before changing phones."
3. Committed workout data is unaffected: it is on the server and appears after sign-in. A new install has no writer token; sending a session needs the explicit takeover of PROTO 8.1.
4. Server restore (`17_RELEASE_OPERATIONS.md` section 7): a record the restored server has no receipt for is a normal first delivery. Duplicate risk is closed by the set-identity rule on committed session state and the compact fence (PROTO 4.2, 5); U11 stays with the core design.

## 9. Voice transcripts and audio

DECISION: the queue stores no audio, transcript, recognition hypothesis or recognized-text snippet. A voice "complete set" and a touch "complete set" produce records that differ only in `body.source` (PROTO FU-AC-101), written by one code path (LQ-10); no other field records the input modality (U12, default no). `intentKey` is an opaque id of the UI event or of a final recognition result and carries no text.
- FACT: `docs/v1/VOICE_READY_PROMPT_DECISION.md`: "Audio and transcripts are not stored"; StartSet is not a queued command and creates no record, receipt or completed-set fact.
- Ambiguous or low-confidence speech never enters the queue as a guess; only a confirmed typed command is accepted.
- Cancelling or invalidating a waiting context (route change, background, sign-out) leaves no record.
Acceptance: FU-AC-123.

## 10. Changes required per document

Package (`FitnessUp_v1_Rebaseline_2026-10-20/docs/`), by the package author:

| File | Section | Change |
|---|---|---|
| `05_DATA_MODEL.md` | 2 entity dictionary | add `LocalCommandQueue` (device-local, UID-partitioned, schema by reference to PROTO 3.1), `QueueLifecycleCheckpoint` (uid, stage) and `WriterToken` (secure storage, never exported) |
| `05_DATA_MODEL.md` | 6 retention table | add rows: queue (until `SYNCED`/exported/`DISCARDED`; 400/500/25/30); writer token (until session removal or account deletion); deletion checkpoint (until finalization) |
| `05_DATA_MODEL.md` | 7 migration | queue and Firestore SDK pending writes are two generations (doc 14); both excluded from backup |
| `04_CORE_TDD.md` | 6 outcome table and paragraph after it | replace NOT_SENT_OFFLINE; remove "not a stored unsent payload or an offline operation queue"; adopt the seven states; logout paragraph points to sections 3.2 to 3.7 of this file; "Preserve S04 cannot-check/wipe guards" names `sign_out_guard.dart` as the single flow the queue joins |
| `04_CORE_TDD.md` | 7 | remove "No durable manual-draft replacement"; replace with the queue and PROTO 8 preservation |
| `11_SECURITY_PRIVACY.md` | 2 data-flow table | add row "Queued workout commands and writer token" (device only, UID partitioned, excluded from backup, token in secure storage, no payload or identifier in logs) |
| `11_SECURITY_PRIVACY.md` | 3 | replace the Option A paragraph; local acceptance precedes any server step |
| `11_SECURITY_PRIVACY.md` | 6 | sign-out outcomes, two-phase fence, deletion order (4.2), orphan rule (3.7) |
| `11_SECURITY_PRIVACY.md` | 7 | add negative tests FU-AC-120 to FU-AC-128 to the pre-release list |
| `12_ACCEPTANCE_AND_TEST_STRATEGY.md` | register | add rows from `ACCEPTANCE_AMENDMENTS.csv` and the rows below |
| `14_INTEGRATION_MIGRATION_RUNBOOK.md` | pending writes | two generations; drain before cutover |
| `15_DECISIONS_AND_RISKS.md` | ADR-CMD-03 | supersede; add an ADR "Queue is a first-class UID data class, excluded from backup, unencrypted at app level, writer token in secure storage" with the alternatives of 1.4 |
| `17_RELEASE_OPERATIONS.md` | section 7 restore, logs | add the queue and tokens to restore notes (8) and to log redaction (7) |
| `16_DOCUMENT_REGISTRY.md` | register | add this file and `OFFLINE_COMMAND_PROTOCOL.md` |

Protocol (`docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md`), by its owner: DONE in version 1.3.2 (T17, `DISCARDED` stub rules, the `effective_set` marker/values split, the `UNKNOWN_EFFECT` removal rule). Still owed: the 30-day stronger copy in 3.8 or drop it (U22); the fixture extension with the export entry, the lifecycle rows of 1.7 and the sign-out/deletion expectations so that FU-AC-125 also covers them.

Repository (`D:\Repo\Fitness_App` after implementation), by the implementer:

| File | Change |
|---|---|
| `mobile/android/app/src/main/res/xml/backup_rules.xml` and `data_extraction_rules.xml` | exclude the queue (or document its excluded placement) and the Firestore cache location; keep the secure-storage files excluded |
| `mobile/test/android/backup_rules_test.dart` | assert the final exclusion set in all three sections |
| `mobile/lib/features/account_deletion/state/account_deletion_providers.dart` | new ordering and checkpoint (4.2, 4.3) |
| `mobile/lib/features/account_deletion/data/local_data_wipe.dart` | add queue-partition and writer-token steps and `queue`/`writer_token` to `remaining`; keep the best-effort contract |
| `mobile/lib/features/account_deletion/data/cloud_functions_account_deletion_service.dart` | pre-flight token refresh and the begin-deletion call (U7) |
| `mobile/lib/features/activity/state/sign_out_guard.dart` and `widgets/sign_out_warning_sheet.dart` | queue step, S7 without "Sign out anyway", commit phase, ahead of the `JournalNotEnabled` early return |
| `mobile/lib/features/profile/profile_page.dart` | no change to lines 287-291; guests reach Link account from the new sheet |
| `mobile/lib/main.dart` (`sanitizeForGlobalHandler`) | redact queue-origin errors (lines 427-450) |
| `mobile/lib/features/data_export/data_export.dart` and `data_export_providers.dart` | `deviceOnlyCommands`, format version 2 |
| `mobile/lib/l10n/app_en.arb` and locale files | sheet, warning and settings-page strings |
| `docs/v1/package-amendments/ACCEPTANCE_AMENDMENTS.csv` and `SUPERSESSION.csv` | add the rows below; supersede the Option A rows |

### Acceptance obligations
Existing rows, with the concrete failing scenarios of sections 2, 3.6, 3.7, 4.5 and 5.5:

| Row | Failing scenario that must be caught |
|---|---|
| FU-AC-102 | sender uses the current user's authentication for another UID's record; partition deleted or re-keyed on switch; another UID's count, records or token readable; with A's orphaned partition left behind, B plus the phone unlock credential can inspect, count or export A's commands |
| FU-AC-103 | request for A's `operationId` after the fence; record lost on timeout; a new `operationId` after resume; a direct discard button; S6 without the number; "Sign out anyway" for the queue; Cancel leaving a durable fence or a paused sender |
| FU-AC-104 | any document reappearing after deletion with a send racing; a record sent after the first restart; a failed `deleteAccount` (recent-login, Stripe, offline) before `DELETING` leaving a destroyed queue; writer tokens surviving deletion |
| FU-AC-105 | offline export missing `CONFLICTED`/`HELD` records; pending records also in `workoutLogs`; writer token in the file |

Proposed new rows (status NOT_RUN, priority P0, same columns as the CSV). FU-AC-125 is already taken by the protocol (shared fixture) and is not reused; FU-AC-119 is the protocol's migration row.

| ID | Requirement/task | Scenario | Expected result |
|---|---|---|---|
| FU-AC-120 | FU-RQ-013 | Backup and transfer exclusion | The final exclusion set (nine current entries plus the queue location and the Firestore cache location, or the documented placement under an excluded directory) is asserted exactly in `full-backup-content`, `cloud-backup` and `device-transfer`; the secure-storage files stay excluded; the queue is flagged excluded on iOS; a restore or transfer to a second device yields an empty queue and no token, and the first device still sends once. Static assertion plus a device or emulator backup/restore run. |
| FU-AC-121 | FU-RQ-049 | Deletion checkpoint crash recovery | Kill at each stage of 4.3; after each restart no record is sent, deletion is cancellable only in `FENCED`, and no marker or checkpoint remains after finalization. Includes: kill after the server delete but before the `SERVER_DELETED` write erases all uid-keyed device data (queue, tables, writer tokens, preferences, photos, scan history) on next launch; a failing begin-deletion step (recent-login, Stripe, offline) leaves the queue intact. |
| FU-AC-122 | FU-RQ-013 | No payload or identifier in logs and telemetry | With a log capture and a Crashlytics test sink, run accept, sync, conflict, cap refusal, token-store failure, sign-out and deletion, and inject a store failure with a path and an `operationId` in its text; no payload value, `operationId`, uid, `sessionId`, exercise name or writer token appears in any captured line, key or error; bucketed fields only. |
| FU-AC-123 | FU-RQ-019 | No audio or transcript in the store | After 20 voice-initiated queued commands and 20 rejected utterances, the store, the tables and the logs contain no audio, transcript or modality field; rejected utterances created 0 records. |
| FU-AC-124 | FU-RQ-049 | Export format and offline snapshot | Schema validation of `deviceOnlyCommands` against the fixture's golden export entry (`exportFormatVersion` 2, PROTO 3.1 names, seven state names, lossless `dependsOn`); consistent snapshot while a send is acknowledged mid-export; works with the network off; excludes `SYNCED` stubs and `DISCARDED`; never contains a writer token; a corrupt record is included raw with a flag. |
| FU-AC-126 | FU-RQ-013 | Sign-out guard sequence and sheet states | Widget test of `confirmSignOutWithLocalData` with N queue records plus M journal entries (journal not enabled, journal cannot check, queue cannot be read included): one coherent sequence, queue first; no path returns true with queue records dropped unless Remove was confirmed with the count; "Sign out anyway" never offered for the queue; Cancel anywhere leaves everything intact. Each of S1 to S7 reachable with exact counts from the PROTO states; offline disables Sync first with a reason; dismissing the share sheet keeps Remove disabled; a command accepted after the snapshot survives Remove; open sheet then Cancel then log a set online is sent in the normal interval; Sync first reaches `SYNCED`. |
| FU-AC-127 | FU-RQ-013 | Guest accounts and orphaned partitions | An anonymous account never sees Keep; Link account first keeps the uid and the queue. With an orphaned partition of A and B signed in with the phone unlock credential: B sees only the non-identifying status, cannot inspect, count, preview, export or remove A's commands, and none is sent; A signing in recovers them; A's account deletion clears them; a server-reported deletion of A purges them when observed; with no signal the partition is preserved. |
| FU-AC-128 | FU-RQ-015 | Per-UID cap, warnings and lifecycle table | 500 for UID A leaves UID B able to accept; removal follows the table of 1.7 store by store (records to `DISCARDED` for the snapshot IDs only, `effective_set` values erased and identity markers kept, `session_seq` kept, tokens removed only for fully removed sessions); no age, clock change, reboot, update or sign-out removes a counted record; an aged never-sent command stays eligible with no "too old" outcome (PROTO 3.7 via FU-AC-125). |

## 11. UNKNOWNs
| ID | Question | Why it matters / default |
|---|---|---|
| U1 | Which storage engine implements the atomic local commit (new dependency)? | dependency review; must pass FU-AC-093; same as PROTO 11.2 item 1 |
| U2 | Is app-level encryption of the queue required by the privacy review? | default no (1.4); the writer token stays in secure storage regardless |
| U3 | iOS backup exclusion, data protection class and Keychain backup behaviour of the token storage | no iOS evidence in this review |
| U4 | Device-wide cap, and storage growth from several accounts or orphaned guest partitions | default per UID only |
| U5 | RESOLVED: the cannot-check sheet exists in `sign_out_guard.dart` (an earlier draft was wrong) | the queue joins that flow (3.1, 3.2) |
| U6 | Bounded wait for an in-flight send during sign-out | value to freeze at implementation |
| U7 | Deployed `deleteAccount`: begin-deletion step with pre-checks (Stripe) before `DELETING`, and the workout-command fence | functions code not inspected; needs operator approval of a new server step; FU-AC-104 gates either variant (4.2); PROTO 11.2 item 5 |
| U8 | Readers of export format version 1 outside the app | decides whether bumping to 2 is safe |
| U9 | Whether diagnostics consent permits bucketed queue metrics | PROTO 4.6 and 11.2 item 10 |
| U10 | Whether a clean reinstall can be told from a restore | default: no claim (PROTO 11.2 item 11) |
| U11 | Set-identity uniqueness enforced on committed session state, not on receipts only | belongs to the core design (PROTO 4.2, 5) |
| U12 | Whether product analytics wants an input-modality field | default: not stored |
| U13 | Exact Firestore offline-cache location and whether a restored cache is usable | decides the exclusion entry (1.6) |
| U14 | Which auth errors prove the account was deleted server-side | crash recovery (4.3) and orphan purge (3.7) |
| U15 | A defined authorized recovery capability for an orphaned partition | none designed; default: partition preserved isolated (3.7) |
| U16 | Firestore SDK gives no count or enumeration of legacy pending writes; only a bounded `waitForPendingWrites` | 3.2, PROTO 8.5 |
| U17 | A save-to-files export sink returning a user-chosen location | would replace the "I saved the file" confirmation (3.5) |
| U18 | Whether the server requires recent login or fails deletion for other reasons; no client re-authentication exists | pre-flight in 4.2 |
| U19 | CLOSED in protocol 1.3.2: T17 and the `DISCARDED` stub lifetime are in PROTO 3.2 and 3.6 | 1.5 |
| U20 | CLOSED in protocol 1.3.2: marker kept, values erased (PROTO 3.6) | 1.7 |
| U21 | Whether `canonicalBytes` appears in the export entry | decided by the fixture's golden export entry (5.3) |
| U22 | The 30-day stronger warning is not in PROTO 3.8 | add there or drop (6) |

Contradictions found with existing material (none with LQ-1 to LQ-14):
1. Existing deletion order (server first, wipe after) versus LQ-13 and PROTO 8.7 (clear queue before the final server delete): resolved in 4.4 for the queue and writer tokens only.
2. The package's `04_CORE_TDD.md` sections 6 and 7 and `11_SECURITY_PRIVACY.md` section 3 still state Option A (recorded as B-01/B-03 in the reconciliation); not changed here.
3. LQ-12 calls the cannot-check sheet existing; it does exist (`sign_out_guard.dart`). That sheet offers "Sign out anyway", LQ-3 forbids silent loss, so the queue variant forbids it (3.2).
4. (Resolved in protocol 1.3.2.) PROTO 3.2 had no transition into `DISCARDED` from the non-terminal states, yet LQ-12 requires removal of such records: T17 is now defined there.
5. PROTO 8.7 makes `DELETING` terminal and irreversible; an earlier draft of this file assumed a reversible deletion-pending mark. Conformed: cancellation is possible only before the server step (4.3).
6. FU-AC-125 was used by an earlier draft of this file for a different row; renumbered to FU-AC-128 so the protocol's fixture row keeps FU-AC-125.
