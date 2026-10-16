// S02-02 I09, I10, I25: wipe on account deletion, on relaunch with an auth
// failure, and the sign-out rules of design 3.5.
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';

class _Hooks implements ActivitySignOutHooks {
  _Hooks(this.confirm, {this.onOffer});

  final bool confirm;
  final Future<void> Function()? onOffer;
  final List<String> calls = [];
  SignOutAssessment? seen;

  @override
  Future<void> offerExport(SignOutAssessment a) async {
    calls.add('offerExport');
    seen = a;
    await onOffer?.call();
  }

  @override
  Future<bool> confirmWipe(SignOutAssessment a) async {
    calls.add('confirmWipe');
    return confirm;
  }
}

Future<void> seedSideFiles(JournalHarness h) async {
  await h.writeText('sources/garmin.cursor.json', '{"cursor":1}');
  await h.writeText('sources/queue-1.json', '{"queued":true}');
  await h.writeText('quarantine/rejected-1.json', '{"raw":1}');
}

/// True when no activity data remains. An EMPTY index.jsonl written by the
/// recovery pass is not data.
Future<bool> noDataLeft(JournalHarness h) async {
  for (final d in ['journal', 'sources', 'quarantine']) {
    for (final e in (await h.snapshot(d)).entries) {
      if (e.key == 'journal/index.jsonl' &&
          e.value == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') {
        continue;
      }
      return false;
    }
    for (final n in await h.names(d)) {
      if (n != 'index.jsonl') return false;
    }
  }
  return true;
}

void main() {
  late JournalHarness h;
  ActivityWipeCoordinator wipe() => ActivityWipeCoordinator(h.journal);

  setUp(() async {
    h = JournalHarness.memory();
    await h.open();
  });

  tearDown(() => h.dispose());

  Future<void> seed({JournalSyncState state = JournalSyncState.synced}) async {
    await h.journal.put(journalSession(idFor(1), seed: 1), syncState: state);
    await h.journal.put(journalSession(idFor(2), seed: 2), syncState: state);
    await seedSideFiles(h);
    await h.journal.delete(idFor(2)); // a tombstone is data too
  }

  group('I09 wipe on account deletion', () {
    test('account deletion wipes journal, sources, quarantine, queue files and '
        'the key with no prompt and no export offer', () async {
      await seed();
      expect(await noDataLeft(h), isFalse, reason: 'precondition: data exists');
      expect(await h.keys.loadKey(), isNotNull);

      await wipe().onAccountDeleted();

      expect(await noDataLeft(h), isTrue);
      expect(await h.journal.list(), isEmpty);
      expect(await h.journal.listTombstones(), isEmpty);
      expect(await h.keys.loadKey(), isNull, reason: 'the key is forgotten');
      expect((await h.journal.assessSignOut()).entryCount, 0);
    });

    test('nothing comes back after a restart, and the journal is usable again '
        'with a new key', () async {
      await seed();
      await wipe().onAccountDeleted();
      await h.restart();
      expect(await h.listIds(), isEmpty);
      expect(await noDataLeft(h), isTrue);
      await h.journal.put(journalSession(idFor(5), seed: 5));
      final e = (await h.journal.read(idFor(5)))!;
      expect(e.streamLost, isFalse);
    });

    test('a confirmed sign-out wipes everything', () async {
      await seed();
      final hooks = _Hooks(true);
      expect(await wipe().onSignOut(hooks), isTrue);
      expect(await noDataLeft(h), isTrue);
    });
  });

  group('I10 relaunch with an auth failure wipes', () {
    test('no valid session for the stored uid / user-not-found: wipe without a '
        'prompt', () async {
      await seed();
      await wipe().onAuthFailureAtLaunch();
      expect(await noDataLeft(h), isTrue);
      expect(await h.keys.loadKey(), isNull);
      await h.restart();
      expect(await h.listIds(), isEmpty);
    });

    test('control: a start WITHOUT the auth failure keeps the journal', () async {
      await seed();
      await h.restart();
      expect(await h.listIds(), [idFor(1)]);
      expect(await noDataLeft(h), isFalse);
    });
  });

  group('I25 sign-out with unsynced data (design 3.5)', () {
    final cases = <String, Future<void> Function()>{
      '(a) all entries synced and uploadable': () async {
        await h.journal.put(journalSession(idFor(1)), syncState: JournalSyncState.synced);
        await h.journal.put(journalSession(idFor(2), seed: 2),
            syncState: JournalSyncState.synced);
      },
      '(b) one entry with a heart-rate stream': () async {
        await h.journal.put(journalSession(idFor(1), withGps: false),
            syncState: JournalSyncState.synced);
      },
      '(c) one with laps and provenance only on the device': () async {
        await h.journal.put(journalSession(idFor(1), withGps: false, withHr: false),
            syncState: JournalSyncState.synced);
      },
      '(d) one stream while the cloud flag is off (never synced)': () async {
        await h.journal.put(journalSession(idFor(1)));
      },
      '(e) one upload_failed entry': () async {
        await h.journal.put(journalSession(idFor(1)),
            syncState: JournalSyncState.uploadFailed);
      },
    };

    for (final c in cases.entries) {
      test('${c.key}: warns, offers export first, a declined prompt keeps '
          'every file, a confirmed one wipes', () async {
        await c.value();
        await seedSideFiles(h);
        final before = {
          ...await h.snapshot('journal'),
          ...await h.snapshot('sources'),
          ...await h.snapshot('quarantine'),
        };
        final assessment = await h.journal.assessSignOut();
        expect(assessment.requiresWarning, isTrue,
            reason: 'a non-empty journal always warns, even when all is synced');

        // Declined.
        final no = _Hooks(false, onOffer: () async {
          expect(await noDataLeft(h), isFalse,
              reason: 'the export is offered BEFORE anything is deleted');
        });
        expect(await wipe().onSignOut(no), isFalse);
        expect(no.calls, ['offerExport', 'confirmWipe']);
        expect({
          ...await h.snapshot('journal'),
          ...await h.snapshot('sources'),
          ...await h.snapshot('quarantine'),
        }, before, reason: 'declining leaves every file intact');
        expect(await h.keys.loadKey(), isNotNull);
        await h.restart();
        final e = (await h.journal.read(idFor(1)))!;
        expect(e.streamLost, isFalse, reason: 'and the key still opens the stream');

        // Confirmed.
        final yes = _Hooks(true);
        expect(await wipe().onSignOut(yes), isTrue);
        expect(yes.calls, ['offerExport', 'confirmWipe']);
        expect(yes.seen!.entryCount, greaterThan(0));
        expect(await noDataLeft(h), isTrue);
      });
    }

    test('(f) an empty journal signs out without any prompt or export offer',
        () async {
      final hooks = _Hooks(false);
      expect((await h.journal.assessSignOut()).requiresWarning, isFalse);
      expect(await wipe().onSignOut(hooks), isTrue);
      expect(hooks.calls, isEmpty);
    });

    test('a journal holding only tombstones counts as empty (nothing device-only)',
        () async {
      await h.journal.put(journalSession(idFor(1)));
      await h.journal.delete(idFor(1));
      final a = await h.journal.assessSignOut();
      expect(a.entryCount, 0);
      expect(a.requiresWarning, isFalse);
    });

    test('unsynced and stream-lost counts are reported', () async {
      await h.journal.put(journalSession(idFor(1)), syncState: JournalSyncState.synced);
      await h.journal.put(journalSession(idFor(2), seed: 2));
      await h.deleteRawFile(h.gen(idFor(2), 2, 'streams.bin'));
      await h.restart();
      final a = await h.journal.assessSignOut();
      expect([a.entryCount, a.unsyncedCount, a.streamLostCount], [2, 1, 1]);
    });

    test('the key store wipe is best effort and reaches the secure storage',
        () async {
      final storage = FakeJournalSecureStorage();
      h.keys = SecureStorageJournalKeyProvider(storage: storage);
      await h.restart();
      await h.journal.put(journalSession(idFor(1)));
      expect(storage.values, isNotEmpty);
      await wipe().onAccountDeleted();
      expect(storage.values, isEmpty);
      expect(storage.deletes, 1);
    });
  });
}
