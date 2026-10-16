/// Presenter of the sync-conflict UI (S02 design 3.2, 6.2; story S02-12).
///
/// Exposes the conflict and candidate entries of the repository state stream
/// (summary fields only: no coordinates, heart rate or place text) and wires
/// the user's choices to the repository exactly once each. The entry list is
/// ONLY ever replaced from the stream, so a conflict disappears after its
/// resolution is stored, never before. There is no delete action.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart' show authUserProvider;
import '../data/summary_projection.dart' show CandidateChoice;
import '../repository/activity_sync_repository.dart';
import '../repository/sync_models.dart';

/// Overridden in `main.dart` with the real repository, like the other
/// feature service providers.
final activitySyncRepositoryProvider = Provider<ActivitySyncRepository>(
  (_) => throw UnimplementedError('activitySyncRepositoryProvider not set'),
);

class SyncConflictViewState {
  const SyncConflictViewState({
    this.sync = ActivitySyncState.empty,
    this.busy = const {},
    this.lastFailed = false,
    this.loaded = false,
    this.loadFailed = false,
  });

  /// The latest state from the repository stream.
  final ActivitySyncState sync;

  /// True once the repository stream has emitted a real state. Until then the
  /// default (empty) [sync] must not be shown as "everything is in sync".
  final bool loaded;

  /// The repository stream reported an error and no newer state arrived since;
  /// the sheet shows an error state with a retry action.
  final bool loadFailed;

  /// Keys of the actions in flight (a second tap on the same one is ignored).
  final Set<String> busy;

  /// The last action could not be stored now (offline); the entry stays.
  final bool lastFailed;

  List<SyncConflict> get conflicts => sync.conflicts;
  List<SyncCandidate> get candidates => sync.candidates;
  bool get hasItems => !sync.isEmpty;

  SyncConflictViewState copyWith({
    ActivitySyncState? sync,
    Set<String>? busy,
    bool? lastFailed,
    bool? loaded,
    bool? loadFailed,
  }) =>
      SyncConflictViewState(
        sync: sync ?? this.sync,
        busy: busy ?? this.busy,
        lastFailed: lastFailed ?? this.lastFailed,
        loaded: loaded ?? this.loaded,
        loadFailed: loadFailed ?? this.loadFailed,
      );
}

/// The signed-in uid the presenter state belongs to (remediation H6). The
/// presenter is `keepAlive`: without this dependency it would carry the
/// previous account's conflicts, busy keys and failure flag across a uid
/// change. Tests override this provider.
final syncConflictUidProvider = Provider<String?>(
  (ref) => ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid)),
);

class SyncConflictPresenter extends Notifier<SyncConflictViewState> {
  StreamSubscription<ActivitySyncState>? _sub;
  bool _disposed = false;

  /// Bumped by every [build]; an action that completes under an older value
  /// belongs to a previous account and must not touch the new state.
  int _generation = 0;

  @override
  SyncConflictViewState build() {
    _disposed = false;
    _generation++;
    ref.watch(activitySyncRepositoryProvider); // rebuild if the repo changes
    // A uid change rebuilds: the first frame of the new account is loading,
    // with no conflicts, no busy keys and no failure flag.
    ref.watch(syncConflictUidProvider);
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _sub = null;
    });
    _subscribe();
    return const SyncConflictViewState();
  }

  void _subscribe() {
    final repo = ref.read(activitySyncRepositoryProvider);
    _sub = repo.watch().listen((s) {
      if (_disposed) return;
      state = state.copyWith(sync: s, loaded: true, loadFailed: false);
    }, onError: (Object _) {
      // A failed read must not leave the sheet in a false "all in sync" state,
      // and must not keep the previous list either: it is cleared.
      if (_disposed) return;
      state = state.copyWith(
          sync: ActivitySyncState.empty, loadFailed: true);
    });
  }

  /// Re-subscribes to the repository stream after a failed load.
  void retry() {
    if (_disposed) return;
    _sub?.cancel();
    _sub = null;
    state = state.copyWith(loaded: false, loadFailed: false);
    _subscribe();
  }

  static String conflictKey(String id) => 'conflict/$id';
  static String candidateKey(String id, String field) => 'candidate/$id/$field';

  Future<void> keepDevice(String id) => _conflict(id, ConflictChoice.keepDevice);

  Future<void> keepCloud(String id) => _conflict(id, ConflictChoice.keepCloud);

  /// The uid is captured at tap time and travels with the operation as
  /// `expectedUid`: a tap made under account A and queued behind a long
  /// operation must not resolve the entry of account B.
  Future<void> resolveCandidate(
    String id,
    String field,
    CandidateChoice choice,
  ) {
    final uid = ref.read(syncConflictUidProvider);
    return _run(
      candidateKey(id, field),
      () => ref.read(activitySyncRepositoryProvider).resolveCandidate(
          id, field, choice,
          expectedUid: uid),
    );
  }

  Future<void> _conflict(String id, ConflictChoice choice) {
    final uid = ref.read(syncConflictUidProvider);
    return _run(
      conflictKey(id),
      () => ref
          .read(activitySyncRepositoryProvider)
          .resolveConflict(id, choice, expectedUid: uid),
    );
  }

  Future<void> _run(String key, Future<SyncOutcome> Function() action) async {
    if (state.busy.contains(key)) return;
    final generation = _generation;
    state = state.copyWith(busy: {...state.busy, key}, lastFailed: false);
    var failed = false;
    try {
      final outcome = await action();
      failed = outcome == SyncOutcome.unavailable;
    } catch (_) {
      failed = true;
    }
    // The account changed (the state was rebuilt) or the presenter was
    // disposed while the action ran: its result is not this state's business.
    if (_disposed || generation != _generation) return;
    state = state.copyWith(
      busy: {...state.busy}..remove(key),
      lastFailed: failed,
    );
  }
}

final syncConflictPresenterProvider =
    NotifierProvider<SyncConflictPresenter, SyncConflictViewState>(
        SyncConflictPresenter.new);
