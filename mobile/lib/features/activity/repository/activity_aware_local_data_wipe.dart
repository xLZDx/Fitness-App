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
import 'activity_journal.dart';
import 'uid_scoped_activity_journal.dart';

class ActivityAwareLocalDataWipe implements LocalDataWipe {
  ActivityAwareLocalDataWipe({
    required LocalDataWipe inner,
    required ActivityJournal? journal,
  })  : _inner = inner,
        _journal = journal;

  final LocalDataWipe _inner;
  final ActivityJournal? _journal;

  /// Name reported in [LocalWipeIncomplete.remaining] when the journal remains.
  static const remainingName = 'activity_journal';

  @override
  Future<void> wipe(String uid) async {
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
        if (journal is AccountScopedJournal) {
          await journal.wipeForUid(uid);
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
