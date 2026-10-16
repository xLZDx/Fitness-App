// Crash and fault matrix over one mutation of a committed activity (test plan
// I20, I40, I46-I49). Test-only.
//
// Fixture (the common fixture of I46-I49): `other` is committed first, then
// the target activity at generation `base` = R1/S1 with the `synced` marker,
// base revision 8 and override O1 (5 000). A mutation M then creates
// generation `base + 1` = R2/S2.
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/summary_overrides.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'journal_fault_fs.dart';
import 'journal_harness.dart';

enum Mut { reedit, delete, synced }

final String kTarget = idFor(1);
final String kOther = idFor(2);

ActivitySession withOverride(ActivitySession s, double v, {int rev = 8}) =>
    s.copyWith(summaryOverrides: {
      'distanceM': SummaryOverride(
        value: v,
        atComputed: 4800,
        atVersions: CalcVersions.current,
        atRev: rev,
      ),
    });

ActivitySession r1() => withOverride(journalSession(kTarget, seed: 1), 5000);
ActivitySession r2() => withOverride(journalSession(kTarget, seed: 2), 5100, rev: 9);
ActivitySession r3() =>
    withOverride(journalSession(kTarget, seed: 1, distanceM: 4900), 5100, rev: 9);

/// Opens the harness and commits the fixture. Returns the base generation.
Future<int> setupFixture(JournalHarness h) async {
  await h.open();
  await h.journal.put(journalSession(kOther, seed: 9));
  final e = await h.journal.put(r1(),
      syncState: JournalSyncState.synced, baseRev: 8);
  h.acks.clear();
  return e.generation;
}

Future<void> applyMutation(JournalHarness h, Mut m) async {
  switch (m) {
    case Mut.reedit:
      await h.journal.put(r2());
    case Mut.delete:
      await h.journal.delete(kTarget);
    case Mut.synced:
      await h.journal.updateRecord(kTarget, r3(),
          syncState: JournalSyncState.synced, baseRev: 9);
  }
}

class Baseline {
  Baseline(this.log, this.mutationOps, this.commitIndex);

  /// Every real operation of the mutation plus the following `read`.
  final List<FsOp> log;

  /// Number of operations before the acknowledgement.
  final int mutationOps;

  /// Index of the operation that renames the COMMIT marker.
  final int commitIndex;

  int get total => log.where((o) => o.kind != FsOpKind.note).length;
}

Future<Baseline> baselineFor(Mut m) async {
  final h = JournalHarness.memory();
  try {
    await setupFixture(h);
    h.fs.clearLog();
    await applyMutation(h, m);
    if (m != Mut.delete) await h.journal.read(kTarget);
    final log = List.of(h.fs.log);
    final ackPos = log.indexWhere((o) => o.kind == FsOpKind.note);
    final ops = log.where((o) => o.kind != FsOpKind.note).toList();
    final commit = ops.firstWhere(
        (o) => o.kind == FsOpKind.rename && o.to!.endsWith('/COMMIT'));
    return Baseline(
        log, log.sublist(0, ackPos).where((o) => o.kind != FsOpKind.note).length, commit.index);
  } finally {
    await h.dispose();
  }
}

bool newExpected(FaultPlan p, Baseline b) {
  final performed =
      p.mode == FaultMode.crashAfter || p.mode == FaultMode.errorAfter;
  return performed ? p.opIndex >= b.commitIndex : p.opIndex > b.commitIndex;
}

class CrashRun {
  CrashRun(this.h, this.plan, this.error, this.completed, this.base);

  final JournalHarness h;
  final FaultPlan plan;
  final Object? error;
  final bool completed;
  final int base;
}

/// Commits the fixture, arms [plan], runs the mutation (and the read that
/// follows it while the process lives), then restarts on the same directory.
/// [h] is restarted; the previous instance's report is in `h.report`.
Future<CrashRun> runWithFault(Mut m, FaultPlan plan,
    {JournalHarness? harness, void Function(JournalHarness)? beforeArm}) async {
  final h = harness ?? JournalHarness.memory();
  final base = await setupFixture(h);
  beforeArm?.call(h);
  h.fs.clearLog();
  h.fs.arm(plan);
  Object? error;
  var completed = false;
  try {
    await applyMutation(h, m);
    completed = true;
  } catch (e) {
    error = e;
  }
  if (!h.fs.dead) {
    try {
      if (m != Mut.delete) await h.journal.read(kTarget);
    } catch (_) {}
  }
  return CrashRun(h, plan, error, completed, base);
}

/// What a restart on the crashed directory must show.
Future<void> expectRecovered(
  JournalHarness h,
  Mut m, {
  required bool isNew,
  required int base,
  String why = '',
}) async {
  final newSeq = base + 1;
  final sel = h.report.selectedGenerations[kTarget];
  expect(sel, isNotNull, reason: '$why target must be recovered');
  expect(sel, isNew ? newSeq : base,
      reason: '$why strictly selected generation');
  expect(h.report.streamLost, isEmpty, reason: '$why never streamLost');
  expect(h.report.absent, isEmpty, reason: '$why');
  final cur = await h.currentJson(kTarget);
  expect(cur?['seq'], sel, reason: '$why CURRENT names the selected generation');
  final tree = await h.snapshot();
  expect(tree.keys.where((k) => k.endsWith('.tmp')), isEmpty,
      reason: '$why no temp file survives the start');
  if (!isNew) {
    expect(await h.generations(kTarget), [base],
        reason: '$why the uncommitted generation is deleted');
    expect(await h.exists(h.gen(kTarget, newSeq)), isFalse, reason: why);
  } else {
    expect(await h.exists(h.gen(kTarget, newSeq, 'COMMIT')), isTrue, reason: why);
  }

  // The other activity is untouched.
  final other = await h.journal.read(kOther);
  expect(other, isNotNull, reason: '$why other session intact');
  expect(other!.streamLost, isFalse, reason: why);
  expect(streamsOf(other.session), streamsOf(journalSession(kOther, seed: 9)),
      reason: why);

  final ids = await h.listIds();
  final tombs = [for (final e in await h.journal.listTombstones()) e.id];

  if (isNew && m == Mut.delete) {
    expect(ids, [kOther], reason: '$why tombstone present: entry not listed');
    expect(tombs, [kTarget], reason: why);
    expect(await h.journal.read(kTarget), isNull, reason: why);
    return;
  }
  expect(tombs, isEmpty, reason: '$why tombstone absent');
  expect(ids.where((i) => i == kTarget), hasLength(1), reason: '$why listed once');

  final e = (await h.journal.read(kTarget))!;
  expect(e.streamLost, isFalse, reason: why);
  expect(e.streamsLoaded, isTrue, reason: why);
  expect(e.generation, sel, reason: why);
  final ov = e.session.summaryOverrides['distanceM']!;
  if (!isNew) {
    expect(sessionJson(e.session), sessionJson(r1()), reason: '$why R1 byte for byte');
    expect(streamsOf(e.session), streamsOf(r1()), reason: '$why S1');
    expect(e.state.synced, isTrue, reason: '$why synced marker present');
    expect(e.state.baseRev, 8, reason: why);
    expect(e.state.tombstone, isFalse, reason: why);
    expect(ov.value, 5000, reason: '$why overrides O1');
    return;
  }
  switch (m) {
    case Mut.reedit:
      expect(sessionJson(e.session), sessionJson(r2()), reason: '$why R2');
      expect(streamsOf(e.session), streamsOf(r2()), reason: '$why S2');
      expect(e.state.synced, isFalse, reason: '$why synced cleared: re-queued');
      expect(ov.value, 5100, reason: '$why overrides O2');
    case Mut.synced:
      expect(sessionJson(e.session), sessionJson(r3()), reason: '$why R2');
      expect(streamsOf(e.session), streamsOf(r1()), reason: '$why streams kept');
      expect(e.state.synced, isTrue, reason: '$why');
      expect(e.state.baseRev, 9, reason: why);
      expect(ov.value, 5100, reason: why);
    case Mut.delete:
      break;
  }
}

/// Typed error expected from a mutation that did not commit.
void expectTypedAbort(CrashRun r, Mut m, {bool onRead = false}) {
  if (onRead) {
    // A read can fail for any reason; both typed errors are write failures.
    expect(r.error, isA<JournalWriteFailure>(), reason: '${r.plan}');
  } else if (r.plan.mode == FaultMode.diskFullAt) {
    expect(r.error, isA<JournalStorageFullException>(), reason: '${r.plan}');
  } else {
    expect(r.error, isA<JournalIoException>(), reason: '${r.plan}');
  }
  if (m == Mut.reedit) {
    expect((r.error as JournalWriteFailure).pending?.id, kTarget,
        reason: '${r.plan}: the recording is kept for a retry');
  }
}
