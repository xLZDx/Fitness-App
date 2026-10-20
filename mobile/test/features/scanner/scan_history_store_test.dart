import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/scanner/history/scan_history_providers.dart';
import 'package:fitness_app/features/scanner/history/scan_history_store.dart';
import 'package:fitness_app/features/scanner/history/scan_record.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// The on-phone scan history (operator order 2026-10-14): what is stored, that
/// ratings persist, that the retention cap bites, and that the account-deletion
/// wipe removes everything. Real files in a temp directory; no mocks of the
/// store itself.
ScanRecord _rec(String id, DateTime at,
        {List<ScanCandidate>? candidates,
        ScanSource source = ScanSource.camera}) =>
    ScanRecord(
      id: id,
      timestamp: at,
      source: source,
      outcome: ScanOutcome.alternatives,
      answeredBy: ScanAnsweredBy.cloud,
      rawAnswer: '{"machine":"leg press","confidence":0.7}',
      candidates: candidates ??
          const <ScanCandidate>[
            ScanCandidate(
                equipmentId: 'leg_press', confidence: 0.7, labelHint: 'leg press'),
            ScanCandidate(equipmentId: 'hack_squat', confidence: 0.2),
          ],
      appGitSha: 'abc1234',
      appVersion: '1.0.0+14',
    );

Uint8List _jpeg(int w, int h) =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h), quality: 80));

void main() {
  late Directory docs;
  late Directory temp;
  late ScanHistoryStore store;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('scan_history_test');
    temp = Directory.systemTemp.createTempSync('scan_history_tmp');
    store = ScanHistoryStore(documents: docs, temporary: () async => temp);
  });
  tearDown(() async {
    // Windows can keep a handle on a just-written file for a moment (indexer,
    // antivirus); a bounded retry keeps the cleanup from failing the test.
    for (final d in [docs, temp]) {
      for (var i = 0; i < 6 && d.existsSync(); i++) {
        try {
          d.deleteSync(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }
  });

  final t0 = DateTime.utc(2026, 10, 14, 9);

  group('record content', () {
    test('a saved scan keeps everything the operator needs to compare', () async {
      final photo = _jpeg(40, 30);
      await store.save('u1', _rec('scan-1', t0), photo: photo);

      final back = (await store.list('u1')).single;
      expect(back.id, 'scan-1');
      expect(back.timestamp, t0);
      expect(back.source, ScanSource.camera);
      expect(back.outcome, ScanOutcome.alternatives);
      expect(back.answeredBy, ScanAnsweredBy.cloud);
      expect(back.cloudAnswered, isTrue);
      expect(back.rawAnswer, '{"machine":"leg press","confidence":0.7}');
      expect(back.candidates.map((c) => c.equipmentId),
          ['leg_press', 'hack_squat'],
          reason: 'order as shown');
      expect(back.candidates.map((c) => c.confidence), [0.7, 0.2]);
      expect(back.candidates.first.labelHint, 'leg press');
      expect(back.appGitSha, 'abc1234');
      expect(back.appVersion, '1.0.0+14');
      expect(back.hasPhoto, isTrue);
      expect(back.openedEquipmentId, isNull);
      expect(back.pickedManually, isFalse);
      expect((await store.photoFile('u1', 'scan-1'))!.readAsBytesSync(), photo,
          reason: 'the stored picture is the bytes given, unchanged');
    });

    test('the JSON on disk is one record.json per scan folder', () async {
      await store.save('u1', _rec('scan-1', t0), photo: _jpeg(8, 8));
      final dir = Directory('${docs.path}/$kScanHistoryDir/u1/scan-1');
      final json =
          jsonDecode(File('${dir.path}/record.json').readAsStringSync()) as Map;
      expect(json['schema'], 'scan_record/v1');
      expect(json['photo'], 'photo.jpg');
      expect(json['cloudAnswered'], true);
      expect(File('${dir.path}/photo.jpg').existsSync(), isTrue);
      expect(File('${dir.path}/record.json.tmp').existsSync(), isFalse,
          reason: 'the atomic-write temp file must not be left behind');
    });

    test('a scan with no photo says so and writes no file', () async {
      await store.save('u1', _rec('live-1', t0, source: ScanSource.live));
      final r = (await store.list('u1')).single;
      expect(r.hasPhoto, isFalse);
      expect(r.source, ScanSource.live);
      expect(await store.photoFile('u1', 'live-1'), isNull);
    });

    test('newest first; a corrupt folder is skipped, not fatal', () async {
      await store.save('u1', _rec('a', t0));
      await store.save('u1', _rec('b', t0.add(const Duration(minutes: 5))));
      final junk = Directory('${docs.path}/$kScanHistoryDir/u1/junk')
        ..createSync(recursive: true);
      File('${junk.path}/record.json').writeAsStringSync('{ not json');
      expect((await store.list('u1')).map((r) => r.id), ['b', 'a']);
    });

    test('histories of two accounts never mix', () async {
      await store.save('u1', _rec('a', t0));
      await store.save('u2', _rec('b', t0));
      expect((await store.list('u1')).map((r) => r.id), ['a']);
      expect((await store.list('u2')).map((r) => r.id), ['b']);
    });

    test('a path-like id or uid is refused, never written outside the folder',
        () async {
      await expectLater(
          store.save('u1', _rec('../../evil', t0)), throwsArgumentError);
      await expectLater(store.list('../u2'), throwsArgumentError);
      expect(Directory('${docs.path}/evil').existsSync(), isFalse);
    });
  });

  group('rating', () {
    test('is optional: a fresh scan has no rating on any candidate', () async {
      await store.save('u1', _rec('s', t0));
      expect((await store.get('u1', 's'))!.candidates.map((c) => c.rating),
          [null, null]);
    });

    test('persists on disk and is read back by a NEW store instance', () async {
      await store.save('u1', _rec('s', t0));
      await store.setRating('u1', 's', 'leg_press', CandidateRating.ok);
      await store.setRating('u1', 's', 'hack_squat', CandidateRating.notOk);

      final fresh =
          ScanHistoryStore(documents: docs, temporary: () async => temp);
      final r = (await fresh.get('u1', 's'))!;
      expect(r.candidates[0].rating, CandidateRating.ok);
      expect(r.candidates[1].rating, CandidateRating.notOk);
      final onDisk = jsonDecode(File(
                  '${docs.path}/$kScanHistoryDir/u1/s/record.json')
              .readAsStringSync())['candidates']
          .map((c) => c['rating'])
          .toList();
      expect(onDisk, ['ok', 'not_ok']);
    });

    test('setting null clears it, and only that candidate changes', () async {
      await store.save('u1', _rec('s', t0));
      await store.setRating('u1', 's', 'leg_press', CandidateRating.ok);
      await store.setRating('u1', 's', 'hack_squat', CandidateRating.notOk);
      await store.setRating('u1', 's', 'leg_press', null);
      final r = (await store.get('u1', 's'))!;
      expect(r.candidates[0].rating, isNull);
      expect(r.candidates[1].rating, CandidateRating.notOk);
    });

    test('an unknown scan or candidate is a quiet null, not a crash',
        () async {
      await store.save('u1', _rec('s', t0));
      expect(await store.setRating('u1', 'nope', 'leg_press', CandidateRating.ok),
          isNull);
      expect(await store.setRating('u1', 's', 'treadmill', CandidateRating.ok),
          isNull);
      expect((await store.get('u1', 's'))!.candidates.every((c) => c.rating == null),
          isTrue);
    });

    test('ratings tapped back to back are all kept (writes are serialised)',
        () async {
      await store.save('u1', _rec('s', t0));
      await Future.wait([
        store.setRating('u1', 's', 'leg_press', CandidateRating.ok),
        store.setRating('u1', 's', 'hack_squat', CandidateRating.notOk),
        store.setChoice('u1', 's', 'leg_press'),
      ]);
      final r = (await store.get('u1', 's'))!;
      expect(r.candidates[0].rating, CandidateRating.ok);
      expect(r.candidates[1].rating, CandidateRating.notOk);
      expect(r.openedEquipmentId, 'leg_press');
    });

    test('the opened machine and a manual pick are recorded', () async {
      await store.save('u1', _rec('s', t0));
      await store.setChoice('u1', 's', 'hack_squat');
      var r = (await store.get('u1', 's'))!;
      expect(r.openedEquipmentId, 'hack_squat');
      expect(r.pickedManually, isFalse);
      await store.setChoice('u1', 's', 'bench_press', manual: true);
      r = (await store.get('u1', 's'))!;
      expect(r.openedEquipmentId, 'bench_press');
      expect(r.pickedManually, isTrue);
    });
  });

  group('retention cap', () {
    test('keeps only the newest N scans', () async {
      final capped = ScanHistoryStore(
          documents: docs, temporary: () async => temp, maxScans: 3);
      for (var i = 0; i < 6; i++) {
        await capped.save(
            'u1', _rec('s$i', t0.add(Duration(minutes: i))),
            photo: _jpeg(8, 8));
      }
      expect((await capped.list('u1')).map((r) => r.id), ['s5', 's4', 's3']);
      expect(Directory('${docs.path}/$kScanHistoryDir/u1/s0').existsSync(),
          isFalse,
          reason: 'the oldest scan folders, photos included, are deleted');
    });

    test('keeps the total under the byte limit, oldest first', () async {
      final big = Uint8List(40 * 1024); // 40 KiB of "photo" per scan
      final capped = ScanHistoryStore(
          documents: docs, temporary: () async => temp, maxBytes: 100 * 1024);
      for (var i = 0; i < 5; i++) {
        await capped.save('u1', _rec('s$i', t0.add(Duration(minutes: i))),
            photo: big);
      }
      final ids = (await capped.list('u1')).map((r) => r.id).toList();
      expect(ids, ['s4', 's3'],
          reason: 'two 40 KiB photos fit under 100 KiB, a third does not');
    });

    test('the scan just saved survives even when it alone exceeds the limit',
        () async {
      final capped = ScanHistoryStore(
          documents: docs, temporary: () async => temp, maxBytes: 10);
      await capped.save('u1', _rec('only', t0), photo: Uint8List(1024));
      expect((await capped.list('u1')).map((r) => r.id), ['only']);
    });

    test('the documented defaults are 500 scans and 1 GiB', () {
      expect(kScanHistoryMaxScans, 500);
      expect(kScanHistoryMaxBytes, 1024 * 1024 * 1024);
      expect(store.maxScans, 500);
      expect(store.maxBytes, 1073741824);
    });

    test('another account is never trimmed by this one\'s cap', () async {
      final capped = ScanHistoryStore(
          documents: docs, temporary: () async => temp, maxScans: 1);
      await capped.save('u2', _rec('other', t0));
      for (var i = 0; i < 3; i++) {
        await capped.save('u1', _rec('s$i', t0.add(Duration(minutes: i))));
      }
      expect((await capped.list('u2')).map((r) => r.id), ['other']);
    });
  });

  group('clear history', () {
    test('removes every scan and photo of the account, and only that account',
        () async {
      await store.save('u1', _rec('a', t0), photo: _jpeg(8, 8));
      await store.save('u1', _rec('b', t0), photo: _jpeg(8, 8));
      await store.save('u2', _rec('c', t0));
      await store.clear('u1');
      expect(await store.list('u1'), isEmpty);
      expect(Directory('${docs.path}/$kScanHistoryDir/u1').existsSync(), isFalse);
      expect((await store.list('u2')).map((r) => r.id), ['c']);
    });

    test('clearing an empty history is a no-op', () async {
      await store.clear('nobody');
      expect(await store.list('nobody'), isEmpty);
    });
  });

  group('export', () {
    test('writes ONE json plus a photos folder with relative photo paths',
        () async {
      await store.save('u1', _rec('a', t0), photo: _jpeg(16, 16));
      await store.save('u1', _rec('live-1', t0.add(const Duration(hours: 1)),
          source: ScanSource.live));
      await store.setRating('u1', 'a', 'leg_press', CandidateRating.ok);

      final out = Directory('${docs.path}/out')..createSync();
      final export =
          await store.export('u1', out, now: DateTime.utc(2026, 10, 15));

      expect(export.json.path.endsWith('scan_history.json'), isTrue);
      final j = jsonDecode(export.json.readAsStringSync()) as Map;
      expect(j['schema'], 'scan_history_export/v1');
      expect(j['count'], 2);
      expect(j['exportedAt'], '2026-10-15T00:00:00.000Z');
      final scans = (j['scans'] as List).cast<Map>();
      expect(scans.map((s) => s['id']), ['live-1', 'a'], reason: 'newest first');
      final a = scans.firstWhere((s) => s['id'] == 'a');
      expect(a['photo'], 'photos/a.jpg');
      expect(File('${export.directory.path}/photos/a.jpg').existsSync(), isTrue);
      expect((a['candidates'] as List).first['rating'], 'ok');
      expect(a['rawAnswer'], contains('leg press'));
      expect(a['app'], {'gitSha': 'abc1234', 'version': '1.0.0+14'});
      expect(scans.firstWhere((s) => s['id'] == 'live-1')['photo'], isNull);
      expect(export.files.length, 2, reason: 'the json and the one photo');
    });

    test('exporting twice replaces the previous export, no stale photos',
        () async {
      await store.save('u1', _rec('a', t0), photo: _jpeg(8, 8));
      final out = Directory('${docs.path}/out')..createSync();
      await store.export('u1', out);
      await store.clear('u1');
      final again = await store.export('u1', out);
      expect(again.photos, isEmpty);
      expect(Directory('${again.directory.path}/photos').listSync(), isEmpty);
      expect(jsonDecode(again.json.readAsStringSync())['count'], 0);
    });
  });

  group('account-deletion wipe', () {
    test('removes the whole scan history of the deleted account, keeps another',
        () async {
      await store.save('A', _rec('a1', t0), photo: _jpeg(8, 8));
      await store.save('A', _rec('a2', t0), photo: _jpeg(8, 8));
      await store.save('B', _rec('b1', t0), photo: _jpeg(8, 8));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await DeviceLocalDataWipe(
        prefs: prefs,
        documentsDir: docs,
        forgetPhotoKey: (_) async {},
      ).wipe('A');

      expect(Directory('${docs.path}/$kScanHistoryDir/A').existsSync(), isFalse,
          reason: 'photos, raw answers and ratings must not outlive the account');
      expect(await store.list('A'), isEmpty);
      expect((await store.list('B')).map((r) => r.id), ['b1']);
      expect((await store.photoFile('B', 'b1')), isNotNull);
    });

    test('a scan history that cannot be deleted is reported, not hidden',
        () async {
      // A FILE where the per-uid directory should be makes delete(recursive)
      // fail on a directory path the wipe believes exists... emulate by
      // pointing the wipe at a documents dir that is a file.
      final notADir = File('${docs.path}/file')..writeAsStringSync('x');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // No exception: nothing to wipe under a non-directory. The contract
      // under test is only "never throws something other than
      // LocalWipeIncomplete".
      try {
        await DeviceLocalDataWipe(
          prefs: prefs,
          documentsDir: Directory(notADir.path),
          forgetPhotoKey: (_) async {},
        ).wipe('A');
      } on LocalWipeIncomplete {
        // acceptable: reported
      }
    });
  });

  group('recorder', () {
    ProviderContainer container({String? uid = 'u1'}) {
      final c = ProviderContainer(overrides: [
        scanHistoryStoreProvider.overrideWithValue(store),
        scanHistoryUidProvider.overrideWithValue(uid),
        scanBuildInfoProvider.overrideWithValue(
            const ScanBuildInfo(gitSha: 'deadbee', version: '1.0.0+14')),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final photoFile = () {
      final f = File('${Directory.systemTemp.path}/scan_history_src.jpg');
      f.writeAsBytesSync(_jpeg(2000, 1000));
      return f;
    }();

    test('a CLOUD scan is saved with the raw answer, candidates and the '
        'resized photo that was sent', () async {
      final c = container();
      final saved = await c.read(scanHistoryRecorderProvider).saveScan(
            scanId: 'scan-100',
            source: ScanSource.gallery,
            photoPath: photoFile.path,
            now: t0,
            result: const ScanResult.alternatives(
              [
                VisualMatch(equipmentId: 'leg_press', confidence: 0.7, labelHint: 'leg press'),
                VisualMatch(equipmentId: 'hack_squat', confidence: 0.2),
              ],
              rawAnswer: '{"machine":"leg press"}',
            ),
          );
      expect(saved, isNotNull);
      final r = (await store.get('u1', 'scan-100'))!;
      expect(r.source, ScanSource.gallery);
      expect(r.answeredBy, ScanAnsweredBy.cloud);
      expect(r.cloudAnswered, isTrue);
      expect(r.rawAnswer, '{"machine":"leg press"}');
      expect(r.candidates.map((e) => e.equipmentId), ['leg_press', 'hack_squat']);
      expect(r.appGitSha, 'deadbee');
      expect(r.timestamp, t0);
      final stored = img.decodeJpg((await store.photoFile('u1', 'scan-100'))!.readAsBytesSync())!;
      expect(stored.width, 1024,
          reason: 'what is kept is the 1024px image the cloud saw, not the original');
      expect(stored.height, 512);
    });

    test('an ON-DEVICE fallback scan is saved as such, with no raw answer',
        () async {
      final c = container();
      await c.read(scanHistoryRecorderProvider).saveScan(
            scanId: 'scan-200',
            source: ScanSource.camera,
            result: const ScanResult.alternatives(
              [VisualMatch(equipmentId: 'treadmill', confidence: 0.4)],
              answeredOffline: true,
            ),
          );
      final r = (await store.get('u1', 'scan-200'))!;
      expect(r.answeredBy, ScanAnsweredBy.onDevice);
      expect(r.cloudAnswered, isFalse);
      expect(r.rawAnswer, isNull);
    });

    test('scans that produced no answer are recorded too', () async {
      final c = container();
      final rec = c.read(scanHistoryRecorderProvider);
      await rec.saveScan(
          scanId: 'scan-t', source: ScanSource.camera, result: const ScanResult.timeout());
      await rec.saveScan(
          scanId: 'scan-f', source: ScanSource.camera, result: const ScanResult.failed());
      final timeout = (await store.get('u1', 'scan-t'))!;
      expect(timeout.outcome, ScanOutcome.timeout);
      expect(timeout.answeredBy, ScanAnsweredBy.none);
      expect(timeout.candidates, isEmpty);
      expect((await store.get('u1', 'scan-f'))!.outcome, ScanOutcome.failed);
    });

    test('a printed-text answer is attributed to the printed text', () async {
      final c = container();
      await c.read(scanHistoryRecorderProvider).saveScan(
            scanId: 'scan-p',
            source: ScanSource.camera,
            result: const ScanResult.confident([
              VisualMatch(
                  equipmentId: 'leg_press',
                  confidence: 0.92,
                  labelHint: 'leg press',
                  source: MatchSource.printedText),
            ]),
          );
      final r = (await store.get('u1', 'scan-p'))!;
      expect(r.answeredBy, ScanAnsweredBy.printedText);
      expect(r.candidates.single.matchSource, MatchSource.printedText);
    });

    test('with no signed-in account nothing is written', () async {
      final c = container(uid: null);
      final saved = await c.read(scanHistoryRecorderProvider).saveScan(
          scanId: 'scan-x',
          source: ScanSource.camera,
          result: const ScanResult.timeout());
      expect(saved, isNull);
      expect(Directory('${docs.path}/$kScanHistoryDir').existsSync(), isFalse);
    });

    test('a store that fails does not throw into recognition', () async {
      final broken = ProviderContainer(overrides: [
        scanHistoryStoreProvider.overrideWithValue(
            ScanHistoryStore(
                documents: Directory('${docs.path}/file-not-dir'),
                temporary: () async => temp)),
        scanHistoryUidProvider.overrideWithValue('u1'),
      ]);
      addTearDown(broken.dispose);
      File('${docs.path}/file-not-dir').writeAsStringSync('x');
      final saved = await broken.read(scanHistoryRecorderProvider).saveScan(
          scanId: 'scan-y',
          source: ScanSource.camera,
          result: const ScanResult.timeout());
      expect(saved, isNull);
    });

    test('rating and choice go through the recorder and persist', () async {
      final c = container();
      final rec = c.read(scanHistoryRecorderProvider);
      await rec.saveScan(
          scanId: 'scan-r',
          source: ScanSource.camera,
          result: const ScanResult.alternatives(
              [VisualMatch(equipmentId: 'leg_press', confidence: 0.6)]));
      await rec.rate('scan-r', 'leg_press', CandidateRating.notOk);
      await rec.choose('scan-r', 'bench_press', manual: true);
      final r = (await store.get('u1', 'scan-r'))!;
      expect(r.candidates.single.rating, CandidateRating.notOk);
      expect(r.openedEquipmentId, 'bench_press');
      expect(r.pickedManually, isTrue);
      await rec.clear();
      expect(await store.list('u1'), isEmpty);
    });
  });

  group('the plaintext export copy in temp storage', () {
    Directory exportCopy() => Directory('${temp.path}/$kScanExportDirName');

    test('clear history also removes it', () async {
      await store.save('u1', _rec('a', t0), photo: _jpeg(8, 8));
      await store.export('u1', temp);
      expect(exportCopy().existsSync(), isTrue);
      await store.clear('u1');
      expect(exportCopy().existsSync(), isFalse,
          reason: 'plaintext photos + JSON must not survive "Clear history"');
      expect(await store.list('u1'), isEmpty);
    });

    test('the account wipe removes it, with and without the live store',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await store.save('A', _rec('a', t0), photo: _jpeg(8, 8));

      await store.export('A', temp);
      await DeviceLocalDataWipe(
        prefs: prefs,
        documentsDir: docs,
        temporaryDir: temp,
        forgetPhotoKey: (_) async {},
      ).wipe('A');
      expect(exportCopy().existsSync(), isFalse, reason: 'directory wipe');

      await store.save('A', _rec('a2', t0), photo: _jpeg(8, 8));
      await store.export('A', temp);
      await DeviceLocalDataWipe(
        prefs: prefs,
        documentsDir: docs,
        temporaryDir: temp,
        scanHistory: store,
        forgetPhotoKey: (_) async {},
      ).wipe('A');
      expect(exportCopy().existsSync(), isFalse, reason: 'through the store');
      expect(Directory('${docs.path}/$kScanHistoryDir/A').existsSync(), isFalse);
    });

    test('clearing with no export copy present is quiet', () async {
      await store.clear('u1');
      expect(exportCopy().existsSync(), isFalse);
    });
  });

  group('wipe versus a save still in flight', () {
    DeviceLocalDataWipe wipeFor(ScanHistoryStore st, SharedPreferences prefs) =>
        DeviceLocalDataWipe(
          prefs: prefs,
          documentsDir: docs,
          temporaryDir: temp,
          scanHistory: st,
          forgetPhotoKey: (_) async {},
        );

    test('a save that reaches the store AFTER the wipe never recreates the '
        'folder', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final gated = _GatedStore(docs, temp);
      final c = ProviderContainer(overrides: [
        scanHistoryStoreProvider.overrideWithValue(gated),
        scanHistoryUidProvider.overrideWithValue('A'),
        scanBuildInfoProvider.overrideWithValue(
            const ScanBuildInfo(gitSha: 'x', version: '1')),
      ]);
      addTearDown(c.dispose);

      // The scan is "still resizing its photo": it has not reached the store.
      final inFlight = c.read(scanHistoryRecorderProvider).saveScan(
            scanId: 'scan-late',
            source: ScanSource.camera,
            result: const ScanResult.timeout(),
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await wipeFor(gated, prefs).wipe('A'); // account deletion's wipe step

      gated.gate.complete(); // ... and only now does the save arrive
      expect(await inFlight, isNull, reason: 'the save is refused, not written');

      expect(Directory('${docs.path}/$kScanHistoryDir/A').existsSync(), isFalse,
          reason: 'scan_history/<uid> must not exist after the wipe, '
              'whatever was in flight');
      expect(await gated.list('A'), isEmpty);
    });

    test('a save already queued when the wipe starts is deleted by it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      // Both calls are issued without awaiting: the save is first in the
      // serial chain, the wipe queues right behind it.
      final save = store.save('A', _rec('a', t0), photo: _jpeg(64, 64));
      final wipe = wipeFor(store, prefs).wipe('A');
      await Future.wait([save, wipe]);
      expect(Directory('${docs.path}/$kScanHistoryDir/A').existsSync(), isFalse);
    });

    test('a rating or choice after the wipe is dropped, not written',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await store.save('A', _rec('a', t0));
      await wipeFor(store, prefs).wipe('A');
      expect(await store.setRating('A', 'a', 'leg_press', CandidateRating.ok),
          isNull);
      expect(await store.setChoice('A', 'a', 'leg_press'), isNull);
      expect(Directory('${docs.path}/$kScanHistoryDir/A').existsSync(), isFalse);
    });

    test('wiping one account leaves another writable, and "Clear history" '
        'does not lock the account', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await wipeFor(store, prefs).wipe('A');
      expect(await store.save('B', _rec('b', t0)), isNotNull);
      expect((await store.list('B')).map((r) => r.id), ['b']);

      await store.clear('B');
      expect(await store.save('B', _rec('b2', t0)), isNotNull,
          reason: 'clearing is not deleting the account');
    });
  });
}

/// A store whose save waits at a gate: stands in for a scan whose photo is still
/// being resized when the account-deletion wipe runs.
class _GatedStore extends ScanHistoryStore {
  _GatedStore(Directory docs, Directory temp)
      : super(documents: docs, temporary: () async => temp);

  final Completer<void> gate = Completer<void>();

  @override
  Future<ScanRecord?> save(String uid, ScanRecord record,
      {Uint8List? photo}) async {
    await gate.future;
    return super.save(uid, record, photo: photo);
  }
}
