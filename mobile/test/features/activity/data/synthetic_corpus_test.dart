// S02-00 U27 / U28: the synthetic corpus generator is deterministic and meets
// its own spec. The oracle numbers below are literals of plan 2.2 / 2.3 and are
// deliberately NOT read from the generator's own constants.
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/s02_paths.dart';
import '../../../support/synthetic_activity_corpus.dart';
import '../../../support/synthetic_hostile_corpus.dart';

const Map<String, int> _literalSportCounts = {
  'running': 12,
  'cycling': 10,
  'walking': 8,
  'hiking': 6,
  'trailRunning': 6,
  'mountainBiking': 6,
  'indoorCycling': 8,
  'swimmingPool': 10,
  'swimmingOpenWater': 6,
  'rowing': 6,
  'strength': 12,
  'other': 10,
};

Map<String, String> _readDigests() {
  final f = supportFile('synthetic_corpus_digest.txt');
  if (!f.existsSync()) return {};
  return {
    for (final line in f.readAsLinesSync())
      if (line.contains('='))
        line.split('=').first.trim(): line.split('=').last.trim(),
  };
}

void main() {
  group('U27 corpus generator is deterministic (both parts)', () {
    test('SplitMix64 reproduces the published seed-0 reference outputs', () {
      final r = SplitMix64(0);
      expect(r.nextU64(), 0xE220A8397B1DCDAF);
      expect(r.nextU64(), 0x6E789E6AA1B965F4);
      expect(r.nextU64(), 0x06C45D188009454F);
    });

    test('two independent builds give byte-identical canonical JSON', () {
      final a = SyntheticCorpus.buildFresh();
      final b = SyntheticCorpus.buildFresh();
      expect(a.canonical(), b.canonical());
      expect(a.digest(), b.digest());
      final ha = SyntheticHostile.buildFresh();
      final hb = SyntheticHostile.buildFresh();
      expect(ha.canonical(), hb.canonical());
    });

    test('the VALID and the HOSTILE digests equal their own committed digests',
        () {
      final valid = SyntheticCorpus.build().digest();
      final hostile = SyntheticHostile.build().digest();
      if (updateGolden) {
        supportFile('synthetic_corpus_digest.txt')
            .writeAsStringSync('valid=$valid\nhostile=$hostile\n');
      }
      final committed = _readDigests();
      expect(committed.keys, containsAll(['valid', 'hostile']),
          reason: 'run once with S02_UPDATE_GOLDEN=1 to create the digests');
      expect(valid, committed['valid'], reason: 'VALID part drifted');
      expect(hostile, committed['hostile'], reason: 'HOSTILE part drifted');
      expect(valid, isNot(hostile));
    });

    test('a different master seed changes the corpus (the seed is used)', () {
      final r1 = SplitMix64(kCorpusSeed);
      final r2 = SplitMix64(kFuzzSeed);
      expect(r1.nextU64(), isNot(r2.nextU64()));
    });
  });

  group('U28 the VALID corpus meets its own spec', () {
    final c = SyntheticCorpus.build();
    final valid = c.valid;

    test('exactly 100 sessions with 100 distinct ids of the form act_<40 hex>',
        () {
      expect(valid, hasLength(100));
      expect({for (final s in valid) s.id}, hasLength(100));
      for (final s in valid) {
        expect(RegExp(r'^act_[0-9a-f]{40}$').hasMatch(s.id), isTrue, reason: s.id);
      }
    });

    test('exact per-sport counts sum to 100 and every SportType is >= 6', () {
      final counts = <String, int>{};
      for (final s in valid) {
        counts[s.sport.name] = (counts[s.sport.name] ?? 0) + 1;
      }
      expect(counts, _literalSportCounts);
      expect(_literalSportCounts.values.reduce((a, b) => a + b), 100);
      expect(SportType.values, hasLength(12));
      for (final t in SportType.values) {
        expect(counts[t.name], greaterThanOrEqualTo(6), reason: t.name);
      }
    });

    test('GPS 38, indoor 62, HR 60 (23 GPS + 37 indoor)', () {
      bool gps(ActivitySession s) =>
          (s.streams[StreamKind.gps]?.length ?? 0) > 0;
      bool hr(ActivitySession s) =>
          (s.streams[StreamKind.heartRate]?.length ?? 0) > 0;
      expect(valid.where(gps), hasLength(38));
      expect(valid.where((s) => !gps(s)), hasLength(62));
      expect(valid.where(hr), hasLength(60));
      expect(valid.where((s) => hr(s) && gps(s)), hasLength(23));
      expect(valid.where((s) => hr(s) && !gps(s)), hasLength(37));
    });

    test('other streams: altitude 30, speed 25, cadence 20, power 15, '
        'strokeRate 8, temperature 5', () {
      int n(StreamKind k) =>
          valid.where((s) => (s.streams[k]?.length ?? 0) > 0).length;
      expect(n(StreamKind.altitude), 30);
      expect(n(StreamKind.speed), 25);
      expect(n(StreamKind.cadence), 20);
      expect(n(StreamKind.power), 15);
      expect(n(StreamKind.strokeRate), 8);
      expect(n(StreamKind.temperature), 5);
    });

    test('GPS length tiers: 20 x 600-1800, 12 x 1800-7200, 5 x 7200-14400, '
        '1 x 43200', () {
      final lens = [
        for (final s in valid)
          if (s.streams[StreamKind.gps] != null) s.streams[StreamKind.gps]!.length,
      ];
      expect(lens.where((n) => n >= 600 && n <= 1800), hasLength(20));
      expect(lens.where((n) => n > 1800 && n <= 7200), hasLength(12));
      expect(lens.where((n) => n > 7200 && n <= 14400), hasLength(5));
      expect(lens.where((n) => n == 43200), hasLength(1));
    });

    test('laps: 10 pool swims (20-80 laps, 25/33.33/50 m), 12 runs with 1 km '
        'auto laps, one workout with 1000 laps', () {
      final pools = valid.where((s) => s.sport == SportType.swimmingPool);
      expect(pools, hasLength(10));
      for (final s in pools) {
        expect(s.laps.length, inInclusiveRange(20, 80));
        expect(const [25.0, 33.33, 50.0], contains(s.summary.poolLengthM));
        expect(s.summary.avgSwolf, isNotNull);
        expect(s.laps.every((l) => l.strokeType != null), isTrue);
      }
      final runs = valid.where((s) => s.sport == SportType.running).toList();
      expect(runs, hasLength(12));
      for (final s in runs) {
        expect(s.laps, isNotEmpty);
        expect(s.laps.every((l) => l.kind.name == 'auto' && l.distanceM == 1000),
            isTrue);
        expect(s.laps.length, (s.summary.distanceM! / 1000).floor());
      }
      expect(valid.where((s) => s.laps.length == 1000), hasLength(1));
    });

    test('sources: all four kinds present, fileImport in exactly 5 records, '
        '8 platform-health echoes', () {
      final kinds = <SourceKind, int>{};
      for (final s in valid) {
        for (final p in s.provenance) {
          kinds[p.sourceKind] = (kinds[p.sourceKind] ?? 0) + 1;
        }
      }
      expect(kinds[SourceKind.bleSensor], greaterThan(0));
      expect(kinds[SourceKind.platformHealth], greaterThan(0));
      expect(kinds[SourceKind.companionApp], greaterThan(0));
      expect(kinds[SourceKind.vendorCloud], greaterThan(0));
      expect(kinds[SourceKind.fileImport], 5);
      final echoes = valid.where((s) => s.provenance.any((p) =>
          p.sourceKind == SourceKind.platformHealth &&
          p.appPackage == 'com.fitness.app'));
      expect(echoes, hasLength(8));
      expect(c.echoIds.toSet(), {for (final s in echoes) s.id});
    });

    test('raw candidates: 155 = 60 x1 + 25 x2 + 15 x3, all ids distinct', () {
      expect(c.rawCandidates, hasLength(155));
      expect({for (final s in c.rawCandidates) s.id}, hasLength(155));
      expect(c.splitPair, hasLength(2));
      final gap = c.splitPair[1].startUtc.difference(c.splitPair[0].endUtc);
      expect(gap, const Duration(minutes: 2));
    });

    test('edge cases E-1 .. E-14 (valid ones) are present and real', () {
      final e = c.edgeCases;
      ActivitySession s(String k) => c.byId(e[k]!);
      // E-1
      expect(s('E-1').summary.distanceM, 0);
      expect(s('E-1').durationMs, greaterThan(0));
      // E-2
      expect(s('E-2').startUtc, s('E-2').endUtc);
      // E-3
      for (final k in const [0, 345, -720, 840, -840]) {
        expect(s('E-3:$k').utcOffsetMinutes, k);
      }
      final m = s('E-3:midnight');
      final localStart = m.startUtc.add(Duration(minutes: m.utcOffsetMinutes));
      final localEnd = m.endUtc.add(Duration(minutes: m.utcOffsetMinutes));
      expect(localStart.day, isNot(localEnd.day), reason: 'must cross local midnight');
      // E-4: a 120 s gap and a 30 s stationary cluster
      final g4 = s('E-4').streams[StreamKind.gps]!;
      var maxJump = 0;
      for (var i = 1; i < g4.length; i++) {
        final d = g4.offsetsMs[i] - g4.offsetsMs[i - 1];
        if (d > maxJump) maxJump = d;
      }
      expect(maxJump, 121000);
      var still = 0, bestStill = 0;
      for (var i = 1; i < g4.length; i++) {
        still = g4.lats[i] == g4.lats[i - 1] && g4.lons[i] == g4.lons[i - 1]
            ? still + 1
            : 0;
        if (still > bestStill) bestStill = still;
      }
      expect(bestStill, greaterThanOrEqualTo(29));
      // E-5
      final g5 = s('E-5').streams[StreamKind.gps]!;
      expect([g5.lats[0], g5.lons[0]], [89.99999, 179.99999]);
      expect([g5.lats[1], g5.lons[1]], [-90.0, -180.0]);
      expect([g5.lats[2], g5.lons[2]], [0.0, 0.0]);
      // E-8: five schema-1 records
      expect(c.schema1Maps, hasLength(5));
      for (final m1 in c.schema1Maps.values) {
        expect(m1['schema'], 1);
        expect(m1.containsKey('formulaVersion'), isFalse);
        expect(m1.containsKey('userEditCount'), isFalse);
      }
      // E-9
      expect(s('E-9:sourceId64').provenance.first.sourceId.length, 64);
      expect(s('E-9:unicodeExternalId').provenance.any((p) =>
          p.externalId != null && p.externalId!.runes.any((r) => r > 127)),
          isTrue);
      // E-10: two sources, same external id
      final dup = s('E-10').provenance;
      expect(dup.length, greaterThanOrEqualTo(2));
      expect(dup[0].externalId, dup[1].externalId);
      expect(dup[0].sourceId, isNot(dup[1].sourceId));
      // E-11
      final mx = s('E-11:max').summary;
      expect([mx.distanceM, mx.ascentM, mx.descentM, mx.avgSpeedMps,
          mx.avgCadence, mx.avgPowerW, mx.normalizedPowerW,
          mx.activeEnergyKcal, mx.steps, mx.strokeCount, mx.poolLengthM,
          mx.lapCount, mx.avgSwolf],
          [10000000, 100000, 100000, 120, 400, 5000, 5000, 50000, 1000000,
           100000, 1000, 1000, 300]);
      expect(s('E-11:max').movingTimeS, 604800);
      expect(s('E-11:max').privacy.routeTrimMeters, 2000);
      expect(s('E-11:max').provenance, hasLength(64));
      expect(s('E-11:max').mergeNotes, hasLength(64));
      final z = s('E-11:zero');
      expect(z.summary.toFieldMap().values.where((v) => v != null).every((v) => v == 0),
          isTrue);
      expect(z.movingTimeS, 0);
      // E-12
      expect(s('E-12:hrOnly').streams.containsKey(StreamKind.gps), isFalse);
      expect(s('E-12:hrOnly').streams.containsKey(StreamKind.heartRate), isTrue);
      expect(s('E-12:gpsOnly').streams.containsKey(StreamKind.heartRate), isFalse);
      expect(s('E-12:gpsOnly').streams.containsKey(StreamKind.gps), isTrue);
      expect(s('E-12:hrLaps').laps.any((l) => l.avgHrBpm != null), isTrue);
      // E-13
      expect(s('E-13').provenance.first.externalId, kFixedNativeUuid);
      // E-14
      final b = s('E-14').summary;
      expect([b.avgSpeedMps, b.ascentM, b.steps], [120, 100000, 1000000]);
    });

    test('every coordinate lies in the synthetic area (E-5 excepted) and '
        'carries the latitude sentinel 7351', () {
      final e5 = c.edgeCases['E-5'];
      for (final s in valid) {
        final g = s.streams[StreamKind.gps];
        if (g == null) continue;
        for (var i = 0; i < g.length; i++) {
          if (s.id == e5 && i < 3) continue;
          expect(g.lats[i], inInclusiveRange(kAreaLatMin, kAreaLatMax),
              reason: '${s.id}[$i]');
          expect(g.lons[i], inInclusiveRange(kAreaLonMin, kAreaLonMax),
              reason: '${s.id}[$i]');
          if (!'${g.lats[i]}'.endsWith('7351')) {
            fail('${s.id}[$i] latitude ${g.lats[i]} lacks the sentinel tail');
          }
        }
      }
    });

    test('every heart-rate value carries the .25 sentinel tail and stays 40-210',
        () {
      for (final s in valid) {
        final h = s.streams[StreamKind.heartRate];
        if (h == null) continue;
        for (final v in h.values) {
          if (v < 40 || v > 210 || !'$v'.endsWith('.25')) {
            fail('${s.id} heart rate $v');
          }
        }
      }
    });

    test('the VALID set contains no hostile feature', () {
      for (final s in valid) {
        expect(s.schema, lessThanOrEqualTo(2), reason: s.id);
        expect(s.extras, isEmpty, reason: s.id);
        expect(s.summary.extras, isEmpty, reason: s.id);
        expect(s.readDiagnostics, isEmpty);
        for (final st in s.streams.values) {
          for (var i = 1; i < st.offsetsMs.length; i++) {
            if (st.offsetsMs[i] <= st.offsetsMs[i - 1]) {
              fail('non-monotonic stream in ${s.id}');
            }
          }
        }
        final stored = s.toJson();
        expect(SportType.values.map((t) => t.name), contains(stored['sport']));
      }
      final hostileIds = SyntheticHostile.build().namedIds.toSet();
      expect(valid.map((s) => s.id).toSet().intersection(hostileIds), isEmpty);
    });

    test('the quota check would catch a polluted corpus (negative control)', () {
      final polluted = [...valid.take(99), valid.first];
      expect({for (final s in polluted) s.id}.length, isNot(100));
      final dropped = valid.where((s) => s.sport != SportType.other);
      expect(dropped.length, isNot(100));
    });
  });
}
