import 'dart:async' show Completer;
import 'dart:io' show Directory, File;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/equipment_identity_telemetry_outbox.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('equipment_identity_telemetry_outbox_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  // Constructs directly against a file in the test's own temp directory --
  // same pattern `photo_directory_test.dart` already uses for this
  // codebase's other file-backed local storage -- rather than through
  // `open()`, which would need a real `path_provider` platform channel.
  FileEquipmentIdentityTelemetryOutbox outboxAt(String fileName) =>
      FileEquipmentIdentityTelemetryOutbox(File('${tempDir.path}/$fileName'));

  group('FileEquipmentIdentityTelemetryOutbox', () {
    test('a successful send never enqueues anything', () async {
      final outbox = outboxAt('outbox.json');

      await outbox.sendOrEnqueue((body) async {}, {'scanId': 'scan-1'});

      expect(await outbox.pendingCount, 0);
    });

    test('a failed send is durably enqueued and never rethrows', () async {
      final outbox = outboxAt('outbox.json');

      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );

      expect(await outbox.pendingCount, 1);
    });

    test('an enqueued report survives a fresh instance pointed at the same file', () async {
      final path = '${tempDir.path}/outbox.json';
      final first = FileEquipmentIdentityTelemetryOutbox(File(path));
      await first.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );

      // Simulates the real app's own lifecycle: the outbox opened once in
      // `main()` survives for the process lifetime, but the durability claim
      // is about the STORAGE, not the object -- so a fresh instance pointed
      // at the same file must see what the first instance wrote.
      final reopened = FileEquipmentIdentityTelemetryOutbox(File(path));
      expect(await reopened.pendingCount, 1);
    });

    test('drainPending retries every queued report and clears successes', () async {
      final outbox = outboxAt('outbox.json');
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-2'},
      );
      expect(await outbox.pendingCount, 2);

      final delivered = <String>[];
      await outbox.drainPending((body) async {
        delivered.add(body['scanId'] as String);
      });

      expect(delivered, ['scan-1', 'scan-2']);
      expect(await outbox.pendingCount, 0);
    });

    test('drainPending keeps only the reports that still fail, in order', () async {
      final outbox = outboxAt('outbox.json');
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-2'},
      );
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-3'},
      );

      await outbox.drainPending((body) async {
        // Only scan-2 succeeds this round -- the network is flaky, not
        // fully recovered.
        if (body['scanId'] != 'scan-2') throw StateError('still offline');
      });

      expect(await outbox.pendingCount, 2);

      final delivered = <String>[];
      await outbox.drainPending((body) async {
        delivered.add(body['scanId'] as String);
      });
      expect(delivered, ['scan-1', 'scan-3']);
      expect(await outbox.pendingCount, 0);
    });

    test('drainPending on an empty outbox never calls send', () async {
      final outbox = outboxAt('outbox.json');

      var calls = 0;
      await outbox.drainPending((body) async => calls++);

      expect(calls, 0);
    });

    test('drainPending when the store file does not exist yet never calls send', () async {
      // No sendOrEnqueue call at all -- the file this outbox points at has
      // never been created, distinct from "created but empty".
      final outbox = outboxAt('never-written.json');

      var calls = 0;
      await outbox.drainPending((body) async => calls++);

      expect(calls, 0);
    });

    test('a corrupt individual entry is skipped without poisoning the rest', () async {
      final path = '${tempDir.path}/outbox.json';
      // The store's top-level shape is a JSON array of entries -- one
      // element here is missing its own `body` key entirely (simulating a
      // future format change/truncated write), the other is well-formed.
      await File(path).writeAsString(
        '[{"id":"bad-1","enqueuedAt":"2026-09-16T00:00:00.000Z"},'
        '{"id":"good-1","body":{"scanId":"scan-good"},"enqueuedAt":"2026-09-16T00:00:00.000Z"}]',
      );
      final outbox = FileEquipmentIdentityTelemetryOutbox(File(path));

      expect(await outbox.pendingCount, 1);

      final delivered = <String>[];
      await outbox.drainPending((body) async {
        delivered.add(body['scanId'] as String);
      });
      expect(delivered, ['scan-good']);
    });

    test('a wholly unparseable store file degrades to empty rather than throwing', () async {
      final path = '${tempDir.path}/outbox.json';
      await File(path).writeAsString('not valid json at all {{{');
      final outbox = FileEquipmentIdentityTelemetryOutbox(File(path));

      expect(await outbox.pendingCount, 0);
    });

    test('a stored entry from before the id field existed is tolerated (backward compatibility)', () async {
      final path = '${tempDir.path}/outbox.json';
      await File(path).writeAsString(
        '[{"body":{"scanId":"scan-legacy"},"enqueuedAt":"2026-09-16T00:00:00.000Z"}]',
      );
      final outbox = FileEquipmentIdentityTelemetryOutbox(File(path));

      final delivered = <String>[];
      await outbox.drainPending((body) async {
        delivered.add(body['scanId'] as String);
      });
      expect(delivered, ['scan-legacy']);
    });

    // GPT-PM BLOCKER, P2.G5-readiness step 3b review round 3, 2026-09-16:
    // `_writeAll` writes the new state to a sibling `.tmp` file and only
    // then atomically renames it over the real store. Stated precisely
    // what this ONE test proves and does not, rather than implying more:
    // it proves `_readAll` never reads `.tmp`, so a leftover incomplete
    // `.tmp` (standing in for what an interrupted write leaves behind)
    // can never be mistaken for real state. It does NOT, by itself, prove
    // the write is atomic -- mutation-checked directly: this exact test
    // still passes unchanged even against a REVERTED, non-atomic
    // implementation that writes straight to `_file` (no `.tmp` involved
    // at all), because `_readAll` ignoring `.tmp` is true either way. The
    // actual atomicity guarantee rests on `dart:io`'s `File.rename`
    // mapping to the platform's own atomic rename primitive (`rename(2)`
    // on POSIX for a same-directory move; the Win32 call Dart's runtime
    // uses is likewise atomic for a same-volume move) -- a platform
    // contract, not something fault-injectable here without a mockable
    // filesystem seam this class does not have. Keeping this test anyway
    // because the invariant it DOES prove is real and worth guarding, not
    // as a substitute for the atomicity claim itself.
    test('a stale/incomplete .tmp file from an interrupted write never corrupts a read of the real store', () async {
      final path = '${tempDir.path}/outbox.json';
      await File(path).writeAsString(
        '[{"id":"old-1","body":{"scanId":"scan-old"},"enqueuedAt":"2026-09-16T00:00:00.000Z"}]',
      );
      // Simulates a write interrupted after the tmp file was partially
      // written but before the rename that would have replaced the real
      // store -- deliberately truncated mid-object, not merely a different
      // valid JSON value, matching what a real interrupted write leaves.
      await File('$path.tmp').writeAsString('[{"id":"new-1","body":{"scanId":"sc');

      final outbox = FileEquipmentIdentityTelemetryOutbox(File(path));
      final delivered = <String>[];
      await outbox.drainPending((body) async {
        delivered.add(body['scanId'] as String);
      });

      expect(delivered, ['scan-old']);
    });

    // GPT-PM MAJOR, P2.G5-readiness step 3b review round 1, 2026-09-16: the
    // design contract's own binding Story DoD requires "no silent drop" from
    // the readiness metric's denominator (`P2_G5_READINESS_SHADOW_TELEMETRY_
    // LIFECYCLE_CONTRACT_2026-09-12.md` §1, §5.3). A LOCAL_FAILURE report
    // evicted here before it ever reaches the server would be gone with no
    // trace anywhere -- unlike the contract's own 8 infrastructure outcomes,
    // which stay excluded-but-counted. This outbox must never silently drop
    // a queued (retryable) report regardless of how many accumulate.
    test('no retryable report is ever silently dropped, well past what an old fixed cap would have allowed', () async {
      final outbox = outboxAt('outbox.json');

      for (var i = 0; i < 250; i++) {
        await outbox.sendOrEnqueue(
          (body) async => throw StateError('offline'),
          {'scanId': 'scan-$i'},
        );
      }

      expect(await outbox.pendingCount, 250);

      final delivered = <String>[];
      await outbox.drainPending((body) async {
        delivered.add(body['scanId'] as String);
      });
      expect(delivered, hasLength(250));
      expect(delivered.toSet(), {for (var i = 0; i < 250; i++) 'scan-$i'});
    });

    // GPT-PM MAJOR, P2.G5-readiness step 3b review round 2, 2026-09-16: once
    // the 200-cap was removed (round 1's fix, above), a report the server
    // will NEVER accept -- a schema-invalid body, surfaced as
    // `invalid-argument` -- would otherwise sit in this now-uncapped queue
    // forever, retried on every cold start/resume with no way to ever drain.
    // `invalid-argument` is the one failure `telemetry_handler.ts` itself
    // documents as genuinely terminal: retrying the identical body cannot
    // ever change the outcome.
    group('terminal (invalid-argument) failures are dropped, not retried', () {
      test('sendOrEnqueue drops a permanently undeliverable report instead of queuing it', () async {
        final outbox = outboxAt('outbox.json');

        await outbox.sendOrEnqueue(
          (body) async => throw FirebaseFunctionsException(code: 'invalid-argument', message: 'bad'),
          {'scanId': 'scan-malformed'},
        );

        expect(await outbox.pendingCount, 0);
      });

      test('a report that turns terminal on a later drain retry is dropped from the queue, not kept', () async {
        final outbox = outboxAt('outbox.json');
        // First failure is retryable -- gets queued normally.
        await outbox.sendOrEnqueue(
          (body) async => throw StateError('offline'),
          {'scanId': 'scan-1'},
        );
        expect(await outbox.pendingCount, 1);

        // On retry, the server now rejects it outright (e.g. a contract
        // change) -- must be dropped, not kept for endless future retries.
        await outbox.drainPending(
          (body) async => throw FirebaseFunctionsException(code: 'invalid-argument', message: 'bad'),
        );

        expect(await outbox.pendingCount, 0);
      });

      test('a genuinely retryable failure (unavailable) is NOT confused with a terminal one', () async {
        final outbox = outboxAt('outbox.json');

        await outbox.sendOrEnqueue(
          (body) async => throw FirebaseFunctionsException(code: 'unavailable', message: 'down'),
          {'scanId': 'scan-1'},
        );

        expect(await outbox.pendingCount, 1);
      });

      test('a mixed drain drops the terminal report and keeps the retryable one queued', () async {
        final outbox = outboxAt('outbox.json');
        await outbox.sendOrEnqueue(
          (body) async => throw StateError('offline'),
          {'scanId': 'scan-terminal'},
        );
        await outbox.sendOrEnqueue(
          (body) async => throw StateError('offline'),
          {'scanId': 'scan-retryable'},
        );
        expect(await outbox.pendingCount, 2);

        await outbox.drainPending((body) async {
          if (body['scanId'] == 'scan-terminal') {
            throw FirebaseFunctionsException(code: 'invalid-argument', message: 'bad');
          }
          throw StateError('still offline');
        });

        expect(await outbox.pendingCount, 1);
        final delivered = <String>[];
        await outbox.drainPending((body) async {
          delivered.add(body['scanId'] as String);
        });
        expect(delivered, ['scan-retryable']);
      });
    });

    // P2.G5-readiness lifecycle contract §6 rule 2: any report whose
    // payloadFingerprint matches what is already stored is a pure no-op.
    // This outbox relies on that server-side guarantee to make blind retry
    // safe -- it never checks whether an earlier attempt actually reached
    // the server, only whether THIS attempt succeeded. Retrying the exact
    // same body twice must therefore be something this outbox is willing to
    // do without any special-casing.
    // Every real call site fires `sendOrEnqueue`/`drainPending` unawaited
    // (`equipment_identity_providers.dart`'s `_sendTelemetryReport`, and both
    // the cold-start and resume drain triggers in `main.dart`), so two calls
    // CAN genuinely overlap -- e.g. two scans fail telemetry in the same
    // burst. Without serializing the read-modify-write against this file,
    // the second call's write (computed from a stale pre-first-call
    // snapshot) would silently clobber the first call's write, losing a
    // report that was never actually sent.
    test('two concurrent failing sendOrEnqueue calls both persist -- neither clobbers the other', () async {
      final outbox = outboxAt('outbox.json');

      // Deliberately NOT awaited between the two calls -- this is what
      // "concurrent" means for two `Future`s sharing an event loop: both
      // start before either finishes.
      final first = outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );
      final second = outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-2'},
      );
      await Future.wait([first, second]);

      expect(await outbox.pendingCount, 2);
    });

    test('a concurrent sendOrEnqueue failure during an in-flight drainPending is not lost', () async {
      final outbox = outboxAt('outbox.json');
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-already-queued'},
      );
      expect(await outbox.pendingCount, 1);

      // A drain whose own retry hangs until released -- simulates a slow
      // network call, giving the concurrent enqueue below a real window to
      // race the drain's read-modify-write instead of relying on scheduling
      // luck.
      final release = Completer<void>();
      final drain = outbox.drainPending((body) async {
        await release.future;
        throw StateError('still offline');
      });

      final concurrentEnqueue = outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-new-failure'},
      );

      release.complete();
      await Future.wait([drain, concurrentEnqueue]);

      final ids = <String>[];
      await outbox.drainPending((body) async {
        ids.add(body['scanId'] as String);
      });
      expect(ids, unorderedEquals(['scan-already-queued', 'scan-new-failure']));
    });

    // The previous test can pass even with a reconcile step that writes back
    // only the ORIGINAL snapshot (ignoring anything added concurrently),
    // because in that scenario nothing in the snapshot succeeds --
    // `drainPending`'s own early return on an empty removal set skips the
    // reconcile write entirely, so a stale-snapshot bug in the reconcile
    // step is never exercised. This test forces that write to actually
    // happen: one report SUCCEEDS on retry (so reconcile runs), while a
    // second, brand-new report is enqueued concurrently, DURING the window
    // the first report's send is still in flight -- proving the reconcile
    // step reads the CURRENT persisted state (picking up the concurrent
    // addition) rather than blindly re-persisting its own outdated snapshot
    // (which would silently erase the concurrent addition).
    test('a report enqueued while a drain is reconciling a successful retry is not erased', () async {
      final outbox = outboxAt('outbox.json');
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-old'},
      );
      expect(await outbox.pendingCount, 1);

      final release = Completer<void>();
      final drain = outbox.drainPending((body) async {
        await release.future;
        // Succeeds this time -- the reconcile step below has something to
        // actually remove, which is what makes the reconcile write happen
        // at all.
      });

      final concurrentEnqueue = outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-concurrent'},
      );
      await concurrentEnqueue;

      release.complete();
      await drain;

      expect(await outbox.pendingCount, 1);
      final ids = <String>[];
      await outbox.drainPending((body) async {
        ids.add(body['scanId'] as String);
      });
      expect(ids, ['scan-concurrent']);
    });

    test('the same body can be sent twice across two independent failures without special-casing', () async {
      final outbox = outboxAt('outbox.json');
      const body = {'scanId': 'scan-1', 'payloadFingerprint': 'fp-1'};

      await outbox.sendOrEnqueue((b) async => throw StateError('offline'), body);
      expect(await outbox.pendingCount, 1);

      var attempts = 0;
      await outbox.drainPending((b) async {
        attempts++;
        throw StateError('still offline');
      });
      await outbox.drainPending((b) async {
        attempts++;
      });

      expect(attempts, 2);
      expect(await outbox.pendingCount, 0);
    });
  });

  group('InMemoryEquipmentIdentityTelemetryOutbox', () {
    test('a successful send never enqueues anything', () async {
      final outbox = InMemoryEquipmentIdentityTelemetryOutbox();

      await outbox.sendOrEnqueue((body) async {}, {'scanId': 'scan-1'});

      expect(outbox.pending, isEmpty);
      expect(await outbox.pendingCount, 0);
    });

    test('a failed send enqueues the exact body, inspectable directly', () async {
      final outbox = InMemoryEquipmentIdentityTelemetryOutbox();

      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );

      expect(outbox.pending, [
        {'scanId': 'scan-1'},
      ]);
    });

    test('drainPending increments drainAttempts and clears successes', () async {
      final outbox = InMemoryEquipmentIdentityTelemetryOutbox();
      await outbox.sendOrEnqueue(
        (body) async => throw StateError('offline'),
        {'scanId': 'scan-1'},
      );

      await outbox.drainPending((body) async {});

      expect(outbox.drainAttempts, 1);
      expect(outbox.pending, isEmpty);
    });

    test('a permanently undeliverable failure is dropped, not enqueued', () async {
      final outbox = InMemoryEquipmentIdentityTelemetryOutbox();

      await outbox.sendOrEnqueue(
        (body) async => throw FirebaseFunctionsException(code: 'invalid-argument', message: 'bad'),
        {'scanId': 'scan-1'},
      );

      expect(outbox.pending, isEmpty);
    });
  });
}
