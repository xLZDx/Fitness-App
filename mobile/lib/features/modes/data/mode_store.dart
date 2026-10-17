/// Per-account storage of the mode state (design 5.1-5.3).
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'mode_codec.dart';
import 'mode_models.dart';

/// SharedPreferences key of one account's mode state. It starts with
/// `activity.` and ends with `.<uid>`, the shape the account-deletion wipe
/// already removes (`local_data_wipe.dart`).
String modeStorageKeyFor(String uid) => 'activity.mode.v1.$uid';

abstract class ModeStore {
  /// Three-way read (RV-2). May throw when the platform store fails; the
  /// caller treats that as a load error (default state, no writes).
  Future<ModeRead> read(String uid);

  /// Writes [state] for [uid]. Never throws. Refuses a wiped uid (RV-14).
  Future<ModeWriteResult> write(String uid, ModeState state);

  /// Fail-closed wiped-uid guard (RV-14, the `_wipedUid` idea of
  /// `UidScopedActivityJournal`). After this call every [write] for [uid]
  /// is refused for the rest of the process, and a write that was already in
  /// flight removes its key again when it completes. Call it BEFORE the
  /// account-deletion wipe starts.
  void markUidWiped(String uid);

  /// True when [uid] is being or was wiped in this process.
  bool isUidWiped(String uid);
}

/// [ModeStore] over SharedPreferences. The only place that touches the key.
class PrefsModeStore implements ModeStore {
  PrefsModeStore({Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;
  final Set<String> _wiped = <String>{};

  @override
  void markUidWiped(String uid) {
    if (uid.isNotEmpty) _wiped.add(uid);
  }

  @override
  bool isUidWiped(String uid) => _wiped.contains(uid);

  @override
  Future<ModeRead> read(String uid) async {
    if (uid.isEmpty || _wiped.contains(uid)) return const ModeReadMissing();
    final prefs = await _prefs();
    final Object? raw = prefs.get(modeStorageKeyFor(uid));
    if (raw == null) return const ModeReadMissing();
    // A non-string value under our key is corrupt, not missing.
    if (raw is! String) {
      return const ModeReadUnreadable(UnreadableReason.corrupt);
    }
    return decodeModeState(raw);
  }

  @override
  Future<ModeWriteResult> write(String uid, ModeState state) async {
    if (uid.isEmpty) return ModeWriteResult.refusedInvalidUid;
    if (_wiped.contains(uid)) return ModeWriteResult.refusedWipedUid;
    final key = modeStorageKeyFor(uid);
    try {
      final prefs = await _prefs();
      if (_wiped.contains(uid)) return ModeWriteResult.refusedWipedUid;
      final ok = await prefs.setString(key, encodeModeState(state));
      if (_wiped.contains(uid)) {
        // The account was wiped while this write was in flight: undo it so the
        // deleted account's key is not resurrected.
        await prefs.remove(key);
        return ModeWriteResult.refusedWipedUid;
      }
      return ok ? ModeWriteResult.written : ModeWriteResult.failed;
    } catch (e) {
      debugPrint('mode store: write failed (${e.runtimeType})');
      return ModeWriteResult.failed;
    }
  }
}
