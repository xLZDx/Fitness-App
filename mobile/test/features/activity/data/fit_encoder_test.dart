// S02 test epic 3, U19 (and the FIT half of U18): structural round trip of the
// FIT encoder through the independent test-only decoder.
//
// Oracles: FIT epoch 1989-12-31 = Unix 631065600; semicircles = degrees *
// 2^31 / 180; sport / sub_sport codes from the FIT profile (written here as
// literals, not read from the encoder); record count from the streams of the
// session.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/fit_encoder.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fit_test_decoder.dart';
import '../../../support/s02_fixtures.dart';
import '../../../support/synthetic_activity_corpus.dart';

const int _fitEpoch = 631065600;

/// FIT profile: sport, sub_sport per SportType (literals).
const Map<SportType, (int, int)> _fitSport = {
  SportType.running: (1, 0), // running, generic
  SportType.trailRunning: (1, 3), // running, trail
  SportType.cycling: (2, 0), // cycling, generic
  SportType.indoorCycling: (2, 6), // cycling, indoor_cycling
  SportType.mountainBiking: (2, 8), // cycling, mountain
  SportType.swimmingPool: (5, 17), // swimming, lap_swimming
  SportType.swimmingOpenWater: (5, 18), // swimming, open_water
  SportType.rowing: (15, 0), // rowing, generic
  SportType.walking: (11, 0), // walking, generic
  SportType.hiking: (17, 0), // hiking, generic
  SportType.strength: (10, 20), // training, strength_training
  SportType.other: (0, 0), // generic
};

int _fitSec(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 - _fitEpoch;

int _expectedRecords(ActivitySession s) {
  final gps = s.streams[StreamKind.gps];
  if (gps != null && !gps.isEmpty) return gps.length;
  final offs = <int>{};
  for (final e in s.streams.entries) {
    if (e.key == StreamKind.strokeRate) continue; // not encoded in records
    offs.addAll(e.value.offsetsMs);
  }
  return offs.length;
}

void _check(ActivitySession s, Uint8List bytes) {
  final why = s.id;
  final d = decodeFit(bytes);
  expect(d.errors, isEmpty, reason: why);
  expect(d.ok, isTrue, reason: why);
  expect(d.headerSize, 14, reason: why);
  expect(d.protocolVersion, 0x20, reason: why);
  expect(d.signatureOk, isTrue, reason: why);

  // file_id
  final fileId = d.byNum(0);
  expect(fileId, hasLength(1), reason: why);
  expect(fileId.single.intField(0), 4, reason: '$why file type = activity');
  expect(fileId.single.intField(4), _fitSec(s.startUtc), reason: why);
  expect(d.messages.first.globalNum, 0, reason: 'file_id comes first');

  // session
  final sess = d.byNum(18);
  expect(sess, hasLength(1), reason: why);
  final m = sess.single;
  expect(m.intField(2), _fitSec(s.startUtc), reason: '$why start_time');
  expect(m.intField(253), _fitSec(s.endUtc), reason: '$why timestamp');
  expect(m.intField(7), s.durationMs, reason: '$why elapsed ms');
  expect(m.intField(8),
      s.movingTimeS == null ? s.durationMs : (s.movingTimeS! * 1000).round(),
      reason: '$why timer ms');
  final (sport, sub) = _fitSport[s.sport]!;
  expect(m.intField(5), sport, reason: '$why sport ${s.sport}');
  expect(m.intField(6), sub, reason: '$why sub_sport ${s.sport}');
  final d0 = s.summary.distanceM;
  if (d0 != null && d0 * 100 < 4e9) {
    expect(m.intField(9), (d0 * 100).round(), reason: '$why distance');
  }
  final lapMsgs = d.byNum(19);
  final expectedLaps = s.laps.isEmpty ? 1 : s.laps.length;
  expect(lapMsgs, hasLength(expectedLaps), reason: '$why laps');
  expect(m.intField(26), expectedLaps, reason: '$why num_laps');

  // records
  final recs = d.byNum(20);
  expect(recs, hasLength(_expectedRecords(s)), reason: '$why records');
  var prev = -1;
  final startSec = _fitSec(s.startUtc);
  final gps = s.streams[StreamKind.gps];
  final hr = s.streams[StreamKind.heartRate];
  final hrByOffset = {
    if (hr != null)
      for (var i = 0; i < hr.length; i++) hr.offsetsMs[i]: hr.values[i],
  };
  for (var i = 0; i < recs.length; i++) {
    final ts = recs[i].intField(253)!;
    expect(ts, greaterThanOrEqualTo(prev), reason: '$why record $i order');
    prev = ts;
    if (gps != null && !gps.isEmpty) {
      expect(ts, startSec + gps.offsetsMs[i] ~/ 1000, reason: '$why ts $i');
      final lat = recs[i].intField(0)!;
      final lon = recs[i].intField(1)!;
      expect(lat * 180 / 2147483648, closeTo(gps.lats[i], 1e-6), reason: '$why lat $i');
      expect(lon * 180 / 2147483648, closeTo(gps.lons[i], 1e-6), reason: '$why lon $i');
      final h = hrByOffset[gps.offsetsMs[i]];
      if (h != null) {
        expect(recs[i].intField(3), math.min(254, math.max(0, h.round())),
            reason: '$why hr $i');
      }
    }
  }
  if (gps != null && gps.length > 1) {
    // distance field is cumulative and non-decreasing
    var last = 0;
    for (final r in recs) {
      final dist = r.intField(5)!;
      expect(dist, greaterThanOrEqualTo(last), reason: '$why cumulative distance');
      last = dist;
    }
  }
}

void main() {
  final corpus = SyntheticCorpus.build();

  group('decoder self-tests (the instrument can fail)', () {
    test('CRC-16/ARC known vector 123456789 = 0xBB3D', () {
      expect(fitTestCrc('123456789'.codeUnits), 0xBB3D);
    });

    test('the independent CRC equals the encoder CRC on random data', () {
      final r = SplitMix64(5);
      for (var n = 0; n < 50; n++) {
        final data = [for (var i = 0; i < 1 + r.nextInt(300); i++) r.nextInt(256)];
        expect(fitCrc16(data), fitTestCrc(data), reason: 'len ${data.length}');
      }
    });

    test('one flipped byte makes the decoder report a CRC failure, at every '
        'position of a small file', () {
      final bytes = FitEncoder.encode(miniSession());
      expect(decodeFit(bytes).ok, isTrue);
      for (var i = 0; i < bytes.length; i++) {
        final bad = Uint8List.fromList(bytes)..[i] ^= 0x01;
        final d = decodeFit(bad);
        expect(d.ok, isFalse, reason: 'flip at byte $i');
        expect(d.errors, isNotEmpty, reason: 'flip at byte $i');
      }
    });

    test('a flipped byte in the middle of a large corpus file fails the file CRC',
        () {
      final s = corpus.valid.firstWhere((s) => (s.streams[StreamKind.gps]?.length ?? 0) > 100);
      final bytes = FitEncoder.encode(s);
      final bad = Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 0x80;
      final d = decodeFit(bad);
      expect(d.fileCrcOk, isFalse);
      expect(d.headerCrcOk, isTrue);
    });

    test('truncated and extended files are refused', () {
      final bytes = FitEncoder.encode(miniSession());
      expect(decodeFit(Uint8List.sublistView(bytes, 0, bytes.length - 1)).ok, isFalse);
      expect(decodeFit(Uint8List.fromList([...bytes, 0])).ok, isFalse);
      expect(decodeFit(Uint8List(5)).ok, isFalse);
    });
  });

  group('U19 FIT structural round trip', () {
    test('all 100 valid corpus sessions decode with the right messages and fields',
        () {
      expect(corpus.valid, hasLength(100));
      var withRecords = 0;
      for (final s in corpus.valid) {
        _check(s, FitEncoder.encode(s));
        if (_expectedRecords(s) > 0) withRecords++;
      }
      expect(withRecords, greaterThan(50), reason: 'most sessions carry streams');
    });

    test('record counts are not vacuous: a GPS session has as many records as '
        'GPS samples', () {
      final s = corpus.valid.firstWhere((s) => (s.streams[StreamKind.gps]?.length ?? 0) > 100);
      final d = decodeFit(FitEncoder.encode(s));
      expect(d.byNum(20), hasLength(s.streams[StreamKind.gps]!.length));
    });

    test('a session without any stream still yields file_id, lap and session '
        'and no record', () {
      final s = miniSession();
      final d = decodeFit(FitEncoder.encode(s));
      expect(d.ok, isTrue);
      expect(d.byNum(0), hasLength(1));
      expect(d.byNum(18), hasLength(1));
      expect(d.byNum(19), hasLength(1));
      expect(d.byNum(20), isEmpty);
    });

    test('an indoor session (no GPS) encodes: records follow the other streams',
        () {
      final s = corpus.valid.firstWhere((s) =>
          s.sport == SportType.indoorCycling &&
          s.streams.isNotEmpty &&
          !s.streams.containsKey(StreamKind.gps));
      _check(s, FitEncoder.encode(s));
    });

    test('every sport maps to its FIT sport and sub_sport', () {
      for (final sport in SportType.values) {
        final s = miniSession(sport: sport);
        final m = decodeFit(FitEncoder.encode(s)).byNum(18).single;
        final (a, b) = _fitSport[sport]!;
        expect([m.intField(5), m.intField(6)], [a, b], reason: sport.name);
      }
      expect(_fitSport.keys.toSet(), SportType.values.toSet());
    });

    test('encoding is deterministic', () {
      final s = corpus.valid[3];
      expect(FitEncoder.encode(s), FitEncoder.encode(s));
    });
  });
}
