/// State behind the Today, This week and Progress dashboards (S03-13, design
/// 3.1, 3.6, 3.7; RV-3, RV-10, RV-11, RV-16). One read path: the digests
/// notifier calls the bound journal's `list()` once per refresh and turns the
/// entries into [SessionDigest]s. Everything else is derived from it.
///
/// Rules: a completion for another uid or an older generation is discarded; a
/// previous value is reused only for the SAME uid; while the journal is not
/// `open` the notifier stays loading (never empty); errors are caught inside
/// the notifier, so a failed refresh after a success keeps the value and sets
/// `lastLoadFailedAt`. Screens call `refreshIfStale()` from `initState` or
/// `didChangeDependencies`, never from `build`.
library;

import 'dart:async' show Completer, scheduleMicrotask, unawaited;

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/wiring/activity_wiring.dart';
import '../../home/state/home_dashboard_providers.dart' show homeNowProvider;
import '../data/activity_aggregates.dart';
import 'journal_availability.dart';

/// The loaded digests of ONE account. [ownerUid] and [generation] (the bind
/// generation the load ran under) stamp it; a consumer shows it only when
/// [ownerUid] equals the current uid.
@immutable
class DigestSnapshot {
  const DigestSnapshot({
    required this.ownerUid,
    required this.generation,
    required this.loadedAt,
    required this.digests,
    this.lastLoadFailedAt,
    this.unreadableSessions = 0,
    this.recoveredAbsent = 0,
    this.streamLost = 0,
  });

  final String ownerUid;
  final int generation;
  final DateTime loadedAt;

  /// Set when a refresh failed after this value was loaded (RV-11); the value
  /// is kept. Null after a successful load.
  final DateTime? lastLoadFailedAt;

  /// Newest first is NOT guaranteed; use the pure functions to order.
  final List<SessionDigest> digests;

  /// Sessions whose effective summary could not be read. Never "no data".
  final int unreadableSessions;

  /// Activities dropped by the recovery pass (RV-10).
  final int recoveredAbsent;

  /// Activities found `streamLost` by the recovery pass (RV-10).
  final int streamLost;

  /// `recoveredAbsent + streamLost + unreadableSessions`: the count of the
  /// "could not be restored" notice.
  int get notRestoredCount => recoveredAbsent + streamLost + unreadableSessions;

  /// True while totals may be incomplete ("Totals may be incomplete").
  bool get mayBeIncomplete => notRestoredCount > 0;

  DigestSnapshot withLoadFailure(DateTime at) => DigestSnapshot(
        ownerUid: ownerUid,
        generation: generation,
        loadedAt: loadedAt,
        lastLoadFailedAt: at,
        digests: digests,
        unreadableSessions: unreadableSessions,
        recoveredAbsent: recoveredAbsent,
        streamLost: streamLost,
      );
}

/// Counter that every future writer (recorder, import, delete, conflict
/// resolution) increments to request a reload. S03 has no writer: this is the
/// seam. A uid change is a reset, not a bump.
final activityJournalRevisionProvider = StateProvider<int>((_) => 0);

/// The clock of `loadedAt` and the staleness check; tests override it.
final activityDigestClockProvider =
    Provider<DateTime Function()>((_) => DateTime.now);

/// The zone used to assign sessions to local days and weeks; null = the device
/// zone. Tests override it to exercise two offsets.
final activityZoneProvider = Provider<ZoneFn?>((_) => null);

/// A digest value older than this is stale for `refreshIfStale()`.
const Duration kActivityDigestMaxAge = Duration(seconds: 60);

/// Loads and caches the digests of the signed-in account (design 3.1).
class ActivityDigestsNotifier extends AsyncNotifier<DigestSnapshot> {
  int _loadGen = 0;
  bool _inFlight = false;
  bool _dirty = false;
  bool _open = false;
  String? _uid;
  DigestSnapshot? _last;

  @override
  Future<DigestSnapshot> build() {
    final gen = ++_loadGen;
    ref.onDispose(() => _loadGen++);
    _inFlight = false;
    _dirty = false;
    // Rebuild (a synchronous reset to loading) only when the account or the
    // open-ness changes, not on every bind-status change.
    final key = ref.watch(journalAvailabilityProvider
        .select((a) => (a.ownerUid, a is JournalOpen)));
    final uid = key.$1;
    _uid = uid;
    _open = key.$2;
    ref.listen<int>(activityJournalRevisionProvider, (_, __) {
      unawaited(refresh());
    });
    // A value of another account is never reused (DT-13-10).
    if (_last != null && _last!.ownerUid != uid) _last = null;
    if (!_open || uid == null) {
      // binding, gaveUp, failedToOpen, notEnabled: loading, never empty. The
      // UI reads the availability for the other states.
      return Completer<DigestSnapshot>().future;
    }
    return _firstLoad(uid, gen);
  }

  /// Reloads now (pull-to-refresh, Try again, app resume, revision bump).
  /// Coalesced: while a load runs, the request sets a dirty flag and exactly
  /// one more load follows. Never throws.
  Future<void> refresh() async {
    final uid = _uid;
    if (!_open || uid == null) return;
    if (_inFlight) {
      _dirty = true;
      return;
    }
    final gen = _loadGen;
    _inFlight = true;
    try {
      do {
        _dirty = false;
        if (state.hasError) state = const AsyncLoading<DigestSnapshot>();
        try {
          final snap = await _loadKeepingPrior(uid, gen);
          if (snap == null || gen != _loadGen) return;
          state = AsyncData<DigestSnapshot>(snap);
        } catch (e, st) {
          if (gen != _loadGen) return;
          // No earlier value for this uid: the error panel case.
          state = AsyncError<DigestSnapshot>(e, st);
        }
      } while (_dirty && gen == _loadGen);
    } finally {
      if (gen == _loadGen) _inFlight = false;
    }
  }

  /// Refreshes when there is no value, the value failed to refresh, or it is
  /// older than [maxAge]. Call from `initState` or `didChangeDependencies`,
  /// never from `build`.
  void refreshIfStale({Duration maxAge = kActivityDigestMaxAge}) {
    if (!_open || _uid == null || _inFlight) return;
    final last = _last;
    final stale = state.hasError ||
        last == null ||
        last.lastLoadFailedAt != null ||
        _now().difference(last.loadedAt) > maxAge;
    if (stale) unawaited(refresh());
  }

  DateTime _now() => ref.read(activityDigestClockProvider)();

  Future<DigestSnapshot> _firstLoad(String uid, int gen) async {
    _inFlight = true;
    DigestSnapshot? snap;
    try {
      snap = await _loadKeepingPrior(uid, gen);
    } finally {
      if (gen == _loadGen) {
        _inFlight = false;
        if (_dirty) {
          _dirty = false;
          scheduleMicrotask(() => unawaited(refresh()));
        }
      }
    }
    // Discarded (another uid or generation): this build is obsolete, so it
    // never publishes a value.
    if (snap == null) return Completer<DigestSnapshot>().future;
    return snap;
  }

  /// True while this load still belongs to the current uid, generation and an
  /// `open` journal.
  bool _isCurrent(String uid, int gen) {
    if (gen != _loadGen) return false;
    try {
      final a = ref.read(journalAvailabilityProvider);
      return a is JournalOpen && a.ownerUid == uid;
    } catch (_) {
      return false;
    }
  }

  /// A successful snapshot; the prior value of the same uid with
  /// `lastLoadFailedAt` set when the load failed; null when the result is to be
  /// discarded; rethrows when the load failed and there is no prior value.
  Future<DigestSnapshot?> _loadKeepingPrior(String uid, int gen) async {
    try {
      final snap = await _fetch(uid, gen);
      if (snap == null) return null;
      _last = snap;
      return snap;
    } catch (e) {
      // RV-16: fixed message, content-free code, exception type only.
      debugPrint('activity: dashboard load failed (code=list_failed, '
          '${e.runtimeType})');
      if (!_isCurrent(uid, gen)) return null;
      final prior = _last;
      if (prior != null && prior.ownerUid == uid) {
        final kept = prior.withLoadFailure(_now());
        _last = kept;
        return kept;
      }
      rethrow;
    }
  }

  Future<DigestSnapshot?> _fetch(String uid, int gen) async {
    final journal = ref.read(activityJournalProvider);
    if (journal == null) throw StateError('journal missing');
    final entries = await journal.list();
    // Another account or generation took over while list() was pending.
    if (!_isCurrent(uid, gen)) return null;
    final digests = <SessionDigest>[];
    var unreadable = 0;
    for (final e in entries) {
      try {
        final d = buildDigest(
          e.session,
          syncState: e.state.syncState,
          streamLost: e.streamLost,
        );
        if (d != null) digests.add(d);
      } catch (_) {
        // Counted, never shown as "no data" (RV-11).
        unreadable++;
      }
    }
    if (unreadable > 0) {
      debugPrint('activity: dashboard sessions unreadable '
          '(code=digest_unreadable, count=$unreadable)');
    }
    final status = ref.read(activityBindStatusProvider);
    final mine = status.uid == uid;
    return DigestSnapshot(
      ownerUid: uid,
      generation: mine ? status.generation : 0,
      loadedAt: _now(),
      digests: List.unmodifiable(digests),
      unreadableSessions: unreadable,
      recoveredAbsent: mine ? status.recoveredAbsentCount : 0,
      streamLost: mine ? status.streamLostCount : 0,
    );
  }
}

final activityDigestsProvider =
    AsyncNotifierProvider<ActivityDigestsNotifier, DigestSnapshot>(
        ActivityDigestsNotifier.new);

/// The current account's snapshot, or null while the journal is not `open`,
/// nothing is loaded yet, or the loaded value belongs to another account.
final activityDigestSnapshotProvider = Provider<DigestSnapshot?>((ref) {
  final a = ref.watch(journalAvailabilityProvider);
  if (a is! JournalOpen) return null;
  final snap = ref.watch(activityDigestsProvider).valueOrNull;
  if (snap == null || snap.ownerUid != a.ownerUid) return null;
  return snap;
});

/// Sessions that started on the local date of "now" (`homeNowProvider`), newest
/// first. Empty unless the journal is `open` and loaded.
final activityTodayProvider = Provider<List<SessionDigest>>((ref) {
  final snap = ref.watch(activityDigestSnapshotProvider);
  if (snap == null) return const [];
  return todaySessions(snap.digests, ref.watch(homeNowProvider),
      zone: ref.watch(activityZoneProvider));
});

/// The week tiles (Monday week of "now"). Empty unless `open` and loaded.
final activityWeekTilesProvider = Provider<WeekAggregate>((ref) {
  final snap = ref.watch(activityDigestSnapshotProvider);
  if (snap == null) return WeekAggregate.empty;
  return aggregateWeek(snap.digests, ref.watch(homeNowProvider),
      zone: ref.watch(activityZoneProvider));
});

/// The five latest sessions, newest first. Empty unless `open` and loaded.
final activityRecentProvider = Provider<List<SessionDigest>>((ref) {
  final snap = ref.watch(activityDigestSnapshotProvider);
  if (snap == null) return const [];
  return recentSessions(snap.digests);
});
