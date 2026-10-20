// S02 test epic 3, U21, U22, U36: the merger budget is an OPERATION COUNT
// (design 10, DQ-14), reported through the `onPairCompared` seam. Wall-clock
// time is printed for information and never asserted.
//
// Two ceilings per scenario: the design ceiling (100 000 / 4 000 000, the plan
// oracle) and a calibrated ceiling frozen from the first run (see
// docs/phase2/s02/S02_TEST_FINDINGS_EPIC3.md), which is what catches a
// regression towards O(n^2) because n^2/2 = 45 000 for 300 candidates would
// still pass the design ceiling.
import 'package:fitness_app/features/activity/data/activity_merger.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/merge_policy.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/synthetic_activity_corpus.dart';

const _policy = MergePolicy();

// Design ceilings (plan oracle).
const int kDesignCeiling300 = 100000;
const int kDesignCeiling2000 = 4000000;

// Calibrated on the first run (findings epic 3), frozen.
const int kCalibratedCeiling300 = 1000; // measured 300
const int kCalibratedCeiling2000 = 6000; // measured 2000

final DateTime _t0 = DateTime.utc(2026, 3, 1, 5);

const List<(String, SourceKind, String?)> _threeSources = [
  ('garmin', SourceKind.companionApp, null),
  ('strava', SourceKind.vendorCloud, null),
  ('hc', SourceKind.platformHealth, 'garmin'),
];

ActivitySession _session({
  required String source,
  required SourceKind kind,
  String? app,
  required String ext,
  required DateTime start,
  required int durS,
  double distanceM = 8000,
  SampleStream? gps,
}) =>
    ActivitySession(
      id: activityIdFor(sourceId: source, externalId: ext, startUtc: start),
      sport: SportType.running,
      startUtc: start,
      endUtc: start.add(Duration(seconds: durS)),
      summary: ActivitySummary(distanceM: distanceM),
      streams: gps == null ? const {} : {StreamKind.gps: gps},
      provenance: [
        SourceRecord(
          sourceId: source,
          sourceKind: kind,
          importedAt: start.add(Duration(seconds: durS + 600)),
          externalId: ext,
          appPackage: app,
        ),
      ],
    );

SampleStream _track(String source, int points, double lat0, double jitter) {
  return SampleStream.checked(
    kind: StreamKind.gps,
    sourceId: source,
    offsetsMs: [for (var i = 0; i < points; i++) i * 1000],
    lats: [for (var i = 0; i < points; i++) lat0 + i * 1e-5 + jitter],
    lons: [for (var i = 0; i < points; i++) 10.0 + jitter],
  );
}

/// 100 workouts x 3 sources, each with a 3 600 point GPS track.
List<ActivitySession> _candidates300() {
  final out = <ActivitySession>[];
  for (var w = 0; w < 100; w++) {
    final start = _t0.add(Duration(hours: 3 * w));
    for (var k = 0; k < 3; k++) {
      final (src, kind, app) = _threeSources[k];
      final s = start.add(Duration(seconds: k * 3));
      out.add(_session(
        source: src,
        kind: kind,
        app: app,
        ext: 'w$w',
        start: s,
        durS: 3599,
        gps: _track(src, 3600, w * 0.01, k * 2e-6),
      ));
    }
  }
  return out;
}

/// 1 000 workouts x 2 sources, no streams.
List<ActivitySession> _sessions2000() {
  final out = <ActivitySession>[];
  for (var w = 0; w < 1000; w++) {
    final start = _t0.add(Duration(minutes: 45 * w));
    out.add(_session(
        source: 'garmin', kind: SourceKind.companionApp, ext: 'w$w', start: start, durS: 1800));
    out.add(_session(
        source: 'hc',
        kind: SourceKind.platformHealth,
        app: 'garmin',
        ext: 'w$w',
        start: start.add(const Duration(seconds: 4)),
        durS: 1800));
  }
  return out;
}

String _sig(MergeResult r) => canonicalJson([for (final s in r.sessions) s.toJson()]);

void main() {
  group('U21 300 candidates x 3 600 GPS points', () {
    test('comparison count stays under the design and the calibrated ceiling',
        () {
      final input = _candidates300();
      expect(input, hasLength(300));
      expect(input.every((s) => s.streams[StreamKind.gps]!.length == 3600), isTrue);
      var n = 0;
      final sw = Stopwatch()..start();
      final r = merge(input, _policy, onPairCompared: () => n++);
      sw.stop();
      // ignore: avoid_print
      print('U21 comparisons=$n merged=${r.sessions.length} wall=${sw.elapsedMilliseconds} ms (information only)');
      expect(r.sessions, hasLength(100), reason: 'the 3 sources of a workout merge');
      // Analytic lower bound: every record that joins a cluster is compared with
      // at least its head: 300 - 100 = 200.
      expect(n, greaterThanOrEqualTo(200), reason: 'the seam must be invoked');
      expect(n, lessThanOrEqualTo(kDesignCeiling300));
      expect(n, lessThanOrEqualTo(kCalibratedCeiling300));
    });
  });

  group('U22 2 000 sessions without streams', () {
    test('comparison count stays under the design and the calibrated ceiling',
        () {
      final input = _sessions2000();
      expect(input, hasLength(2000));
      var n = 0;
      final sw = Stopwatch()..start();
      final r = merge(input, _policy, onPairCompared: () => n++);
      sw.stop();
      // ignore: avoid_print
      print('U22 comparisons=$n merged=${r.sessions.length} wall=${sw.elapsedMilliseconds} ms (information only)');
      expect(r.sessions, hasLength(1000));
      expect(n, greaterThanOrEqualTo(1000),
          reason: '1000 records join a cluster, each needs one comparison');
      expect(n, lessThanOrEqualTo(kDesignCeiling2000));
      expect(n, lessThanOrEqualTo(kCalibratedCeiling2000));
    });

    test('2 000 echoes/duplicates of one hour fall into one cluster cheaply', () {
      final input = [
        for (var i = 0; i < 2000; i++)
          _session(
              source: 'garmin',
              kind: SourceKind.companionApp,
              ext: 'dup$i',
              start: _t0.add(Duration(seconds: i % 10)),
              durS: 3600),
      ];
      var n = 0;
      final r = merge(input, _policy, onPairCompared: () => n++);
      expect(r.sessions, hasLength(1));
      expect(n, greaterThanOrEqualTo(1999));
      expect(n, lessThanOrEqualTo(kDesignCeiling2000));
    });
  });

  group('U36 the seam is behaviour-neutral', () {
    final corpus = SyntheticCorpus.build();

    test('merge(corpus) is identical with and without the counter', () {
      var n = 0;
      final without = merge(corpus.rawCandidates, _policy);
      final withSeam =
          merge(corpus.rawCandidates, _policy, onPairCompared: () => n++);
      expect(withSeam.sessions.length, without.sessions.length);
      expect(_sig(withSeam), _sig(without));
      for (var i = 0; i < without.sessions.length; i++) {
        expect(withSeam.sessions[i].id, without.sessions[i].id, reason: 'order $i');
      }
      expect(n, greaterThan(0), reason: 'the corpus needs comparisons');
    });

    test('the counter equals the number of calls and a null callback is fine',
        () {
      var n = 0;
      merge(corpus.rawCandidates, _policy, onPairCompared: () => n++);
      var m = 0;
      merge(corpus.rawCandidates, _policy, onPairCompared: () => m++);
      expect(m, n, reason: 'deterministic count');
      expect(() => merge(corpus.rawCandidates, _policy, onPairCompared: null),
          returnsNormally);
    });

    test('no comparisons for an empty input and for a single record', () {
      var n = 0;
      expect(merge(const [], _policy, onPairCompared: () => n++).sessions, isEmpty);
      expect(n, 0);
      merge([corpus.valid.first], _policy, onPairCompared: () => n++);
      expect(n, 0);
    });
  });
}
