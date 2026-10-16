/// Which account the device-wide activity journal belongs to (S02 design 6.2,
/// 7 and 17). The journal is not uid-scoped, so without an owner record the
/// sessions of account A would be synced into account B's cloud after a
/// sign-in switch, and a deletion of account B would wipe A's data.
///
/// The marker holds a uid only, never activity data.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'activity_journal.dart';

abstract class ActivityJournalOwnerStore {
  /// The recorded owner uid, or null when none is recorded.
  Future<String?> read();

  Future<void> write(String uid);

  Future<void> clear();
}

class PrefsActivityJournalOwnerStore implements ActivityJournalOwnerStore {
  PrefsActivityJournalOwnerStore({SharedPreferences? prefs})
      : _injected = prefs;

  final SharedPreferences? _injected;

  /// Not a per-uid key (the uid is a value), so the per-account device wipe
  /// does not remove it; the activity wipe clears it after the journal.
  static const key = 'activity.journalOwnerUid';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  @override
  Future<String?> read() async => (await _prefs).getString(key);

  @override
  Future<void> write(String uid) async {
    if (!await (await _prefs).setString(key, uid)) {
      throw StateError('could not record the activity journal owner');
    }
  }

  @override
  Future<void> clear() async {
    await (await _prefs).remove(key);
  }
}

class InMemoryActivityJournalOwnerStore implements ActivityJournalOwnerStore {
  String? _uid;

  @override
  Future<String?> read() async => _uid;

  @override
  Future<void> write(String uid) async => _uid = uid;

  @override
  Future<void> clear() async => _uid = null;
}

/// Makes [uid] the owner of the journal before any cloud sync for [uid] runs.
///
/// - no owner recorded: record [uid], keep the data;
/// - same owner: nothing to do, the data stays;
/// - another owner: wipe the journal (sources, quarantine and key included)
///   first, then record [uid].
///
/// Fail closed: returns false when the owner cannot be read or recorded or the
/// wipe fails; the caller must then NOT start the sync. The owner is recorded
/// only after a successful wipe, so a crash in between repeats the wipe.
Future<bool> claimActivityJournal({
  required ActivityJournal journal,
  required ActivityJournalOwnerStore store,
  required String uid,
}) async {
  try {
    final owner = await store.read();
    if (owner == uid) return true;
    if (owner != null) await journal.wipe();
    await store.write(uid);
    return true;
  } catch (_) {
    return false;
  }
}
