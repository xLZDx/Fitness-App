import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import '../../auth/state/auth_providers.dart';
import '../data/mode_models.dart';
import '../data/mode_store.dart';
import 'mode_flags.dart';
import 'mode_migration.dart';

// R-M1: nothing in this file (or any timer provider) watches the other side.
// The mode state never imports a timer provider and no timer provider watches
// the mode state.

/// Flags for the new modes (design 4.2, 4.3). Tests override this provider.
final modeFlagsProvider = Provider<ModeFlags>((_) => ModeFlags.compileTime);

/// The store. Tests override it with a fake.
final modeStoreProvider = Provider<ModeStore>((_) => PrefsModeStore());

/// Wiped-uid guard feed (RV-14). `accountBeingDeletedUidProvider` is set
/// BEFORE the pending-wipe marker and the wipe, while auth still reports the
/// uid, so this marks the uid on the store synchronously before the wipe starts.
/// Not covered: the interrupted-wipe relaunch path. There the wipe finishes
/// before or without any signed-in session for the deleted uid, so no signed-in
/// writer for that uid exists to be refused.
///
/// Kept apart from [modeStoreProvider] so that it also guards a store that a
/// test overrides. The notifier watches it.
final modeWipeGuardProvider = Provider<void>((ref) {
  final store = ref.watch(modeStoreProvider);
  ref.listen<String?>(accountBeingDeletedUidProvider, (_, next) {
    if (next != null) store.markUidWiped(next);
  }, fireImmediately: true);
});

/// Who asks for the first chooser status (design 2.2, RV-1).
enum InitSource { migration, onboarding }

/// Result of a mode mutation.
enum ModeSaveResult {
  /// Applied and persisted.
  saved,

  /// Nothing to do (same mode, status already set, init refused because the
  /// stored value is unreadable). No write, no event.
  unchanged,

  /// The mode is not available in this build.
  unavailable,

  /// Not persisted: write failed or threw, uid changed (account switch), uid
  /// wiped, or the run is read-only (newer stored version or load failure). The
  /// in-memory state may still have changed for the session, except for a uid
  /// mismatch or wiped uid, which change nothing.
  saveFailed,

  /// State not loaded for a signed-in account (loading or signed out).
  notReady,
}

/// One real mode change.
class ModeChanged {
  const ModeChanged(this.from, this.to);
  final AppMode from;
  final AppMode to;
}

/// Broadcast bus behind [modeChangedProvider].
final modeChangeBusProvider = Provider<StreamController<ModeChanged>>((ref) {
  final c = StreamController<ModeChanged>.broadcast();
  ref.onDispose(c.close);
  return c;
});

/// One event per real mode change; nothing for selecting the current mode.
final modeChangedProvider = StreamProvider<ModeChanged>(
    (ref) => ref.watch(modeChangeBusProvider).stream);

/// The signed-in account's mode state. App-scoped (not auto-dispose) and
/// rebuilt when the auth user changes.
final modeStateProvider =
    AsyncNotifierProvider<ModeNotifier, ModeState>(ModeNotifier.new);

/// The selected mode, or null while the state is (re)loading (an account
/// switch keeps the previous value during the reload; it must not be shown).
final selectedModeProvider = Provider<AppMode?>((ref) {
  final async = ref.watch(modeStateProvider);
  return async.isLoading ? null : async.valueOrNull?.selectedMode;
});

void _log(String code, [Object? error]) {
  // Fixed message, content-free reason code, exception type only.
  debugPrint(
      'mode state: $code${error == null ? '' : ' (${error.runtimeType})'}');
}

class ModeNotifier extends AsyncNotifier<ModeState> {
  /// The uid the current state was loaded for. Cleared at the start of every
  /// rebuild (Riverpod keeps the previous value while an account switch loads).
  String? _uid;
  int _gen = 0;

  /// Newer stored version or a failed load: user choices stay in memory and
  /// are never written for the whole run (RV-2).
  bool _readOnly = false;

  /// The stored value was unreadable or the load failed: [initIfAbsent]
  /// refuses (RV-2).
  bool _unreadable = false;

  /// The last write for this uid failed (or was refused as read-only), so the
  /// in-memory state may be ahead of the disk. While set, an identical call is
  /// NOT `unchanged`: it persists again and reports the truthful result
  /// ("Try again" after a failed save). Cleared by a successful write and
  /// reset on every rebuild (uid change).
  bool _persistFailed = false;

  /// The stored mode that was unavailable (flag rolled back) and is shown as
  /// train in memory only. Written back unchanged until the user selects a
  /// mode (null after that and after every rebuild).
  AppMode? _rawStoredMode;

  Map<AppMode, ModeAvailability> _table = kDefaultModeAvailability;

  ModeState get _current => state.valueOrNull ?? ModeState.initial();

  @override
  Future<ModeState> build() async {
    final gen = ++_gen;
    _uid = null;
    _readOnly = false;
    _unreadable = false;
    _persistFailed = false;
    _rawStoredMode = null;
    ref.watch(modeWipeGuardProvider);
    _table = ref.watch(modeFlagsProvider).availabilityTable;
    final store = ref.watch(modeStoreProvider);
    String? uid;
    try {
      final user = await ref.watch(authUserProvider.future);
      if (user == null) return ModeState.initial();
      uid = user.uid;
      if (store.isUidWiped(uid)) {
        _log('wiped-uid');
        return ModeState.initial();
      }
      final read = await store.read(uid);
      if (gen != _gen) return ModeState.initial();
      if (read is ModeReadValue) {
        _uid = uid;
        final stored = read.state;
        // A stored-but-unavailable mode (a flag rolled back) is coerced to
        // train in memory only and is not rewritten.
        if (_isAvailable(stored.selectedMode)) return stored;
        _rawStoredMode = stored.selectedMode;
        return stored.copyWith(selectedMode: AppMode.train);
      }
      if (read is ModeReadUnreadable) {
        _uid = uid;
        _unreadable = true;
        _readOnly = read.reason == UnreadableReason.newerVersion;
        _log('unreadable ${read.reason.name}');
        return ModeState.initial();
      }
      _uid = uid; // missing
      return ModeState.initial();
    } catch (e) {
      // RV-2: a failed load gives the default state, no chooser, no writes.
      _log('load failed', e);
      if (gen == _gen && uid != null) {
        _uid = uid;
        _unreadable = true;
        _readOnly = true;
      }
      return ModeState.initial();
    }
  }

  bool _isAvailable(AppMode m) =>
      availabilityOfMode(m, table: _table) == ModeAvailability.available;

  /// Null when a write for the loaded uid is allowed, otherwise the result to
  /// return. Same guard as `TrainingContextNotifier.select`.
  ModeSaveResult? _refusal() {
    final uid = _uid;
    if (uid == null) return ModeSaveResult.notReady;
    try {
      final current = ref.read(authUserProvider).valueOrNull?.uid;
      if (current == null || current != uid) return ModeSaveResult.saveFailed;
      if (ref.read(modeStoreProvider).isUidWiped(uid)) {
        return ModeSaveResult.saveFailed;
      }
    } on Error catch (e) {
      // A stale ref after an account switch (debug AssertionError / StateError):
      // the write belongs to a previous account, so it changes nothing.
      _log('refusal on stale ref', e);
      return ModeSaveResult.saveFailed;
    }
    return null;
  }

  void _emit(AppMode from, AppMode to) {
    final bus = ref.read(modeChangeBusProvider);
    if (!bus.isClosed) bus.add(ModeChanged(from, to));
  }

  Future<ModeSaveResult> _write(int gen, String uid, ModeState next) async {
    if (_readOnly) {
      _persistFailed = true;
      return ModeSaveResult.saveFailed;
    }
    ModeSaveResult result;
    try {
      // Keep the raw stored mode on disk unless the user selected one.
      final raw = _rawStoredMode;
      final toWrite = (raw != null && next.selectedMode == AppMode.train)
          ? next.copyWith(selectedMode: raw)
          : next;
      final r = await ref.read(modeStoreProvider).write(uid, toWrite);
      result = r == ModeWriteResult.written
          ? ModeSaveResult.saved
          : ModeSaveResult.saveFailed;
    } catch (e) {
      _log('write failed', e);
      result = ModeSaveResult.saveFailed;
    }
    // A result for a previous account must not touch the new account's flag.
    if (gen == _gen) _persistFailed = result != ModeSaveResult.saved;
    return result;
  }

  /// Selects [mode]. State changes first, then the awaited write; a failed
  /// write keeps the mode for the session and returns saveFailed.
  Future<ModeSaveResult> selectMode(AppMode mode) async {
    if (!_isAvailable(mode)) return ModeSaveResult.unavailable;
    final refusal = _refusal();
    if (refusal != null) return refusal;
    final cur = _current;
    if (cur.selectedMode == mode) {
      // Same mode: no event. Persist again only after a failed save.
      return _persistFailed
          ? _write(_gen, _uid!, cur)
          : ModeSaveResult.unchanged;
    }
    _rawStoredMode = null; // an explicit choice replaces the stored value
    final next = cur.copyWith(selectedMode: mode);
    state = AsyncData(next);
    _emit(cur.selectedMode, mode);
    return _write(_gen, _uid!, next);
  }

  /// Chooser Continue: sets the mode and `resolved`. On a write failure the
  /// mode stays in memory and the chooser status stays as it was (AC-CH-6).
  Future<ModeSaveResult> resolveChooser(AppMode mode) async {
    if (!_isAvailable(mode)) return ModeSaveResult.unavailable;
    final refusal = _refusal();
    if (refusal != null) return refusal;
    final cur = _current;
    final changed = cur.selectedMode != mode;
    if (!changed &&
        cur.chooserStatus == ChooserStatus.resolved &&
        !_persistFailed) {
      return ModeSaveResult.unchanged;
    }
    final gen = _gen;
    final uid = _uid!;
    _rawStoredMode = null; // an explicit choice replaces the stored value
    final inMemory = cur.copyWith(selectedMode: mode);
    if (changed) {
      state = AsyncData(inMemory);
      _emit(cur.selectedMode, mode);
    }
    final next = inMemory.copyWith(chooserStatus: ChooserStatus.resolved);
    final result = await _write(gen, uid, next);
    if (result == ModeSaveResult.saved && gen == _gen && _uid == uid) {
      state = AsyncData(_current.copyWith(chooserStatus: ChooserStatus.resolved));
    }
    return result;
  }

  /// "Decide later": train and `resolved` (AC-CH-4).
  Future<ModeSaveResult> decideLater() => resolveChooser(AppMode.train);

  /// Intro card "Not now" / "Choose a mode": `pending` or `migrated` becomes
  /// `resolved`. Anything else is a no-op.
  Future<ModeSaveResult> markResolved() async {
    final refusal = _refusal();
    if (refusal != null) return refusal;
    final cur = _current;
    if (cur.chooserStatus == ChooserStatus.resolved && _persistFailed) {
      return _write(_gen, _uid!, cur); // retry after a failed save
    }
    if (cur.chooserStatus != ChooserStatus.pending &&
        cur.chooserStatus != ChooserStatus.migrated) {
      return ModeSaveResult.unchanged;
    }
    final next = cur.copyWith(chooserStatus: ChooserStatus.resolved);
    state = AsyncData(next);
    return _write(_gen, _uid!, next);
  }

  /// Stores a real answer for [mode]. Validates the mode; an answer that is
  /// not [ModeAnswerKind.answered] is a no-op (use [skipQuestion]).
  Future<ModeSaveResult> answerQuestion(AppMode mode, ModeAnswer answer) =>
      _setAnswer(mode, answer.isAnswered ? answer : null);

  /// Marks the question of [mode] as skipped.
  Future<ModeSaveResult> skipQuestion(AppMode mode) =>
      _setAnswer(mode, ModeAnswer.skipped);

  Future<ModeSaveResult> _setAnswer(AppMode mode, ModeAnswer? answer) async {
    if (!_isAvailable(mode)) return ModeSaveResult.unavailable;
    final refusal = _refusal();
    if (refusal != null) return refusal;
    if (answer == null) return ModeSaveResult.unchanged;
    final cur = _current;
    if (cur.answerFor(mode) == answer) {
      // Identical value in memory: persist again only after a failed save.
      return _persistFailed
          ? _write(_gen, _uid!, cur)
          : ModeSaveResult.unchanged;
    }
    final next = cur.withAnswer(mode, answer);
    state = AsyncData(next);
    return _write(_gen, _uid!, next);
  }

  /// The ONLY writer of the first chooser status (RV-1). Atomic: the check and
  /// the in-memory set happen in one synchronous step, so whichever source
  /// arrives second finds the status set and does nothing. Acts only when the
  /// store read was `missing` (never on an unreadable value or a failed load)
  /// and refuses a wiped uid. [forUid], when given, must equal the uid the
  /// state was loaded for.
  Future<ModeSaveResult> initIfAbsent(InitSource source,
      {String? forUid}) async {
    final refusal = _refusal();
    if (refusal != null) return refusal;
    if (forUid != null && forUid != _uid) return ModeSaveResult.saveFailed;
    final cur = _current;
    if (_unreadable || cur.chooserStatus != ChooserStatus.absent) {
      return ModeSaveResult.unchanged;
    }
    final next = cur.copyWith(
      chooserStatus: source == InitSource.migration
          ? ChooserStatus.migrated
          : ChooserStatus.pending,
    );
    state = AsyncData(next); // claims the slot before the first await
    return _write(_gen, _uid!, next);
  }
}

/// The single provider `FitnessApp.build` watches (RV-18a). It starts the mode
/// state and the migration and never throws. It listens (does not watch) the
/// mode state, so the app root is not rebuilt on each mode choice.
final modeWarmUpProvider = Provider<void>((ref) {
  try {
    ref.listen<AsyncValue<ModeState>>(modeStateProvider, (_, __) {});
    ref.watch(modeMigrationProvider);
  } catch (e) {
    _log('warm-up failed', e);
  }
});
