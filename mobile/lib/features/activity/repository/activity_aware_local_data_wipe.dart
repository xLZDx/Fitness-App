/// Extends the account-deletion device wipe with the activity journal (S02
/// design 6.2 and 7, GPS-PRIV-085).
///
/// `DeviceLocalDataWipe` knows nothing about the journal, so deleting the
/// account used to leave every recorded session, the side files and the
/// journal key on the phone. This decorator runs the inner wipe and then the
/// journal wipe of the deleted account's scope (journal, sources, quarantine,
/// key). It is the ONE wipe object
/// behind `localDataWipeProvider`, so the normal deletion path and the
/// kill-after-server-confirmation relaunch path (`finishInterruptedWipe`) both
/// reach it.
library;

import '../../account_deletion/data/local_data_wipe.dart';
import '../../recording/journal/pre_unbind_hook.dart';
import 'activity_journal.dart';
import 'uid_scoped_activity_journal.dart';

/// Wipe ordering (S04 design 4.7, S04-30 AC-4):
///  1. the injected [PreUnbindHookRegistry] shuts the recorder down
///     (`UnbindReason.accountDeleted`: shutdown only, no hand-off), bounded and
///     never throwing;
///  2. the inner wipe;
///  3. the journal wipe of the deleted uid's scope, which closes the recording
///     journal first (refuse-after-wipe tombstone) and then empties
///     `recording/`.
/// The registry is the only link to the recorder: the repository layer never
/// imports it. With no registry, or no hook registered in it (for example the
/// relaunch `finishInterruptedWipe` path before any recorder exists), step 1 is
/// skipped and the wipe behaves exactly as before.
class ActivityAwareLocalDataWipe implements LocalDataWipe {
  ActivityAwareLocalDataWipe({
    required LocalDataWipe inner,
    required ActivityJournal? journal,
    PreUnbindHookRegistry? preUnbind,
  })  : _inner = inner,
        _journal = journal,
        _preUnbind = preUnbind;

  final LocalDataWipe _inner;
  final ActivityJournal? _journal;
  final PreUnbindHookRegistry? _preUnbind;

  /// Name reported in [LocalWipeIncomplete.remaining] when the journal remains.
  static const remainingName = 'activity_journal';

  @override
  Future<void> wipe(String uid) async {
    // A shutdown that times out or fails must not block the deletion: the
    // journal wipe below closes the recording journal and removes its files.
    await _preUnbind?.runBounded(uid, UnbindReason.accountDeleted);

    Object? innerError;
    StackTrace? innerStack;
    try {
      await _inner.wipe(uid);
    } catch (e, s) {
      innerError = e;
      innerStack = s;
    }

    var journalLeft = false;
    final journal = _journal;
    if (journal != null) {
      try {
        // Account-scoped journals: wipe exactly the scope of the deleted uid,
        // whoever is bound now, and never another uid's scope (a relaunch with
        // a pending wipe while a different account is bound is safe). A plain
        // journal (not account-scoped) is wiped as a whole.
        if (journal case final AccountScopedJournal scoped) {
          await scoped.wipeForUid(uid);
        } else {
          await ActivityWipeCoordinator(journal).onAccountDeleted();
        }
      } catch (_) {
        journalLeft = true;
      }
    }

    if (innerError == null && !journalLeft) return;
    if (innerError is! LocalWipeIncomplete && innerError != null) {
      Error.throwWithStackTrace(innerError, innerStack!);
    }
    throw LocalWipeIncomplete([
      if (innerError is LocalWipeIncomplete) ...innerError.remaining,
      if (journalLeft) remainingName,
    ]);
  }
}
