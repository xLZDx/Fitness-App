// S02 test epic 7b: client consent withdrawal (plan I28, I17; design 9.1).
// Withdrawing stops queued and in-flight uploads before their next network
// step; "delete my cloud streams now" is only OFFERED and, when chosen, sends
// deleteExisting exactly once; not choosing it leaves cloud streams; nothing
// local or in the summary is ever deleted.
import 'dart:async';

import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

void main() {
  late StreamUploadWorld w;
  late FakeSettingsServer settings;
  late InMemoryCloudStreamsConsentStore store;
  late ActivityCloudSettingsClient client;
  late ActivityConsentWithdrawal withdrawal;
  final ids = [idFor(1), idFor(2), idFor(3)];

  setUp(() async {
    w = await StreamUploadWorld.open();
    settings = FakeSettingsServer();
    // Remediation I2: the store must be bound to an account to persist.
    store = InMemoryCloudStreamsConsentStore(boundUid: 'uid');
    client = ActivityCloudSettingsClient(
        call: settings.call, currentUid: storeUid(store), store: store);
    w.uploader = w.makeUploader(consentView: client);
    withdrawal = ActivityConsentWithdrawal(settings: client, uploader: w.uploader);
    await client.grant();
    for (var i = 0; i < ids.length; i++) {
      await w.h.journal.put(journalSession(ids[i], seed: i));
    }
    await w.summarySync();
  });

  tearDown(() async => w.dispose());

  test('withdraw stops queued entries: a run in progress sends nothing more '
      'after the user withdraws', () async {
    final gate = Completer<void>();
    w.cloud.duringCreate = (n, _) => gate.future;
    final run = w.uploader.runPending();
    await Future<void>.delayed(Duration.zero);
    expect(w.cloud.creates, hasLength(1), reason: 'first entry is in flight');

    await withdrawal.withdraw();
    gate.complete();
    await run;

    expect(w.cloud.creates, hasLength(1), reason: 'queued entries never created');
    expect(w.cloud.puts, isEmpty, reason: 'in-flight run stopped before the PUT');
    expect(w.cloud.commits, isEmpty);
    expect(w.cloud.stored, isEmpty);
  });

  test('withdraw while the PUT is in flight: no commit follows', () async {
    final gate = Completer<void>();
    w.cloud.duringPut = (n, _) => gate.future;
    final run = w.uploader.uploadEntry(ids[0]);
    await Future<void>.delayed(Duration.zero);
    expect(w.cloud.puts, hasLength(1));
    await withdrawal.withdraw();
    gate.complete();
    expect(await run, StreamUploadOutcome.cancelled);
    expect(w.cloud.commits, isEmpty);
  });

  test('withdraw during the backoff: the next attempt is not made', () async {
    w.cloud.createFault = (_) => const StreamUploadTransient();
    final cancelling = ActivityStreamUploader(
      journal: w.h.journal,
      callables: w.cloud,
      consent: client,
      put: w.cloud.put,
      flags: w.flags,
      now: w.h.clock.call,
      delay: (d) async => withdrawal.withdraw(),
    );
    withdrawal = ActivityConsentWithdrawal(settings: client, uploader: cancelling);
    expect(await cancelling.uploadEntry(ids[0]), StreamUploadOutcome.cancelled);
    expect(w.cloud.creates, hasLength(1));
  });

  test('after withdrawal nothing is sent, also from a fresh run and after a '
      'restart of the app (consent is read from the store)', () async {
    await withdrawal.withdraw();
    await w.uploader.runPending();
    expect(w.cloud.log, isEmpty);

    await w.restartApp();
    final reloaded = ActivityCloudSettingsClient(
        call: settings.call, currentUid: storeUid(store), store: store);
    await reloaded.load();
    expect(reloaded.state, CloudStreamsConsent.withdrawn);
    final fresh = w.makeUploader(consentView: reloaded);
    await fresh.runPending();
    expect(w.cloud.log, isEmpty);
  });

  test('withdraw flips the local cache first: a failing server call still '
      'stops uploads, the error is surfaced, and a retry is idempotent',
      () async {
    settings.fault = (n) => n == 2 ? StateError('offline') : null;
    await expectLater(withdrawal.withdraw(), throwsStateError);
    expect(client.state, CloudStreamsConsent.withdrawn);
    await w.uploader.runPending();
    expect(w.cloud.log, isEmpty);
    await withdrawal.withdraw();
    expect(client.state, CloudStreamsConsent.withdrawn);
  });

  test('withdraw sends granted:false with the version and NO deleteExisting; '
      'the delete option is offered', () async {
    final res = await withdrawal.withdraw();
    expect(res.offerDeleteCloudStreams, isTrue);
    final req = settings.requests.last['cloudStreams'] as Map;
    expect(req['granted'], isFalse);
    expect(req['version'], kCloudStreamsConsentVersion);
    expect(req.containsKey('deleteExisting'), isFalse);
    expect(settings.deleteRequests, isEmpty);
  });

  group('delete my cloud streams now (I28)', () {
    setUp(() async {
      await w.uploader.runPending();
      expect(w.cloud.stored.keys, unorderedEquals(ids));
      settings.cloudStreams.addAll(ids);
    });

    test('not chosen: no deleteExisting is ever sent and the cloud streams '
        'stay', () async {
      await withdrawal.withdraw();
      expect(settings.deleteRequests, isEmpty);
      expect(settings.cloudStreams, unorderedEquals(ids));
      expect(w.cloud.stored.keys, unorderedEquals(ids));
    });

    test('chosen: exactly one request with deleteExisting, and the cloud '
        'streams are removed', () async {
      await withdrawal.withdraw();
      await withdrawal.deleteCloudStreamsNow();
      expect(settings.deleteRequests, hasLength(1));
      final cs = settings.deleteRequests.single['cloudStreams'] as Map;
      expect(cs['granted'], isFalse);
      expect(cs['deleteExisting'], isTrue);
      expect(settings.cloudStreams, isEmpty);
    });

    test('chosen twice or double-tapped: still exactly one request', () async {
      await withdrawal.withdraw();
      await Future.wait([
        withdrawal.deleteCloudStreamsNow(),
        withdrawal.deleteCloudStreamsNow(),
      ]);
      await withdrawal.deleteCloudStreamsNow();
      expect(settings.deleteRequests, hasLength(1));
    });

    test('a failed delete may be retried; after success it is not repeated',
        () async {
      await withdrawal.withdraw();
      settings.fault = (n) => StateError('offline');
      await expectLater(withdrawal.deleteCloudStreamsNow(), throwsStateError);
      settings.fault = null;
      await withdrawal.deleteCloudStreamsNow();
      await withdrawal.deleteCloudStreamsNow();
      expect(settings.deleteRequests, hasLength(2),
          reason: 'one failed attempt (recorded) and one successful');
      expect(settings.cloudStreams, isEmpty);
    });

    test('nothing local or in the summary is deleted by either path', () async {
      final before = {
        for (final id in ids) id: (await w.h.journal.read(id))!,
      };
      final docs = {for (final e in w.backend.docs.entries) e.key: {...e.value}};
      await withdrawal.withdraw();
      await withdrawal.deleteCloudStreamsNow();

      expect((await w.h.journal.list()).map((e) => e.id), unorderedEquals(ids));
      for (final id in ids) {
        final after = (await w.h.journal.read(id))!;
        expect(after.generation, before[id]!.generation, reason: 'no write');
        expect(streamsOf(after.session), streamsOf(before[id]!.session));
        expect(after.state.syncState, before[id]!.state.syncState);
      }
      expect(w.backend.docs, docs);
      expect(w.backend.tombstones, isEmpty);
    });
  });

  test('resume lifts the cancel: after a re-grant uploads work again',
      () async {
    await withdrawal.withdraw();
    await client.grant();
    await w.uploader.runPending();
    expect(w.cloud.log, isEmpty, reason: 'cancelled until resume()');
    w.uploader.resume();
    await w.uploader.runPending();
    expect(w.cloud.creates, isNotEmpty);
  });
}
