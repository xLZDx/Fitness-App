import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/body_scan/data/face_check_port.dart';
import 'package:fitness_app/features/body_scan/data/provisional_estimator.dart';
import 'package:fitness_app/features/body_scan/state/blur_service.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_api.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_job_runner.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/photo_upload_port.dart';
import 'package:fitness_app/features/nutrition_plan/data/energy_math.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';

// ---- fakes ---------------------------------------------------------------

class _Repo implements ScanRepository {
  final Map<String, ScanRecord> byId = {};
  final Map<String, int> saves = {};
  int get totalSaves => saves.values.fold(0, (a, b) => a + b);

  void put(ScanRecord r) => byId[r.id] = r;

  bool failList = false;

  @override
  Future<List<ScanRecord>> list() async {
    if (failList) throw StateError('disk');
    final l = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  @override
  Future<void> save(ScanRecord r) async {
    byId[r.id] = r;
    saves[r.id] = (saves[r.id] ?? 0) + 1;
  }

  @override
  Future<void> delete(String id) async => byId.remove(id);

  ScanRecord operator [](String id) => byId[id]!;
}

typedef _CreateFn = FutureOr<CreateScanResult> Function(String scanId, int n);

class _Api implements BodyScanApi {
  final List<String> log = [];
  final List<String> createIds = [];
  final List<String> estimateIds = [];
  final List<(String, bool)> deletes = [];
  final List<_CreateFn> createQueue = [];
  final List<Object> estimateErrors = [];
  Object? deleteError;
  int creates = 0;

  int get calls => createIds.length + estimateIds.length + deletes.length;

  static CreateScanResult pending(String scanId, int n,
          {bool requiresPhotos = true}) =>
      CreateScanResult(
        scanId: scanId,
        done: false,
        provider: BodyScanProviderInfo(
            id: 'cloud', version: '1', provisional: false, requiresPhotos: requiresPhotos),
        uploads: requiresPhotos
            ? {
                for (final p in ScanPose.ordered)
                  p: BodyScanUploadTarget(
                    url: 'https://up/$scanId/${p.name}/$n',
                    headers: {'Content-Type': 'image/jpeg'},
                    expiresAtMs: 0,
                  ),
              }
            : const {},
      );

  @override
  Future<CreateScanResult> createBodyScan({
    required String scanId,
    required DateTime takenAt,
    required String sexAtBirth,
    required int heightCm,
    required double weightKg,
    required Map<ScanPose, bool> manualOverride,
  }) async {
    creates++;
    createIds.add(scanId);
    log.add('create:$scanId');
    if (createQueue.isNotEmpty) return createQueue.removeAt(0)(scanId, creates);
    return pending(scanId, creates);
  }

  @override
  Future<EstimateResult> estimateBodyScan(String scanId) async {
    estimateIds.add(scanId);
    log.add('estimate:$scanId');
    if (estimateErrors.isNotEmpty) throw estimateErrors.removeAt(0);
    return EstimateResult(scanId: scanId, estimate: _cloudEstimate);
  }

  @override
  Future<void> deleteBodyScan(String scanId, {required bool photosOnly}) async {
    deletes.add((scanId, photosOnly));
    log.add('delete:$scanId');
    if (deleteError != null) throw deleteError!;
  }
}

const _cloudEstimate = BodyFatEstimate(
  value: 20,
  low: 17,
  high: 23,
  confidence: EstimateConfidence.medium,
  modelId: 'cloud-model',
  modelVersion: '1',
  provisional: false,
);

class _Uploader implements PhotoUploadPort {
  final List<(String, Uint8List)> puts = [];
  final List<Object> errors = []; // consumed one per put call
  Completer<void>? block;
  int aborts = 0;

  @override
  Future<void> put(BodyScanUploadTarget target, Uint8List jpeg,
      {void Function(int, int)? onProgress}) async {
    puts.add((target.url, jpeg));
    if (block != null) await block!.future;
    if (errors.isNotEmpty) throw errors.removeAt(0);
  }

  @override
  void abortInFlight() => aborts++;
}

class _Blur extends BlurService {
  _Blur({this.refusal});
  final BlurRefusal? refusal;
  final List<(Uint8List, int)> calls = [];

  @override
  Future<BlurOutcome> blur(
      {required Uint8List photo, required List<ScanLandmark> landmarks}) async {
    calls.add((photo, landmarks.length));
    if (refusal != null) return BlurRefused(refusal!);
    return BlurSuccess(Uint8List.fromList([...photo, 0xB1]));
  }
}

class _Face extends FaceCheckPort {
  _Face(this.result, {this.throws = false});
  final FaceCheckResult result;
  final bool throws;
  int calls = 0;

  @override
  Future<FaceCheckResult> countFaces(Uint8List jpeg) async {
    calls++;
    if (throws) throw StateError('detector crashed');
    return result;
  }
}

class _BadEstimator implements BodyCompositionEstimator {
  @override
  String get id => 'bad';
  @override
  String get version => '1';
  @override
  bool get provisional => true;
  @override
  bool get requiresPhotos => false;
  @override
  Future<BodyFatEstimate> estimate(EstimatorInput input) async =>
      const BodyFatEstimate(
        value: 2,
        low: 1,
        high: 3,
        confidence: EstimateConfidence.low,
        modelId: 'bad',
        modelVersion: '1',
        provisional: true,
      );
}

// ---- harness ---------------------------------------------------------------

const _subject = EstimatorSubject(
    heightCm: 175, weightKg: 80, ageYears: 30, sex: SexBasis.male);

ScanRecord _rec(
  String id, {
  DateTime? at,
  ScanAnalysis? analysis = const ScanAnalysis.queued(),
  double? weight = 80,
  Map<ScanPose, bool> override = const {},
  bool pendingDelete = false,
}) =>
    ScanRecord(
      id: id,
      createdAt: at ?? DateTime.utc(2026, 10, 1, 8),
      shots: {
        for (final p in ScanPose.ordered)
          p: ScanShot(photoId: 'ph_${id}_${p.name}', landmarks: const [
            ScanLandmark(name: 'nose', x: 0.5, y: 0.1, likelihood: 0.9),
          ]),
      },
      analysis: analysis,
      weightKg: weight,
      manualOverride: override,
      pendingRemoteDelete: pendingDelete,
    );

class _H {
  _H({
    bool cloud = false,
    int? consent,
    FaceCheckPort? face,
    BlurService? blurService,
    this.subject = _subject,
    BodyCompositionEstimator? estimator,
  })  : flags = BodyScanFlags(cloudPhotos: cloud),
        settings = BodyScanSettings(cloudConsentVersion: consent),
        face = face ?? _Face(const FacesFound(0)),
        blur = blurService ?? _Blur() {
    runner = BodyScanJobRunner(
      scans: repo,
      readPhoto: (id) async {
        reads.add(id);
        return photoMissing ? null : Uint8List.fromList([1, 2, 3]);
      },
      api: api,
      uploader: uploader,
      blur: this.blur,
      faceCheck: this.face,
      flags: flags,
      settings: () => settings,
      resolveSubject: (r) async {
        subjectCalls++;
        await subjectGate?.future;
        if (subjectQueue.isNotEmpty) return subjectQueue.removeAt(0);
        return this.subject;
      },
      subjectPending: (_) => subjectLoading,
      onRemoteDeleteFlushed: (r) async {
        flushed.add(r.id);
        await repo.delete(r.id);
      },
      accountChanged: () => changed(),
      now: () => clock,
      onChanged: () => changes++,
      onScanDone: done.add,
      onError: errors.add,
      estimator: estimator ?? const ProvisionalEstimator(),
    );
  }

  final repo = _Repo();
  final api = _Api();
  final uploader = _Uploader();
  final BlurService blur;
  final FaceCheckPort face;
  final BodyScanFlags flags;
  final BodyScanSettings settings;
  final EstimatorSubject? subject;
  late final BodyScanJobRunner runner;
  DateTime clock = DateTime.utc(2026, 10, 2, 9);
  bool Function() changed = () => false;
  bool photoMissing = false;
  Completer<void>? subjectGate;
  int subjectCalls = 0;
  bool subjectLoading = false;
  final List<EstimatorSubject?> subjectQueue = [];
  final List<String> flushed = [];
  int changes = 0;
  final List<String> reads = [];
  final List<String> done = [];
  final List<Object> errors = [];

  /// Waits for a run (also one started by `retry`) to finish.
  Future<void> settle() async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(Duration.zero);
      if (!runner.isBusy) return;
    }
    fail('runner never became idle');
  }

  Future<void> run() async {
    await runner.resume();
    await settle();
  }

  void tick(int seconds) => clock = clock.add(Duration(seconds: seconds));
}

void main() {
  late List<_H> hs;
  _H h({
    bool cloud = false,
    int? consent,
    FaceCheckPort? face,
    BlurService? blurService,
    EstimatorSubject? subject = _subject,
    BodyCompositionEstimator? estimator,
  }) {
    final x = _H(
        cloud: cloud,
        consent: consent,
        face: face,
        blurService: blurService,
        subject: subject,
        estimator: estimator);
    hs.add(x);
    return x;
  }

  setUp(() => hs = []);
  tearDown(() {
    for (final x in hs) {
      x.runner.dispose();
    }
  });

  group('LOCAL path (default): zero api and zero upload calls', () {
    test('flag off: a queued scan becomes done with the on-device estimate', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      await x.run();

      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.done);
      expect(a.estimate!.value, closeTo(22.047, 0.01));
      expect(a.estimate!.modelId, ProvisionalEstimator.estimatorId);
      expect(a.estimate!.provisional, isTrue);
      expect(a.estimate!.checkCodes, contains(CheckCode.provisionalEstimator));
      expect(a.lastError, isNull);
      expect(a.remoteStatus, isNull);
      expect(x.api.calls, 0);
      expect(x.api.creates, 0);
      expect(x.uploader.puts, isEmpty);
      expect((x.blur as _Blur).calls, isEmpty);
      expect(x.reads, isEmpty, reason: 'a photo is never read on the local path');
      expect((x.face as _Face).calls, 0);
      expect(x.done, ['s1']);
      expect(x.changes, greaterThan(0));
    });

    test('flag off, even with a current consent: still no network', () async {
      final x = h(cloud: false, consent: kBodyScanCloudConsentVersion);
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
      expect(x.api.calls, 0);
      expect(x.uploader.puts, isEmpty);
    });

    test('flag on but consent missing: the cloud branch is unreachable', () async {
      final x = h(cloud: true, consent: null);
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
      expect(x.repo['s1'].analysis!.estimate!.provisional, isTrue);
      expect(x.api.calls, 0);
      expect(x.uploader.puts, isEmpty);
      expect(x.reads, isEmpty);
    });

    test('flag on and consent version 0 (older than current) is not consent', () async {
      final x = h(cloud: true, consent: 0);
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.calls, 0);
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });

    test('a manual capture is recorded in the verified check codes', () async {
      final x = h();
      x.repo.put(_rec('s1', override: {ScanPose.front: true}));
      await x.run();
      expect(x.repo['s1'].analysis!.estimate!.checkCodes,
          contains(CheckCode.manualCapture));
      final y = h();
      y.repo.put(_rec('s2'));
      await y.run();
      expect(y.repo['s2'].analysis!.estimate!.checkCodes,
          isNot(contains(CheckCode.manualCapture)));
    });

    test('a scan saved without a weight carries weightMissing', () async {
      final x = h();
      x.repo.put(_rec('s1', weight: null));
      await x.run();
      expect(x.repo['s1'].analysis!.estimate!.checkCodes,
          contains(CheckCode.weightMissing));
    });

    test('missing height/age/sex fails closed with subject-missing', () async {
      final x = h(subject: null);
      x.repo.put(_rec('s1'));
      await x.run();
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.failed);
      expect(a.lastError, 'subject-missing');
      expect(x.done, isEmpty);
    });

    test('an implausible estimate is rejected, not shown', () async {
      final x = h(estimator: _BadEstimator());
      x.repo.put(_rec('s1'));
      await x.run();
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.failed);
      expect(a.lastError, 'estimate-out-of-range');
      expect(a.estimate, isNull);
      expect(x.done, isEmpty);
    });

    test('the previous scan weight feeds the plausibility context', () async {
      final x = h();
      x.repo.put(_rec('old',
          at: DateTime.utc(2026, 9, 28, 8),
          weight: 60,
          analysis: const ScanAnalysis(status: JobStatus.done, estimate: _cloudEstimate)));
      x.repo.put(_rec('new', at: DateTime.utc(2026, 10, 1, 8), weight: 80));
      await x.run();
      expect(x.repo['new'].analysis!.estimate!.checkCodes,
          contains(CheckCode.weightJump),
          reason: '20 kg in 3 days is a jump');
      expect(x.repo['old'].analysis!.status, JobStatus.done);
      expect(x.repo.saves['old'], isNull, reason: 'a done scan is never rewritten');
    });
  });

  group('queue rules', () {
    test('legacy v1 scans are NEVER touched, even with everything enabled', () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('legacy', analysis: null));
      await x.run();
      expect(x.repo['legacy'].analysis, isNull);
      expect(x.repo.saves['legacy'], isNull);
      expect(x.api.calls, 0);
      expect(x.uploader.puts, isEmpty);
      expect(x.reads, isEmpty);
      expect(x.subjectCalls, 0);
    });

    test('terminal scans (done, failed, cancelled) never re-run', () async {
      final x = h();
      for (final s in [JobStatus.done, JobStatus.failed, JobStatus.cancelled]) {
        x.repo.put(_rec('t_${s.name}', analysis: ScanAnalysis(status: s)));
      }
      await x.run();
      expect(x.repo.totalSaves, 0);
      expect(x.subjectCalls, 0);
    });

    test('an unknown stored status reads as failed and is not resumed', () async {
      final x = h();
      final parsed = ScanRecord.tryFromJson({
        ..._rec('s1').toJson(),
        'analysis': {'status': 'warp'},
      })!;
      x.repo.put(parsed);
      await x.run();
      expect(x.repo.totalSaves, 0);
    });

    test('one scan at a time, oldest first', () async {
      final x = h();
      x.repo.put(_rec('b', at: DateTime.utc(2026, 10, 2)));
      x.repo.put(_rec('a', at: DateTime.utc(2026, 10, 1)));
      await x.run();
      expect(x.done, ['a', 'b']);
    });

    test('resume while a run is active is a no-op', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      x.subjectGate = Completer<void>();
      final first = x.runner.resume();
      await Future<void>.delayed(Duration.zero);
      expect(x.runner.isBusy, isTrue);
      await x.runner.resume(); // returns immediately
      await x.runner.resume();
      x.subjectGate!.complete();
      await first;
      expect(x.subjectCalls, 1, reason: 'the scan was processed exactly once');
      expect(x.done, ['s1']);
    });

    test('a disposed runner does nothing', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      x.runner.dispose();
      await x.runner.resume();
      expect(x.repo.totalSaves, 0);
    });
  });

  group('account-change fence', () {
    test('account already changed: no write, no call', () async {
      final x = h(cloud: true, consent: 1);
      x.changed = () => true;
      x.repo.put(_rec('s1'));
      x.repo.put(_rec('s2', pendingDelete: true, analysis: const ScanAnalysis(status: JobStatus.done)));
      await x.run();
      expect(x.repo.totalSaves, 0);
      expect(x.api.calls, 0);
      expect(x.uploader.puts, isEmpty);
    });

    test('account changes mid-run: the result is never written', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      var calls = 0;
      x.changed = () => ++calls > 2; // fine at the start, gone after subject
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.queued);
      expect(x.repo.totalSaves, 0);
      expect(x.done, isEmpty);
    });

    test('account changes between the cloud steps: nothing after it is called',
        () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1'));
      // Flip once the first PUT has happened.
      x.changed = () => x.uploader.puts.isNotEmpty;
      await x.run();
      expect(x.uploader.puts, hasLength(1));
      expect(x.api.estimateIds, isEmpty);
      expect(x.repo['s1'].analysis!.status, isNot(JobStatus.done));
    });

    test('retry and cancel do nothing for a foreign account', () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1', analysis: const ScanAnalysis(status: JobStatus.failed, attempt: 5)));
      x.changed = () => true;
      await x.runner.retry('s1');
      await x.runner.cancel('s1');
      expect(x.repo.totalSaves, 0);
      expect(x.api.deletes, isEmpty);
    });
  });

  group('CLOUD path', () {
    test('create, blur, face check, 3 sequential PUTs, estimate, done', () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1'));
      await x.run();

      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.done);
      expect(a.remoteStatus, 'done');
      expect(a.estimate!.modelId, 'cloud-model');
      expect(a.estimate!.provisional, isFalse);
      expect(x.api.log, ['create:s1', 'estimate:s1']);
      expect(x.uploader.puts.map((p) => p.$1), [
        'https://up/s1/front/1',
        'https://up/s1/side/1',
        'https://up/s1/back/1',
      ], reason: 'poses are uploaded in order, one at a time');
      // The uploaded bytes are the BLURRED bytes (marker 0xB1), never the photo.
      expect(x.uploader.puts.every((p) => p.$2.last == 0xB1), isTrue);
      expect((x.blur as _Blur).calls, hasLength(3));
      expect((x.blur as _Blur).calls.every((c) => c.$2 == 1), isTrue,
          reason: 'the stored landmarks reach the blur');
      expect((x.face as _Face).calls, 3);
      expect(x.reads, ['ph_s1_front', 'ph_s1_side', 'ph_s1_back']);
      expect(x.done, ['s1']);
    });

    test('status moves queued -> uploading -> analysing -> done', () async {
      final seen = <JobStatus>[];
      final y = _H(cloud: true, consent: 1);
      y.repo.put(_rec('s1'));
      final observed = _ObservingRepo(y.repo, seen);
      hs.add(y);
      final runner = BodyScanJobRunner(
        scans: observed,
        readPhoto: (_) async => Uint8List.fromList([1]),
        api: y.api,
        uploader: y.uploader,
        blur: y.blur,
        faceCheck: y.face,
        flags: y.flags,
        settings: () => y.settings,
        resolveSubject: (_) async => _subject,
        accountChanged: () => false,
        now: () => y.clock,
      );
      await runner.resume();
      runner.dispose();
      expect(seen.first, JobStatus.uploading);
      expect(seen, contains(JobStatus.analysing));
      expect(seen.last, JobStatus.done);
      expect(seen.indexOf(JobStatus.uploading) < seen.indexOf(JobStatus.analysing),
          isTrue);
    });

    test('an idempotent replay (create returns done) uploads and estimates nothing',
        () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) => CreateScanResult(
            scanId: id,
            done: true,
            provider: const BodyScanProviderInfo(
                id: 'cloud', version: '1', provisional: false, requiresPhotos: true),
            estimate: _cloudEstimate,
          ));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
      expect(x.uploader.puts, isEmpty);
      expect(x.api.estimateIds, isEmpty);
    });

    test('a provider that needs no photos goes straight to estimate', () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) => _Api.pending(id, n, requiresPhotos: false));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.uploader.puts, isEmpty);
      expect((x.blur as _Blur).calls, isEmpty);
      expect(x.api.estimateIds, ['s1']);
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });

    for (final slug in ['provider-not-configured', 'feature-disabled']) {
      test('$slug falls back to the on-device estimate without uploading',
          () async {
        final x = h(cloud: true, consent: 1);
        x.api.createQueue.add(
            (id, n) => throw BodyScanApiException(slug, retriable: false));
        x.repo.put(_rec('s1'));
        await x.run();
        final a = x.repo['s1'].analysis!;
        expect(a.status, JobStatus.done);
        expect(a.estimate!.provisional, isTrue);
        expect(x.uploader.puts, isEmpty);
        expect(x.api.creates, 1);
      });
    }

    test('photo that cannot be read: failed photo-missing, nothing uploaded',
        () async {
      final x = h(cloud: true, consent: 1);
      x.photoMissing = true;
      x.repo.put(_rec('s1'));
      await x.run();
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.failed);
      expect(a.lastError, 'photo-missing');
      expect(x.uploader.puts, isEmpty);
    });
  });

  group('fail closed before any upload (D-4, D-69)', () {
    test('the DEFAULT face check ("cannot verify") refuses every upload', () async {
      final x = h(cloud: true, consent: 1, face: const UnavailableFaceCheck());
      x.repo.put(_rec('s1'));
      await x.run();
      final a = x.repo['s1'].analysis!;
      expect(x.uploader.puts, isEmpty);
      expect(x.api.estimateIds, isEmpty);
      expect(a.status, JobStatus.failed);
      expect(a.lastError, 'blur-unavailable');
      expect(checkCodeForSlug(a.lastError), CheckCode.blurUnavailable);
      expect(checkCodeForSlug('network-error'), isNull);
      expect(checkCodeForSlug(null), isNull);
    });

    test('a remaining face refuses the upload', () async {
      final x = h(cloud: true, consent: 1, face: _Face(const FacesFound(1)));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.uploader.puts, isEmpty);
      expect(x.repo['s1'].analysis!.lastError, 'blur-unavailable');
    });

    test('a crashing detector refuses the upload', () async {
      final x = h(
          cloud: true,
          consent: 1,
          face: _Face(const FacesFound(0), throws: true));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.uploader.puts, isEmpty);
      expect(x.repo['s1'].analysis!.status, JobStatus.failed);
    });

    for (final r in BlurRefusal.values) {
      test('blur refusal ${r.name}: no PUT and no face check', () async {
        final f = _Face(const FacesFound(0));
        final x = h(
            cloud: true, consent: 1, blurService: _Blur(refusal: r), face: f);
        x.repo.put(_rec('s1'));
        await x.run();
        expect(x.uploader.puts, isEmpty);
        expect(f.calls, 0);
        expect(x.repo['s1'].analysis!.lastError, 'blur-unavailable');
        expect(x.repo['s1'].analysis!.status, JobStatus.failed,
            reason: 'a refusal is not retried automatically');
      });
    }
  });

  group('scan-cancelled rotates remoteId', () {
    test('first create says scan-cancelled -> retried as <id>_r1', () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) =>
          throw const BodyScanApiException('scan-cancelled', retriable: false));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.createIds, ['s1', 's1_r1']);
      final rec = x.repo['s1'];
      expect(rec.remoteId, 's1_r1');
      expect(rec.analysis!.status, JobStatus.done);
      expect(x.api.estimateIds, ['s1_r1']);
      expect(x.uploader.puts.first.$1, startsWith('https://up/s1_r1/'));
      expect(rec.id, 's1', reason: 'the local id never changes');
    });

    test('a second tombstone rotates again to _r2, a third to _r3', () async {
      final x = h(cloud: true, consent: 1);
      for (var i = 0; i < 3; i++) {
        x.api.createQueue.add((id, n) =>
            throw const BodyScanApiException('scan-cancelled', retriable: false));
      }
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.createIds, ['s1', 's1_r1', 's1_r2', 's1_r3']);
      expect(x.repo['s1'].remoteId, 's1_r3');
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });

    test('the rotation is capped at 3: a fourth tombstone fails the scan',
        () async {
      final x = h(cloud: true, consent: 1);
      for (var i = 0; i < 6; i++) {
        x.api.createQueue.add((id, n) =>
            throw const BodyScanApiException('scan-cancelled', retriable: false));
      }
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.creates, 4);
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.failed);
      expect(a.lastError, 'scan-cancelled');
      expect(x.uploader.puts, isEmpty);
    });

    test('an already rotated remoteId keeps rotating from its suffix', () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) =>
          throw const BodyScanApiException('scan-cancelled', retriable: false));
      x.repo.put(_rec('s1',
          analysis: const ScanAnalysis(status: JobStatus.queued, remoteId: 's1_r4')));
      await x.run();
      expect(x.api.createIds, ['s1_r4', 's1_r5']);
    });
  });

  group('expired upload URL', () {
    test('403 once: ONE idempotent re-create with the same id, then it succeeds',
        () async {
      final x = h(cloud: true, consent: 1);
      x.uploader.errors.add(const BodyScanApiException('upload-url-expired'));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.createIds, ['s1', 's1'], reason: 'same scan id both times');
      expect(x.uploader.puts.map((p) => p.$1), [
        'https://up/s1/front/1',
        'https://up/s1/front/2', // fresh URL
        'https://up/s1/side/2',
        'https://up/s1/back/2',
      ]);
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });

    test('expiring twice for the same pose is not retried a second time',
        () async {
      final x = h(cloud: true, consent: 1);
      x.uploader.errors
        ..add(const BodyScanApiException('upload-url-expired'))
        ..add(const BodyScanApiException('upload-url-expired'));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.creates, 2);
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.queued);
      expect(a.attempt, 1);
      expect(a.lastError, 'upload-url-expired');
    });
  });

  group('retry, backoff and the 5-attempt cap', () {
    test('a retriable failure requeues with attempt+1 and waits 1,2,4,8 s',
        () async {
      final x = h(cloud: true, consent: 1);
      for (var i = 0; i < 10; i++) {
        x.api.createQueue.add((id, n) =>
            throw const BodyScanApiException('upload-url-failed'));
      }
      x.repo.put(_rec('s1'));

      await x.run();
      var a = x.repo['s1'].analysis!;
      expect([a.status, a.attempt, a.lastError],
          [JobStatus.queued, 1, 'upload-url-failed']);
      expect(x.api.creates, 1);

      // Not due yet: resuming immediately must not call the server.
      await x.run();
      expect(x.api.creates, 1);
      x.tick(1);
      await x.run();
      a = x.repo['s1'].analysis!;
      expect([x.api.creates, a.attempt], [2, 2]);

      x.tick(1); // needs 2 s
      await x.run();
      expect(x.api.creates, 2, reason: '1 s < 2 s backoff');
      x.tick(1);
      await x.run();
      expect([x.api.creates, x.repo['s1'].analysis!.attempt], [3, 3]);

      x.tick(3); // needs 4 s
      await x.run();
      expect(x.api.creates, 3);
      x.tick(1);
      await x.run();
      expect([x.api.creates, x.repo['s1'].analysis!.attempt], [4, 4]);

      x.tick(7); // needs 8 s
      await x.run();
      expect(x.api.creates, 4);
      x.tick(1);
      await x.run();
      a = x.repo['s1'].analysis!;
      expect(x.api.creates, 5);
      expect(a.status, JobStatus.failed, reason: 'the 5th failure caps the job');
      expect(a.attempt, 5);
      expect(a.lastError, 'upload-url-failed');

      // Capped: no further automatic attempt, however long we wait.
      x.tick(100000);
      await x.run();
      expect(x.api.creates, 5);
    });

    test('retry() on a failed scan resets attempts and runs it again', () async {
      final x = h();
      x.repo.put(_rec('s1',
          analysis: const ScanAnalysis(
              status: JobStatus.failed, attempt: 5, lastError: 'network-error')));
      await x.runner.retry('s1');
      await x.settle();
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.done);
      expect(a.attempt, 0);
      expect(a.lastError, isNull);
    });

    test('retry() of an unknown or legacy scan is a no-op', () async {
      final x = h();
      x.repo.put(_rec('legacy', analysis: null));
      await x.runner.retry('missing');
      await x.runner.retry('legacy');
      expect(x.repo.totalSaves, 0);
    });

    test('a non-retriable error fails at once without counting an attempt',
        () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) =>
          throw const BodyScanApiException('consent-required', retriable: false));
      x.repo.put(_rec('s1'));
      await x.run();
      final a = x.repo['s1'].analysis!;
      expect(a.status, JobStatus.failed);
      expect(a.attempt, 0);
      expect(a.lastError, 'consent-required');
      await x.run();
      expect(x.api.creates, 1);
    });

    test('a retried upload re-creates with the SAME scan id (idempotent)',
        () async {
      final x = h(cloud: true, consent: 1);
      x.uploader.errors.add(const BodyScanApiException('upload-failed'));
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.queued);
      expect(x.repo['s1'].analysis!.lastError, 'upload-failed');
      x.tick(1);
      await x.run();
      expect(x.api.createIds, ['s1', 's1']);
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });

    test('a record persisted as uploading with attempt 2 resumes after a kill',
        () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1',
          analysis: ScanAnalysis(
              status: JobStatus.uploading,
              attempt: 2,
              updatedAt: DateTime.utc(2026, 10, 2, 8))));
      await x.run();
      expect(x.api.createIds, ['s1']);
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });
  });

  group('error scrubbing (D-67)', () {
    test('a raw exception text never reaches lastError or onError', () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) =>
          throw StateError('open /users/uid123/photos/secret.jpg failed'));
      x.repo.put(_rec('s1'));
      await x.run();
      final a = x.repo['s1'].analysis!;
      expect(a.lastError, 'unknown-error');
      expect(x.errors, isNotEmpty);
      for (final e in x.errors) {
        expect(e.toString(), isNot(contains('secret')));
        expect(e.toString(), isNot(contains('uid123')));
      }
    });
  });

  group('cancel', () {
    test('cancel during an upload aborts the PUT, deletes remotely, and the run never overwrites it',
        () async {
      final x = h(cloud: true, consent: 1);
      x.uploader.block = Completer<void>();
      x.repo.put(_rec('s1'));
      final running = x.runner.resume();
      for (var i = 0; i < 50 && x.uploader.puts.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(x.uploader.puts, hasLength(1), reason: 'precondition: mid-upload');

      await x.runner.cancel('s1');
      expect(x.uploader.aborts, greaterThanOrEqualTo(1));
      expect(x.api.deletes, [('s1', false)]);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);

      x.uploader.block!.complete(); // the aborted PUT returns
      await running;
      await x.settle();
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled,
          reason: 'the run must not resurrect or complete a cancelled scan');
      expect(x.api.estimateIds, isEmpty);
      expect(x.uploader.puts, hasLength(1), reason: 'no further pose is uploaded');
      expect(x.done, isEmpty);
    });

    test('a failing remote delete is owed: pendingRemoteDelete, then flushed on resume',
        () async {
      final x = h(cloud: true, consent: 1);
      x.api.deleteError = const BodyScanApiException('scan-delete-failed');
      x.repo.put(_rec('s1',
          analysis: const ScanAnalysis(status: JobStatus.uploading, remoteStatus: 'pending')));
      await x.runner.cancel('s1');
      expect(x.repo['s1'].pendingRemoteDelete, isTrue);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.errors.map((e) => e.toString()).join(), contains('scan-delete-failed'));

      // Still failing: stays owed.
      await x.run();
      expect(x.repo['s1'].pendingRemoteDelete, isTrue);
      expect(x.api.deletes.length, 2);

      // Server reachable again.
      x.api.deleteError = null;
      await x.run();
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
      expect(x.api.deletes.length, 3);
      expect(x.api.deletes.last, ('s1', false));
      await x.run();
      expect(x.api.deletes.length, 3, reason: 'nothing more is owed');
    });

    test('the owed delete uses the rotated remote id', () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1',
          pendingDelete: true,
          analysis: const ScanAnalysis(status: JobStatus.cancelled, remoteId: 's1_r2')));
      await x.run();
      expect(x.api.deletes, [('s1_r2', false)]);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
    });

    test('with the cloud flag off cancel makes no server call at all', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      await x.runner.cancel('s1');
      expect(x.api.calls, 0);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
    });

    test('a cancelled queued scan is not run afterwards', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      await x.runner.cancel('s1');
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.done, isEmpty);
    });

    test('forget(): a locally deleted scan is never resurrected', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      x.runner.forget('s1');
      expect(x.uploader.aborts, 1);
      await x.run();
      expect(x.repo.totalSaves, 0);
      expect(x.done, isEmpty);
    });
  });

  group('review fixes: owed delete, not-ready inputs, timer, errors', () {
    test('SF-F1: an owed delete makes a queued scan non-resumable; after the '
        'flush nothing is created or uploaded and the record stays terminal',
        () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1',
          pendingDelete: true,
          analysis: const ScanAnalysis(status: JobStatus.queued)));
      await x.run();
      expect(x.api.deletes, [('s1', false)]);
      expect(x.api.creates, 0);
      expect(x.uploader.puts, isEmpty);
      expect(x.done, isEmpty);
    });

    test('SF-F1: a run holding an older copy never overwrites a cancel that '
        'landed meanwhile', () async {
      final x = h();
      x.repo.put(_rec('s1'));
      x.subjectGate = Completer<void>();
      final running = x.runner.resume();
      await Future<void>.delayed(Duration.zero);
      // Another writer (the actions) records the cancel + owed delete.
      x.repo.put(x.repo['s1'].copyWith(
          pendingRemoteDelete: true,
          analysis: const ScanAnalysis(status: JobStatus.cancelled)));
      x.subjectGate!.complete();
      await running;
      expect(x.repo['s1'].pendingRemoteDelete, isTrue);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.done, isEmpty);
    });

    test('SF-F5: an owed PHOTOS-ONLY delete is sent as photosOnly and the '
        'phone copy goes after the flush', () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(ScanRecord(
        id: 'p1',
        createdAt: DateTime.utc(2026, 10, 1),
        shots: const {},
        analysis: const ScanAnalysis(status: JobStatus.done),
        pendingRemoteDelete: true,
        pendingPhotosOnly: true,
      ));
      await x.run();
      expect(x.api.deletes, [('p1', true)]);
      expect(x.flushed, ['p1']);
      expect(x.repo.byId.containsKey('p1'), isFalse);
    });

    test('SF-F5: a failing photos-only flush keeps the flag and the phone copy',
        () async {
      final x = h(cloud: true, consent: 1);
      x.api.deleteError = const BodyScanApiException('scan-delete-failed');
      x.repo.put(ScanRecord(
        id: 'p1',
        createdAt: DateTime.utc(2026, 10, 1),
        shots: const {},
        analysis: const ScanAnalysis(status: JobStatus.done),
        pendingRemoteDelete: true,
        pendingPhotosOnly: true,
      ));
      await x.run();
      expect(x.flushed, isEmpty);
      expect(x.repo['p1'].pendingRemoteDelete, isTrue);
    });

    test('SF-F2: inputs still loading keep the scan queued, then it completes',
        () async {
      final x = h();
      x.subjectLoading = true;
      x.subjectQueue.add(null);
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.queued);
      expect(x.repo['s1'].analysis!.lastError, isNull);
      expect(x.repo.totalSaves, 0);
      x.subjectLoading = false;
      await x.run();
      expect(x.repo['s1'].analysis!.status, JobStatus.done);
    });

    test('SF-F2: a LOADED profile lacking data is still subject-missing',
        () async {
      final x = h(subject: null);
      x.subjectLoading = false;
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.repo['s1'].analysis!.lastError, 'subject-missing');
    });

    test('SF-F2: loading inputs on the cloud path make no API call', () async {
      final x = h(cloud: true, consent: 1, subject: null);
      x.subjectLoading = true;
      x.repo.put(_rec('s1'));
      await x.run();
      expect(x.api.calls, 0);
      expect(x.repo['s1'].analysis!.status, JobStatus.queued);
    });

    test('SF-F3: a resume that arrives while busy is not lost (rerun pass)',
        () async {
      final x = h();
      x.repo.put(_rec('a', at: DateTime.utc(2026, 10, 1)));
      x.subjectGate = Completer<void>();
      final first = x.runner.resume();
      await Future<void>.delayed(Duration.zero);
      // A second scan arrives and the timer-style resume hits a busy runner.
      x.repo.put(_rec('b', at: DateTime.utc(2026, 10, 2)));
      await x.runner.resume();
      x.subjectGate!.complete();
      await first;
      expect(x.done, ['a', 'b'],
          reason: 'the second pass picked up what the busy runner had missed');
    });

    test('SF-F3: a scan that failed during the pass is re-run by the retry '
        'timer even though another scan was skipped as not due', () async {
      final x = h(cloud: true, consent: 1);
      x.api.createQueue.add((id, n) =>
          throw const BodyScanApiException('upload-url-failed'));
      x.repo.put(_rec('a', at: DateTime.utc(2026, 10, 1)));
      // b is backing off with a LATER due time than a's first retry.
      x.repo.put(_rec('b',
          at: DateTime.utc(2026, 10, 2),
          analysis: ScanAnalysis(
              status: JobStatus.queued,
              attempt: 4,
              updatedAt: x.clock.add(const Duration(seconds: 1)))));
      await x.run();
      expect(x.repo['a'].analysis!.attempt, 1);
      // a's retry (1 s) must still be armed: let the real timer fire.
      x.tick(2);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      await x.settle();
      expect(x.api.createIds.where((i) => i == 'a').length, greaterThanOrEqualTo(2));
    });

    test('SF-F6: a failing repository never escapes resume, retry or cancel',
        () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('s1'));
      x.repo.failList = true;
      await x.runner.resume();
      await x.runner.retry('s1');
      await x.runner.cancel('s1');
      expect(x.errors, isNotEmpty);
    });
  });

  group('pending remote delete flush', () {
    test('runs before the queue and clears the flag on success', () async {
      final x = h(cloud: true, consent: 1);
      x.repo.put(_rec('gone',
          at: DateTime.utc(2026, 9, 1),
          pendingDelete: true,
          analysis: const ScanAnalysis(status: JobStatus.done)));
      x.repo.put(_rec('next'));
      await x.run();
      expect(x.api.log.first, 'delete:gone');
      expect(x.repo['gone'].pendingRemoteDelete, isFalse);
      expect(x.repo['next'].analysis!.status, JobStatus.done);
    });
  });

  // Cancel while createBodyScan is unresolved. The server writes a cancellation
  // tombstone on deleteBodyScan even when the scan doc does not exist yet and
  // then refuses createBodyScan for that id ('scan-cancelled'), so the client
  // only has to guarantee that the delete is SENT or durably OWED.
  group('cancel while createBodyScan is unresolved', () {
    /// A second runner over the same stores = an app restart.
    BodyScanJobRunner restarted(_H x) => BodyScanJobRunner(
          scans: x.repo,
          readPhoto: (id) async => Uint8List.fromList([1, 2, 3]),
          api: x.api,
          uploader: x.uploader,
          blur: x.blur,
          faceCheck: x.face,
          flags: x.flags,
          settings: () => x.settings,
          resolveSubject: (r) async => _subject,
          accountChanged: () => false,
          now: () => x.clock,
          onError: x.errors.add,
        );

    /// Waits until createBodyScan is in flight.
    Future<void> waitCreateInFlight(_H x) async {
      for (var i = 0; i < 50 && x.api.createIds.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(x.api.createIds, ['s1'], reason: 'precondition: create in flight');
      expect(x.repo['s1'].analysis!.status, JobStatus.uploading,
          reason: 'precondition: the scan is persisted as uploading');

    }

    void expectNothingStartedAfterCancel(_H x) {
      expect(x.api.estimateIds, isEmpty);
      expect(x.uploader.puts, isEmpty, reason: 'no photo PUT after a cancel');
      expect(x.reads, isEmpty);
      expect(x.done, isEmpty);
      expect(x.api.createIds, ['s1'], reason: 'the scan is never re-created');
    }

    test('(a) create then succeeds: delete was sent, scan stays cancelled, nothing starts',
        () async {
      final x = h(cloud: true, consent: 1);
      final gate = Completer<CreateScanResult>();
      x.api.createQueue.add((id, n) => gate.future);
      x.repo.put(_rec('s1'));
      final running = x.runner.resume();
      await waitCreateInFlight(x);

      await x.runner.cancel('s1');
      expect(x.api.log, ['create:s1', 'delete:s1'],
          reason: 'the delete is sent while create is still unresolved');
      expect(x.api.deletes, [('s1', false)]);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);

      gate.complete(_Api.pending('s1', 1)); // the late create succeeds
      await running;
      await x.settle();
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
      expectNothingStartedAfterCancel(x);

      await x.run(); // a later resume must not restart it either
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expectNothingStartedAfterCancel(x);
      expect(x.api.deletes, [('s1', false)], reason: 'delete is not repeated');
    });

    test('(b) delete fails: owed delete is persisted and flushed after a restart',
        () async {
      final x = h(cloud: true, consent: 1);
      final gate = Completer<CreateScanResult>();
      x.api.createQueue.add((id, n) => gate.future);
      x.api.deleteError = const BodyScanApiException('scan-delete-failed');
      x.repo.put(_rec('s1'));
      final running = x.runner.resume();
      await waitCreateInFlight(x);

      await x.runner.cancel('s1');
      expect(x.api.deletes, [('s1', false)]);
      expect(x.repo['s1'].pendingRemoteDelete, isTrue);
      expect(x.repo['s1'].remoteId, 's1');
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);

      gate.complete(_Api.pending('s1', 1));
      await running;
      await x.settle();
      expect(x.repo['s1'].pendingRemoteDelete, isTrue,
          reason: 'the late create must not clear or lose the owed delete');
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expectNothingStartedAfterCancel(x);

      // App restart: a brand new runner over the same stores, server reachable.
      x.runner.dispose();
      x.api.deleteError = null;
      await restarted(x).resume();
      expect(x.api.deletes, [('s1', false), ('s1', false)],
          reason: 'the owed delete is sent after the restart');
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expectNothingStartedAfterCancel(x);
    });

    test('(c) create response lost: delete is still sent and the scan is not retried',
        () async {
      final x = h(cloud: true, consent: 1);
      final gate = Completer<CreateScanResult>();
      x.api.createQueue.add((id, n) => gate.future);
      x.repo.put(_rec('s1'));
      final running = x.runner.resume();
      await waitCreateInFlight(x);

      await x.runner.cancel('s1');
      expect(x.api.deletes, [('s1', false)]);

      gate.completeError(const BodyScanApiException('network-error')); // lost
      await running;
      await x.settle();
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled,
          reason: 'a lost create must not requeue or fail a cancelled scan');
      expect(x.repo['s1'].analysis!.attempt, 0);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
      expectNothingStartedAfterCancel(x);
      await x.run();
      expectNothingStartedAfterCancel(x);
    });

    test('(c2) create response lost AND delete fails: delete stays owed, flushed on restart',
        () async {
      final x = h(cloud: true, consent: 1);
      final gate = Completer<CreateScanResult>();
      x.api.createQueue.add((id, n) => gate.future);
      x.api.deleteError = StateError('offline');
      x.repo.put(_rec('s1'));
      final running = x.runner.resume();
      await waitCreateInFlight(x);

      await x.runner.cancel('s1');
      gate.completeError(StateError('connection reset')); // lost
      await running;
      await x.settle();
      expect(x.repo['s1'].pendingRemoteDelete, isTrue);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expectNothingStartedAfterCancel(x);

      x.runner.dispose();
      x.api.deleteError = null;
      await restarted(x).resume();
      expect(x.api.deletes.length, 2);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expectNothingStartedAfterCancel(x);
    });

    test('(d) delete lands first, late create hits the tombstone: stays cancelled, no re-create',
        () async {
      final x = h(cloud: true, consent: 1);
      final gate = Completer<void>();
      // Fake server: a create that is resolved after a delete of the same id is
      // refused with the tombstone slug.
      x.api.createQueue.add((id, n) async {
        await gate.future;
        if (x.api.deletes.any((d) => d.$1 == id)) {
          throw const BodyScanApiException('scan-cancelled', retriable: false);
        }
        return _Api.pending(id, n);
      });
      x.repo.put(_rec('s1'));
      final running = x.runner.resume();
      await waitCreateInFlight(x);

      await x.runner.cancel('s1');
      expect(x.api.deletes, [('s1', false)], reason: 'delete reached the server first');

      gate.complete();
      await running;
      await x.settle();
      expect(x.repo['s1'].analysis!.status, JobStatus.cancelled);
      expect(x.repo['s1'].pendingRemoteDelete, isFalse);
      expect(x.repo['s1'].remoteId, 's1',
          reason: 'the tombstone must not rotate the id of a cancelled scan');
      expectNothingStartedAfterCancel(x);

      await x.run();
      expectNothingStartedAfterCancel(x);
      expect(x.api.deletes, [('s1', false)]);
    });
  });
}

class _ObservingRepo implements ScanRepository {
  _ObservingRepo(this.inner, this.seen);
  final _Repo inner;
  final List<JobStatus> seen;

  @override
  Future<List<ScanRecord>> list() => inner.list();
  @override
  Future<void> save(ScanRecord r) async {
    if (r.analysis != null) seen.add(r.analysis!.status);
    await inner.save(r);
  }

  @override
  Future<void> delete(String id) => inner.delete(id);
}
