// S04 gate 1, finding M-02: with zero activities and only recordings that do
// not block Start (quarantined, FALLBACK-held or permission-revoked pending
// decision), the sign-out guard used to return "sign out" without running the
// pre-unbind hook, so the recorder was not handed off while the scope was still
// bound. Now the bounded hook runs whenever the recording journal lists any
// recording; only an empty journal skips it, and an unreadable listing is the
// "cannot check" outcome (never a silent pass).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/state/sign_out_guard.dart';
import 'package:fitness_app/features/recording/journal/pre_unbind_hook.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_providers.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';

import '../../../support/s03_step4_support.dart';

Finder key(String k) => find.byKey(Key(k));

class _Port extends Fake implements RecordingJournalPort {
  _Port(this.items);
  List<UnfinishedRecording> items;
  Object? error;
  int lists = 0;
  @override
  Future<List<UnfinishedRecording>> listUnfinished() async {
    lists++;
    if (error != null) throw error!;
    return List.of(items);
  }
}

class _Hook implements PreUnbindHook {
  _Hook({this.behaviour = 'ok'});
  final String behaviour; // ok | hang
  final List<UnbindReason> reasons = <UnbindReason>[];
  final List<String> uids = <String>[];
  @override
  Future<void> run(String ownerUid, UnbindReason reason) async {
    uids.add(ownerUid);
    reasons.add(reason);
    if (behaviour == 'hang') await Completer<void>().future;
  }
}

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
  _W(this.results, this.port);
  final List<bool> results;
  final _Port port;
}

Future<_W> pumpGuard(
  WidgetTester t, {
  List<UnfinishedRecording> recs = const <UnfinishedRecording>[],
  Object? portError,
  _Hook? hook,
}) async {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final journal = FakeJournal(const []);
  final port = _Port(List.of(recs))..error = portError;
  final registry = PreUnbindHookRegistry();
  if (hook != null) registry.register(hook);
  final results = <bool>[];
  await t.pumpWidget(appHost(_Host(results), overrides: [
    ...dashOverrides(journal: journal),
    recordingJournalPortProvider.overrideWithValue(port),
    recorderPhaseProvider.overrideWithValue(RecorderPhase.idle),
    activityPreUnbindHookRegistryProvider.overrideWithValue(registry),
  ]));
  await settle(t);
  return _W(results, port);
}

Future<void> trigger(WidgetTester t) async {
  await t.tap(key('host.signOut'));
  await settle(t);
}

const UnfinishedRecording _quarantined =
    UnfinishedRecording(recordingId: 'q', status: UnfinishedStatus.quarantined);
const UnfinishedRecording _pendingRevoked = UnfinishedRecording(
    recordingId: 'p', status: UnfinishedStatus.readable, pendingDecision: true);
const UnfinishedRecording _fallbackHeld = UnfinishedRecording(
    recordingId: 'f',
    status: UnfinishedStatus.quarantined,
    pendingDecision: true);

void main() {
  group('M-02 zero activities, only non-blocking recordings', () {
    for (final entry in <String, UnfinishedRecording>{
      'quarantined': _quarantined,
      'permission-revoked pending decision': _pendingRevoked,
      'FALLBACK-held (quarantined and pending)': _fallbackHeld,
    }.entries) {
      testWidgets('${entry.key}: the pre-unbind hook runs for the owner with '
          'reason signOut, no warning sheet, sign-out proceeds', (t) async {
        final h = _Hook();
        final w = await pumpGuard(t, recs: [entry.value], hook: h);
        await trigger(t);
        expect(h.uids, ['A'], reason: 'hook ran while the scope is bound');
        expect(h.reasons, [UnbindReason.signOut]);
        expect(w.results, [true]);
        expect(key('signOut.cancel'), findsNothing,
            reason: 'nothing blocking: no warning sheet');
        expect(key('signOut.noticeDone'), findsNothing,
            reason: 'a non-blocking recording needs no notice');
      });
    }

    testWidgets('an empty recording journal runs no hook and signs out at once',
        (t) async {
      final h = _Hook();
      final w = await pumpGuard(t, hook: h);
      await trigger(t);
      expect(h.uids, isEmpty);
      expect(w.results, [true]);
      expect(w.port.lists, greaterThan(0), reason: 'the journal was consulted');
    });

    testWidgets('a hook that hangs is bounded: sign-out still completes after '
        'the 5 s bound', (t) async {
      final h = _Hook(behaviour: 'hang');
      final w = await pumpGuard(t, recs: [_quarantined], hook: h);
      await t.tap(key('host.signOut'));
      await t.pump(const Duration(seconds: 1));
      expect(w.results, isEmpty, reason: 'still waiting for the hook');
      await t.pump(const Duration(seconds: 6));
      await settle(t);
      expect(h.uids, ['A']);
      // A timed-out hand-off always tells the user, then lets them leave.
      expect(key('signOut.noticeDone'), findsOneWidget);
      await t.tap(key('signOut.noticeDone'));
      await settle(t);
      expect(w.results, [true]);
    });

    testWidgets('a listing that throws is the cannot-check outcome, never a '
        'silent pass; the hook does not run; Sign out anyway stays', (t) async {
      final h = _Hook();
      final w = await pumpGuard(t, portError: StateError('io'), hook: h);
      await trigger(t);
      expect(find.text('We could not check the activity stored on this device'),
          findsOneWidget);
      expect(w.results, isEmpty);
      expect(h.uids, isEmpty);
      expect(key('signOut.anyway'), findsOneWidget);
      await t.tap(key('signOut.anyway'));
      await settle(t);
      expect(w.results, [true]);
    });
  });
}
