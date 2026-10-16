/// Decision taken when a summary write is rejected (S02 design 6.2; test plan
/// I26, I37). No upload/sync code exists in the activity feature yet, so the
/// decision is a pure function the future Firestore repository calls after it
/// has performed the two reads.
///
/// Permission-denied is NOT deletion: it is routine under the `rev`,
/// immutability, clamp, batch and account-deletion-fence rules. The only
/// evidence of a cloud delete is the server tombstone
/// `users/{uid}/activity_tombstones/{id}` (owner-readable, server-written).
library;

/// What the sync layer does with the local entry after a rejected write.
enum SummaryDenialAction {
  /// The tombstone exists: delete wins. Write a tombstone line to
  /// `record.json` (`ActivityJournal.delete`) and remove the local data.
  deleteLocal,

  /// No tombstone (or it could not be read): keep ALL local data, mark the
  /// entry `JournalSyncState.syncConflict`, never `synced`, never deleted.
  /// Resolved by read, three-way merge and one retry, or by the user's choice;
  /// retried at the next start (no hot loop).
  markSyncConflict,
}

/// [tombstoneExists] is the result of reading `activity_tombstones/{id}`:
/// `true` = document present, `false` = read succeeded and it is absent,
/// `null` = the read failed or was not attempted. Only `true` deletes; `null`
/// is treated like `false` so a transient failure can never destroy local data.
/// A rejection caused by the account-deletion fence is indistinguishable from
/// other rejections and also lands on [SummaryDenialAction.markSyncConflict]
/// (the account-deletion wipe removes the local data, design 3.5).
SummaryDenialAction decideOnSummaryWriteDenied({required bool? tombstoneExists}) =>
    tombstoneExists == true
        ? SummaryDenialAction.deleteLocal
        : SummaryDenialAction.markSyncConflict;
