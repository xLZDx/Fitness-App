/// Extends the account-deletion device wipe with the activity journal (S02
/// design 6.2 and 7, GPS-PRIV-085).
///
/// `DeviceLocalDataWipe` knows nothing about the journal, so deleting the
/// account used to leave every recorded session, the side files and the
/// journal key on the phone. This decorator runs the inner wipe and then the
/// journal wipe (journal, sources, quarantine, key). It is the ONE wipe object
/// behind `localDataWipeProvider`, so the normal deletion path and the
/// kill-after-server-confirmation relaunch path (`finishInterruptedWipe`) both
/// reach it.
library;

import '../../account_deletion/data/local_data_wipe.dart';
import 'activity_journal.dart';
import 'activity_journal_owner.dart';

class ActivityAwareLocalDataWipe implements LocalDataWipe {
  ActivityAwareLocalDataWipe({
    required LocalDataWipe inner,
    required ActivityJournal? journal,
    required ActivityJournalOwnerStore ownerStore,
  })  : _inner = inner,
        _journal = journal,
        _owner = ownerStore;

  final LocalDataWipe _inner;
  final ActivityJournal? _journal;
  final ActivityJournalOwnerStore _owner;

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
        // A recorded owner other than [uid] means the journal holds ANOTHER
        // account's sessions (a pending wipe of an older deletion while a
        // different account is signed in): leave it. No owner recorded: the
        // data is unclaimed and goes with the deletion.
        final owner = await _owner.read();
        if (owner == null || owner == uid) {
          await ActivityWipeCoordinator(journal).onAccountDeleted();
          await _owner.clear();
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
