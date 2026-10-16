// S02 test epic 7b: client stream upload (plan I15, I16, I17 and neighbours:
// the real sequence "summary sync first, then the stream upload", the create ->
// PUT -> commit order, the hash of the PUT bytes, the flag wiring).
//
// Oracles are the plan rows and design 5.1, 5.2 and 9, not the uploader code.
import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_stream_payload.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_cloud_settings_client.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/journal_harness.dart';
import '../../../support/stream_upload_world.dart';

/// Heart-rate data in every place a client could leak it: the HR stream (with
/// the plan sentinel 173.25), a lap average and a contributed-field name.
ActivitySession hrRichSession(String id) {
  final offs = [for (var i = 0; i < 10; i++) i * 1000];
  final start = DateTime.utc(2026, 5, 1, 6);
  return ActivitySession(
    id: id,
    sport: SportType.running,
    startUtc: start,
    endUtc: start.add(const Duration(minutes: 30)),
    movingTimeS: 1700,
    summary: ActivitySummary(distanceM: 4800),
    streams: {
      StreamKind.gps: SampleStream.checked(
        kind: StreamKind.gps,
        sourceId: 'app',
        offsetsMs: offs,
        lats: [for (var i = 0; i < 10; i++) (10000000000 + i * 50000 + 7351) / 1e10],
        lons: [for (var i = 0; i < 10; i++) -27.5 + i * 0.0001],
        accuracies: [for (var i = 0; i < 10; i++) 4.5],
      ),
      StreamKind.altitude: SampleStream.checked(
        kind: StreamKind.altitude,
        sourceId: 'app',
        offsetsMs: offs,
        values: [for (var i = 0; i < 10; i++) 120.5 + i],
      ),
      StreamKind.heartRate: SampleStream.checked(
        kind: StreamKind.heartRate,
        sourceId: 'app',
        offsetsMs: offs,
        values: [for (var i = 0; i < 10; i++) i == 5 ? 173.25 : 150.5 + i],
      ),
      StreamKind.cadence: SampleStream.checked(
        kind: StreamKind.cadence,
        sourceId: 'app',
        offsetsMs: offs,
        values: [for (var i = 0; i < 10; i++) 80.5 + i],
      ),
    },
    laps: const [
      Lap(
        index: 0,
        kind: LapKind.auto,
        startOffsetS: 0,
        durationS: 600,
        distanceM: 1000,
        avgHrBpm: 173.25,
      ),
    ],
    provenance: [
      SourceRecord(
        sourceId: 'app',
        sourceKind: SourceKind.companionApp,
        importedAt: DateTime.utc(2026, 5, 1, 7),
        externalId: 'e1',
        fieldsContributed: const ['distanceM', 'avgHrBpm', 'heartRate'],
      ),
    ],
  );
}

String gunzipText(Uint8List body) => utf8.decode(GZipCodec().decode(body));

void main() {
  late StreamUploadWorld w;
  final id = idFor(1);

  tearDown(() async => w.dispose());

  /// Journal put, then the real summary sync pass: the entry is `synced`.
  Future<void> seedSynced(String activityId, {int seed = 0}) async {
    await w.h.journal.put(journalSession(activityId, seed: seed));
    await w.summarySync();
  }

  group('I15 flag OFF: no upload path', () {
    test('flag off and consent granted: no callable, no PUT, journal untouched',
        () async {
      w = await StreamUploadWorld.open(flagOn: false, granted: true);
      await seedSynced(id);
      final before = await w.h.snapshot();

      await w.uploader.runPending();
      final direct = await w.uploader.uploadEntry(id);

      expect(direct, StreamUploadOutcome.skipped);
      expect(w.cloud.log, isEmpty);
      expect(w.cloud.creates, isEmpty);
      expect(await w.h.snapshot(), before, reason: 'no generation written');
    });

    test('an uploader built without a flags argument is OFF in a default build',
        () async {
      // The default is the compile-time flag; the contract says OFF unless
      // --dart-define=ACTIVITY_CLOUD_STREAMS=true.
      expect(ActivityFlags.compileTime.cloudSync, isFalse);
      w = await StreamUploadWorld.open(flagOn: true, granted: true);
      await seedSynced(id);
      final defaulted = ActivityStreamUploader(
        journal: w.h.journal,
        callables: w.cloud,
        consent: w.consent,
        put: w.cloud.put,
        now: w.h.clock.call,
      );
      await defaulted.runPending();
      expect(w.cloud.log, isEmpty);
    });

    test('same journal, flag ON: the upload happens (control for the OFF tests)',
        () async {
      w = await StreamUploadWorld.open(flagOn: true, granted: true);
      await seedSynced(id);
      await w.uploader.runPending();
      expect(w.cloud.log, ['create', 'put', 'commit']);
    });
  });

  group('I17 consent missing or revoked: no upload', () {
    late FakeSettingsServer settings;
    late InMemoryCloudStreamsConsentStore store;
    late ActivityCloudSettingsClient client;

    Future<void> setUpClient({CloudStreamsConsent stored = CloudStreamsConsent.unknown}) async {
      w = await StreamUploadWorld.open(flagOn: true, granted: true);
      settings = FakeSettingsServer();
      // Remediation I2: an unbound store makes grant/withdraw throw.
      store = InMemoryCloudStreamsConsentStore(boundUid: 'uid');
      await store.write(stored);
      client = ActivityCloudSettingsClient(
          call: settings.call, currentUid: storeUid(store), store: store);
      w.uploader = w.makeUploader(consentView: client);
      await seedSynced(id);
    }

    test('consent never recorded (unknown): nothing is sent', () async {
      await setUpClient();
      await client.load();
      await w.uploader.runPending();
      expect(client.isGranted, isFalse);
      expect(w.cloud.log, isEmpty);
    });

    test('granted in the store but not loaded yet: still unknown, nothing sent; '
        'after load it uploads', () async {
      await setUpClient(stored: CloudStreamsConsent.granted);
      await w.uploader.runPending();
      expect(w.cloud.log, isEmpty, reason: 'unknown until load()');
      await client.load();
      await w.uploader.runPending();
      expect(w.cloud.log, ['create', 'put', 'commit']);
    });

    test('withdrawn in the store: nothing is sent', () async {
      await setUpClient(stored: CloudStreamsConsent.withdrawn);
      await client.load();
      await w.uploader.runPending();
      expect(w.cloud.log, isEmpty);
    });

    test('grant whose server call fails: the cache does not flip, nothing sent',
        () async {
      await setUpClient();
      settings.fault = (_) => StateError('offline');
      await expectLater(client.grant(), throwsStateError);
      expect(client.state, CloudStreamsConsent.unknown);
      await w.uploader.runPending();
      expect(w.cloud.log, isEmpty);
    });

    test('grant then withdraw: the second entry is never sent', () async {
      await setUpClient();
      await client.grant();
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(1));
      await client.withdraw();
      await seedSynced(idFor(2), seed: 3);
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(1), reason: 'no create after withdrawal');
    });

    test('revoked while the run is between entries: the next entry is not sent',
        () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await seedSynced(idFor(2), seed: 2);
      w.cloud.duringCommit = (n, _) async => w.consent.granted = false;
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(1));
    });

    test('consent is per account: another uid starts unknown', () async {
      SharedPreferences.setMockInitialValues({});
      final scoped = AccountScopedConsentStore();
      await scoped.signIn('uidA');
      await scoped.write(CloudStreamsConsent.granted);
      expect(await scoped.read(), CloudStreamsConsent.granted);
      await scoped.signIn('uidB');
      expect(await scoped.read(), CloudStreamsConsent.unknown);
      await scoped.signIn('uidA');
      expect(await scoped.read(), CloudStreamsConsent.granted);
      w = await StreamUploadWorld.open();
    });

    test('before sign-in the scoped store is unknown and a write THROWS '
        '(never dropped silently, remediation H)', () async {
      SharedPreferences.setMockInitialValues({});
      final scoped = AccountScopedConsentStore();
      await expectLater(
          scoped.write(CloudStreamsConsent.granted), throwsStateError);
      expect(await scoped.read(), CloudStreamsConsent.unknown);
      expect(scoped.boundUid, isNull);
      w = await StreamUploadWorld.open();
    });
  });

  group('happy path: order, hash, closed payload', () {
    test('create -> PUT -> commit once, in order, with the announced hash and '
        'the upload id of that create', () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await w.uploader.runPending();

      expect(w.cloud.log, ['create', 'put', 'commit']);
      final create = w.cloud.creates.single;
      final put = w.cloud.puts.single;
      final commit = w.cloud.commits.single;
      expect(create.activityId, id);
      expect(create.bytes, put.body.length);
      expect(create.sha, FakeStreamCloud.shaOf(put.body),
          reason: 'contentSha256 is the hash of the exact PUT bytes');
      expect(put.url.toString(), contains('/upl1'));
      expect(put.headers['content-type'], 'application/gzip');
      expect(commit.activityId, id);
      expect(commit.uploadId, put.uploadId);
      expect(w.cloud.stored[id], put.body, reason: 'the cloud holds what was PUT');
      expect(w.delays, isEmpty);
    });

    test('the PUT body is gzip of a closed payload; positive control: GPS is in '
        'it', () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await w.uploader.runPending();
      final text = gunzipText(w.cloud.puts.single.body);
      final doc = jsonDecode(text) as Map<String, dynamic>;
      expect(doc.keys.toSet(), {'schema', 'kinds', 'meta'});
      final kinds = doc['kinds'] as Map<String, dynamic>;
      expect(kinds.keys, ['gps'], reason: 'journalSession has gps and heartRate');
      expect(text, contains('7351'), reason: 'control: the GPS sentinel is there');
      expect(text.toLowerCase(), isNot(contains('heart')));
    });

    test('I16: a session with HR stream, HR laps and an HR field name sends none '
        'of it: no heartRate, no avgHrBpm, no 173.25, no device-only kinds',
        () async {
      w = await StreamUploadWorld.open();
      await w.h.journal.put(hrRichSession(id));
      await w.summarySync();
      // Precondition: the HR data really is in the local journal.
      final local = (await w.h.journal.read(id))!.session;
      expect(local.streams.containsKey(StreamKind.heartRate), isTrue);
      expect(local.laps.single.avgHrBpm, 173.25);

      await w.uploader.runPending();

      final text = gunzipText(w.cloud.puts.single.body);
      expect(text, isNot(contains('heartRate')));
      expect(text, isNot(contains('avgHrBpm')));
      expect(text, isNot(contains('173.25')));
      expect(text.toLowerCase(), isNot(contains('heart')));
      final doc = jsonDecode(text) as Map<String, dynamic>;
      final kinds = (doc['kinds'] as Map<String, dynamic>).keys.toSet();
      expect(kinds, {'gps', 'altitude'}, reason: 'cadence is device-only (DQ-2)');
      for (final k in (doc['kinds'] as Map<String, dynamic>).values) {
        expect((k as Map).keys.toSet().difference(kStreamKeys), isEmpty);
      }
      final meta = doc['meta'] as Map<String, dynamic>;
      for (final lap in (meta['laps'] as List)) {
        expect((lap as Map).keys.toSet().difference(kLapKeys), isEmpty);
      }
      final prov = (meta['provenance'] as List).single as Map;
      expect(prov['fieldsContributed'], ['distanceM']);
      // The local data is unchanged by the upload.
      final after = (await w.h.journal.read(id))!.session;
      expect(streamsOf(after), streamsOf(local));
    });

    test('a session whose only stream is heart rate sends nothing', () async {
      w = await StreamUploadWorld.open();
      await w.h.journal.put(journalSession(id, withGps: false));
      await w.summarySync();
      await w.uploader.runPending();
      expect(w.cloud.log, isEmpty, reason: 'no cloud kind, no object');
    });

    test('already_stored after a kill between the server commit and the local '
        'marker: no second PUT or commit, and the stream counts as uploaded',
        () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      w.cloud.afterCommit = (n, _) async => throw KilledMidUpload();
      await expectLater(
          w.uploader.uploadEntry(id), throwsA(isA<KilledMidUpload>()));
      expect(w.cloud.stored, contains(id), reason: 'the server did commit');
      expect((await w.stateOf(id)).streamUploadPending, isTrue,
          reason: 'the marker is written only after the client saw the commit');

      w.cloud.afterCommit = null;
      await w.restartApp();
      await w.uploader.runPending();

      expect(w.cloud.log, ['create', 'put', 'commit', 'create'],
          reason: 'already_stored ends the second run');
      expect((await w.stateOf(id)).streamUploadPending, isFalse);
    });

    test('a server refusal is not retried and leaves the entry as it was',
        () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      w.cloud.createFault = (_) => const StreamUploadRefused('consent_withdrawn');
      final before = await w.stateOf(id);
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.refused);
      expect(w.cloud.creates, hasLength(1));
      expect(w.cloud.puts, isEmpty);
      expect(w.delays, isEmpty);
      final after = await w.stateOf(id);
      expect(after.syncState, before.syncState);
      expect(after.streamUploadPending, isTrue);
    });
  });

  group('the real sequence: summary sync first, then the upload', () {
    test('an entry the summary sync already marked synced IS uploaded, and the '
        'summary state is not rewritten', () async {
      w = await StreamUploadWorld.open();
      await w.h.journal.put(journalSession(id));
      await w.summarySync();
      final synced = await w.stateOf(id);
      // Preconditions that make this the suspect scenario.
      expect(synced.syncState, JournalSyncState.synced);
      expect(synced.baseRev, 1);
      expect(synced.streamUploadPending, isTrue);

      await w.uploader.runPending();

      expect(w.cloud.log, ['create', 'put', 'commit']);
      final after = await w.stateOf(id);
      expect(after.streamUploadPending, isFalse);
      expect(after.syncState, JournalSyncState.synced);
      expect(after.baseRev, 1);
      expect(after.baseSummary, synced.baseSummary);
    });

    test('the second pass and a restart do not upload again; the marker is on '
        'disk', () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await w.uploader.runPending();
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(1));

      await w.restartApp();
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(1), reason: 'durable across a restart');
      final last = (await w.h.generations(id)).last;
      final rec = await w.h.recordJson(id, last);
      final state = rec['state'] as Map;
      expect(state['streamUploadedHash'], state['streamsPlainHash']);
    });

    test('edited streams are pending again and are uploaded after the next '
        'summary sync', () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await w.uploader.runPending();
      await w.h.journal.put(journalSession(id, seed: 1));
      expect((await w.stateOf(id)).streamUploadPending, isTrue);
      await w.summarySync();
      await w.uploader.runPending();
      expect(w.cloud.creates, hasLength(2));
      expect(w.cloud.puts.last.body, isNot(w.cloud.puts.first.body));
      expect((await w.stateOf(id)).streamUploadPending, isFalse);
    });

    test('an edit during the run: the old bytes are stored but the NEW streams '
        'stay pending (the marker is not set for content never uploaded)',
        () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      w.cloud.duringCreate = (n, _) async {
        await w.h.journal.put(journalSession(id, seed: 1));
      };
      final out = await w.uploader.uploadEntry(id);
      expect(out, StreamUploadOutcome.uploaded);
      expect((await w.stateOf(id)).streamUploadPending, isTrue);
    });

    test('the upload does not mark an UNSYNCED summary as synced', () async {
      w = await StreamUploadWorld.open();
      await w.h.journal.put(journalSession(id));
      w.backend.failWrites = true;
      await w.summarySync();
      expect((await w.stateOf(id)).syncState, JournalSyncState.uploadFailed);
      w.backend.failWrites = false;

      await w.uploader.runPending();
      expect((await w.stateOf(id)).syncState, JournalSyncState.uploadFailed,
          reason: 'only the summary sync may write synced');

      await w.summarySync();
      expect(w.backend.applied, 1, reason: 'the summary was still pushed');
      expect((await w.stateOf(id)).syncState, JournalSyncState.synced);
    });

    test('a never-synced (pending) entry is not uploaded before its summary',
        () async {
      w = await StreamUploadWorld.open();
      await w.h.journal.put(journalSession(id));
      await w.uploader.runPending();
      expect(w.cloud.log, isEmpty, reason: 'the create callable needs the summary');
      await w.summarySync();
      await w.uploader.runPending();
      expect(w.cloud.log, ['create', 'put', 'commit']);
    });

    test('a sync_conflict entry is not uploaded and keeps its conflict state',
        () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await w.h.journal.updateSyncState(id, JournalSyncState.syncConflict);
      await w.uploader.runPending();
      expect(w.cloud.log, isEmpty);
      expect((await w.stateOf(id)).syncState, JournalSyncState.syncConflict);
    });

    test('a deleted activity is not uploaded', () async {
      w = await StreamUploadWorld.open();
      await seedSynced(id);
      await w.h.journal.delete(id);
      await w.uploader.runPending();
      expect(await w.uploader.uploadEntry(id), StreamUploadOutcome.skipped);
      expect(w.cloud.log, isEmpty);
    });
  });

  group('wiring behind ACTIVITY_CLOUD_STREAMS', () {
    test('default build: no overrides, no uploader, no withdrawal presenter',
        () async {
      w = await StreamUploadWorld.open();
      expect(activityRootOverrides(), isEmpty);
      expect(
          activityRootOverrides(flags: const ActivityFlags(), journal: w.h.journal),
          isEmpty);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(activityStreamUploaderProvider), isNull);
      expect(c.read(activityConsentWithdrawalProvider), isNull);
    });

    test('flag on but no journal opened: still no uploader', () async {
      w = await StreamUploadWorld.open();
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(const ActivityFlags(cloudSync: true)),
      ]);
      addTearDown(c.dispose);
      expect(c.read(activityStreamUploaderProvider), isNull);
      expect(c.read(activityConsentWithdrawalProvider), isNull);
    });

    test('flag on with a journal: an uploader and a presenter exist, and '
        'consent is unknown (so nothing is sent) until sign-in loaded it',
        () async {
      w = await StreamUploadWorld.open();
      final c = ProviderContainer(overrides: [
        activityFlagsProvider.overrideWithValue(const ActivityFlags(cloudSync: true)),
        activityJournalProvider.overrideWithValue(w.h.journal),
      ]);
      addTearDown(c.dispose);
      expect(c.read(activityStreamUploaderProvider), isNotNull);
      expect(c.read(activityConsentWithdrawalProvider), isNotNull);
      expect(c.read(activityCloudSettingsClientProvider).isGranted, isFalse);
      expect(identical(c.read(activityStreamUploaderProvider),
          c.read(activityStreamUploaderProvider)), isTrue);
    });
  });

  group('backoff function', () {
    test('1 s, 2 s, 4 s, 8 s and no randomness', () {
      expect([for (var n = 1; n <= 4; n++) streamUploadBackoff(n)], [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
        const Duration(seconds: 8),
      ]);
      expect(streamUploadBackoff(3), streamUploadBackoff(3));
    });
  });
}
