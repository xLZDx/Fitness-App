// T29 activity_merger_test (ACT-05..ACT-13). The merge is deterministic and
// order-independent; every threshold is exercised on both sides.
//
// MAP NOTE (deviation 7): clock skew of a complementary stream is the
// difference of the session START times (not a cross-correlation search); a
// skew above 5 s means the stream is not aligned and is not taken. A stream is
// taken from a source only when it covers >= 80 % of the session; below that
// the next source is tried, and if none qualifies the stream is omitted.
import 'dart:math' as math;

import 'package:fitness_app/features/activity/data/activity_merger.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/device_source.dart';
import 'package:fitness_app/features/activity/data/fake_device_source.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/merge_policy.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _base = DateTime.utc(2026, 10, 10, 6);
const _policy = MergePolicy();

ActivitySession _s({
  SportType sport = SportType.running,
  num startS = 0,
  num durS = 600,
  String source = 'garmin',
  SourceKind kind = SourceKind.companionApp,
  String? ext,
  String? app,
  double? distance,
  Map<StreamKind, SampleStream> streams = const {},
  Map<String, Object?> edits = const {},
  int tz = 0,
  List<Lap> laps = const [],
  ActivitySummary? summary,
}) {
  final start = _base.add(Duration(milliseconds: (startS * 1000).round()));
  final end = start.add(Duration(milliseconds: (durS * 1000).round()));
  final e = ext ?? 'e-${start.millisecondsSinceEpoch}-$source';
  return ActivitySession(
    id: activityIdFor(sourceId: source, externalId: e, startUtc: start),
    sport: sport,
    startUtc: start,
    endUtc: end,
    utcOffsetMinutes: tz,
    summary: summary ?? ActivitySummary(distanceM: distance),
    streams: streams,
    laps: laps,
    userEdits: edits,
    provenance: [
      SourceRecord(
        sourceId: source,
        sourceKind: kind,
        importedAt: _base.add(const Duration(hours: 2)),
        externalId: e,
        appPackage: app,
      ),
    ],
  );
}

SampleStream _vals(StreamKind k, String source, List<int> offsets, List<double> v) =>
    SampleStream.checked(kind: k, sourceId: source, offsetsMs: offsets, values: v);

SampleStream _track(String source, List<int> offsets, List<double> lats,
        {double lon = 0.0}) =>
    SampleStream.checked(
      kind: StreamKind.gps,
      sourceId: source,
      offsetsMs: offsets,
      lats: lats,
      lons: [for (final _ in lats) lon],
    );

/// Degrees of latitude that make [m] metres on the sphere used by the merger.
double _deg(double m) => m / (6371000.0 * math.pi / 180);

List<ActivitySession> _merge(List<ActivitySession> l, [MergePolicy p = _policy]) =>
    merge(l, p).sessions;

void main() {
  group('policy defaults (design 31.3)', () {
    test('thresholds', () {
      const p = MergePolicy();
      expect(p.minIou, 0.8);
      expect(p.maxStartDiffSeconds, 120);
      expect(p.maxEndDiffSeconds, 300);
      expect(p.maxDistanceRelDiff, 0.15);
      expect(p.maxGpsMeanMeters, 100);
      expect(p.minStreamCoverage, 0.8);
      expect(p.maxClockSkewSeconds, 5);
      expect(p.summaryDisagreement, 0.10);
      expect(p.splitGapSeconds, 60);
      expect(p.joinSplits, isFalse);
    });
    test('source priority: ble sensor > watch/vendor > file > platform aggregate', () {
      expect(MergePolicy.defaultKindPriority, {
        SourceKind.bleSensor: 0,
        SourceKind.companionApp: 1,
        SourceKind.vendorCloud: 1,
        SourceKind.fileImport: 2,
        SourceKind.platformHealth: 3,
      });
      expect(const MergePolicy().echoRank, 100);
    });
    test('a per-source override beats the kind priority', () {
      final p = const MergePolicy(sourcePriority: {'phone': 0});
      final r = SourceRecord(
          sourceId: 'phone',
          sourceKind: SourceKind.fileImport,
          importedAt: _base);
      expect(p.priorityOf(r), 0);
      expect(const MergePolicy().priorityOf(r), 2);
    });
  });

  group('ACT-05 exact duplicate', () {
    test('the same sourceId + externalId imported twice gives one session', () {
      final a = _s(ext: 'x1');
      final b = _s(ext: 'x1');
      expect(_merge([a, b]).length, 1);
    });
    test('re-import of a session already merged is idempotent', () {
      final once = _merge([_s(ext: 'x1', distance: 10000)]);
      final twice = _merge([...once, _s(ext: 'x1', distance: 10000)]);
      expect(twice.length, 1);
      expect(twice.single, once.single);
    });
    test('a different externalId from the same source in a different time slot stays separate', () {
      expect(_merge([_s(ext: 'x1'), _s(ext: 'x2', startS: 7200)]).length, 2);
    });
    test('the same externalId from a DIFFERENT source is not an exact duplicate', () {
      final a = _s(ext: 'x1', source: 'garmin');
      final b = _s(ext: 'x1', source: 'polar', startS: 9000);
      expect(_merge([a, b]).length, 2);
    });
  });

  group('ACT-06 watch + phone + platform echo -> one session', () {
    final watch = _s(source: 'garmin', kind: SourceKind.companionApp, ext: 'g1',
        distance: 10000);
    final phone = _s(source: 'phone', kind: SourceKind.fileImport, ext: 'p1',
        startS: 20, distance: 9900);
    final echo = _s(source: 'health_connect', kind: SourceKind.platformHealth,
        ext: 'h1', app: 'garmin', startS: 5, distance: 10050);

    test('three candidates -> one session with provenance of three', () {
      final out = _merge([phone, echo, watch]);
      expect(out.length, 1);
      expect(out.single.provenance.length, 3);
      expect(out.single.provenance.map((p) => p.sourceId).toSet(),
          {'garmin', 'phone', 'health_connect'});
    });
    test('provenance keeps every original record and ranks the echo last', () {
      final out = _merge([echo, phone, watch]).single;
      expect(out.provenance.map((p) => p.sourceId).toList(),
          ['garmin', 'phone', 'health_connect']);
      expect(out.provenance.map((p) => p.externalId).toList(), ['g1', 'p1', 'h1']);
    });
    test('the direct source is the primary: its id and times survive; the echo is noted', () {
      final out = _merge([echo, phone, watch]).single;
      expect(out.id, watch.id);
      expect(out.startUtc, watch.startUtc);
      expect(out.mergeNotes, contains('echo:health_connect'));
      expect(out.summary.distanceM, 10000); // the primary's value
    });
    test('the echo is ranked below even a lower-priority direct source', () {
      // phone (file import, rank 2) must beat the platform echo of the watch.
      final out = _merge([echo, phone]);
      // no watch held, so the echo is NOT an echo of a held source: platform
      // rank 3 still sits below the file import rank 2.
      expect(out.length, 1);
      expect(out.single.id, phone.id);
    });
    test('a platform record WITHOUT an app package is an ordinary platform source', () {
      final plain = _s(source: 'health_connect', kind: SourceKind.platformHealth,
          ext: 'h2', startS: 5, distance: 10050);
      final out = _merge([watch, plain]).single;
      expect(out.mergeNotes.where((n) => n.startsWith('echo:')), isEmpty);
    });
  });

  group('ACT-07 thresholds at the boundary', () {
    ActivitySession a() => _s(source: 'garmin', ext: 'a', durS: 3600);

    test('IoU exactly 0.80 is merged, 0.79 is not (start/end rule violated on purpose)', () {
      // B = [0, 2880 s]: inter 2880 / union 3600 = 0.80; end diff 720 s > 300.
      expect(_merge([a(), _s(source: 'polar', ext: 'b', durS: 2880)]).length, 1);
      // B = [0, 2844 s]: IoU 0.79.
      expect(_merge([a(), _s(source: 'polar', ext: 'b', durS: 2844)]).length, 2);
    });
    // short sessions so the IoU rule cannot apply: A = [0, 600].
    ActivitySession s600() => _s(source: 'garmin', ext: 'a', durS: 600);

    test('start diff 120 s and end diff 300 s are merged', () {
      // B = [120, 900]: IoU 480/900 = 0.53.
      expect(_merge([s600(), _s(source: 'polar', ext: 'b', startS: 120, durS: 780)]).length, 1);
    });
    test('start diff 121 s is not merged', () {
      expect(_merge([s600(), _s(source: 'polar', ext: 'b', startS: 121, durS: 779)]).length, 2);
    });
    test('end diff 301 s is not merged', () {
      expect(_merge([s600(), _s(source: 'polar', ext: 'b', startS: 120, durS: 781)]).length, 2);
    });
    test('distance relative difference 15 % is merged, 16 % is not', () {
      final base = _s(source: 'garmin', ext: 'a', distance: 10000);
      expect(_merge([base, _s(source: 'polar', ext: 'b', distance: 8500)]).length, 1);
      expect(_merge([base, _s(source: 'polar', ext: 'b', distance: 8400)]).length, 2);
    });
    test('distance is only compared when both sessions report one', () {
      final base = _s(source: 'garmin', ext: 'a', distance: 10000);
      expect(_merge([base, _s(source: 'polar', ext: 'b')]).length, 1);
    });
    test('GPS mean distance 100 m is merged, 101 m is not', () {
      final offs = [0, 1000, 2000];
      final lats = [10.0, 10.001, 10.002];
      ActivitySession withTrack(String src, double shiftM) => _s(
            source: src,
            ext: src,
            streams: {
              StreamKind.gps: _track(
                  src, offs, [for (final l in lats) l + _deg(shiftM)])
            },
          );
      expect(_merge([withTrack('garmin', 0), withTrack('polar', 100)]).length, 1);
      expect(_merge([withTrack('garmin', 0), withTrack('polar', 101)]).length, 2);
    });
    test('GPS is only compared when both sessions have a track', () {
      final tr = _track('garmin', [0, 1000], [10.0, 10.001]);
      expect(
          _merge([
            _s(source: 'garmin', ext: 'a', streams: {StreamKind.gps: tr}),
            _s(source: 'polar', ext: 'b')
          ]).length,
          1);
    });
    test('the thresholds are configurable', () {
      final base = _s(source: 'garmin', ext: 'a', distance: 10000);
      final other = _s(source: 'polar', ext: 'b', distance: 8400);
      expect(_merge([base, other], const MergePolicy(maxDistanceRelDiff: 0.20)).length, 1);
    });
  });

  group('ACT-08 not merged', () {
    test('a brick session (run then ride) stays two sessions', () {
      final run = _s(sport: SportType.running, source: 'garmin', ext: 'r', durS: 1800);
      final ride = _s(sport: SportType.cycling, source: 'garmin', ext: 'c', startS: 1800, durS: 1800);
      expect(_merge([run, ride]).length, 2);
    });
    test('two runs that barely overlap stay two sessions', () {
      final a = _s(source: 'garmin', ext: 'a', durS: 1800);
      final b = _s(source: 'polar', ext: 'b', startS: 1700, durS: 1800);
      expect(_merge([a, b]).length, 2);
    });
    test('pool swim and open-water swim at the same time are never merged', () {
      final pool = _s(sport: SportType.swimmingPool, source: 'garmin', ext: 'a');
      final open = _s(sport: SportType.swimmingOpenWater, source: 'polar', ext: 'b');
      expect(_merge([pool, open]).length, 2);
    });
    test('running vs cycling at the same time are never merged', () {
      expect(
          _merge([
            _s(sport: SportType.running, source: 'garmin', ext: 'a'),
            _s(sport: SportType.cycling, source: 'polar', ext: 'b')
          ]).length,
          2);
    });
    test('running / trail running and cycling / indoor cycling families do merge', () {
      expect(
          _merge([
            _s(sport: SportType.running, source: 'garmin', ext: 'a'),
            _s(sport: SportType.trailRunning, source: 'polar', ext: 'b')
          ]).length,
          1);
      expect(
          _merge([
            _s(sport: SportType.cycling, source: 'garmin', ext: 'a'),
            _s(sport: SportType.indoorCycling, source: 'polar', ext: 'b')
          ]).length,
          1);
    });
    test('same-source back-to-back with a 60 s gap stays two when joinSplits is off (default)', () {
      final a = _s(source: 'garmin', ext: 'a', durS: 600);
      final b = _s(source: 'garmin', ext: 'b', startS: 660, durS: 600);
      expect(_merge([a, b]).length, 2);
    });
    test('joinSplits on: a 60 s gap is joined, 61 s is not', () {
      const on = MergePolicy(joinSplits: true);
      final a = _s(source: 'garmin', ext: 'a', durS: 600, distance: 2000);
      final b60 = _s(source: 'garmin', ext: 'b', startS: 660, durS: 600, distance: 2500);
      final joined = _merge([a, b60], on);
      expect(joined.length, 1);
      expect(joined.single.id, a.id);
      expect(joined.single.startUtc, a.startUtc);
      expect(joined.single.endUtc, b60.endUtc);
      expect(joined.single.summary.distanceM, 4500);
      expect(joined.single.mergeNotes, contains('joinedSplit'));
      final b61 = _s(source: 'garmin', ext: 'b', startS: 661, durS: 600);
      expect(_merge([a, b61], on).length, 2);
    });
    test('joinSplits never joins different sports or different sources', () {
      const on = MergePolicy(joinSplits: true);
      final a = _s(source: 'garmin', ext: 'a', durS: 600);
      expect(
          _merge([a, _s(sport: SportType.cycling, source: 'garmin', ext: 'b', startS: 630)], on)
              .length,
          2);
      expect(_merge([a, _s(source: 'polar', ext: 'b', startS: 630)], on).length, 2);
    });
  });

  group('ACT-09 field policy and complementary merge', () {
    List<int> offs(int n, int stepMs) => [for (var i = 0; i < n; i++) i * stepMs];

    ActivitySession strap({List<int>? o, List<double>? v}) => _s(
          source: 'strap',
          kind: SourceKind.bleSensor,
          ext: 's',
          streams: {
            StreamKind.heartRate: _vals(StreamKind.heartRate, 'strap',
                o ?? [0, 300000, 600000], v ?? [100, 120, 140])
          },
        );
    ActivitySession phoneGps({num startS = 0, List<int>? o}) => _s(
          source: 'phone',
          kind: SourceKind.fileImport,
          ext: 'p',
          startS: startS,
          streams: {
            StreamKind.gps: _track('phone', o ?? [0, 300000, 590000],
                [0.0, 0.001, 0.002])
          },
        );

    test('HR from the strap + GPS from the phone are combined (one session)', () {
      final m = _merge([phoneGps(), strap()]).single;
      expect(m.streams.keys.toSet(), {StreamKind.heartRate, StreamKind.gps});
      expect(m.streams[StreamKind.heartRate]!.sourceId, 'strap');
      expect(m.streams[StreamKind.gps]!.sourceId, 'phone');
    });
    test('a 3 s clock skew is aligned: the phone track is shifted by +3000 ms', () {
      final m = _merge([phoneGps(startS: 3), strap()]).single;
      expect(m.streams[StreamKind.gps]!.offsetsMs, [3000, 303000, 593000]);
    });
    test('a 5 s skew is still aligned; a 6 s skew is NOT (the stream is omitted)', () {
      expect(_merge([phoneGps(startS: 5), strap()]).single.streams.containsKey(StreamKind.gps),
          isTrue);
      final six = _merge([phoneGps(startS: 6), strap()]).single;
      expect(six.streams.containsKey(StreamKind.gps), isFalse);
      expect(six.streams.containsKey(StreamKind.heartRate), isTrue);
    });
    test('stream coverage 79 % falls to the next source, 80 % is taken', () {
      // session 600 s; a 79 % strap HR (0..474 s) loses to the watch's 95 % HR.
      final watch = _s(
        source: 'garmin',
        kind: SourceKind.companionApp,
        ext: 'w',
        streams: {
          StreamKind.heartRate:
              _vals(StreamKind.heartRate, 'garmin', [0, 570000], [90, 95])
        },
      );
      final low = strap(o: [0, 474000], v: [100, 110]);
      final m79 = _merge([watch, low]).single;
      expect(m79.streams[StreamKind.heartRate]!.sourceId, 'garmin');
      final ok = strap(o: [0, 480000], v: [100, 110]);
      final m80 = _merge([watch, ok]).single;
      expect(m80.streams[StreamKind.heartRate]!.sourceId, 'strap');
    });
    test('when no source reaches 80 % coverage the stream is omitted', () {
      final m = _merge([strap(o: [0, 400000], v: [100, 110]), phoneGps()]).single;
      expect(m.streams.containsKey(StreamKind.heartRate), isFalse);
    });
    test('samples are never mixed within one kind: the merged HR is exactly one source', () {
      final watch = _s(
        source: 'garmin',
        kind: SourceKind.companionApp,
        ext: 'w',
        streams: {
          StreamKind.heartRate:
              _vals(StreamKind.heartRate, 'garmin', [0, 300000, 600000], [90, 95, 99])
        },
      );
      final m = _merge([watch, strap()]).single;
      final hr = m.streams[StreamKind.heartRate]!;
      expect(hr.sourceId, 'strap'); // rank 0 beats the watch
      expect(hr.values, [100, 120, 140]);
      expect(hr.offsetsMs, [0, 300000, 600000]);
    });
    test('the summary is recomputed from the merged streams: HR avg 120 max 140', () {
      final m = _merge([phoneGps(), strap()]).single;
      expect(m.summary.avgHrBpm, closeTo(120, 1e-9));
      expect(m.summary.maxHrBpm, 140);
    });
    test('distance is recomputed from the merged GPS: 0.002 deg of latitude = 222.39 m', () {
      final m = _merge([phoneGps(), strap()]).single;
      expect(m.summary.distanceM!, closeTo(222.3899, 1e-3));
    });
    test('ascent and descent are recomputed from altitude: 100,110,105,120 -> +25 / -5', () {
      final alt = _s(
        source: 'garmin',
        ext: 'a',
        streams: {
          StreamKind.altitude: _vals(StreamKind.altitude, 'garmin',
              [0, 200000, 400000, 600000], [100, 110, 105, 120])
        },
      );
      final m = _merge([alt, strap()]).single;
      expect(m.summary.ascentM, 25);
      expect(m.summary.descentM, 5);
    });
    test('the merged stream list keeps provenance fieldsContributed per source', () {
      final m = _merge([phoneGps(), strap()]).single;
      final byId = {for (final p in m.provenance) p.sourceId: p};
      expect(byId['strap']!.fieldsContributed, ['heartRate']);
      expect(byId['phone']!.fieldsContributed, ['gps']);
    });
    test('a summary disagreement above 10 % is noted; exactly 10 % is not', () {
      ActivitySession d(String src, double dist) => _s(
          source: src,
          ext: src,
          distance: dist,
          kind: src == 'garmin' ? SourceKind.companionApp : SourceKind.fileImport);
      final over = _merge([d('garmin', 10000), d('polar', 11200)]).single;
      expect(over.mergeNotes, contains('summaryDisagreement:distanceM'));
      expect(over.summary.distanceM, 10000); // the higher-priority source's value
      final exact = _merge([d('garmin', 9000), d('polar', 10000)]).single;
      expect(exact.mergeNotes, isNot(contains('summaryDisagreement:distanceM')));
      final under = _merge([d('garmin', 10000), d('polar', 11000)]).single;
      expect(under.mergeNotes, isEmpty);
    });
    test('the first source with a non-null summary value wins field by field', () {
      final a = _s(source: 'garmin', ext: 'a',
          summary: const ActivitySummary(distanceM: 10000));
      final b = _s(source: 'polar', kind: SourceKind.fileImport, ext: 'b',
          summary: const ActivitySummary(distanceM: 9900, activeEnergyKcal: 640));
      final m = _merge([a, b]).single;
      expect(m.summary.distanceM, 10000);
      expect(m.summary.activeEnergyKcal, 640);
    });
    test('laps come from the first session that has any', () {
      const lap = Lap(index: 0, kind: LapKind.manual, startOffsetS: 0, durationS: 100);
      final a = _s(source: 'garmin', ext: 'a');
      final b = _s(source: 'polar', ext: 'b', laps: const [lap]);
      expect(_merge([a, b]).single.laps, [lap]);
    });
  });

  group('ACT-10 user edits win', () {
    test('an edited distance survives a re-merge with higher-priority source data', () {
      final low = _s(source: 'phone', kind: SourceKind.fileImport, ext: 'p',
          distance: 10000, edits: const {'distanceM': 10200.0});
      final high = _s(source: 'garmin', ext: 'g', distance: 10100);
      final m = _merge([high, low]).single;
      expect(m.summary.distanceM, 10200);
      expect(m.userEdits, {'distanceM': 10200.0});
    });
    test('an edit also beats a value recomputed from the streams', () {
      final strap = _s(
        source: 'strap',
        kind: SourceKind.bleSensor,
        ext: 's',
        streams: {
          StreamKind.heartRate:
              _vals(StreamKind.heartRate, 'strap', [0, 600000], [100, 140])
        },
      );
      final edited = _s(source: 'phone', kind: SourceKind.fileImport, ext: 'p',
          edits: const {'avgHrBpm': 111.0});
      final m = _merge([strap, edited]).single;
      expect(m.summary.avgHrBpm, 111);
    });
    test('an edited sport wins', () {
      final a = _s(sport: SportType.running, source: 'garmin', ext: 'a');
      final b = _s(
          sport: SportType.running,
          source: 'phone',
          kind: SourceKind.fileImport,
          ext: 'b',
          edits: const {'sport': 'trailRunning'});
      expect(_merge([a, b]).single.sport, SportType.trailRunning);
    });
    test('the higher-priority holder of the same edited key wins', () {
      final a = _s(source: 'garmin', ext: 'a', edits: const {'distanceM': 1.0});
      final b = _s(source: 'phone', kind: SourceKind.fileImport, ext: 'b',
          edits: const {'distanceM': 2.0});
      expect(_merge([b, a]).single.summary.distanceM, 1);
    });
  });

  group('ACT-11 order independence', () {
    test('20 seeded shuffles of the same inputs give a deep-equal result', () {
      final inputs = <ActivitySession>[
        _s(source: 'garmin', ext: 'g1', distance: 10000, streams: {
          StreamKind.heartRate:
              _vals(StreamKind.heartRate, 'garmin', [0, 300000, 600000], [90, 95, 99])
        }),
        _s(source: 'phone', kind: SourceKind.fileImport, ext: 'p1', startS: 4,
            distance: 9900, streams: {
          StreamKind.gps: _track('phone', [0, 300000, 596000], [0.0, 0.001, 0.002])
        }),
        _s(source: 'health_connect', kind: SourceKind.platformHealth, ext: 'h1',
            app: 'garmin', startS: 2, distance: 10100),
        _s(source: 'strap', kind: SourceKind.bleSensor, ext: 's1', startS: 1,
            streams: {
          StreamKind.heartRate:
              _vals(StreamKind.heartRate, 'strap', [0, 300000, 600000], [100, 120, 140])
        }),
        _s(sport: SportType.cycling, source: 'garmin', ext: 'g2', startS: 4000, distance: 30000),
        _s(sport: SportType.swimmingPool, source: 'polar', ext: 'x1', startS: 9000),
      ];
      final reference = _merge(inputs);
      for (var seed = 0; seed < 20; seed++) {
        final shuffled = [...inputs]..shuffle(math.Random(seed));
        final out = _merge(shuffled);
        expect(out.length, reference.length, reason: 'seed $seed');
        for (var i = 0; i < out.length; i++) {
          expect(out[i], reference[i], reason: 'seed $seed index $i');
        }
      }
    });
    test('the output is ordered by start time then id', () {
      final out = _merge([
        _s(source: 'garmin', ext: 'late', startS: 5000),
        _s(source: 'garmin', ext: 'early', startS: 0),
        _s(source: 'garmin', ext: 'mid', startS: 2500),
      ]);
      expect(out.map((s) => s.startUtc).toList(),
          [for (final s in [0, 2500, 5000]) _base.add(Duration(seconds: s))]);
    });
    test('an empty input gives an empty result', () {
      expect(_merge(const []), isEmpty);
    });
  });

  group('ACT-12 UTC handling', () {
    test('sessions with different utcOffsetMinutes but the same UTC times still match', () {
      final a = _s(source: 'garmin', ext: 'a', tz: 60); // CET
      final b = _s(
          source: 'polar',
          kind: SourceKind.fileImport,
          ext: 'b',
          tz: 120); // CEST after the DST change
      final m = _merge([a, b]);
      expect(m.length, 1);
      expect(m.single.utcOffsetMinutes, 60); // the primary's display offset
    });
    test('the display offset of the primary is preserved, not recomputed', () {
      final a = _s(source: 'garmin', ext: 'a', tz: -300);
      final b = _s(source: 'phone', kind: SourceKind.fileImport, ext: 'b', tz: 0);
      expect(_merge([b, a]).single.utcOffsetMinutes, -300);
    });
    test('the same local clock time with different offsets is a DIFFERENT instant: not merged', () {
      final a = _s(source: 'garmin', ext: 'a', startS: 0);
      final b = _s(source: 'polar', ext: 'b', startS: 3600, tz: 60); // an hour later in UTC
      expect(_merge([a, b]).length, 2);
    });
    test('times round-trip as UTC', () {
      final m = _merge([_s(source: 'garmin', ext: 'a', tz: 330)]).single;
      expect(m.startUtc.isUtc, isTrue);
      expect(m.endUtc.isUtc, isTrue);
    });
  });

  group('ACT-13 DeviceSource contract and FakeDeviceSource', () {
    test('permission is notDetermined until requested; request grants the kinds', () async {
      final f = FakeDeviceSource(id: 'fake');
      expect(await f.permission({StreamKind.heartRate}),
          SourcePermission.notDetermined);
      expect(await f.request({StreamKind.heartRate, StreamKind.gps}),
          SourcePermission.granted);
      expect(f.requestCalls, 1);
      expect(await f.permission({StreamKind.heartRate}), SourcePermission.granted);
      expect(await f.permission({StreamKind.heartRate, StreamKind.gps}),
          SourcePermission.granted);
      expect(await f.permission({StreamKind.power}), SourcePermission.notDetermined);
    });
    test('a source that refuses answers denied and grants nothing', () async {
      final f = FakeDeviceSource(id: 'fake', grantOnRequest: false);
      expect(await f.request({StreamKind.heartRate}), SourcePermission.denied);
      expect(await f.permission({StreamKind.heartRate}),
          SourcePermission.notDetermined);
    });
    test('fetchSessions returns the sessions overlapping the window, inclusive', () async {
      final inside = _s(source: 'fake', ext: 'a', startS: 0, durS: 600);
      final before = _s(source: 'fake', ext: 'b', startS: -7200, durS: 600);
      final after = _s(source: 'fake', ext: 'c', startS: 7200, durS: 600);
      final touching = _s(source: 'fake', ext: 'd', startS: 3600, durS: 600);
      final f = FakeDeviceSource(
          id: 'fake', sessions: [inside, before, after, touching]);
      final got = await f.fetchSessions(
          from: _base.subtract(const Duration(minutes: 5)),
          to: _base.add(const Duration(hours: 1)));
      expect(got.map((s) => s.id).toSet(), {inside.id, touching.id});
    });
    test('disconnect(deleteImported: true) discards imported data and the grants', () async {
      final f = FakeDeviceSource(
          id: 'fake', sessions: [_s(source: 'fake', ext: 'a')]);
      await f.request({StreamKind.heartRate});
      await f.disconnect(deleteImported: true);
      expect(f.disconnectCalls, 1);
      expect(f.lastDisconnectDeletedImported, isTrue);
      expect(f.imported, isEmpty);
      expect(await f.permission({StreamKind.heartRate}),
          SourcePermission.notDetermined);
    });
    test('disconnect() keeps the imported data by default', () async {
      final f = FakeDeviceSource(
          id: 'fake', sessions: [_s(source: 'fake', ext: 'a')]);
      await f.disconnect();
      expect(f.lastDisconnectDeletedImported, isFalse);
      expect(f.imported.length, 1);
    });
    test('live emits only the requested kinds, in order', () async {
      final f = FakeDeviceSource(id: 'fake');
      f.scriptLive([
        LiveSample(kind: StreamKind.heartRate, at: _base, value: 100),
        LiveSample(kind: StreamKind.power, at: _base, value: 200),
        LiveSample(kind: StreamKind.heartRate, at: _base, value: 101),
      ]);
      final got = await f.live({StreamKind.heartRate}).toList();
      expect(got.map((s) => s.value).toList(), [100, 101]);
      expect(await f.live({StreamKind.cadence}).toList(), isEmpty);
    });
    test('capability matrix constants (design 31.6) are unchanged', () {
      final m = kCapabilityMatrix;
      expect(m.keys.toSet(), {
        'health_connect', 'healthkit', 'ble_hr', 'ble_rsc', 'ble_csc',
        'ble_cp', 'ble_ftms', 'wear_os', 'vendor_cloud',
      });
      final hc = m['health_connect']!;
      expect(hc.levelOf(CapabilityColumn.sessionList), CapabilityLevel.yes);
      expect(hc.levelOf(CapabilityColumn.strokesLaps), CapabilityLevel.partial);
      expect(hc.levelOf(CapabilityColumn.liveStream), CapabilityLevel.no);
      expect(m['healthkit']!.levelOf(CapabilityColumn.liveStream),
          CapabilityLevel.partial);
      final hr = m['ble_hr']!;
      expect(hr.levelOf(CapabilityColumn.heartRate), CapabilityLevel.yes);
      expect(hr.levelOf(CapabilityColumn.liveStream), CapabilityLevel.yes);
      expect(hr.levelOf(CapabilityColumn.sessionList), CapabilityLevel.no);
      expect(hr.levelOf(CapabilityColumn.gpsRoute), CapabilityLevel.no);
      final cp = m['ble_cp']!;
      expect(cp.levelOf(CapabilityColumn.power), CapabilityLevel.yes);
      expect(cp.levelOf(CapabilityColumn.speedPace), CapabilityLevel.partial);
      expect(m['ble_ftms']!.levelOf(CapabilityColumn.heartRate),
          CapabilityLevel.partial);
      expect(m['wear_os']!.levelOf(CapabilityColumn.power), CapabilityLevel.unknown);
      for (final c in CapabilityColumn.values) {
        if (c == CapabilityColumn.liveStream) continue;
        expect(m['vendor_cloud']!.levelOf(c), CapabilityLevel.unknown,
            reason: c.name);
      }
      expect(m['vendor_cloud']!.levelOf(CapabilityColumn.liveStream),
          CapabilityLevel.no);
    });
    test('supportsStream maps stream kinds to capability columns', () {
      final hr = kCapabilityMatrix['ble_hr']!;
      expect(hr.supportsStream(StreamKind.heartRate), isTrue);
      expect(hr.supportsStream(StreamKind.gps), isFalse);
      expect(hr.supportsStream(StreamKind.temperature), isFalse);
      final hc = kCapabilityMatrix['health_connect']!;
      expect(hc.supportsStream(StreamKind.gps), isTrue);
      expect(hc.supportsStream(StreamKind.altitude), isTrue);
      expect(hc.supportsStream(StreamKind.strokeRate), isTrue); // partial counts
      expect(hc.supportsStream(StreamKind.temperature), isFalse);
      expect(kCapabilityMatrix['vendor_cloud']!.supportsStream(StreamKind.heartRate),
          isFalse);
    });
    test('the fake carries its kind and id', () {
      final f = FakeDeviceSource(id: 'ble_hr', kind: SourceKind.bleSensor);
      expect(f.id, 'ble_hr');
      expect(f.kind, SourceKind.bleSensor);
    });
  });

  group('haversine', () {
    test('0.001 degree of latitude = 111.195 m; zero distance for equal points', () {
      expect(haversineMeters(0, 0, 0.001, 0), closeTo(111.19493, 1e-4));
      expect(haversineMeters(10, 20, 10, 20), 0);
    });
    test('one degree of longitude shrinks with latitude: at 60 N it is half', () {
      final eq = haversineMeters(0, 0, 0, 1);
      final n60 = haversineMeters(60, 0, 60, 1);
      expect(n60 / eq, closeTo(0.5, 1e-3));
    });
  });
}
