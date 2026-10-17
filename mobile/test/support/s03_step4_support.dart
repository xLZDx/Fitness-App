// Shared test support of S03 step 4 (EP-3 and EP-4): hand-built sessions, a
// fake journal with spies, a fake account-scoped journal with completers, a
// fake timer factory and a Progress/Home/Sources host. Test-only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/activity/state/activity_dashboard_providers.dart';
import 'package:fitness_app/features/activity/state/journal_availability.dart';
import 'package:fitness_app/features/progress/data/progress_stats.dart' show ZoneFn;
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/home/state/home_dashboard_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

import '../helpers/test_app.dart';

/// Fixed "now" of the dashboard tests: Wednesday 2026-10-14 12:00 UTC.
final DateTime kNow = DateTime.utc(2026, 10, 14, 12);

/// Zone used by every dashboard test: UTC (no shift), so day/week maths does not
/// depend on the machine zone.
DateTime utcZone(DateTime utc) => utc;

DateTime minus8Zone(DateTime utc) => utc.subtract(const Duration(hours: 8));

SourceRecord src(String id, SourceKind kind) => SourceRecord(
      sourceId: id,
      sourceKind: kind,
      importedAt: DateTime.utc(2026, 10, 1),
    );

ActivitySession sess(
  String id, {
  SportType sport = SportType.running,
  required DateTime start,
  double? dist,
  double? time,
  List<SourceRecord> prov = const [],
}) =>
    ActivitySession(
      id: id,
      sport: sport,
      startUtc: start,
      endUtc: start.add(const Duration(minutes: 30)),
      movingTimeS: time,
      summary: ActivitySummary(distanceM: dist),
      provenance: prov,
    );

/// A session whose `summary` getter throws, so `SummaryProjection.effective`
/// throws (the unreadable-session case of RV-11).
class BadSession extends ActivitySession {
  BadSession(String id, DateTime start)
      : super(
          id: id,
          sport: SportType.running,
          startUtc: start,
          endUtc: start.add(const Duration(minutes: 1)),
        );

  @override
  ActivitySummary get summary => throw StateError('unreadable');
}

JournalEntry entry(ActivitySession s,
        {JournalSyncState sync = JournalSyncState.pending,
        bool streamLost = false}) =>
    JournalEntry(
      session: s,
      state: JournalState(syncState: sync, streamLost: streamLost),
      generation: 1,
      streamsLoaded: false,
    );

/// A plain (not account-scoped) journal: availability is `open` as soon as the
/// user is signed in.
class FakeJournal extends Fake implements ActivityJournal {
  FakeJournal([List<JournalEntry>? entries]) : entries = entries ?? [];
  List<JournalEntry> entries;
  int listCalls = 0;
  int tombstoneCalls = 0;
  int wipeCalls = 0;
  Object? listError;
  Object? wipeError;
  Object? assessError;
  Completer<List<JournalEntry>>? gate;
  Completer<void>? wipeGate;
  final List<Completer<List<JournalEntry>>> gateQueue = [];

  @override
  Future<List<JournalEntry>> list() async {
    listCalls++;
    if (gateQueue.isNotEmpty) return gateQueue.removeAt(0).future;
    if (gate != null) return gate!.future;
    if (listError != null) throw listError!;
    return List.of(entries);
  }

  @override
  Future<List<JournalEntry>> listTombstones() async {
    tombstoneCalls++;
    return const [];
  }

  @override
  Future<SignOutAssessment> assessSignOut() async {
    if (assessError != null) throw assessError!;
    return SignOutAssessment(
        entryCount: entries.length, unsyncedCount: 0, streamLostCount: 0);
  }

  @override
  Future<void> wipe() async {
    wipeCalls++;
    if (wipeGate != null) await wipeGate!.future;
    if (wipeError != null) throw wipeError!;
    entries = [];
  }

  @override
  int get streamLostCount => 0;
}

/// Account-scoped fake: `bindUid` is driven by completers.
class ScopedFakeJournal extends FakeJournal
    implements AccountScopedJournal, RecoveryReportSource {
  ScopedFakeJournal([super.entries]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);

  final List<String?> bindCalls = [];
  final List<Completer<bool>> pending = [];
  bool autoSucceed = false;
  String? _uid;
  JournalRecoveryReport? report;

  @override
  Future<bool> bindUid(String? uid) {
    bindCalls.add(uid);
    if (autoSucceed) {
      _uid = uid;
      return Future.value(true);
    }
    final c = Completer<bool>();
    pending.add(c);
    return c.future.then((ok) {
      if (ok) _uid = uid;
      return ok;
    });
  }

  /// Completes the oldest pending attempt.
  void complete(bool ok) => pending.removeAt(0).complete(ok);

  @override
  String? get boundUid => _uid;
  @override
  bool get isBound => _uid != null;
  @override
  Future<void> wipeForUid(String uid) async => wipeCalls++;
  @override
  JournalRecoveryReport? get lastRecoveryReport => report;
}

class FakeTimer implements Timer {
  FakeTimer(this.delay, this._cb);
  final Duration delay;
  final void Function() _cb;
  bool _active = true;
  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
  void fire() {
    if (!_active) return;
    _active = false;
    _cb();
  }
}

class FakeTimers {
  final List<FakeTimer> all = [];
  FakeTimer call(Duration d, void Function() cb) {
    final t = FakeTimer(d, cb);
    all.add(t);
    return t;
  }

  int get active => all.where((t) => t.isActive).length;
}

AuthUser user(String uid) =>
    AuthUser(uid: uid, displayName: 'Ivan Test', provider: AuthProvider.google);

/// Overrides that put the dashboards on [journal] for [uid] with a fixed clock.
List<Override> dashOverrides({
  FakeJournal? journal,
  String? uid = 'A',
  StreamController<AuthUser?>? auth,
  FakeTimers? timers,
  bool localJournal = true,
  DateTime? now,
  ZoneFn? zone = utcZone,
  DateTime Function()? clock,
}) =>
    [
      activityFlagsProvider
          .overrideWithValue(ActivityFlags(localJournal: localJournal)),
      if (journal != null) activityJournalProvider.overrideWithValue(journal),
      authUserProvider.overrideWith((ref) => auth != null
          ? auth.stream
          : Stream<AuthUser?>.value(uid == null ? null : user(uid))),
      if (timers != null)
        activityBindRetryTimerFactoryProvider.overrideWithValue(timers.call),
      homeNowProvider.overrideWithValue(now ?? kNow),
      activityZoneProvider.overrideWithValue(zone),
      activityDigestClockProvider.overrideWithValue(clock ?? () => kNow),
    ];


Widget appHost(
  Widget home, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
  GoRouter? router,
}) {
  final r = router ??
      GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => home),
          GoRoute(
              path: '/sources',
              builder: (_, __) => const Scaffold(body: Text('sources-stub'))),
          GoRoute(
              path: '/mode-chooser',
              builder: (_, __) => const Scaffold(body: Text('chooser-stub'))),
        ],
      );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: r,
      builder: (context, child) => Consumer(builder: (context, ref, _) {
        // The app root watches the binding once; the hosts do the same.
        ref.watch(activityJournalBindingProvider);
        // The running app keeps auth and availability alive (shell, dashboards).
        ref.watch(journalAvailabilityProvider);
        return Material(
            type: MaterialType.transparency,
            child: AuroraBackground(child: child ?? const SizedBox.shrink()));
      }),
    ),
  );
}
