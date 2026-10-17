// S03-0 (EP-0) design tests DT-0-1 to DT-0-5 and DT-0-9 to DT-0-16: the local
// journal opens in the default build and the bind retry state machine behind
// `journalAvailabilityProvider`. Oracle: docs/phase2/s03/S03_TEST_PLAN.md
// section 2.1 and S03_DESIGN.md 2.1 / 4. DT-0-6 to DT-0-8 live in
// test/android/backup_rules_test.dart and
// test/features/activity/repository/backup_exclusion_test.dart.
//
// Fakes: ControlledJournal (completer-driven bindUid), FakeBindTimers (virtual
// clock behind activityBindRetryTimerFactoryProvider). No real waiting except
// DT-0-1 / DT-0-10 which use the real scoped journal on a temp directory.
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/activity/state/journal_availability.dart';
import 'package:fitness_app/features/activity/state/sync_conflict_presenter.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../support/bind_fakes.dart';
import '../../support/scoped_journal_world.dart';

const _local = ActivityFlags(localJournal: true);
const _both = ActivityFlags(localJournal: true, cloudSync: true);

AuthUser _user(String uid) =>
    AuthUser(uid: uid, displayName: 'n', provider: AuthProvider.google);

class _SyncSpy extends Fake implements ActivitySyncRepository {
  int changes = 0;
  @override
  void onJournalBindingChanged() => changes++;
}

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.dir);
  final String dir;
  int calls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    return dir;
  }
}

/// A journal that counts `bindUid` calls and delegates to the real scoped one.
class _SpyScoped extends UidScopedActivityJournal {
  _SpyScoped(ActivityJournalFactory factory) : super(factory: factory);
  int bindCalls = 0;

  @override
  Future<bool> bindUid(String? uid) {
    bindCalls++;
    return super.bindUid(uid);
  }
}

void main() {
  late FakeBindTimers timers;
  late StreamController<AuthUser?> auth;
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  setUp(() {
    timers = FakeBindTimers();
    auth = StreamController<AuthUser?>();
    logs = [];
    savedDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });

  tearDown(() {
    debugPrint = savedDebugPrint;
    unawaited(auth.close());
  });

  ProviderContainer make({
    ActivityFlags? flags = _local,
    ActivityJournal? journal,
    List<Override> extra = const [],
    StreamController<AuthUser?>? authCtl,
  }) {
    final a = authCtl ?? auth;
    final c = ProviderContainer(overrides: [
      if (flags != null) activityFlagsProvider.overrideWithValue(flags),
      if (journal != null) activityJournalProvider.overrideWithValue(journal),
      authUserProvider.overrideWith((ref) => a.stream),
      activityBindRetryTimerFactoryProvider.overrideWithValue(timers.call),
      ...extra,
    ]);
    addTearDown(c.dispose);
    c.read(activityJournalBindingProvider);
    return c;
  }

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await pumpEventQueue();
  }

  JournalAvailability avail(ProviderContainer c) =>
      c.read(journalAvailabilityProvider);
  ActivityBindStatus status(ProviderContainer c) =>
      c.read(activityBindStatusProvider);
  Future<RetryResult> retry(ProviderContainer c) =>
      c.read(activityBindStatusProvider.notifier).retryNow();

  Future<void> driveToGaveUp(ProviderContainer c) async {
    await emit(_user('A'));
    for (final d in kActivityBindRetryDelays) {
      await timers.advance(d);
    }
  }

  test('DT-0-1 default build: availability binding before the bind, open '
      'after it; bindUid called once; construction does no I/O', () async {
    final world = await ScopedJournalWorld.create();
    addTearDown(world.dispose);
    final spy = _SpyScoped(world.factory);
    // No flag override: the compile-time default of a test build.
    final c = make(flags: null, journal: spy);
    expect(ActivityFlags.compileTime.journalEnabled, isTrue,
        reason: 'the default build must have the local journal on');
    expect(ActivityFlags.compileTime.cloudSync, isFalse);
    expect(avail(c), isA<JournalBinding>());
    expect(spy.bindCalls, 0);
    expect(world.opened, isEmpty, reason: 'construction does no I/O');
    expect(world.tmp.listSync(), isEmpty);

    final gate = Completer<void>();
    world.gate = gate;
    await emit(_user('U1'));
    expect(avail(c), isA<JournalBinding>(), reason: 'bind in flight');
    expect(spy.bindCalls, 1);
    gate.complete();
    for (var i = 0; i < 200 && avail(c) is! JournalOpen; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(avail(c), isA<JournalOpen>(), reason: 'logs: $logs');
    expect(spy.bindCalls, 1, reason: 'exactly one bindUid');
    expect(world.opened, [activityJournalScopeId('U1')]);
  });

  test('DT-0-2 the local journal switches on no cloud piece; the cloud flag '
      'alone does', () async {
    // Scope 1: flag off (local only).
    final j1 = ControlledJournal();
    final c1 = make(flags: _local, journal: j1, extra: [
      activityCloudSettingsClientProvider
          .overrideWith((ref) => throw StateError('settings client built')),
    ]);
    await emit(_user('A'));
    expect(avail(c1), isA<JournalOpen>());
    expect(c1.read(activityStreamUploaderProvider), isNull);
    expect(c1.read(activityConsentWithdrawalProvider), isNull);
    expect(() => c1.read(activitySyncRepositoryProvider), throwsA(anything),
        reason: 'no sync repository is built with the cloud flag off');
    expect(activityRootOverrides(flags: _local, journal: j1), hasLength(1));

    // Scope 2: flag on (second ProviderScope in sequence).
    final auth2 = StreamController<AuthUser?>();
    addTearDown(() => unawaited(auth2.close()));
    final j2 = ControlledJournal();
    final c2 = make(flags: _both, journal: j2, authCtl: auth2, extra: [
      activityCloudSettingsClientProvider
          .overrideWith((ref) => throw StateError('unused')),
      activitySyncRepositoryProvider.overrideWithValue(_SyncSpy()),
    ]);
    auth2.add(_user('B'));
    await pumpEventQueue();
    expect(avail(c2), isA<JournalOpen>());
    expect(activityRootOverrides(flags: _both, journal: j2), hasLength(2),
        reason: 'with the cloud flag the sync repository is overridden too');
  });

  test('DT-0-3a journal flag on but no journal provided: failedToOpen, no '
      'timer, no crash', () async {
    final c = make(flags: _local, journal: null);
    await emit(_user('A'));
    expect(avail(c), isA<JournalFailedToOpen>());
    expect(timers.all, isEmpty);
    expect(status(c).phase, BindPhase.none);
  });

  test('DT-0-3b a recovery failure inside bindUid is binding with ONE armed '
      'retry (not failedToOpen); log has the type only', () async {
    const secret = 'secret-path-/data/user/0/uid-sentinel-9';
    final journal = UidScopedActivityJournal(
        factory: (_) async => throw StateError(secret));
    final c = make(flags: _local, journal: journal);
    await emit(_user('uid-sentinel-9'));
    expect(avail(c), isA<JournalBinding>());
    expect(timers.all, hasLength(1));
    expect(timers.last.delay, const Duration(seconds: 5));
    expect(logs.any((l) => l.contains('StateError')), isTrue,
        reason: 'positive control: the failure is logged with its type');
    for (final l in logs) {
      expect(l.contains(secret), isFalse, reason: 'leak: $l');
      expect(l.contains('uid-sentinel-9'), isFalse, reason: 'uid leak: $l');
      expect(l.contains('secret-path'), isFalse, reason: 'path leak: $l');
    }
  });

  test('DT-0-4 the override wins; the default build is open; flag on with no '
      'journal is failedToOpen (never notEnabled)', () async {
    // Override scope.
    final c1 = ProviderContainer(overrides: [
      journalAvailabilityProvider.overrideWithValue(const JournalNotEnabled()),
    ]);
    addTearDown(c1.dispose);
    expect(c1.read(journalAvailabilityProvider), isA<JournalNotEnabled>());

    // Default scope (no flag override): never notEnabled.
    final j = ControlledJournal();
    final c2 = make(flags: null, journal: j);
    await emit(_user('A'));
    expect(avail(c2), isA<JournalOpen>(),
        reason: 'the default build must not satisfy a notEnabled test');

    // Flag enabled, journal provider null.
    final a3 = StreamController<AuthUser?>();
    addTearDown(() => unawaited(a3.close()));
    final c3 = make(flags: _local, journal: null, authCtl: a3);
    a3.add(_user('A'));
    await pumpEventQueue();
    final v = avail(c3);
    expect(v, isA<JournalFailedToOpen>());
    expect(v, isNot(isA<JournalNotEnabled>()));
    expect(v, isNot(isA<JournalOpen>()));
  });

  test('DT-0-5 failedToOpen: retryNow is notApplicable, no bind, no timer',
      () async {
    final c = make(flags: _local, journal: null);
    await emit(_user('A'));
    expect(await retry(c), RetryResult.notApplicable);
    expect(await retry(c), RetryResult.notApplicable);
    await timers.advance(const Duration(minutes: 10));
    expect(await retry(c), RetryResult.notApplicable);
    expect(timers.all, isEmpty);
    expect(avail(c), isA<JournalFailedToOpen>());
    expect(status(c).bindBusy, isFalse);
  });

  test('DT-0-9 recovery counts reach the bind status after a successful bind; '
      'a journal without RecoveryReportSource yields zeros', () async {
    final j = ControlledJournal()
      ..report = (JournalRecoveryReport()
        ..absent.addAll(['a1', 'a2'])
        ..streamLost.add('s1'))
      ..script.add(false);
    final c = make(journal: j);
    await emit(_user('A'));
    expect(status(c).phase, BindPhase.binding);
    expect(status(c).uid, 'A');
    expect(status(c).recoveredAbsentCount, 0);
    expect(await retry(c), RetryResult.started);
    await pumpEventQueue();
    expect(j.calls, ['A', 'A'], reason: 'retryNow runs exactly one attempt');
    expect(status(c).phase, BindPhase.bound);
    expect(status(c).recoveredAbsentCount, 2);
    expect(status(c).streamLostCount, 1);

    // Counts survive a gave-up schedule followed by a manual success.
    final a2 = StreamController<AuthUser?>();
    addTearDown(() => unawaited(a2.close()));
    final j2 = ControlledJournal()
      ..report = (JournalRecoveryReport()..absent.add('x'))
      ..script.addAll(List<Object>.filled(6, false));
    final c2 = make(journal: j2, authCtl: a2);
    a2.add(_user('B'));
    await pumpEventQueue();
    for (final d in kActivityBindRetryDelays) {
      await timers.advance(d);
    }
    expect(status(c2).phase, BindPhase.gaveUp);
    expect(await retry(c2), RetryResult.started);
    await pumpEventQueue();
    expect(status(c2).phase, BindPhase.bound);
    expect(status(c2).recoveredAbsentCount, 1);

    // Second fake: only the three bind members, counts are zero.
    final a3 = StreamController<AuthUser?>();
    addTearDown(() => unawaited(a3.close()));
    final m = MinimalJournal();
    final c3 = make(journal: m, authCtl: a3);
    a3.add(_user('C'));
    await pumpEventQueue();
    expect(m.calls, ['C']);
    expect(status(c3).phase, BindPhase.bound);
    expect(status(c3).recoveredAbsentCount, 0);
    expect(status(c3).streamLostCount, 0);
  });

  test('DT-0-10 no file or directory I/O before the bind; availability is '
      'binding', () async {
    final tmp = Directory.systemTemp.createTempSync('s03_dt010_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final saved = PathProviderPlatform.instance;
    final paths = _Paths(tmp.path);
    PathProviderPlatform.instance = paths;
    addTearDown(() => PathProviderPlatform.instance = saved);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    final journal = await openActivityJournal(flags: _local);
    expect(journal, isNotNull);
    final c = make(flags: _local, journal: journal);
    await emit(null);
    await pumpEventQueue();
    expect(paths.calls, 0, reason: 'no path lookup before the bind');
    expect(tmp.listSync(), isEmpty);
    expect(avail(c), isA<JournalBinding>());

    // Positive control: the spy sees a lookup once an account binds.
    await emit(_user('A'));
    for (var i = 0; i < 100 && paths.calls == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(paths.calls, greaterThan(0), reason: 'the spy can observe I/O');
  });

  test('DT-0-11 a failed manual attempt keeps the automatic deadline and '
      'advances the index by one', () async {
    final j = ControlledJournal()..script.addAll([false, false, false]);
    final c = make(journal: j);
    await emit(_user('A'));
    expect(timers.all, hasLength(1));
    expect(timers.last.delay, const Duration(seconds: 5));
    final first = timers.last;
    await timers.advance(const Duration(seconds: 2));
    expect(await retry(c), RetryResult.started);
    await pumpEventQueue();
    expect(j.calls, ['A', 'A']);
    expect(avail(c), isA<JournalBinding>());
    expect(first.isActive, isTrue, reason: 'deadline untouched');
    expect(timers.all, hasLength(1));
    await timers.advance(const Duration(seconds: 3));
    expect(j.calls, hasLength(3), reason: 'automatic attempt at the ORIGINAL '
        'deadline (5 s), not at 2 s + 5 s');
    expect(timers.all, hasLength(2));
    expect(timers.last.delay, const Duration(seconds: 15),
        reason: 'index advanced by one, not two');
  });

  test('DT-0-12 a success cancels the timer and resets the index', () async {
    final j = ControlledJournal()..script.addAll([false, true]);
    final c = make(journal: j);
    await emit(_user('A'));
    expect(timers.active, 1);
    expect(await retry(c), RetryResult.started);
    await pumpEventQueue();
    expect(timers.active, 0);
    expect(avail(c), isA<JournalOpen>());
    await timers.advance(const Duration(minutes: 10));
    expect(j.calls, hasLength(2), reason: 'no stale rebind');
    j.script.add(false);
    await emit(_user('B'));
    expect(timers.last.delay, const Duration(seconds: 5),
        reason: 'index was reset');
    expect(timers.active, 1);
  });

  test('DT-0-13 gave up: no automatic loop, one tap one attempt, manual '
      'failure keeps gaveUp and arms nothing', () async {
    final j = ControlledJournal()..script.addAll(List<Object>.filled(6, false));
    final c = make(journal: j);
    await driveToGaveUp(c);
    expect(j.calls, hasLength(6));
    expect(avail(c), isA<JournalGaveUp>());
    expect(timers.all, hasLength(5));
    await timers.advance(const Duration(hours: 24));
    expect(j.calls, hasLength(6), reason: 'no automatic attempt after giving up');

    final hold1 = Completer<bool>();
    j.script.add(hold1);
    expect(await retry(c), RetryResult.started);
    expect(avail(c), isA<JournalGaveUp>(), reason: 'panel stays while pending');
    expect(status(c).bindBusy, isTrue);
    expect(j.calls, hasLength(7));
    hold1.complete(false);
    await pumpEventQueue();
    expect(avail(c), isA<JournalGaveUp>());
    expect(status(c).bindBusy, isFalse);
    expect(timers.active, 0, reason: 'a manual failure starts no timer');
    expect(timers.all, hasLength(5));

    final hold2 = Completer<bool>();
    j.script.add(hold2);
    expect(await retry(c), RetryResult.started);
    expect(await retry(c), RetryResult.busy, reason: 'double tap is one attempt');
    expect(j.calls, hasLength(8));
    hold2.complete(true);
    await pumpEventQueue();
    expect(avail(c), isA<JournalOpen>());
  });

  test('DT-0-14 a due automatic timer during a manual attempt re-arms with the '
      'SAME index; never two bindUid in flight', () async {
    final j = ControlledJournal()..script.add(false);
    final c = make(journal: j);
    await emit(_user('A'));
    final hold = Completer<bool>();
    j.script.add(hold);
    expect(await retry(c), RetryResult.started);
    await timers.advance(const Duration(seconds: 5));
    expect(j.calls, hasLength(2), reason: 'the due timer started nothing');
    expect(timers.all, hasLength(2));
    expect(timers.last.delay, const Duration(seconds: 5),
        reason: 'same index, same delay');
    expect(timers.active, 1);
    j.script.add(false);
    hold.complete(false);
    await pumpEventQueue();
    await timers.advance(const Duration(seconds: 5));
    expect(j.calls, hasLength(3), reason: 'exactly one automatic attempt');
    expect(j.maxInFlight, 1);
    expect(timers.last.delay, const Duration(seconds: 15),
        reason: 'index consumed once, not twice');
  });

  Future<void> dt015({required bool aSucceeds}) async {
    final a = StreamController<AuthUser?>();
    addTearDown(() => unawaited(a.close()));
    final spy = _SyncSpy();
    final j = ControlledJournal();
    final cA = Completer<bool>();
    final cB = Completer<bool>();
    j.script.addAll([false, cA, cB]);
    final c = make(flags: _both, journal: j, authCtl: a, extra: [
      activitySyncRepositoryProvider.overrideWithValue(spy),
    ]);
    a.add(_user('A'));
    await pumpEventQueue();
    expect(spy.changes, 1);
    expect(await retry(c), RetryResult.started);
    a.add(_user('B'));
    await pumpEventQueue();
    expect(j.calls, ['A', 'A', 'B'], reason: 'B starts at once');
    expect(status(c).uid, 'B');
    expect(status(c).bindBusy, isTrue);

    cA.complete(aSucceeds);
    await pumpEventQueue();
    expect(status(c).uid, 'B');
    expect(status(c).phase, BindPhase.binding);
    expect(status(c).bindBusy, isTrue, reason: 'A completion must not clear B busy');
    expect(timers.active, 0, reason: 'A must not arm a timer for B');
    expect(spy.changes, 2, reason: 'publish once per completion, A included');

    cB.complete(false);
    await pumpEventQueue();
    expect(status(c).bindBusy, isFalse);
    expect(timers.active, 1);
    expect(timers.last.delay, const Duration(seconds: 5));
    expect(spy.changes, 3);
  }

  test('DT-0-15a stale success of the old generation changes nothing for the '
      'new account', () => dt015(aSucceeds: true));
  test('DT-0-15b stale failure of the old generation changes nothing for the '
      'new account', () => dt015(aSucceeds: false));

  test('DT-0-16 retryNow results: started, busy, notApplicable', () async {
    // (1) and (2): from gaveUp.
    final j = ControlledJournal()..script.addAll(List<Object>.filled(6, false));
    final c = make(journal: j);
    await driveToGaveUp(c);
    final hold = Completer<bool>();
    j.script.add(hold);
    expect(await retry(c), RetryResult.started);
    expect(await retry(c), RetryResult.busy);
    expect(j.calls, hasLength(7), reason: 'exactly one attempt');
    expect(status(c).bindBusy, isTrue);
    hold.complete(true);
    await pumpEventQueue();
    expect(status(c).bindBusy, isFalse);
    // (3) from Bound.
    expect(status(c).phase, BindPhase.bound);
    expect(await retry(c), RetryResult.notApplicable);
    expect(j.calls, hasLength(7));

    // (4) failedToOpen.
    final c4 = make(flags: _local, journal: null, authCtl: StreamController<AuthUser?>());
    expect(await retry(c4), RetryResult.notApplicable);

    // (5) no bindable uid.
    final a5 = StreamController<AuthUser?>();
    addTearDown(() => unawaited(a5.close()));
    final j5 = ControlledJournal();
    final c5 = make(journal: j5, authCtl: a5);
    a5.add(null);
    await pumpEventQueue();
    expect(await retry(c5), RetryResult.notApplicable);
    a5.add(_user(''));
    await pumpEventQueue();
    expect(await retry(c5), RetryResult.notApplicable);
    c5.read(accountBeingDeletedUidProvider.notifier).state = 'Z';
    a5.add(_user('Z'));
    await pumpEventQueue();
    expect(await retry(c5), RetryResult.notApplicable);
    expect(j5.calls.where((u) => u != null), isEmpty,
        reason: 'no attempt for an unbindable uid');
  });
}
