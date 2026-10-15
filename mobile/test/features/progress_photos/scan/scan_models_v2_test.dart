import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/check_items.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';

Map<String, Object?> _shots() => {
      for (final p in ScanPose.ordered)
        p.name: {
          'photoId': 'ph_${p.name}',
          'landmarks': [
            {'n': 'nose', 'x': 0.5, 'y': 0.1, 'l': 0.9},
          ],
        },
    };

Map<String, Object?> _v1() => {
      'id': 'scan_1',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'shots': _shots(),
    };

const _estimate = BodyFatEstimate(
  value: 21.5,
  low: 18.0,
  high: 25.0,
  confidence: EstimateConfidence.medium,
  modelId: 'provisional-anthropometric',
  modelVersion: '1',
  provisional: true,
  checkCodes: [CheckCode.provisionalEstimator, CheckCode.manualCapture],
);

ScanRecord _roundTrip(ScanRecord r) {
  // Through real JSON text, as the encrypted store does.
  final text = jsonEncode(r.toJson());
  return ScanRecord.tryFromJson(jsonDecode(text))!;
}

void main() {
  group('v1 (legacy) records', () {
    test('a v1 payload without analysis reads as LEGACY and never as queued', () {
      final r = ScanRecord.tryFromJson(_v1())!;
      expect(r.isLegacy, isTrue);
      expect(r.analysis, isNull);
      expect(r.weightKg, isNull);
      expect(r.manualOverride, isEmpty);
      expect(r.pendingRemoteDelete, isFalse);
      expect(r.anyManualOverride, isFalse);
      expect(r.shots.keys.toSet(), ScanPose.values.toSet());
      expect(r.shots[ScanPose.side]!.photoId, 'ph_side');
    });

    test('remoteId of a legacy record is the local id', () {
      expect(ScanRecord.tryFromJson(_v1())!.remoteId, 'scan_1');
    });

    test('a legacy record re-serialises as v2 but still has no analysis', () {
      final again = _roundTrip(ScanRecord.tryFromJson(_v1())!);
      expect(again.isLegacy, isTrue,
          reason: 'saving must not turn a legacy scan into an upload candidate');
      expect(again.toJson()['v'], 2);
      expect(again.toJson().containsKey('analysis'), isFalse);
    });
  });

  group('v2 round trip', () {
    final createdAt = DateTime.utc(2026, 10, 2, 8, 30, 15);
    final updatedAt = DateTime.utc(2026, 10, 2, 8, 31);

    test('every field survives JSON text', () {
      final rec = ScanRecord(
        id: 'scan_9',
        createdAt: createdAt,
        shots: {
          for (final p in ScanPose.ordered)
            p: ScanShot(photoId: 'ph_${p.name}', landmarks: const [
              ScanLandmark(name: 'nose', x: 0.5, y: 0.25, likelihood: 0.75),
            ]),
        },
        analysis: ScanAnalysis(
          status: JobStatus.uploading,
          attempt: 3,
          remoteId: 'scan_9_r1',
          remoteStatus: 'pending',
          lastError: 'network',
          estimate: _estimate,
          updatedAt: updatedAt,
        ),
        weightKg: 81.4,
        manualOverride: const {ScanPose.side: true},
        pendingRemoteDelete: true,
      );
      final back = _roundTrip(rec);
      expect(back.id, 'scan_9');
      expect(back.createdAt.toUtc(), createdAt);
      expect(back.weightKg, 81.4);
      expect(back.pendingRemoteDelete, isTrue);
      expect(back.manualOverride, {ScanPose.side: true});
      expect(back.anyManualOverride, isTrue);
      expect(back.isLegacy, isFalse);
      final a = back.analysis!;
      expect(a.status, JobStatus.uploading);
      expect(a.attempt, 3);
      expect(a.remoteId, 'scan_9_r1');
      expect(a.remoteStatus, 'pending');
      expect(a.lastError, 'network');
      expect(a.updatedAt!.toUtc(), updatedAt);
      expect(a.estimate!.value, 21.5);
      expect(a.estimate!.low, 18.0);
      expect(a.estimate!.high, 25.0);
      expect(a.estimate!.confidence, EstimateConfidence.medium);
      expect(a.estimate!.provisional, isTrue);
      expect(a.estimate!.modelKey, 'provisional-anthropometric|1');
      expect(a.estimate!.checkCodes,
          [CheckCode.provisionalEstimator, CheckCode.manualCapture]);
      expect(back.remoteId, 'scan_9_r1');
      expect(back.shots[ScanPose.front]!.landmarks.single.likelihood, 0.75);
    });

    test('wire shape: v is 2, manualOverride lists all three poses', () {
      final json = ScanRecord(
        id: 'a',
        createdAt: createdAt,
        shots: const {},
        analysis: const ScanAnalysis.queued(),
        manualOverride: const {ScanPose.back: true},
      ).toJson();
      expect(json['v'], 2);
      expect((json['capture'] as Map)['manualOverride'],
          {'front': false, 'side': false, 'back': true});
      expect((json['analysis'] as Map)['status'], 'queued');
      expect(json.containsKey('pendingRemoteDelete'), isFalse,
          reason: 'false is not persisted');
      expect(json.containsKey('weightKg'), isFalse);
    });

    test('ScanAnalysis.queued is status queued with zero attempts', () {
      const a = ScanAnalysis.queued();
      expect(a.status, JobStatus.queued);
      expect(a.attempt, 0);
      expect(a.remoteId, isNull);
      expect(a.estimate, isNull);
    });

    test('copyWith keeps untouched fields and clearLastError clears', () {
      final a = ScanAnalysis(
        status: JobStatus.queued,
        attempt: 2,
        lastError: 'network',
        remoteId: 'x_r1',
      );
      final b = a.copyWith(status: JobStatus.analysing);
      expect(b.status, JobStatus.analysing);
      expect(b.attempt, 2);
      expect(b.lastError, 'network');
      expect(b.remoteId, 'x_r1');
      expect(a.copyWith(clearLastError: true).lastError, isNull);
    });

    test('ScanRecord.copyWith keeps id, shots and createdAt', () {
      final r = ScanRecord.tryFromJson(_v1())!;
      final c = r.copyWith(analysis: const ScanAnalysis.queued(), weightKg: 70);
      expect(c.id, r.id);
      expect(c.shots, same(r.shots));
      expect(c.createdAt, r.createdAt);
      expect(c.analysis!.status, JobStatus.queued);
      expect(c.weightKg, 70);
      expect(c.isLegacy, isFalse);
    });
  });

  group('analysis tolerance', () {
    Map<String, Object?> withAnalysis(Object? a) => {..._v1(), 'analysis': a};

    test('an unknown status reads as failed (terminal, never resumed)', () {
      final r = ScanRecord.tryFromJson(withAnalysis({'status': 'teleporting'}))!;
      expect(r.analysis!.status, JobStatus.failed);
      expect(r.analysis!.status.isTerminal, isTrue);
      expect(r.isLegacy, isFalse);
    });

    test('a missing or non-string status reads as failed', () {
      expect(ScanRecord.tryFromJson(withAnalysis({}))!.analysis!.status,
          JobStatus.failed);
      expect(ScanRecord.tryFromJson(withAnalysis({'status': 7}))!.analysis!.status,
          JobStatus.failed);
    });

    test('a non-map analysis reads as no analysis (legacy)', () {
      expect(ScanRecord.tryFromJson(withAnalysis('queued'))!.isLegacy, isTrue);
    });

    test('negative or non-int attempt reads as 0; empty remoteId as null', () {
      final a = ScanRecord.tryFromJson(withAnalysis({
        'status': 'queued',
        'attempt': -4,
        'remoteId': '',
      }))!
          .analysis!;
      expect(a.attempt, 0);
      expect(a.remoteId, isNull);
      final b = ScanRecord.tryFromJson(withAnalysis({
        'status': 'queued',
        'attempt': 2.5,
      }))!
          .analysis!;
      expect(b.attempt, 0);
    });

    test('a malformed estimate is dropped, the status kept', () {
      final a = ScanRecord.tryFromJson(withAnalysis({
        'status': 'done',
        'estimate': {'bodyFatPct': 'lots'},
      }))!
          .analysis!;
      expect(a.status, JobStatus.done);
      expect(a.estimate, isNull);
    });

    test('an unparseable updatedAt is dropped', () {
      final a = ScanRecord.tryFromJson(
              withAnalysis({'status': 'queued', 'updatedAt': 'yesterday'}))!
          .analysis!;
      expect(a.updatedAt, isNull);
    });
  });

  group('manualOverride and field validation', () {
    test('only an explicit true marks a pose; other values are ignored', () {
      final r = ScanRecord.tryFromJson({
        ..._v1(),
        'capture': {
          'manualOverride': {'front': true, 'side': 'yes', 'back': 1},
        },
      })!;
      expect(r.manualOverride, {ScanPose.front: true});
    });

    test('a non-map capture block yields no override', () {
      final r = ScanRecord.tryFromJson({..._v1(), 'capture': 'x'})!;
      expect(r.manualOverride, isEmpty);
    });

    test('non-finite or non-numeric weight reads as null', () {
      expect(ScanRecord.tryFromJson({..._v1(), 'weightKg': 'heavy'})!.weightKg,
          isNull);
      expect(
          ScanRecord.tryFromJson({..._v1(), 'weightKg': double.nan})!.weightKg,
          isNull);
      expect(ScanRecord.tryFromJson({..._v1(), 'weightKg': 80})!.weightKg, 80.0);
    });

    test('pendingRemoteDelete only for an explicit true', () {
      expect(
          ScanRecord.tryFromJson({..._v1(), 'pendingRemoteDelete': 'true'})!
              .pendingRemoteDelete,
          isFalse);
      expect(
          ScanRecord.tryFromJson({..._v1(), 'pendingRemoteDelete': true})!
              .pendingRemoteDelete,
          isTrue);
    });

    test('malformed top-level payloads return null', () {
      expect(ScanRecord.tryFromJson(null), isNull);
      expect(ScanRecord.tryFromJson('x'), isNull);
      expect(ScanRecord.tryFromJson({..._v1()}..remove('id')), isNull);
      expect(ScanRecord.tryFromJson({..._v1(), 'createdAt': 'nope'}), isNull);
      expect(ScanRecord.tryFromJson({..._v1(), 'shots': 3}), isNull);
    });

    test('a shot with an empty photoId is dropped; bad landmarks skipped', () {
      final r = ScanRecord.tryFromJson({
        ..._v1(),
        'shots': {
          'front': {'photoId': '', 'landmarks': []},
          'side': {
            'photoId': 'ph',
            'landmarks': [
              {'n': 'nose', 'x': 0.1, 'y': 0.2, 'l': 0.5},
              {'n': 'bad'},
            ],
          },
        },
      })!;
      expect(r.shots.keys, [ScanPose.side]);
      expect(r.shots[ScanPose.side]!.landmarks, hasLength(1));
    });
  });
}
