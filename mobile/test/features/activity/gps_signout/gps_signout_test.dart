// S04-30 (sign-out with a recording, DT-30-6, DT-30-7 settings sign-out and
// guard-sheet entries, DT-30-3 notice, DT-30-10 ordering). The REAL sign-out
// guard and sheets; the recording port and the pre-unbind hook are fakes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/state/sign_out_guard.dart';
import 'package:fitness_app/features/recording/journal/pre_unbind_hook.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_ports.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

import '../../../support/s03_step4_support.dart';

Finder key(String k) => find.byKey(Key(k));

class _PortFake extends Fake implements RecordingJournalPort {
  _PortFake(this.items);
  List<UnfinishedRecording> items;
  Object? error;
  @override
  Future<List<UnfinishedRecording>> listUnfinished() async {
    if (error != null) throw error!;
    return List.of(items);
  }
}

class _Hook implements PreUnbindHook {
  _Hook({this.behaviour = 'ok', this.onRun});
  final String behaviour; // ok | throw | hang
  final void Function()? onRun;
  final List<UnbindReason> reasons = <UnbindReason>[];
  final List<String> uids = <String>[];
  @override
  Future<void> run(String ownerUid, UnbindReason reason) async {
    uids.add(ownerUid);
    reasons.add(reason);
    onRun?.call();
    if (behaviour == 'throw') throw StateError('boom');
    if (behaviour == 'hang') await Completer<void>().future;
  }
}

const UnfinishedRecording _rec =
    UnfinishedRecording(recordingId: 'r1', status: UnfinishedStatus.readable);

class _Host extends ConsumerWidget {
  const _Host(this.results);
  final List<bool> results;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('host.signOut'),
            onPressed: () async =>
                results.add(await confirmSignOutWithLocalData(context, ref)),
            child: const Text('go'),
          ),
        ),
      );
}

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

class _W {
  _W(this.results, this.port, this.registry, this.journal);
  final List<bool> results;
  final _PortFake port;
  final PreUnbindHookRegistry registry;
  final FakeJournal journal;
}

Future<_W> pump(
  WidgetTester t, {
  List<UnfinishedRecording> recs = const <UnfinishedRecording>[],
  int activities = 0,
  RecorderPhase phase = RecorderPhase.idle,
  _Hook? hook,
  Object? portError,
  bool noPort = false,
}) async {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final journal = FakeJournal([
    for (var i = 0; i < activities; i++)
      entry(sess('a$i', start: kNow, dist: 1, time: 1))
  ]);
  final port = _PortFake(List.of(recs))..error = portError;
  final registry = PreUnbindHookRegistry();
  if (hook != null) registry.register(hook);
  final results = <bool>[];
  await t.pumpWidget(appHost(_Host(results), overrides: [
    ...dashOverrides(journal: journal),
    if (!noPort) recorderWiredProvider.overrideWithValue(true),
    if (!noPort) recordingJournalPortProvider.overrideWithValue(port),
    recorderPhaseProvider.overrideWithValue(phase),
    activityPreUnbindHookRegistryProvider.overrideWithValue(registry),
  ]));
  await settle(t);
  return _W(results, port, registry, journal);
}

Future<void> trigger(WidgetTester t) async {
  await t.tap(key('host.signOut'));
  await settle(t);
}

void main() {
  group('DT-30-6 the guard counts recordings', () {
    testWidgets('/counts-an-active-recording: the sheet names it', (t) async {
      final w = await pump(t, recs: [_rec], phase: RecorderPhase.recording);
      await trigger(t);
      expect(find.text('1 unfinished recording'), findsOneWidget);
      expect(key('signOut.keep'), findsOneWidget);
      expect(key('signOut.cancel'), findsOneWidget);
      expect(w.results, isEmpty, reason: 'no decision before a choice');
    });

    testWidgets('/unfinished-only-is-not-a-silent-pass: 0 activities, 2 recordings',
        (t) async {
      final w = await pump(t, recs: [
        _rec,
        const UnfinishedRecording(
            recordingId: 'r2', status: UnfinishedStatus.readable)
      ]);
      await trigger(t);
      expect(find.text('2 unfinished recordings'), findsOneWidget);
      expect(w.results, isEmpty);
      expect(key('signOut.cancel'), findsOneWidget);
    });

    testWidgets('an active recording not yet listed counts as one', (t) async {
      await pump(t, phase: RecorderPhase.recording);
      await trigger(t);
      expect(find.text('1 unfinished recording'), findsOneWidget);
    });

    testWidgets('a quarantined or revoked-pending item does not count',
        (t) async {
      final w = await pump(t, recs: const [
        UnfinishedRecording(
            recordingId: 'q', status: UnfinishedStatus.quarantined),
        UnfinishedRecording(
            recordingId: 'p',
            status: UnfinishedStatus.readable,
            pendingDecision: true),
      ]);
      await trigger(t);
      expect(w.results, [true], reason: 'nothing blocks: signs out at once');
      expect(key('signOut.cancel'), findsNothing);
    });

    testWidgets('no recording and no activity: no prompt, no hook', (t) async {
      final h = _Hook();
      final w = await pump(t, hook: h);
      await trigger(t);
      expect(w.results, [true]);
      expect(h.uids, isEmpty);
    });

    testWidgets('activities and recordings: both named', (t) async {
      await pump(t, activities: 3, recs: [_rec]);
      await trigger(t);
      expect(find.text('You have 3 activities stored only on this device'),
          findsOneWidget);
      expect(find.text('1 unfinished recording'), findsOneWidget);
    });

    testWidgets('/cannot-count: never a silent pass; Sign out anyway stays',
        (t) async {
      final w = await pump(t, portError: StateError('io'));
      await trigger(t);
      expect(find.text('We could not check the activity stored on this device'),
          findsOneWidget);
      expect(w.results, isEmpty);
      expect(key('signOut.anyway'), findsOneWidget);
      await t.tap(key('signOut.anyway'));
      await settle(t);
      expect(w.results, [true]);
    });

    testWidgets('recorder not wired at all counts as zero recordings',
        (t) async {
      final w = await pump(t, noPort: true);
      await trigger(t);
      expect(w.results, [true]);
    });
  });

  group('DT-30-7 / DT-30-10 settings sign-out with a recording', () {
    testWidgets('Sign out keeping data runs the hook for the owner with '
        'reason signOut, then signs out', (t) async {
      late _W w;
      final h = _Hook(onRun: () => w.port.items = []);
      w = await pump(t, recs: [_rec], phase: RecorderPhase.recording, hook: h);
      await trigger(t);
      await t.tap(key('signOut.keep'));
      await settle(t);
      expect(h.uids, ['A']);
      expect(h.reasons, [UnbindReason.signOut]);
      expect(w.results, [true]);
      expect(key('signOut.noticeDone'), findsNothing);
    });

    testWidgets('/fallback-notice: a recording still left after the hook '
        'shows gpsSignOutNotice, sign-out still allowed', (t) async {
      final h = _Hook();
      final w = await pump(t, recs: [_rec], hook: h);
      await trigger(t);
      await t.tap(key('signOut.keep'));
      await settle(t);
      expect(
          find.textContaining('stays encrypted on this phone'), findsOneWidget);
      expect(w.results, isEmpty, reason: 'the notice is shown before leaving');
      await t.tap(key('signOut.noticeDone'));
      await settle(t);
      expect(w.results, [true]);
    });

    testWidgets('a throwing hook shows the notice and still signs out',
        (t) async {
      final h = _Hook(behaviour: 'throw');
      final w = await pump(t, recs: [_rec], hook: h);
      await trigger(t);
      await t.tap(key('signOut.keep'));
      await settle(t);
      expect(key('signOut.noticeDone'), findsOneWidget);
      await t.tap(key('signOut.noticeDone'));
      await settle(t);
      expect(w.results, [true]);
    });

    testWidgets('/hook-times-out-at-5-s: the notice appears and the user can '
        'leave', (t) async {
      final h = _Hook(behaviour: 'hang');
      final w = await pump(t, recs: [_rec], hook: h);
      await trigger(t);
      await t.tap(key('signOut.keep'));
      await t.pump(const Duration(seconds: 4));
      expect(key('signOut.noticeDone'), findsNothing,
          reason: 'still inside the 5 s bound');
      await t.pump(const Duration(seconds: 2));
      await settle(t);
      expect(key('signOut.noticeDone'), findsOneWidget);
      await t.tap(key('signOut.noticeDone'));
      await settle(t);
      expect(w.results, [true]);
    });

    testWidgets('/guard-sheet-sign-out-and-delete: two taps; hook runs after '
        'the confirmation and before the result', (t) async {
      late _W w;
      final h = _Hook(onRun: () => w.port.items = []);
      w = await pump(t, activities: 1, recs: [_rec], hook: h);
      await trigger(t);
      await t.tap(key('signOut.andDelete'));
      await settle(t);
      expect(w.journal.wipeCalls, 0, reason: 'first tap deletes nothing');
      expect(h.uids, isEmpty, reason: 'nothing stopped before the confirmation');
      await t.tap(key('signOut.confirmDelete'));
      await settle(t);
      expect(h.uids, ['A']);
      expect(w.journal.wipeCalls, 1);
      expect(w.results, [true]);
    });

    testWidgets('Cancel stops nothing and deletes nothing', (t) async {
      final h = _Hook();
      final w = await pump(t, activities: 1, recs: [_rec], hook: h);
      await trigger(t);
      await t.tap(key('signOut.cancel'));
      await settle(t);
      expect(w.results, [false]);
      expect(h.uids, isEmpty);
      expect(w.journal.wipeCalls, 0);
    });

    testWidgets('Cancel on the confirmation keeps recording and activities',
        (t) async {
      final h = _Hook();
      final w = await pump(t, activities: 1, recs: [_rec], hook: h);
      await trigger(t);
      await t.tap(key('signOut.andDelete'));
      await settle(t);
      await t.tap(key('signOut.cancel'));
      await settle(t);
      expect(h.uids, isEmpty);
      expect(w.journal.wipeCalls, 0);
    });
  });

  group('registry (DT-30-9 / DT-30-10 pure)', () {
    test('no hook, completed, failed, timedOut', () async {
      final r = PreUnbindHookRegistry();
      expect(await r.runBounded('A', UnbindReason.signOut),
          PreUnbindOutcome.noHook);
      r.register(_Hook());
      expect(await r.runBounded('A', UnbindReason.uidChanged),
          PreUnbindOutcome.completed);
      r.register(_Hook(behaviour: 'throw'));
      expect(await r.runBounded('A', UnbindReason.accountDeleted),
          PreUnbindOutcome.failed);
      r.register(_Hook(behaviour: 'hang'));
      expect(
          await r.runBounded('A', UnbindReason.signOut,
              timeout: const Duration(milliseconds: 30)),
          PreUnbindOutcome.timedOut);
    });
    test('default bound is 5 s and unregister of a stranger is ignored', () {
      expect(kPreUnbindTimeout, const Duration(seconds: 5));
      final r = PreUnbindHookRegistry();
      final a = _Hook();
      r.register(a);
      r.unregister(_Hook());
      expect(r.hasHook, isTrue);
      r.unregister(a);
      expect(r.hasHook, isFalse);
    });
  });
}
