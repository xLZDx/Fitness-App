/// The local activity journal interface and the sign-out / wipe hook points
/// (S02 design 3.4, 3.5; GPS-PRIV-085; test plan I09, I10, I25).
///
/// The sign-out warning UI and the local export (GPX/FIT/JSON) belong to other
/// stories (S02-07 export, UI); this file holds only the interfaces and the
/// pure decision logic so those stories plug in without changing the journal.
library;

import '../data/activity_session.dart';
import 'journal_models.dart';

abstract class ActivityJournal {
  /// Opens the journal and runs the recovery pass. Must be called once before
  /// any other method.
  Future<JournalRecoveryReport> start();

  /// Creates or replaces an activity as one new generation. Completes only
  /// after the COMMIT marker rename. An identical re-put (same session, same
  /// streams) is a no-op. Throws [JournalWriteFailure] subclasses (storage
  /// full included); the previous durable state stays intact.
  Future<JournalEntry> put(
    ActivitySession session, {
    JournalSyncState? syncState,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  });

  /// The full entry with streams, or null when unknown, deleted or
  /// unreadable. A `streamLost` entry has no streams.
  Future<JournalEntry?> read(String id);

  /// Live entries WITHOUT streams, in sequence order. Use [read] for streams
  /// and never `put` a session obtained here.
  Future<List<JournalEntry>> list();

  /// Deleted ids (tombstones), for the sync layer to push deletes.
  Future<List<JournalEntry>> listTombstones();

  /// Writes a tombstone generation and drops streams, laps and provenance.
  /// Idempotent. Delete wins over a later put of the same id (design 6.2).
  Future<void> delete(String id);

  /// Records the sync state. When [expectedGeneration] is given and the entry
  /// moved on (it was edited meanwhile) nothing is written and false is
  /// returned. Returns false for an unknown id.
  Future<bool> updateSyncState(
    String id,
    JournalSyncState state, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  });

  /// `synced` marker; call only after the commit callable returned success.
  Future<bool> markSynced(
    String id, {
    int? expectedGeneration,
    int? baseRev,
    Map<String, Object?>? baseSummary,
  });

  /// Counts for the sign-out decision.
  Future<SignOutAssessment> assessSignOut();

  /// Deletes every journal, source and quarantine file and the key.
  Future<void> wipe();

  /// Number of activities found `streamLost` since start.
  int get streamLostCount;

  /// Releases the directory so another instance may open it.
  Future<void> close();
}

/// UI/export seam for sign-out (design 3.5). Implemented by the UI story.
abstract class ActivitySignOutHooks {
  /// Offers the local export (GPX/FIT/JSON) before anything is deleted.
  Future<void> offerExport(SignOutAssessment assessment);

  /// Asks the user to confirm wiping. False keeps every file.
  Future<bool> confirmWipe(SignOutAssessment assessment);
}

/// The wipe rules in one place.
class ActivityWipeCoordinator {
  ActivityWipeCoordinator(this._journal);

  final ActivityJournal _journal;

  /// Sign-out: an empty journal signs out without a prompt; a non-empty one
  /// offers export, asks for confirmation and wipes only when confirmed.
  /// Returns true when the journal holds no data afterwards.
  Future<bool> onSignOut(ActivitySignOutHooks hooks) async {
    final assessment = await _journal.assessSignOut();
    if (!assessment.requiresWarning) {
      await _journal.wipe();
      return true;
    }
    await hooks.offerExport(assessment);
    if (!await hooks.confirmWipe(assessment)) return false;
    await _journal.wipe();
    return true;
  }

  /// Account deletion succeeded: wipe without a prompt or an export offer.
  Future<void> onAccountDeleted() => _journal.wipe();

  /// Relaunch with no valid session for the stored uid, or the user-not-found
  /// response: the account is gone, wipe without a prompt (GPS-PRIV-085).
  Future<void> onAuthFailureAtLaunch() => _journal.wipe();
}
