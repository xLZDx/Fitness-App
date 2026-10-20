// C16 functional tests: scan history actions (design s17, D-72, D-78).
// deletePhotos: cloud first, offline -> pendingRemoteDelete kept on the phone.
// editWeight: local record, re-derived PROVISIONAL estimate, server weight and
// the day's weight_entries row; the flow waits for the data-notice answer.
import 'dart:typed_data';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_entry.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_repository.dart';
import 'package:fitness_app/features/body_scan/data/provisional_estimator.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_api.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_job_runner.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/scan_history_actions.dart';
import 'package:fitness_app/features/body_scan/state/scan_history_rows.dart';
import 'package:fitness_app/features/body_scan/widgets/scan_row_actions.dart';
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/nutrition_plan/data/weight_entry.dart';
import 'package:fitness_app/features/nutrition_plan/state/weight_providers.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/test_app.dart';
import '../../nutrition_plan/plan_state_fixtures.dart';
import '../../nutrition_plan/plan_state_harness.dart';

// ---- fakes -----------------------------------------------------------------

class _Scans implements ScanRepository {
  _Scans(Iterable<ScanRecord> items) {
    for (final r in items) {
      _byId[r.id] = r;
    }
  }
  final Map<String, ScanRecord> _byId = {};
  bool failSave = false;
  int saves = 0;

  ScanRecord? operator [](String id) => _byId[id];

  @override
  Future<List<ScanRecord>> list() async => _byId.values.toList();
  @override
  Future<void> save(ScanRecord r) async {
    if (failSave) throw StateError('disk');
    saves++;
    _byId[r.id] = r;
  }

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}

class _Photos implements ProgressPhotosRepository {
  final deleted = <String>[];
  bool fail = false;
  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);
  @override
  Future<Uint8List?> takeShot() async => null;
  @override
  Future<ProgressPhoto> save(Uint8List bytes,
          {required ProgressPhotoAngle angle,
          double? weightKg,
          String? note}) async =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) async {
    if (fail) throw StateError('io');
    deleted.add(id);
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => Uint8List(0);
}

class _Api extends Fake implements BodyScanApi {
  final calls = <(String, bool)>[];
  Object? error;
  @override
  Future<void> deleteBodyScan(String scanId, {required bool photosOnly}) async {
    calls.add((scanId, photosOnly));
    if (error != null) throw error!;
  }
}

class _ServerRepo implements BodyScanRepository {
  final weights = <(String, double)>[];
  bool fail = false;
  @override
  Stream<List<BodyScanEntry>> watchEntries({int limit = 120}) =>
      Stream.value(const []);
  @override
  Future<void> updateRecordedWeight(String scanId, double weightKg) async {
    if (fail) throw StateError('offline');
    weights.add((scanId, weightKg));
  }

  @override
  Future<void> updateNote(String scanId, String? note) async {}
}

class _Runner extends Fake implements BodyScanJobRunner {
  int resumes = 0;
  final forgotten = <String>[];
  @override
  Future<void> resume() async => resumes++;
  @override
  void forget(String scanId) => forgotten.add(scanId);
}

// ---- fixtures --------------------------------------------------------------

const _prov = 'provisional-anthropometric';

BodyFatEstimate _prEst(double v) => BodyFatEstimate(
      value: v,
      low: v - 5,
      high: v + 5,
      confidence: EstimateConfidence.low,
      modelId: ProvisionalEstimator.estimatorId,
      modelVersion: ProvisionalEstimator.estimatorVersion,
      provisional: true,
    );

BodyFatEstimate _srvEst(double v) => BodyFatEstimate(
      value: v,
      low: v - 2,
      high: v + 2,
      confidence: EstimateConfidence.medium,
      modelId: 'photo-model',
      modelVersion: '1',
      provisional: false,
    );

ScanRecord _rec(
  String id, {
  DateTime? at,
  BodyFatEstimate? estimate,
  double? weight = 80,
  String? remoteId,
  String? remoteStatus,
}) =>
    ScanRecord(
      id: id,
      createdAt: at ?? DateTime(2026, 10, 10, 8),
      shots: {
        for (final p in ScanPose.ordered)
          p: ScanShot(photoId: '$id-${p.name}', landmarks: const []),
      },
      analysis: ScanAnalysis(
        status: JobStatus.done,
        estimate: estimate,
        remoteId: remoteId,
        remoteStatus: remoteStatus,
      ),
      weightKg: weight,
    );

ScanHistoryRow _row({ScanRecord? record, BodyScanEntry? entry, DateTime? at}) =>
    ScanHistoryRow(
      id: record?.id ?? entry!.scanId,
      takenAt: at ?? entry?.takenAt ?? record!.createdAt,
      weightKg: entry?.weightKg ?? record?.weightKg,
      estimate: entry?.estimate ?? record?.analysis?.estimate,
      record: record,
      entry: entry,
    );

BodyScanEntry _entry(String id,
        {PhotosState photos = PhotosState.stored, double? weight = 80}) =>
    BodyScanEntry(
      scanId: id,
      takenAt: DateTime(2026, 10, 10, 8),
      status: ScanDocStatus.done,
      photosState: photos,
      weightKg: weight,
      estimate: _srvEst(20),
    );

class _Env {
  _Env(this.h, this.scans, this.photos, this.api, this.server, this.runner);
  final PlanHarness h;
  final _Scans scans;
  final _Photos photos;
  final _Api api;
  final _ServerRepo server;
  final _Runner runner;
  ScanHistoryActions get actions => h.container.read(scanHistoryActionsProvider);
}

Future<_Env> _env({
  List<ScanRecord> records = const [],
  bool cloud = true,
  String? uid = kUid,
  String? deletingUid,
  bool noticeAcknowledged = true,
  bool completeProfile = true,
}) async {
  final scans = _Scans(records);
  final photos = _Photos();
  final api = _Api();
  final server = _ServerRepo();
  final runner = _Runner();
  final h = await makeHarness(
    uid: uid,
    deletingUid: deletingUid,
    noticeAcknowledged: noticeAcknowledged,
    profile: completeProfile ? eligibleProfile() : eligibleProfile(heightCm: null),
    extra: [
      scanRepositoryProvider.overrideWithValue(scans),
      progressPhotosRepositoryProvider.overrideWithValue(photos),
      bodyScanApiProvider.overrideWithValue(api),
      bodyScanRepositoryProvider.overrideWithValue(server),
      bodyScanRunnerProvider.overrideWithValue(runner),
      bodyScanFlagsProvider.overrideWithValue(BodyScanFlags(cloudPhotos: cloud)),
    ],
  );
  return _Env(h, scans, photos, api, server, runner);
}

void main() {
  late _Env e;
  tearDown(() => e.h.dispose());

  group('deletePhotos', () {
    test('local-only scan: files and record removed, no cloud call', () async {
      final rec = _rec('a', estimate: _prEst(20));
      e = await _env(records: [rec]);
      final out = await e.actions.deletePhotos(_row(record: rec));

      expect(out, DeletePhotosOutcome.deleted);
      expect(e.api.calls, isEmpty);
      expect(e.photos.deleted.toSet(),
          {'a-front', 'a-side', 'a-back'});
      expect(e.scans['a'], isNull);
      expect(e.runner.forgotten, ['a'],
          reason: 'the runner must stop working on a deleted scan');
    });

    test('uploaded scan online: cloud delete (photosOnly) FIRST, then local',
        () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a_r1', remoteStatus: 'done');
      e = await _env(records: [rec]);
      final out = await e.actions
          .deletePhotos(_row(record: rec, entry: _entry('a_r1')));

      expect(out, DeletePhotosOutcome.deleted);
      expect(e.api.calls, [('a_r1', true)]);
      expect(e.scans['a'], isNull);
      expect(e.photos.deleted, hasLength(3));
    });

    test('server-only scan online: cloud delete only, nothing local to do',
        () async {
      e = await _env();
      final out = await e.actions.deletePhotos(_row(entry: _entry('s1')));
      expect(out, DeletePhotosOutcome.deleted);
      expect(e.api.calls, [('s1', true)]);
      expect(e.photos.deleted, isEmpty);
    });

    test('server-only scan offline: failed, nothing queued (no local record)',
        () async {
      e = await _env();
      e.api.error = StateError('offline');
      final out = await e.actions.deletePhotos(_row(entry: _entry('s1')));
      expect(out, DeletePhotosOutcome.failed);
      expect(e.scans.saves, 0);
    });

    test('offline: record saved with pendingRemoteDelete, photos stay on the '
        'phone, runner resumed', () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a', remoteStatus: 'done');
      e = await _env(records: [rec]);
      e.api.error = StateError('offline');
      final out = await e.actions
          .deletePhotos(_row(record: rec, entry: _entry('a')));

      expect(out, DeletePhotosOutcome.queuedOffline);
      expect(e.scans['a']!.pendingRemoteDelete, isTrue);
      expect(e.photos.deleted, isEmpty,
          reason: 'nothing local disappears before the owed delete is recorded');
      expect(e.scans['a']!.pendingPhotosOnly, isTrue,
          reason: 'the owed kind is photos-only, not a full delete');
      expect(e.scans['a']!.analysis!.status, JobStatus.done);
      expect(e.runner.resumes, 1);
      expect(e.runner.forgotten, ['a'],
          reason: 'the runner must stop touching the scan');
    });

    test('offline delete of an UNFINISHED scan stops it: terminal cancelled, '
        'owed, runner told to forget', () async {
      final rec = ScanRecord(
        id: 'u',
        createdAt: DateTime(2026, 10, 10, 8),
        shots: const {},
        analysis: const ScanAnalysis(
            status: JobStatus.uploading, remoteStatus: 'pending'),
        weightKg: 80,
      );
      e = await _env(records: [rec]);
      e.api.error = StateError('offline');
      final out = await e.actions.deletePhotos(ScanHistoryRow(
          id: 'u', takenAt: rec.createdAt, weightKg: 80, record: rec));
      expect(out, DeletePhotosOutcome.queuedOffline);
      expect(e.scans['u']!.analysis!.status, JobStatus.cancelled);
      expect(e.scans['u']!.pendingRemoteDelete, isTrue);
      expect(e.runner.forgotten, ['u']);
    });

    test('an owed FULL delete is not downgraded to photos-only', () async {
      final base = _rec('a', estimate: _srvEst(20), remoteId: 'a', remoteStatus: 'done');
      final rec = base.copyWith(pendingRemoteDelete: true);
      e = await _env(records: [rec]);
      e.api.error = StateError('offline');
      await e.actions.deletePhotos(_row(record: rec, entry: _entry('a')));
      expect(e.scans['a']!.pendingPhotosOnly, isFalse);
    });

    test('offline and the owed delete cannot be saved: failed, local files '
        'untouched', () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a', remoteStatus: 'done');
      e = await _env(records: [rec]);
      e.api.error = StateError('offline');
      e.scans.failSave = true;
      final out = await e.actions
          .deletePhotos(_row(record: rec, entry: _entry('a')));
      expect(out, DeletePhotosOutcome.failed);
      expect(e.scans['a']!.pendingRemoteDelete, isFalse);
      expect(e.photos.deleted, isEmpty);
    });

    test('cloud flag off: a record that once uploaded does NOT report deleted '
        'while the cloud copy remains; the delete is owed', () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a', remoteStatus: 'done');
      e = await _env(records: [rec], cloud: false);
      final out = await e.actions
          .deletePhotos(_row(record: rec, entry: _entry('a')));
      expect(out, DeletePhotosOutcome.queuedOffline);
      expect(e.api.calls, isEmpty);
      expect(e.scans['a']!.pendingRemoteDelete, isTrue);
      expect(e.scans['a']!.pendingPhotosOnly, isTrue);
      expect(e.photos.deleted, isEmpty);
    });

    test('cloud flag off and no local record: failed, nothing reported deleted',
        () async {
      e = await _env(cloud: false);
      final out = await e.actions.deletePhotos(_row(entry: _entry('s1')));
      expect(out, DeletePhotosOutcome.failed);
    });

    test('a local file failure reports failed and keeps the record for retry',
        () async {
      final rec = _rec('a', estimate: _prEst(20));
      e = await _env(records: [rec]);
      e.photos.fail = true;
      final out = await e.actions.deletePhotos(_row(record: rec));
      expect(out, DeletePhotosOutcome.failed);
      expect(e.scans['a'], isNotNull);
    });

    test('the history provider is invalidated so the row disappears',
        () async {
      final rec = _rec('a', estimate: _prEst(20));
      e = await _env(records: [rec]);
      expect(await e.h.container.read(scanHistoryProvider.future), hasLength(1));
      await e.actions.deletePhotos(_row(record: rec));
      expect(await e.h.container.read(scanHistoryProvider.future), isEmpty);
    });
  });

  group('editWeight', () {
    test('provisional scan: record weight saved and the estimate re-derived '
        'from the NEW weight, not just copied', () async {
      final rec = _rec('a', estimate: _prEst(10), weight: 80);
      e = await _env(records: [rec]);
      final out = await e.actions.editWeight(_row(record: rec), 85);

      expect(out, EditWeightOutcome.saved);
      final saved = e.scans['a']!;
      expect(saved.weightKg, 85);
      final est = saved.analysis!.estimate!;
      // Male, 180 cm, born 1985, scan year 2026 -> age 41.
      final expected = const ProvisionalEstimator().estimateNow(EstimatorSubject(
          heightCm: 180, weightKg: 85, ageYears: 41, sex: SexBasis.male));
      expect(est.value, expected.value);
      expect(est.value, closeTo(24.71, 0.01),
          reason: '1.2*BMI(26.235)+0.23*41-10.8-5.4');
      expect(est.value, isNot(10), reason: 'the stale value is replaced');
      expect(est.provisional, isTrue);
      expect(saved.analysis!.updatedAt, kNow);
    });

    test('server (non-provisional) estimate is NOT changed by a weight edit',
        () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a');
      e = await _env(records: [rec]);
      await e.actions.editWeight(_row(record: rec, entry: _entry('a')), 90);
      expect(e.scans['a']!.analysis!.estimate!.value, 20);
      expect(e.scans['a']!.weightKg, 90);
    });

    test('provisional edit with the profile missing height: weight saved, '
        'estimate left as it was', () async {
      final rec = _rec('a', estimate: _prEst(10), weight: 80);
      e = await _env(records: [rec], completeProfile: false);
      final out = await e.actions.editWeight(_row(record: rec), 85);
      expect(out, EditWeightOutcome.saved);
      expect(e.scans['a']!.weightKg, 85);
      expect(e.scans['a']!.analysis!.estimate!.value, 10);
    });

    test('server document gets the weight (scanId of the entry)', () async {
      final rec = _rec('local', estimate: _srvEst(20), remoteId: 'srv');
      e = await _env(records: [rec]);
      await e.actions.editWeight(_row(record: rec, entry: _entry('srv')), 77.5);
      expect(e.server.weights, [('srv', 77.5)]);
    });

    test('writes the same local day weight_entries row with source scan',
        () async {
      final rec = _rec('a', estimate: _prEst(10), at: DateTime(2026, 10, 10, 8));
      e = await _env(records: [rec]);
      await e.actions.editWeight(_row(record: rec), 82.5);
      final log = await e.h.weights.loadLog(kUid);
      expect(log, hasLength(1));
      expect(log.single.entry.kg, 82.5);
      expect(log.single.entry.source, WeightSource.scan);
      expect(log.single.entry.dayKey,
          WeightEntry(at: DateTime(2026, 10, 10, 8), kg: 80).dayKey,
          reason: 'the SCAN day, not today');
    });

    test('writeDayEntry:false (notice not acknowledged) leaves the weight '
        'log untouched but still updates the scan', () async {
      final rec = _rec('a', estimate: _prEst(10));
      e = await _env(records: [rec]);
      final out =
          await e.actions.editWeight(_row(record: rec), 83, writeDayEntry: false);
      expect(out, EditWeightOutcome.saved);
      expect(e.scans['a']!.weightKg, 83);
      expect(await e.h.weights.loadLog(kUid), isEmpty);
    });

    test('30 and 300 are accepted, 29.9 and 300.1 are invalid and write '
        'nothing', () async {
      final rec = _rec('a', estimate: _prEst(10));
      e = await _env(records: [rec]);
      expect(await e.actions.editWeight(_row(record: rec), 29.9),
          EditWeightOutcome.invalid);
      expect(await e.actions.editWeight(_row(record: rec), 300.1),
          EditWeightOutcome.invalid);
      expect(e.scans.saves, 0);
      expect(await e.h.weights.loadLog(kUid), isEmpty);
      expect(await e.actions.editWeight(_row(record: rec), 30),
          EditWeightOutcome.saved);
      expect(await e.actions.editWeight(_row(record: rec), 300),
          EditWeightOutcome.saved);
    });

    test('server failure: reported failed, but the local record and the day '
        'row still stand', () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a');
      e = await _env(records: [rec]);
      e.server.fail = true;
      final out =
          await e.actions.editWeight(_row(record: rec, entry: _entry('a')), 81);
      expect(out, EditWeightOutcome.failed);
      expect(e.scans['a']!.weightKg, 81);
      expect(await e.h.weights.loadLog(kUid), hasLength(1));
    });

    test('local save failure: failed, yet server and day row are still tried',
        () async {
      final rec = _rec('a', estimate: _srvEst(20), remoteId: 'a');
      e = await _env(records: [rec]);
      e.scans.failSave = true;
      final out =
          await e.actions.editWeight(_row(record: rec, entry: _entry('a')), 81);
      expect(out, EditWeightOutcome.failed);
      expect(e.server.weights, [('a', 81.0)]);
      expect(await e.h.weights.loadLog(kUid), hasLength(1));
    });

    test('signed out: failed and nothing is written anywhere', () async {
      final rec = _rec('a', estimate: _prEst(10));
      e = await _env(records: [rec], uid: null);
      final out = await e.actions.editWeight(_row(record: rec), 81);
      expect(out, EditWeightOutcome.failed);
      expect(e.scans.saves, 0);
      expect(e.server.weights, isEmpty);
    });

    test('account being deleted: failed and nothing is written', () async {
      final rec = _rec('a', estimate: _prEst(10));
      e = await _env(records: [rec], deletingUid: kUid);
      final out = await e.actions.editWeight(_row(record: rec), 81);
      expect(out, EditWeightOutcome.failed);
      expect(e.scans.saves, 0);
      expect(await e.h.weights.loadLog(kUid), isEmpty);
    });

    test('an equal same-day MANUAL entry is kept, not replaced by the scan',
        () async {
      final rec = _rec('a', estimate: _prEst(10), at: DateTime(2026, 10, 10, 8));
      e = await _env(records: [rec]);
      await e.h.weights.put(
          kUid, WeightEntry(at: DateTime(2026, 10, 10, 7), kg: 81));
      final out = await e.actions.editWeight(_row(record: rec), 81);
      expect(out, EditWeightOutcome.saved);
      final log = await e.h.weights.loadLog(kUid);
      expect(log.single.entry.source, WeightSource.manual);
    });
  });

  group('editScanWeightFlow waits for the data-notice answer (D-79)', () {
    Future<void> pumpFlow(
      WidgetTester t,
      _Env env,
      ScanHistoryRow row,
      InMemoryDataNoticeStore notice,
    ) async {
      await t.pumpWidget(UncontrolledProviderScope(
        container: env.h.container,
        child: MaterialApp(
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                key: const Key('t.edit'),
                onPressed: () => editScanWeightFlow(context, ref, row),
                child: const Text('edit'),
              ),
            ),
          ),
        ),
      ));
    }

    Future<InMemoryDataNoticeStore> setup(
        WidgetTester t, bool acknowledged, ScanRecord rec) async {
      final notice = InMemoryDataNoticeStore(acknowledged: acknowledged);
      e = await _env(records: [rec]);
      // The harness container was built without the store; rebuild with it.
      e.h.dispose();
      final scans = e.scans;
      final h = await makeHarness(extra: [
        scanRepositoryProvider.overrideWithValue(scans),
        progressPhotosRepositoryProvider.overrideWithValue(e.photos),
        bodyScanApiProvider.overrideWithValue(e.api),
        bodyScanRepositoryProvider.overrideWithValue(e.server),
        bodyScanRunnerProvider.overrideWithValue(e.runner),
        dataNoticeStoreProvider.overrideWith((ref) async => notice),
      ]);
      e = _Env(h, scans, e.photos, e.api, e.server, e.runner);
      return notice;
    }

    testWidgets('acknowledged: save writes the scan and the day row',
        (t) async {
      final rec = _rec('a', estimate: _prEst(10), at: DateTime(2026, 10, 10, 8));
      final notice = (await t.runAsync(() => setup(t, true, rec)))!;
      await pumpFlow(t, e, _row(record: rec), notice);
      await t.tap(find.byKey(const Key('t.edit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('bodyScan.editWeight.field')), '84,5');
      await t.tap(find.byKey(const Key('bodyScan.editWeight.save')));
      await t.pumpAndSettle();

      expect(e.scans['a']!.weightKg, 84.5);
      final log = await e.h.weights.loadLog(kUid);
      expect(log.single.entry.kg, 84.5);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('not acknowledged: the sheet shows BEFORE any weight-log write',
        (t) async {
      final rec = _rec('a', estimate: _prEst(10), at: DateTime(2026, 10, 10, 8));
      final notice = (await t.runAsync(() => setup(t, false, rec)))!;
      await pumpFlow(t, e, _row(record: rec), notice);
      await t.tap(find.byKey(const Key('t.edit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('bodyScan.editWeight.field')), '84');
      await t.tap(find.byKey(const Key('bodyScan.editWeight.save')));
      await t.pumpAndSettle();

      final l10n = AppLocalizations.of(t.element(find.byKey(const Key('t.edit'))));
      expect(find.text(l10n.dataNoticeTitle), findsOneWidget);
      expect(await e.h.weights.loadLog(kUid), isEmpty,
          reason: 'nothing is written while the notice is unanswered');
      expect(e.scans.saves, 0);

      await t.tap(find.text(l10n.dataNoticeAcknowledge));
      await t.pumpAndSettle();
      expect(notice.acknowledgeCalls, 1);
      expect((await e.h.weights.loadLog(kUid)).single.entry.kg, 84);
      expect(e.scans['a']!.weightKg, 84);
    });

    testWidgets('notice dismissed: scan weight still updates, day row is '
        'deferred', (t) async {
      final rec = _rec('a', estimate: _prEst(10), at: DateTime(2026, 10, 10, 8));
      final notice = (await t.runAsync(() => setup(t, false, rec)))!;
      await pumpFlow(t, e, _row(record: rec), notice);
      await t.tap(find.byKey(const Key('t.edit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('bodyScan.editWeight.field')), '84');
      await t.tap(find.byKey(const Key('bodyScan.editWeight.save')));
      await t.pumpAndSettle();
      // Dismiss the sheet by tapping the barrier.
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      expect(notice.acknowledgeCalls, 0);
      expect(e.scans['a']!.weightKg, 84);
      expect(await e.h.weights.loadLog(kUid), isEmpty);
    });

    testWidgets('out-of-range input keeps the dialog open with an error and '
        'writes nothing', (t) async {
      final rec = _rec('a', estimate: _prEst(10));
      final notice = (await t.runAsync(() => setup(t, true, rec)))!;
      await pumpFlow(t, e, _row(record: rec), notice);
      await t.tap(find.byKey(const Key('t.edit')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('bodyScan.editWeight.field')), '29');
      await t.tap(find.byKey(const Key('bodyScan.editWeight.save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bodyScan.editWeight.dialog')), findsOneWidget);
      expect(e.scans.saves, 0);
    });

    testWidgets('cancel writes nothing', (t) async {
      final rec = _rec('a', estimate: _prEst(10));
      final notice = (await t.runAsync(() => setup(t, true, rec)))!;
      await pumpFlow(t, e, _row(record: rec), notice);
      await t.tap(find.byKey(const Key('t.edit')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bodyScan.editWeight.cancel')));
      await t.pumpAndSettle();
      expect(e.scans.saves, 0);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
