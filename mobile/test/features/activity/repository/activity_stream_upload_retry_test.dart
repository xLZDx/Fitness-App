// S02 test epic 7b: client retry policy (plan I16 neighbours, I17, I27; design
// 5.2 item 4 as pinned by plan row I27): at most 5 attempts per run,
// deterministic exponential delays with no jitter, a 10 minute budget on the
// injected clock, restart always re-uploads (never resumes at commit, never
// resumes a half-done PUT), upload_failed after the cap and no hot loop.
//
// The server and the clock are fakes (support/stream_upload_world.dart); the
// journal is the real file journal, so "restart" reads what is on disk.
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

const _expectedDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
];

void main() {
  late StreamUploadWorld w;
  final id = idFor(1);

  setUp(() async {
    w = await StreamUploadWorld.open();
    await w.h.journal.put(journalSession(id));
    await w.summarySync();
  });

  tearDown(() async => w.dispose());

  Object transient(int _) => const StreamUploadTransient();

  group('attempts and delays', () {
    test('create keeps failing: exactly 5 attempts, delays 1 s 2 s 4 s 8 s, then '
        'upload_failed with the stream still pending', () async {
      w.cloud.createFault = transient;
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.failed);
      expect(w.cloud.creates, hasLength(5));
      expect(w.delays, _expectedDelays);
      expect(w.cloud.log, [
        'create', 'delay', 'create', 'delay', 'create', 'delay', 'create',
        'delay', 'create',
      ], reason: 'no delay after the last attempt');
      final st = await w.stateOf(id);
      expect(st.syncState, JournalSyncState.uploadFailed);
      expect(st.streamUploadPending, isTrue);
    });

    for (final stage in ['put status 500', 'put transport error', 'commit transient']) {
      test('$stage on every attempt: 5 attempts, each one a NEW upload, '
          'commit only ever with the upload id of its own create', () async {
        switch (stage) {
          case 'put status 500':
            w.cloud.putStatus = (_) => 500;
          case 'put transport error':
            w.cloud.putFault = (_) => Exception('connection reset');
          default:
            w.cloud.commitFault = transient;
        }
        final out = await w.uploader.uploadEntry(id);
        expect(out, StreamUploadOutcome.failed);
        expect(w.cloud.creates, hasLength(5));
        expect(w.cloud.puts, hasLength(5));
        expect({for (final p in w.cloud.puts) p.uploadId}, hasLength(5),
            reason: 'every attempt asks for a fresh signed URL');
        expect(w.delays, _expectedDelays);
        for (final c in w.cloud.commits) {
          expect(c.uploadId, 'upl${c.n}',
              reason: 'commit n belongs to create n');
        }
        expect(w.cloud.commits.length, stage == 'commit transient' ? 5 : 0);
        expect(w.cloud.stored, isEmpty);
        expect((await w.stateOf(id)).syncState, JournalSyncState.uploadFailed);
      });
    }

    for (final okAt in [2, 3, 5]) {
      test('success on attempt $okAt: $okAt creates, the first ${okAt - 1} '
          'delays, uploaded and marked, summary state untouched', () async {
        w.cloud.createFault = (n) => n < okAt ? const StreamUploadTransient() : null;
        final out = await w.uploader.uploadEntry(id);
        expect(out, StreamUploadOutcome.uploaded);
        expect(w.cloud.creates, hasLength(okAt));
        expect(w.delays, _expectedDelays.take(okAt - 1).toList());
        final st = await w.stateOf(id);
        expect(st.streamUploadPending, isFalse);
        expect(st.syncState, JournalSyncState.synced);
        expect(w.cloud.stored, contains(id));
      });
    }

    test('a refusal at commit is not retried', () async {
      w.cloud.commitFault = (_) => const StreamUploadRefused('superseded');
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.refused);
      expect(w.cloud.creates, hasLength(1));
      expect(w.delays, isEmpty);
      expect((await w.stateOf(id)).streamUploadPending, isTrue);
    });

    test('no jitter: two runs (two entries, two uploader instances) ask for the '
        'identical delays', () async {
      final id2 = idFor(2);
      await w.h.journal.put(journalSession(id2, seed: 2));
      await w.summarySync();
      w.cloud.createFault = transient;

      await w.uploader.uploadEntry(id);
      final first = List.of(w.delays);
      w.delays.clear();
      final second = w.makeUploader();
      await second.uploadEntry(id2);

      expect(first, _expectedDelays);
      expect(w.delays, first);
    });

    test('the retry sends the same bytes every time (hash is stable)', () async {
      w.cloud.putStatus = (n) => n < 3 ? 503 : 200;
      await w.uploader.uploadEntry(id);
      expect(w.cloud.puts, hasLength(3));
      expect({for (final c in w.cloud.creates) c.sha}, hasLength(1));
      expect(w.cloud.puts[0].body, w.cloud.puts[2].body);
    });
  });

  group('10 minute budget on the injected clock', () {
    test('slow attempts: the third attempt is the last because the next delay '
        'would pass the budget; no attempt starts after the budget', () async {
      w.cloud.createFault = transient;
      w.cloud.createTakes = const Duration(minutes: 4);
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.failed);
      expect(w.cloud.creates, hasLength(3));
      expect(w.delays, _expectedDelays.take(2).toList());
      final t0 = w.cloud.creates.first.at;
      for (final c in w.cloud.creates) {
        expect(c.at.difference(t0), lessThanOrEqualTo(const Duration(minutes: 10)));
      }
      expect((await w.stateOf(id)).syncState, JournalSyncState.uploadFailed);
    });

    test('one attempt that eats the whole budget: no second attempt starts at '
        'or after the budget', () async {
      w.cloud.createFault = transient;
      w.cloud.createTakes = const Duration(minutes: 9, seconds: 59);
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.failed);
      expect(w.cloud.creates, hasLength(1));
    });

    test('fast failures never exceed 5 attempts even with plenty of budget '
        '(total fake time of the delays is 15 s, far below 10 minutes)',
        () async {
      w.cloud.createFault = transient;
      final start = w.h.clock.now;
      await w.uploader.uploadEntry(id);
      expect(w.h.clock.now.difference(start), const Duration(seconds: 15));
    });
  });

  group('after the cap: upload_failed, never a hot loop', () {
    test('upload_failed is on disk and the id is not retried for an hour of fake '
        'time within the same app start', () async {
      w.cloud.createFault = transient;
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(5));
      final rec = await w.h.recordJson(id, (await w.h.generations(id)).last);
      expect((rec['state'] as Map)['syncState'], 'upload_failed');

      for (var i = 0; i < 12; i++) {
        w.h.clock.advance(const Duration(minutes: 5));
        await w.uploader.runPending();
      }
      expect(w.cloud.creates, hasLength(5),
          reason: 'one run per app start; an hour later nothing more');
      expect(w.delays, _expectedDelays, reason: 'no further backoff either');
    });

    test('the next app start retries it, once more up to 5 attempts, and a '
        'healed server then stores it', () async {
      w.cloud.createFault = transient;
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(5));

      await w.restartApp();
      await w.summarySync();
      expect(w.backend.applied, 1, reason: 'the summary is not re-written');
      w.cloud.createFault = null;
      await w.uploader.runPending();

      expect(w.cloud.creates, hasLength(6));
      expect(w.cloud.stored, contains(id));
      expect((await w.stateOf(id)).streamUploadPending, isFalse);
    });

    test('a start that fails again is again bounded at 5 attempts', () async {
      w.cloud.createFault = transient;
      await w.uploader.runPending();
      await w.restartApp();
      await w.uploader.runPending();
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(10));
    });

    test('the cap never overwrites a sync_conflict state', () async {
      await w.h.journal.updateSyncState(id, JournalSyncState.syncConflict);
      w.cloud.createFault = transient;
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.failed);
      expect((await w.stateOf(id)).syncState, JournalSyncState.syncConflict);
    });

    test('stale generation: an edit during the backoff keeps the new pending '
        'state; the stale failure must not overwrite it', () async {
      w.cloud.createFault = transient;
      var edited = false;
      // The edit happens from the uploader's delay seam (between attempts).
      final delaying = ActivityStreamUploader(
        journal: w.h.journal,
        callables: w.cloud,
        consent: w.consent,
        put: w.cloud.put,
        flags: w.flags,
        now: w.h.clock.call,
        delay: (d) async {
          if (!edited) {
            edited = true;
            await w.h.journal.put(journalSession(id, seed: 6));
          }
          w.h.clock.advance(d);
        },
      );
      final out = await delaying.uploadEntry(id);
      expect(out, StreamUploadOutcome.failed);
      final st = await w.stateOf(id);
      expect(st.syncState, JournalSyncState.pending,
          reason: 'the edit reset the state; the stale failure must not win');
      expect(st.streamUploadPending, isTrue);
    });
  });

  group('restart never resumes: nothing but the journal state survives', () {
    test('killed after the PUT completed and before commit: the restart '
        'creates and PUTs again and commits ONLY its own upload id', () async {
      w.cloud.duringCommit = (n, _) async {
        if (n == 1) throw KilledMidUpload();
      };
      final lastGen = (await w.h.generations(id)).last;
      final recordBefore = await w.h.recordJson(id, lastGen);
      await expectLater(
          w.uploader.uploadEntry(id), throwsA(isA<KilledMidUpload>()));
      expect(w.cloud.puts.single.completed, isTrue,
          reason: 'precondition: the PUT had completed');
      expect((await w.h.generations(id)).last, lastGen,
          reason: 'the killed run wrote no generation (no uploading line)');
      expect(await w.h.recordJson(id, lastGen), recordBefore);
      expect((await w.h.snapshot()).keys.where((k) => k.contains('upl')), isEmpty,
          reason: 'no upload id or attempt count was written anywhere');

      await w.restartApp();
      await w.uploader.runPending();

      expect(w.cloud.log, [
        'create', 'put', 'commit', // killed
        'create', 'put', 'commit', // restart: a whole new upload
      ]);
      expect(w.cloud.creates, hasLength(2));
      expect(w.cloud.commits.first.uploadId, 'upl1');
      expect(w.cloud.commits.last.uploadId, 'upl2',
          reason: 'resuming at commit would send upl1 again');
      expect(w.cloud.stored, contains(id));
      expect((await w.stateOf(id)).streamUploadPending, isFalse);
    });

    test('killed in the middle of the PUT: the restart does not commit the old '
        'upload id and uploads the whole object again', () async {
      w.cloud.duringPut = (n, put) async {
        if (n == 1) throw KilledMidUpload();
      };
      await expectLater(
          w.uploader.uploadEntry(id), throwsA(isA<KilledMidUpload>()));
      expect(w.cloud.puts.single.completed, isFalse);
      expect(w.cloud.commits, isEmpty);

      await w.restartApp();
      w.cloud.duringPut = null;
      await w.uploader.runPending();

      expect(w.cloud.creates, hasLength(2), reason: 'a new upload, not a resume');
      expect(w.cloud.puts, hasLength(2));
      expect(w.cloud.puts.last.completed, isTrue);
      expect(w.cloud.puts.last.body, w.cloud.puts.first.body);
      expect(w.cloud.commits.map((c) => c.uploadId), ['upl2']);
      expect(w.cloud.stored, contains(id));
    });

    test('killed before the PUT (after create): the restart creates again',
        () async {
      w.cloud.duringCreate = (n, _) async {
        if (n == 1) throw KilledMidUpload();
      };
      await expectLater(
          w.uploader.uploadEntry(id), throwsA(isA<KilledMidUpload>()));
      await w.restartApp();
      w.cloud.duringCreate = null;
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(2));
      expect(w.cloud.puts, hasLength(1));
      expect(w.cloud.commits.map((c) => c.uploadId), ['upl2']);
    });

    test('the same uploader instance does not remember a completed PUT either: '
        'a second run after a failed commit re-uploads', () async {
      w.cloud.commitFault = (n) => n == 1 ? const StreamUploadTransient() : null;
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.uploaded);
      expect(w.cloud.log, [
        'create', 'put', 'commit', 'delay', 'create', 'put', 'commit',
      ]);
      expect(w.cloud.commits.map((c) => c.uploadId), ['upl1', 'upl2']);
    });
  });
}
