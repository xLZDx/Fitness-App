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

class SyncConflictPresenter extends Notifier<SyncConflictViewState> {
  StreamSubscription<ActivitySyncState>? _sub;
  bool _disposed = false;

  @override
  SyncConflictViewState build() {
    _disposed = false;
    ref.watch(activitySyncRepositoryProvider); // rebuild if the repo changes
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
      // A failed read must not leave the sheet in a false "all in sync" state.
      if (_disposed) return;
      state = state.copyWith(loadFailed: true);
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

  Future<void> resolveCandidate(
    String id,
    String field,
    CandidateChoice choice,
  ) =>
      _run(
        candidateKey(id, field),
        () => ref
            .read(activitySyncRepositoryProvider)
            .resolveCandidate(id, field, choice),
      );

  Future<void> _conflict(String id, ConflictChoice choice) => _run(
        conflictKey(id),
        () => ref.read(activitySyncRepositoryProvider).resolveConflict(id, choice),
      );

  Future<void> _run(String key, Future<SyncOutcome> Function() action) async {
    if (state.busy.contains(key)) return;
    state = state.copyWith(busy: {...state.busy, key}, lastFailed: false);
    var failed = false;
    try {
      final outcome = await action();
      failed = outcome == SyncOutcome.unavailable;
    } catch (_) {
      failed = true;
    }
    state = state.copyWith(
      busy: {...state.busy}..remove(key),
      lastFailed: failed,
    );
  }
}

final syncConflictPresenterProvider =
    NotifierProvider<SyncConflictPresenter, SyncConflictViewState>(
        SyncConflictPresenter.new);
