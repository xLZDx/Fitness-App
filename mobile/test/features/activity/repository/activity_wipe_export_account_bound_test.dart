// S02 test epic 14b: remediation H8, the sign-out wipe and the local export are
// bound to the account. Oracles: S02_REMEDIATION_H_TEST_NOTES.md H-B items 7 and
// 8, design 17 item 24 (e) and the promise "the account the user confirmed is
// the account that is wiped, and one export never mixes two accounts". Real
// UidScopedActivityJournal on temp directories.
import 'dart:convert';

import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/activity_local_export.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';
import '../../../support/stale_view_world.dart';

class _Rec extends HookJournal {
  _Rec(super.f);
  final List<String> wiped = [];
  int plainWipes = 0;
  Future<void> Function()? onAssess;

  @override
  Future<void> wipeForUid(String uid) {
    wiped.add(uid);
    return super.wipeForUid(uid);
  }

  @override
  Future<void> wipe() {
    plainWipes++;
    return super.wipe();
  }

  @override
  Future<SignOutAssessment> assessSignOut() async {
    final r = await super.assessSignOut();
    await onAssess?.call();
    return r;
  }
}

class _Hooks implements ActivitySignOutHooks {
  _Hooks({this.confirm = true, this.during});
  final bool confirm;
  final Future<void> Function()? during;
  final List<String> calls = [];

  @override
  Future<void> offerExport(SignOutAssessment a) async => calls.add('offer');

  @override
  Future<bool> confirmWipe(SignOutAssessment a) async {
    calls.add('confirm');
    await during?.call();
    return confirm;
  }
}

void main() {
  late ScopedJournalWorld w;
  late _Rec journal;

  setUp(() async {
    w = await ScopedJournalWorld.create();
    journal = _Rec(w.factory);
  });
  tearDown(() async {
    await journal.close();
    await w.tmp.delete(recursive: true);
  });

  Future<void> seed(String uid, List<int> ns) async {
    expect(await journal.bindUid(uid), isTrue);
    for (final n in ns) {
      await journal.put(journalSession(idFor(n), seed: n));
    }
  }

  group('H8: onSignOut', () {
    test('the bound uid switches A to B during the prompt: nothing is wiped, '
        'B and A are intact, false is returned', () async {
      await seed('B', [11, 12]);
      await seed('A', [1, 2]);
      final aBefore = await w.snapshot('A');
      final bBefore = await w.snapshot('B');
      final hooks = _Hooks(during: () async {
        expect(await journal.bindUid('B'), isTrue);
      });

      final ok = await ActivityWipeCoordinator(journal).onSignOut(hooks);

      expect(ok, isFalse);
      expect(hooks.calls, ['offer', 'confirm']);
      expect(journal.wiped, isEmpty, reason: 'wipeForUid never ran for anyone');
      expect(journal.plainWipes, 0, reason: 'and not the bound-journal wipe');
      expect(await w.snapshot('B'), bBefore, reason: "B's data is intact");
      expect(await w.snapshot('A'), aBefore, reason: "A's data is intact too");
      expect(await journal.list(), hasLength(2));
    });

    test('unbound during the prompt (sign-out elsewhere): nothing is wiped',
        () async {
      await seed('A', [1]);
      final before = await w.snapshot('A');
      final hooks = _Hooks(during: () async => journal.bindUid(null));
      expect(await ActivityWipeCoordinator(journal).onSignOut(hooks), isFalse);
      expect(journal.wiped, isEmpty);
      expect(journal.plainWipes, 0);
      expect(await w.snapshot('A'), before);
    });

    test('the uid switches during assessSignOut: no prompt, no wipe',
        () async {
      await seed('B', [11]);
      await seed('A', [1]);
      journal.onAssess = () async => journal.bindUid('B');
      final hooks = _Hooks();
      expect(await ActivityWipeCoordinator(journal).onSignOut(hooks), isFalse);
      expect(hooks.calls, isEmpty);
      expect(journal.wiped, isEmpty);
    });

    test('no switch: exactly the captured uid is wiped, another account is '
        'untouched', () async {
      await seed('B', [11, 12]);
      await seed('A', [1, 2]);
      final bBefore = await w.snapshot('B');
      final hooks = _Hooks();

      final ok = await ActivityWipeCoordinator(journal).onSignOut(hooks);

      expect(ok, isTrue);
      expect(journal.wiped, ['A']);
      expect(journal.plainWipes, 0);
      expect(await w.snapshot('A'), isEmpty, reason: "A's scope is gone");
      expect(await w.snapshot('B'), bBefore, reason: "B's scope is untouched");
    });

    test('the user declines: nothing is wiped', () async {
      await seed('A', [1]);
      final before = await w.snapshot('A');
      final hooks = _Hooks(confirm: false);
      expect(await ActivityWipeCoordinator(journal).onSignOut(hooks), isFalse);
      expect(journal.wiped, isEmpty);
      expect(await w.snapshot('A'), before);
    });

    test('an empty bound journal signs out without a prompt, wiping A',
        () async {
      expect(await journal.bindUid('A'), isTrue);
      final hooks = _Hooks();
      expect(await ActivityWipeCoordinator(journal).onSignOut(hooks), isTrue);
      expect(hooks.calls, isEmpty);
      expect(journal.wiped, ['A']);
    });

    test('a plain (non-scoped) journal keeps wipe()', () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.journal.close);
      await h.journal.put(journalSession(idFor(1), seed: 1));
      final hooks = _Hooks();
      expect(await ActivityWipeCoordinator(h.journal).onSignOut(hooks), isTrue);
      expect(hooks.calls, ['offer', 'confirm']);
      expect(await h.journal.list(), isEmpty);
    });
  });

  group('H8: exportAll', () {
    test('the uid changes after the listing: a single AccountChanged result',
        () async {
      await seed('B', [11, 12]);
      await seed('A', [1, 2, 3]);
      journal.onListed = () async => journal.bindUid('B');
      final r = await JournalActivityLocalExport(journal)
          .exportAll(ActivityExportFormat.json);
      expect(r, hasLength(1));
      expect(r.single, isA<ActivityExportAccountChanged>());
      expect(r.whereType<ActivityExportFile>(), isEmpty);
    });

    test('the uid changes during the 2nd per-activity read: a single '
        'AccountChanged result and no file of either account', () async {
      await seed('B', [11, 12]);
      await seed('A', [1, 2, 3]);
      journal.reads = 0;
      journal.onRead = (n) async {
        if (n == 2) await journal.bindUid('B');
      };
      final r = await JournalActivityLocalExport(journal)
          .exportAll(ActivityExportFormat.json);
      expect(r, hasLength(1));
      expect(r.single, isA<ActivityExportAccountChanged>());
    });

    test('unbound during a read is also a change', () async {
      await seed('A', [1, 2]);
      journal.onRead = (n) async {
        if (n == 1) await journal.bindUid(null);
      };
      final r = await JournalActivityLocalExport(journal)
          .exportAll(ActivityExportFormat.json);
      expect(r.single, isA<ActivityExportAccountChanged>());
    });

    test('no change: all files of ONE account, the other account\'s ids are '
        'absent, and the streams are in the output', () async {
      await seed('B', [11, 12]);
      await seed('A', [1, 2, 3]);
      final export = JournalActivityLocalExport(journal);

      final gpx = await export.exportAll(ActivityExportFormat.gpx);
      expect(gpx.whereType<ActivityExportFile>(), hasLength(3));
      expect({for (final f in gpx) f.activityId},
          {idFor(1), idFor(2), idFor(3)});
      for (final f in gpx.cast<ActivityExportFile>()) {
        final xml = utf8.decode(f.bytes);
        expect(RegExp('<trkpt').allMatches(xml).length, 20,
            reason: 'the full GPS route of ${f.activityId}');
      }

      final fit = await export.exportAll(ActivityExportFormat.fit);
      for (final f in fit.cast<ActivityExportFile>()) {
        expect(String.fromCharCodes(f.bytes.sublist(8, 12)), '.FIT');
        expect(f.bytes.length, greaterThan(100));
      }

      final json = await export.exportAll(ActivityExportFormat.json);
      expect({for (final f in json) f.activityId},
          isNot(anyOf(contains(idFor(11)), contains(idFor(12)))));
    });

    test('a plain journal exports as before', () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.journal.close);
      await h.journal.put(journalSession(idFor(1), seed: 1));
      final r = await JournalActivityLocalExport(h.journal)
          .exportAll(ActivityExportFormat.gpx);
      expect(r.single, isA<ActivityExportFile>());
    });
  });
}
