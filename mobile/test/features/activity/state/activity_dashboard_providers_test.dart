// S03-13 dashboard providers (test plan 5.2, DT-13-8 to DT-13-16, 18, 20) and
// the availability function (DT-13-13). Real notifier, fake journals, fake
// timers; no widgets.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/state/activity_dashboard_providers.dart';
import 'package:fitness_app/features/activity/state/journal_availability.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

import '../../../support/s03_step4_support.dart';

class _FixedStatus extends ActivityBindStatusNotifier {
  _FixedStatus(this.fixed);
  final ActivityBindStatus fixed;
  @override
  ActivityBindStatus build() => fixed;
}

void main() {
  late StreamController<AuthUser?> auth;
  late FakeTimers timers;
  late List<String> logs;
  late void Function(String?, {int? wrapWidth}) savedPrint;

  setUp(() {
    auth = StreamController<AuthUser?>.broadcast();
    timers = FakeTimers();
    logs = [];
    savedPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
  });
  tearDown(() {
    debugPrint = savedPrint;
    unawaited(auth.close());
  });

  ProviderContainer make(FakeJournal j,
      {DateTime Function()? clock, List<Override> extra = const []}) {
    final c = ProviderContainer(overrides: [
      ...dashOverrides(
          journal: j, auth: auth, timers: timers, clock: clock),
      ...extra,
    ]);
    addTearDown(c.dispose);
    c.read(activityJournalBindingProvider);
    c.listen(activityDigestsProvider, (_, __) {});
    return c;
  }

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await pumpEventQueue();
  }

  JournalEntry run(String id) =>
      entry(sess(id, start: kNow, dist: 1000, time: 600));

  test('DT-13-8 binding shows loading never empty; data appears after the bind',
      () async {
    final j = ScopedFakeJournal([run('s1')]);
    final c = make(j);
    await emit(user('A'));
    expect(c.read(journalAvailabilityProvider), isA<JournalBinding>());
    expect(c.read(activityDigestSnapshotProvider), isNull);
    expect(c.read(activityDigestsProvider).isLoading, isTrue);
    expect(j.listCalls, 0, reason: 'no list() before the journal is open');
    j.complete(true);
    await pumpEventQueue();
    expect(c.read(journalAvailabilityProvider), isA<JournalOpen>());
    final snap = c.read(activityDigestSnapshotProvider);
    expect(snap, isNotNull);
    expect(snap!.digests.map((d) => d.id), ['s1']);
  });

  test('DT-13-9 A late list() of account A never shows for B', () async {
    final j = FakeJournal();
    final ca = Completer<List<JournalEntry>>();
    final cb = Completer<List<JournalEntry>>();
    j.gateQueue.addAll([ca, cb]);
    final c = make(j);
    await emit(user('A'));
    expect(j.listCalls, 1);
    await emit(user('B'));
    expect(j.listCalls, 2);
    // (a) while A's list is pending nothing of A is visible under B.
    expect(c.read(activityDigestSnapshotProvider), isNull);
    // (b) A's late completion is discarded.
    ca.complete([run('A-secret')]);
    await pumpEventQueue();
    expect(c.read(activityDigestSnapshotProvider), isNull,
        reason: 'A completion must not publish for B');
    cb.complete([run('B1')]);
    await pumpEventQueue();
    final snap = c.read(activityDigestSnapshotProvider)!;
    expect(snap.ownerUid, 'B');
    expect(snap.digests.map((d) => d.id), ['B1']);
  });

  test('DT-13-10 B with a throwing journal never reuses A digests', () async {
    final j = FakeJournal([run('A1')]);
    final c = make(j);
    await emit(user('A'));
    expect(c.read(activityDigestSnapshotProvider)!.ownerUid, 'A');
    j.listError = StateError('boom');
    await emit(user('B'));
    expect(c.read(activityDigestSnapshotProvider), isNull);
    expect(c.read(activityDigestsProvider).hasError, isTrue);
  });

  test('DT-13-11 a bind that always fails: 6 attempts, then gaveUp, no timer',
      () async {
    final j = ScopedFakeJournal();
    final c = make(j);
    await emit(user('A'));
    for (var i = 0; i < 5; i++) {
      j.complete(false);
      await pumpEventQueue();
      expect(timers.active, 1, reason: 'retry $i armed');
      timers.all.last.fire();
      await pumpEventQueue();
    }
    j.complete(false);
    await pumpEventQueue();
    expect(j.bindCalls, hasLength(6));
    expect(c.read(journalAvailabilityProvider), isA<JournalGaveUp>());
    expect(timers.active, 0);
    expect(c.read(activityDigestSnapshotProvider), isNull);
    expect(c.read(activityDigestsProvider).isLoading, isTrue,
        reason: 'the notifier stays loading; the UI reads gaveUp');
  });

  test('DT-13-12 a failed refresh keeps the value and sets lastLoadFailedAt',
      () async {
    final j = FakeJournal([run('s1')]);
    final c = make(j, clock: () => kNow);
    await emit(user('A'));
    expect(c.read(activityDigestSnapshotProvider)!.lastLoadFailedAt, isNull);
    j.listError = StateError('x');
    await c.read(activityDigestsProvider.notifier).refresh();
    expect(c.read(activityDigestsProvider).hasError, isFalse);
    final snap = c.read(activityDigestSnapshotProvider)!;
    expect(snap.digests.map((d) => d.id), ['s1']);
    expect(snap.lastLoadFailedAt, kNow);
    // A later success clears it.
    j.listError = null;
    await c.read(activityDigestsProvider.notifier).refresh();
    expect(c.read(activityDigestSnapshotProvider)!.lastLoadFailedAt, isNull);
  });

  group('DT-13-13 availability function', () {
    ProviderContainer fixed({
      required BindPhase phase,
      required String? statusUid,
      String? boundUid,
      String? authUid = 'A',
      bool journalOn = true,
      bool journalPresent = true,
    }) {
      final j = ScopedFakeJournal();
      if (boundUid != null) {
        j.bindCalls.add(boundUid);
        // ignore: invalid_use_of_protected_member
      }
      final c = ProviderContainer(overrides: [
        activityFlagsProvider
            .overrideWithValue(ActivityFlags(localJournal: journalOn)),
        if (journalPresent) activityJournalProvider.overrideWithValue(j),
        ...dashOverrides(auth: auth, localJournal: journalOn),
        activityBindStatusProvider.overrideWith(() => _FixedStatus(
            ActivityBindStatus(phase: phase, uid: statusUid, generation: 1))),
      ]);
      addTearDown(c.dispose);
      if (boundUid != null) {
        j.autoSucceed = true;
        j.bindUid(boundUid);
      }
      c.listen(authUserProvider, (_, __) {});
      if (authUid != null) auth.add(user(authUid));
      return c;
    }

    test('flag off is notEnabled', () async {
      final c = fixed(phase: BindPhase.none, statusUid: null, journalOn: false);
      await pumpEventQueue();
      expect(c.read(journalAvailabilityProvider), isA<JournalNotEnabled>());
    });
    test('flag on without a journal object is failedToOpen', () async {
      final c = fixed(
          phase: BindPhase.none, statusUid: null, journalPresent: false);
      await pumpEventQueue();
      expect(c.read(journalAvailabilityProvider), isA<JournalFailedToOpen>());
    });
    test('open only when bound AND boundUid equals the auth uid', () async {
      final same = fixed(
          phase: BindPhase.bound, statusUid: 'A', boundUid: 'A');
      await pumpEventQueue();
      expect(same.read(journalAvailabilityProvider), isA<JournalOpen>());
      final other = fixed(
          phase: BindPhase.bound, statusUid: 'A', boundUid: 'Z');
      await pumpEventQueue();
      expect(other.read(journalAvailabilityProvider), isA<JournalBinding>());
    });
    test('status of another uid is binding, gaveUp is gaveUp', () async {
      final stale = fixed(
          phase: BindPhase.bound, statusUid: 'Z', boundUid: 'Z');
      await pumpEventQueue();
      expect(stale.read(journalAvailabilityProvider), isA<JournalBinding>());
      final gave = fixed(phase: BindPhase.gaveUp, statusUid: 'A');
      await pumpEventQueue();
      expect(gave.read(journalAvailabilityProvider), isA<JournalGaveUp>());
      final binding = fixed(phase: BindPhase.binding, statusUid: 'A');
      await pumpEventQueue();
      expect(binding.read(journalAvailabilityProvider), isA<JournalBinding>());
    });
    test('signed out is binding', () async {
      final c = fixed(phase: BindPhase.none, statusUid: null, authUid: null);
      await pumpEventQueue();
      expect(c.read(journalAvailabilityProvider), isA<JournalBinding>());
    });
  });

  test('DT-13-14 refresh storm: one in flight plus one dirty rerun', () async {
    final j = FakeJournal([run('s1')]);
    final g1 = Completer<List<JournalEntry>>();
    j.gateQueue.add(g1);
    final c = make(j);
    await emit(user('A'));
    expect(j.listCalls, 1);
    final n = c.read(activityDigestsProvider.notifier);
    c.read(activityJournalRevisionProvider.notifier).state++;
    for (var i = 0; i < 10; i++) {
      unawaited(n.refresh());
      n.refreshIfStale();
    }
    await pumpEventQueue();
    expect(j.listCalls, 1, reason: 'nothing starts while a load is pending');
    g1.complete([run('s1')]);
    await pumpEventQueue();
    expect(j.listCalls, 2, reason: 'exactly one extra list() in total');
    expect(c.read(activityDigestSnapshotProvider), isNotNull);
  });

  test('DT-13-15 sign-out resets synchronously and cancels the retry timer',
      () async {
    final j = ScopedFakeJournal([run('s1')]);
    j.autoSucceed = true;
    final c = make(j);
    await emit(user('A'));
    expect(c.read(activityDigestSnapshotProvider), isNotNull);
    await emit(null);
    expect(c.read(journalAvailabilityProvider), isA<JournalBinding>());
    expect(c.read(activityDigestSnapshotProvider), isNull,
        reason: 'no data of the previous account after sign-out');
    // A pending retry of the departed account is cancelled.
    final j2 = ScopedFakeJournal();
    timers = FakeTimers();
    final auth2 = StreamController<AuthUser?>();
    addTearDown(auth2.close);
    final c2 = ProviderContainer(overrides: [
      ...dashOverrides(journal: j2, auth: auth2, timers: timers),
    ]);
    addTearDown(c2.dispose);
    c2.read(activityJournalBindingProvider);
    auth2.add(user('A'));
    await pumpEventQueue();
    j2.complete(false);
    await pumpEventQueue();
    expect(timers.active, 1);
    auth2.add(null);
    await pumpEventQueue();
    expect(timers.active, 0);
    // A stale completion of the departed generation changes nothing.
    j2.bindCalls.clear();
    expect(c2.read(journalAvailabilityProvider), isA<JournalBinding>());
  });

  test('DT-13-15 an account being deleted has no bindable uid', () async {
    final j = ScopedFakeJournal();
    final c = make(j);
    await emit(user('A'));
    c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
    await pumpEventQueue();
    expect(c.read(journalAvailabilityProvider), isA<JournalBinding>());
    expect(c.read(activityDigestSnapshotProvider), isNull);
  });

  test('DT-13-16 recovery counts survive a refresh', () async {
    final j = ScopedFakeJournal([run('s1')]);
    j.autoSucceed = true;
    j.report = JournalRecoveryReport()..absent.add('gone');
    final c = make(j);
    await emit(user('A'));
    expect(c.read(activityDigestSnapshotProvider)!.recoveredAbsent, 1);
    await c.read(activityDigestsProvider.notifier).refresh();
    final snap = c.read(activityDigestSnapshotProvider)!;
    expect(snap.recoveredAbsent, 1);
    expect(snap.mayBeIncomplete, isTrue);
  });

  test('DT-13-18 logs carry a fixed message, a code and the type only',
      () async {
    final j = FakeJournal()
      ..listError = StateError('secret-session-id-123 /private/path');
    final c = make(j);
    await emit(user('A'));
    await c.read(activityDigestsProvider.notifier).refresh();
    final joined = logs.join('\n');
    expect(joined, contains('list_failed'));
    expect(joined, contains('StateError'));
    expect(joined, isNot(contains('secret-session-id-123')));
    expect(joined, isNot(contains('/private/path')));
  });

  test('DT-13-20 revision bump: one reload; uid change is a reset', () async {
    final j = FakeJournal([run('s1')]);
    final c = make(j);
    await emit(user('A'));
    expect(j.listCalls, 1);
    c.read(activityJournalRevisionProvider.notifier).state++;
    await pumpEventQueue();
    expect(j.listCalls, 2);
    final g = Completer<List<JournalEntry>>();
    j.gateQueue.add(g);
    final rev = c.read(activityJournalRevisionProvider.notifier);
    rev.state++;
    await pumpEventQueue();
    rev.state++;
    rev.state++;
    await pumpEventQueue();
    expect(j.listCalls, 3, reason: 'bumps during a load coalesce');
    g.complete([run('s1')]);
    await pumpEventQueue();
    expect(j.listCalls, 4, reason: 'one dirty rerun');
    await emit(user('B'));
    expect(j.listCalls, 5, reason: 'a uid change loads once, no extra bump');
  });
}
