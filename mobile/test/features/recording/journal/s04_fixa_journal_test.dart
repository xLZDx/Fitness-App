// Review round 1, batch FIX-A: journal findings C1, C2, C3, C4, C5 and the
// security findings S1, S2 (one focused test each).
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart'
    show OwnerCheckedPut;
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/journal/pre_unbind_hook.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart' show GateCounters;
import 'journal_kit.dart';
import 's04_14_handoff_test.dart' show ThrowingRunner;

Uint8List _utf(String s) => Uint8List.fromList(utf8.encode(s));

/// An activity journal that checks the owner like the scoped journal does.
class _Owned extends HookedActivity implements OwnerCheckedPut {
  _Owned(super.inner, super.mark);

  bool refuse = false;
  final List<String> ownersSeen = [];

  @override
  Future<JournalEntry> putForOwner(String expectedUid, ActivitySession session,
      {JournalSyncState? syncState}) async {
    ownersSeen.add(expectedUid);
    if (refuse) throw const JournalUnbound();
    return put(session, syncState: syncState);
  }
}

void main() {
  late RecKit k;
  setUp(() async => k = await RecKit.create());
  tearDown(() => k.dispose());

  test('C1 abandonActive frees the slot, keeps the data and offers it', () async {
    await k.record(recId(1), 4);
    await expectLater(k.journal.begin(k.meta(recId(2))), throwsJournalCode('alreadyActive'));
    await k.journal.abandonActive(recId(1));
    await k.journal.begin(k.meta(recId(2)));
    await k.journal.abandonActive(recId(2));
    final list = await k.journal.listUnfinished();
    expect(list.map((u) => u.recordingId), contains(recId(1)));
    expect(list.firstWhere((u) => u.recordingId == recId(1)).status, UnfinishedStatus.readable);
    expect(k.filesOf(recId(1)), contains('seg-0001.log'));
  });

  test('C2 a seal whose flush fails detaches the journal so Start is not blocked', () async {
    await k.record(recId(1), 3, flush: false);
    k.fs.failSegWrites = true;
    await expectLater(
        k.journal.seal(recId(1), const SealRequest(reason: StopReason.user)),
        throwsJournalCode('flushFailed'));
    k.fs.failSegWrites = false;
    await k.journal.begin(k.meta(recId(2))); // would throw alreadyActive before
  });

  test('C3 a worker failure is unavailable (retryable), never unreadable or quarantined', () async {
    await k.record(recId(1), 4);
    k.runnerOverride = const ThrowingRunner();
    await k.kill();
    final r = await k.journal.listUnfinished();
    expect(r.single.status, UnfinishedStatus.unavailable);
    expect(k.filesOf(recId(1)), isNot(contains('QUARANTINED')));
  });

  test('C4 FALLBACK is written for every remaining recording even when the hook times out', () async {
    await k.record(recId(1), 4);
    await k.kill();
    await k.record(recId(2), 4);
    final hook = RecordingPreUnbindHook(
      journal: k.journal,
      shutdownRecorder: () => Future<void>.delayed(const Duration(hours: 1)),
    );
    final registry = PreUnbindHookRegistry()..register(hook);
    final outcome = await registry.runBounded('user-a', UnbindReason.signOut,
        timeout: const Duration(milliseconds: 50));
    expect(outcome, PreUnbindOutcome.timedOut);
    expect(k.filesOf(recId(1)), contains('FALLBACK'));
    expect(k.filesOf(recId(2)), contains('FALLBACK'), reason: 'the active one too');
  });

  test('C5 a quarantined recording from an invalid DECISION expires after 30 days', () async {
    await k.record(recId(1), 4);
    await k.kill();
    k.put('${k.dirOf(recId(1))}/DECISION', _utf('garbage'));
    expect((await k.journal.listUnfinished()).single.status, UnfinishedStatus.quarantined);
    k.clock.advance(const Duration(days: 31));
    expect(await k.journal.listUnfinished(), isEmpty);
    expect(k.filesOf(recId(1)), isEmpty);
  });

  test('S1 the app-start sweep deletes expired FALLBACK recordings of ANY scope', () async {
    await k.record(recId(1), 4);
    await k.kill();
    k.put('${k.dirOf(recId(1))}/FALLBACK', _utf('${k.nowMs}'));
    final aDir = k.dirOf(recId(1));
    k.uid = 'user-b'; // another account is bound now
    expect(await k.journal.sweepExpiredAllScopes(), 0, reason: 'not yet 30 days');
    k.clock.advance(const Duration(days: 31));
    expect(await k.journal.sweepExpiredAllScopes(), 1);
    expect(k.mem.files.keys.where((f) => f.startsWith('$aDir/')), isEmpty);
  });

  test('S2 the hand-off writes through the owner-checked put and aborts when refused', () async {
    final owned = _Owned(k.activityReal, (m) {});
    k.activity = owned;
    final j = k.secondJournal();
    await j.begin(k.meta(recId(1)));
    for (var i = 1; i <= 5; i++) {
      j.enqueueSample(smp(i), GateCounters.zero);
    }
    await j.flush();
    await j.seal(recId(1), const SealRequest(reason: StopReason.user));
    owned.refuse = true; // the bound account changed under the hand-off
    expect(await j.handOff(recId(1)), HandOffResult.failedKept);
    expect(await activityCount(k), 0, reason: 'nothing landed in a foreign store');
    expect(owned.ownersSeen, ['user-a']);
    owned.refuse = false;
    expect(await j.handOff(recId(1)), HandOffResult.done);
    expect(await activityCount(k), 1);
  });
}
