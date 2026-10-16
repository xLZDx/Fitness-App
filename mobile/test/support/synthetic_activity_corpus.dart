// Deterministic synthetic corpus of 100 real-shaped activity sessions (S02 test
// plan section 2, VALID part). Test-only, pure, no clock, no `dart:math`.
//
// Everything is derived from the master seed through an own SplitMix64, and no
// trigonometry or logarithm is used (only + - * / and sqrt, which are exact
// IEEE operations), so the canonical JSON and its digest are identical on every
// machine. Positions are fabricated on a synthetic grid in open ocean; every
// GPS latitude carries the byte sentinel tail `7351` and every heart-rate value
// the tail `.25`. The HOSTILE / future-schema set lives in
// `synthetic_hostile_corpus.dart` and is never mixed into this one.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/data/summary_overrides.dart';

const int kCorpusSeed = 20261016;
const int kFuzzSeed = 20261017;

/// The synthetic area (open ocean). Only the E-5 bound record leaves it.
const double kAreaLatMin = 0;
const double kAreaLatMax = 5;
const double kAreaLonMin = -30;
const double kAreaLonMax = -25;

/// Own PRNG (stable across SDK versions).
class SplitMix64 {
  SplitMix64(int seed) : _s = seed;

  int _s;

  int nextU64() {
    _s += 0x9E3779B97F4A7C15;
    var z = _s;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    return z ^ (z >>> 31);
  }

  double nextDouble() => (nextU64() >>> 11) / 9007199254740992.0;

  int nextInt(int n) => (nextU64() >>> 1) % n;

  /// Inclusive range.
  int range(int lo, int hi) => lo + nextInt(hi - lo + 1);

  /// Irwin-Hall approximation of a standard normal (no log, no trig).
  double gauss() {
    var s = 0.0;
    for (var i = 0; i < 12; i++) {
      s += nextDouble();
    }
    return s - 6;
  }

  void shuffle<T>(List<T> l) {
    for (var i = l.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = l[i];
      l[i] = l[j];
      l[j] = t;
    }
  }
}

/// Canonical JSON: keys sorted at every depth, no DateTime.
String canonicalJson(Object? v) => jsonEncode(_canon(v));

Object? _canon(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(v[k])};
  }
  if (v is List) return [for (final e in v) _canon(e)];
  if (v is double && !v.isFinite) return v.toString();
  return v;
}

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// The exact per-sport quotas of the VALID set (plan 2.2). The test file keeps
/// its own literal copy as the oracle.
const Map<SportType, int> kSportQuota = {
  SportType.running: 12,
  SportType.cycling: 10,
  SportType.walking: 8,
  SportType.hiking: 6,
  SportType.trailRunning: 6,
  SportType.mountainBiking: 6,
  SportType.indoorCycling: 8,
  SportType.swimmingPool: 10,
  SportType.swimmingOpenWater: 6,
  SportType.rowing: 6,
  SportType.strength: 12,
  SportType.other: 10,
};

/// GPS-bearing workouts per sport (sums to 38).
const Map<SportType, int> _gpsPerSport = {
  SportType.running: 8,
  SportType.trailRunning: 6,
  SportType.walking: 4,
  SportType.hiking: 6,
  SportType.cycling: 4,
  SportType.mountainBiking: 3,
  SportType.swimmingOpenWater: 4,
  SportType.rowing: 3,
};

const String kFixedNativeUuid = '3f2b8c1e-5d4a-4e0b-9a77-0c1d2e3f4a5b';

class _Spec {
  _Spec(this.i, this.sport);
  final int i;
  final SportType sport;
  bool gps = false;
  bool hr = false;
  bool altitude = false;
  bool speed = false;
  bool cadence = false;
  bool power = false;
  bool strokeRate = false;
  bool temperature = false;
  bool noStreams = false;
  bool special = false;
  int group = 1;
  int gpsPoints = 0;
  int? utcOffset;
  bool midnight = false;
  bool gap = false;
  bool edgePoints = false;
  bool zeroDist = false;
  bool zeroDur = false;
  bool maxKeys = false;
  bool allZero = false;
  bool boundsE14 = false;
  bool thousandLaps = false;
  bool fixedUuid = false;
  bool longSource = false;
  bool dupExt = false;
  bool schema1 = false;
  bool echo = false;
  int fileImportSlot = -1;
  String decoration = '';
}

/// The generated VALID corpus.
class SyntheticCorpus {
  SyntheticCorpus._(
    this.valid,
    this.rawCandidates,
    this.schema1Maps,
    this.edgeCases,
    this.splitPair,
    this.echoIds,
  );

  /// The 100 logical workouts (the merged expectation of each workout).
  final List<ActivitySession> valid;

  /// 155 raw per-source candidates (60 workouts x1, 25 x2, 15 x3).
  final List<ActivitySession> rawCandidates;

  /// Stored schema-1 maps of the 5 `schema=1` records, by session id.
  final Map<String, Map<String, dynamic>> schema1Maps;

  /// Named valid edge cases of plan 2.3 to the session id.
  final Map<String, String> edgeCases;

  /// One workout recorded as two halves (gap 2 min), outside the 155.
  final List<ActivitySession> splitPair;

  /// Workouts that carry a platform-health echo of the native record.
  final List<String> echoIds;

  ActivitySession byId(String id) => valid.firstWhere((s) => s.id == id);

  /// The canonical JSON of the VALID set exactly as stored (schema-1 records in
  /// their stored schema-1 form).
  String canonical() => canonicalJson({
        'valid': [
          for (final s in valid) schema1Maps[s.id] ?? s.toJson(),
        ],
        'candidates': [for (final s in rawCandidates) s.toJson()],
        'splitPair': [for (final s in splitPair) s.toJson()],
        'edgeCases': edgeCases,
        'echoIds': echoIds,
      });

  String digest() => sha256Hex(canonical());

  static SyntheticCorpus? _cached;

  static SyntheticCorpus build() => _cached ??= _build();

  /// A fresh, uncached build (the determinism test compares two of them).
  static SyntheticCorpus buildFresh() => _build();
}

// ---------------------------------------------------------------------------
// Build

SyntheticCorpus _build() {
  final master = SplitMix64(kCorpusSeed);
  final sports = <SportType>[
    for (final e in kSportQuota.entries)
      for (var k = 0; k < e.value; k++) e.key,
  ];
  master.shuffle(sports);
  final specs = [for (var i = 0; i < sports.length; i++) _Spec(i, sports[i])];

  // GPS-bearing workouts per sport (38).
  final taken = <SportType, int>{};
  for (final w in specs) {
    final quota = _gpsPerSport[w.sport] ?? 0;
    final used = taken[w.sport] ?? 0;
    if (used < quota) {
      w.gps = true;
      taken[w.sport] = used + 1;
    }
  }
  final gpsSpecs = specs.where((w) => w.gps).toList();

  // Source-group sizes: 60 x 1, 25 x 2, 15 x 3.
  final groups = <int>[
    ...List.filled(60, 1),
    ...List.filled(25, 2),
    ...List.filled(15, 3),
  ];
  master.shuffle(groups);
  for (var i = 0; i < specs.length; i++) {
    specs[i].group = groups[i];
  }

  // Named special records (all `other`, no streams) plus indoor specials.
  final others = specs.where((w) => w.sport == SportType.other).toList();
  others[0]
    ..zeroDur = true
    ..noStreams = true
    ..special = true;
  others[1]
    ..maxKeys = true
    ..noStreams = true
    ..special = true;
  others[2]
    ..allZero = true
    ..noStreams = true
    ..special = true;
  others[3]
    ..boundsE14 = true
    ..noStreams = true
    ..special = true;
  others[4]
    ..thousandLaps = true
    ..noStreams = true
    ..special = true;
  final indoorBikes =
      specs.where((w) => w.sport == SportType.indoorCycling).toList();
  indoorBikes[0]
    ..zeroDist = true
    ..special = true;
  final strength = specs.where((w) => w.sport == SportType.strength).toList();
  const offsets = [0, 345, -720, 840, -840];
  for (var k = 0; k < 5; k++) {
    strength[k].utcOffset = offsets[k];
  }
  strength[1].midnight = true;

  // GPS tiers: 20 x 600-1800, 12 x 1800-7200, 5 x 7200-14400, 1 x 43200.
  final tiers = <int>[
    ...List.filled(20, 0),
    ...List.filled(12, 1),
    ...List.filled(5, 2),
    3,
  ];
  master.shuffle(tiers);
  for (var k = 0; k < gpsSpecs.length; k++) {
    final r = SplitMix64(kCorpusSeed ^ ((1000 + k) * 0x9E3779B97F4A7C15));
    gpsSpecs[k].gpsPoints = switch (tiers[k]) {
      0 => r.range(600, 1800),
      1 => r.range(1801, 7200),
      2 => r.range(7201, 14400),
      _ => 43200,
    };
  }
  final gpsWithGap = gpsSpecs.firstWhere((w) => w.gpsPoints > 700 && w.gpsPoints < 7200);
  gpsWithGap.gap = true;
  final gpsEdge = gpsSpecs.lastWhere((w) => w.gpsPoints > 700 && w.gpsPoints < 7200 && !w.gap);
  gpsEdge.edgePoints = true;

  // Heart rate: 60 = 23 GPS-bearing + 37 indoor.
  void pick(List<_Spec> pool, int n, void Function(_Spec) set) {
    final c = [...pool]..removeWhere((w) => w.noStreams);
    master.shuffle(c);
    for (final w in c.take(n)) {
      set(w);
    }
  }

  pick(gpsSpecs, 23, (w) => w.hr = true);
  pick(specs.where((w) => !w.gps).toList(), 37, (w) => w.hr = true);
  pick(gpsSpecs, 30, (w) => w.altitude = true);
  pick(gpsSpecs, 25, (w) => w.speed = true);
  const cadenceSports = {
    SportType.running,
    SportType.trailRunning,
    SportType.walking,
    SportType.hiking,
    SportType.cycling,
    SportType.indoorCycling,
    SportType.mountainBiking,
  };
  pick(specs.where((w) => cadenceSports.contains(w.sport)).toList(), 20,
      (w) => w.cadence = true);
  const bikes = {
    SportType.cycling,
    SportType.indoorCycling,
    SportType.mountainBiking,
  };
  pick(specs.where((w) => bikes.contains(w.sport)).toList(), 15,
      (w) => w.power = true);
  const paddlers = {
    SportType.rowing,
    SportType.swimmingPool,
    SportType.swimmingOpenWater,
  };
  pick(specs.where((w) => paddlers.contains(w.sport)).toList(), 8,
      (w) => w.strokeRate = true);
  pick(specs, 5, (w) => w.temperature = true);

  // Edge cases riding on natural records.
  final multi = specs.where((w) => w.group >= 2 && !w.special).toList();
  master.shuffle(multi);
  for (var k = 0; k < 5; k++) {
    multi[k].fileImportSlot = 1;
  }
  final echoCandidates = multi.skip(5).take(8).toList();
  for (final w in echoCandidates) {
    w.echo = true;
  }
  final plain = specs.where((w) => !w.special && !w.noStreams).toList();
  specs.firstWhere((w) => w.sport == SportType.running && !w.special).longSource = true;
  plain.firstWhere((w) => w.sport == SportType.cycling).dupExt = true;
  plain.firstWhere((w) => w.sport == SportType.walking).fixedUuid = true;

  // The 5 schema-1 records: undecorated, ordinary content.
  const s1Sports = [
    SportType.running,
    SportType.cycling,
    SportType.swimmingPool,
    SportType.strength,
    SportType.walking,
  ];
  for (final sp in s1Sports) {
    specs
        .firstWhere((w) =>
            w.sport == sp &&
            !w.special &&
            !w.longSource &&
            !w.dupExt &&
            !w.fixedUuid &&
            !w.schema1 &&
            w.utcOffset == null &&
            !w.echo &&
            w.fileImportSlot < 0)
        .schema1 = true;
  }

  // Decorations (explicit values, overrides, counters, A-5 variants).
  final decoratable = specs
      .where((w) =>
          !w.special &&
          !w.schema1 &&
          !w.noStreams &&
          !w.zeroDist &&
          w.sport != SportType.strength)
      .toList();
  master.shuffle(decoratable);
  const decos = [
    ...['explicit', 'explicit', 'explicit', 'explicit', 'explicit'],
    ...['explicitCandidate', 'explicitCandidate'],
    ...['override', 'override', 'override', 'override'],
    ...['overrideCandidate', 'overrideCandidate'],
    ...['explicitOverride', 'explicitOverride'],
    ...['fullRing'],
    ...['legacyEdits', 'legacyEdits', 'legacyEdits'],
    ...['versions', 'versions', 'versions', 'versions'],
    ...['terms', 'terms', 'terms', 'terms', 'terms', 'terms'],
  ];
  for (var k = 0; k < decos.length && k < decoratable.length; k++) {
    decoratable[k].decoration = decos[k];
  }

  final sessions = <ActivitySession>[];
  final schema1 = <String, Map<String, dynamic>>{};
  final edge = <String, String>{};
  final echoIds = <String>[];
  for (final w in specs) {
    final r = SplitMix64(kCorpusSeed ^ (w.i * 0x9E3779B97F4A7C15));
    var s = _buildSession(w, r);
    if (w.decoration.isNotEmpty) s = _decorate(s, w.decoration, r);
    if (w.schema1) {
      schema1[s.id] = _toSchema1(s);
    }
    sessions.add(s);
    if (w.echo) echoIds.add(s.id);
  }
  String idOf(bool Function(_Spec) f) => sessions[specs.firstWhere(f).i].id;
  edge['E-1'] = idOf((w) => w.zeroDist);
  edge['E-2'] = idOf((w) => w.zeroDur);
  for (var k = 0; k < 5; k++) {
    edge['E-3:${offsets[k]}'] = sessions[strength[k].i].id;
  }
  edge['E-3:midnight'] = sessions[strength[1].i].id;
  edge['E-4'] = idOf((w) => w.gap);
  edge['E-5'] = idOf((w) => w.edgePoints);
  var n1 = 0;
  for (final w in specs.where((w) => w.schema1)) {
    edge['E-8:${n1++}'] = sessions[w.i].id;
  }
  edge['E-9:sourceId64'] = idOf((w) => w.longSource);
  edge['E-9:unicodeExternalId'] = idOf((w) => w.longSource);
  edge['E-10'] = idOf((w) => w.dupExt);
  edge['E-11:max'] = idOf((w) => w.maxKeys);
  edge['E-11:zero'] = idOf((w) => w.allZero);
  edge['E-12:hrOnly'] =
      idOf((w) => !w.gps && w.hr && !w.noStreams);
  edge['E-12:gpsOnly'] = idOf((w) => w.gps && !w.hr);
  edge['E-12:hrLaps'] =
      idOf((w) => w.sport == SportType.running && w.hr && !w.special);
  edge['E-13'] = idOf((w) => w.fixedUuid);
  edge['E-14'] = idOf((w) => w.boundsE14);
  edge['laps:1000'] = idOf((w) => w.thousandLaps);

  final candidates = _candidates(specs, sessions);
  final split = _splitPair(specs, sessions);
  return SyntheticCorpus._(
    List.unmodifiable(sessions),
    List.unmodifiable(candidates),
    Map.unmodifiable(schema1),
    Map.unmodifiable(edge),
    List.unmodifiable(split),
    List.unmodifiable(echoIds),
  );
}

// ---------------------------------------------------------------------------
// One session

const List<(String, SourceKind, String?, String?)> _sources = [
  ('ble-strap-1', SourceKind.bleSensor, 'HRM Dual', null),
  ('app', SourceKind.companionApp, 'Pixel 8', 'com.fitness.app'),
  ('hc-android', SourceKind.platformHealth, 'Pixel Watch', 'com.google.android.apps.fitness'),
  ('garmin-connect', SourceKind.vendorCloud, 'Forerunner 245', null),
  ('strava-feed', SourceKind.vendorCloud, null, null),
];

DateTime _startFor(_Spec w, SplitMix64 r) {
  final base = DateTime.utc(2026, 1, 1);
  final jitter = r.nextInt(90 * 60 + 1);
  var start = base.add(Duration(hours: w.i * 17, seconds: jitter));
  if (w.midnight) {
    // Local 23:50 on that day: crosses local midnight.
    final off = w.utcOffset ?? 0;
    final day = DateTime.utc(start.year, start.month, start.day, 23, 50);
    start = day.subtract(Duration(minutes: off));
  }
  return start;
}

ActivitySession _buildSession(_Spec w, SplitMix64 r) {
  final start = _startFor(w, r);
  final primary = _sources[w.i % 5];
  final streams = <StreamKind, SampleStream>{};
  var durS = 0;
  double? distance;
  var ascent = 0.0, descent = 0.0;
  final laps = <Lap>[];
  double? poolLength;
  double? swolf;
  double? strokes;

  const double areaLatMin = 0.1, areaLatMax = 4.9;
  const double areaLonMin = -29.9, areaLonMax = -25.1;
  final srcId = w.longSource ? 's${'x' * 63}' : primary.$1;

  if (w.gps && !w.noStreams) {
    final n = w.gpsPoints;
    final offs = <int>[];
    final lats = <double>[];
    final lons = <double>[];
    final acc = <double>[];
    final spd = <double>[];
    var lat = 0.5 + r.nextDouble() * 4;
    var lon = -29.5 + r.nextDouble() * 4;
    var hx = 1.0, hy = 0.0;
    for (var k = 0; k < 8; k++) {
      (hx, hy) = _rot(hx, hy, (r.nextDouble() - 0.5) * 1.4);
    }
    var length = 0.0;
    var t = 0;
    final gapAt = w.gap ? n ~/ 2 : -1;
    final stillFrom = w.gap ? n ~/ 4 : -1;
    for (var k = 0; k < n; k++) {
      if (k == gapAt) t += 120000;
      final still = k >= stillFrom && k < stillFrom + 30 && stillFrom >= 0;
      var step = 0.0;
      if (k > 0 && !still) {
        (hx, hy) = _rot(hx, hy, _clampD(r.gauss() * 0.10472, -0.5, 0.5));
        step = 3 + 6 * r.nextDouble();
        lat += hy * step / 111320;
        lon += hx * step / 111320;
        if (lat < areaLatMin || lat > areaLatMax) {
          hy = -hy;
          lat = _clampD(lat, areaLatMin, areaLatMax);
        }
        if (lon < areaLonMin || lon > areaLonMax) {
          hx = -hx;
          lon = _clampD(lon, areaLonMin, areaLonMax);
        }
      }
      length += step;
      offs.add(t);
      lats.add(_sentinelLat(lat));
      lons.add((lon * 1e6).round() / 1e6);
      acc.add(3 + (r.nextInt(40)) / 10);
      spd.add((step * 10).round() / 10);
      t += 1000;
    }
    if (w.edgePoints) {
      lats[0] = 89.99999;
      lons[0] = 179.99999;
      lats[1] = -90;
      lons[1] = -180;
      lats[2] = 0;
      lons[2] = 0;
    }
    durS = (offs.last ~/ 1000) + 1;
    streams[StreamKind.gps] = SampleStream.checked(
      kind: StreamKind.gps,
      sourceId: srcId,
      offsetsMs: offs,
      lats: lats,
      lons: lons,
      accuracies: acc,
    );
    if (w.altitude) {
      var a = 5 + r.nextDouble() * 200;
      final vals = <double>[];
      for (var k = 0; k < n; k++) {
        final next = _clampD(a + r.gauss() * 0.4, -5, 900);
        if (k > 0) {
          if (next > a) {
            ascent += next - a;
          } else {
            descent += a - next;
          }
        }
        a = next;
        vals.add((a * 10).round() / 10);
      }
      streams[StreamKind.altitude] = SampleStream.checked(
        kind: StreamKind.altitude,
        sourceId: srcId,
        offsetsMs: offs,
        values: vals,
      );
    }
    if (w.speed) {
      streams[StreamKind.speed] = SampleStream.checked(
        kind: StreamKind.speed,
        sourceId: srcId,
        offsetsMs: offs,
        values: spd,
      );
    }
    distance = (length * 10).round() / 10;
  } else if (w.zeroDur) {
    durS = 0;
  } else if (w.maxKeys) {
    durS = 604800;
  } else if (w.thousandLaps) {
    durS = 6000;
  } else if (w.sport == SportType.swimmingPool) {
    poolLength = const [25.0, 33.33, 50.0][r.nextInt(3)];
  } else {
    durS = r.range(1200, 5400);
  }

  if (w.sport == SportType.swimmingPool) {
    final nLaps = r.range(20, 80);
    var off = 0.0;
    var sc = 0;
    for (var k = 0; k < nLaps; k++) {
      final d = (25 + r.nextInt(36)).toDouble();
      final st = 12 + r.nextInt(19);
      sc += st;
      laps.add(Lap(
        index: k,
        kind: LapKind.poolLength,
        startOffsetS: off,
        durationS: d,
        distanceM: poolLength,
        strokeCount: st,
        strokeType: StrokeType.values[r.nextInt(StrokeType.values.length)],
      ));
      off += d;
    }
    durS = off.ceil();
    distance = (nLaps * poolLength! * 100).round() / 100;
    strokes = sc.toDouble();
    swolf = 30 + r.nextInt(30).toDouble();
  }

  // Non-GPS sessions get their duration-based streams below.
  if (!w.noStreams) {
    if (w.hr && durS > 0) {
      streams[StreamKind.heartRate] = _hrStream(r, durS, 'ble-strap-1');
    }
    final base = durS;
    List<double> series(double lo, double hi, {int dec = 0}) {
      final p = pow10(dec);
      var v = lo + r.nextDouble() * (hi - lo);
      return [
        for (var k = 0; k < base; k++)
          () {
            v = _clampD(v + r.gauss() * (hi - lo) * 0.02, lo, hi);
            return (v * p).round() / p;
          }(),
      ];
    }

    if (w.cadence && base > 0) {
      streams[StreamKind.cadence] = SampleStream.checked(
        kind: StreamKind.cadence,
        sourceId: srcId,
        offsetsMs: _offsetsLike(streams, base),
        values: series(60, 110).sublist(0, _offsetsLike(streams, base).length),
      );
    }
    if (w.power && base > 0) {
      streams[StreamKind.power] = SampleStream.checked(
        kind: StreamKind.power,
        sourceId: srcId,
        offsetsMs: _offsetsLike(streams, base),
        values: series(110, 320).sublist(0, _offsetsLike(streams, base).length),
      );
    }
    if (w.strokeRate && base > 0) {
      streams[StreamKind.strokeRate] = SampleStream.checked(
        kind: StreamKind.strokeRate,
        sourceId: srcId,
        offsetsMs: _offsetsLike(streams, base),
        values: series(18, 40).sublist(0, _offsetsLike(streams, base).length),
      );
    }
    if (w.temperature && base > 0) {
      final offs = [for (var k = 0; k < base; k += 60) k * 1000];
      streams[StreamKind.temperature] = SampleStream.checked(
        kind: StreamKind.temperature,
        sourceId: srcId,
        offsetsMs: offs,
        values: [for (var k = 0; k < offs.length; k++) 14 + (r.nextInt(150)) / 10],
      );
    }
  }

  // Laps for runs: auto laps per kilometre.
  if (w.sport == SportType.running && !w.special) {
    final dist = distance ?? (durS * (2.4 + r.nextDouble() * 1.2));
    distance ??= (dist * 10).round() / 10;
    final km = (dist / 1000).floor();
    final secPerKm = durS / (dist / 1000);
    for (var k = 0; k < km; k++) {
      laps.add(Lap(
        index: k,
        kind: LapKind.auto,
        startOffsetS: (k * secPerKm * 10).round() / 10,
        durationS: (secPerKm * 10).round() / 10,
        distanceM: 1000,
        avgHrBpm: w.hr ? 120.0 + (k % 40) + 0.25 : null,
      ));
    }
  }
  if (w.thousandLaps) {
    for (var k = 0; k < 1000; k++) {
      laps.add(Lap(
        index: k,
        kind: LapKind.interval,
        startOffsetS: k * 6.0,
        durationS: 5,
      ));
    }
  }

  // Indoor distance for treadmill / trainer without a stream.
  if (distance == null && durS > 0) {
    if (w.sport == SportType.running ||
        w.sport == SportType.indoorCycling ||
        w.sport == SportType.walking ||
        w.sport == SportType.hiking ||
        w.sport == SportType.rowing) {
      distance = (durS * (2 + r.nextDouble() * 2) * 10).round() / 10;
    }
  }
  if (w.zeroDist) distance = 0;

  final hrStream = streams[StreamKind.heartRate];
  final cadStream = streams[StreamKind.cadence];
  final powStream = streams[StreamKind.power];
  double? mean(SampleStream? st) {
    if (st == null || st.values.isEmpty) return null;
    var sum = 0.0;
    for (final v in st.values) {
      sum += v;
    }
    return sum / st.values.length;
  }

  final meanHr = mean(hrStream);
  final meanPow = mean(powStream);
  var summary = ActivitySummary(
    distanceM: distance,
    ascentM: w.altitude && streams.containsKey(StreamKind.altitude)
        ? (ascent * 10).round() / 10
        : null,
    descentM: w.altitude && streams.containsKey(StreamKind.altitude)
        ? (descent * 10).round() / 10
        : null,
    avgHrBpm: meanHr == null ? null : meanHr.floorToDouble() + 0.25,
    maxHrBpm: hrStream == null
        ? null
        : hrStream.values.reduce((a, b) => a > b ? a : b),
    avgSpeedMps: distance != null && distance > 0 && durS > 0
        ? (distance / durS * 1000).round() / 1000
        : null,
    avgCadence: cadStream == null ? null : (mean(cadStream)! * 10).round() / 10,
    avgPowerW: meanPow == null ? null : (meanPow * 10).round() / 10,
    normalizedPowerW:
        meanPow == null ? null : (meanPow * 1.05 * 10).round() / 10,
    activeEnergyKcal: durS > 0 && w.sport != SportType.other
        ? (durS / 3600 * (350 + r.nextInt(400))).roundToDouble()
        : null,
    steps: const {SportType.running, SportType.walking, SportType.hiking, SportType.trailRunning}
                .contains(w.sport) &&
            durS > 0
        ? (durS * 2.6).roundToDouble()
        : null,
    strokeCount: strokes ??
        (w.sport == SportType.rowing && durS > 0
            ? (durS / 60 * 24).roundToDouble()
            : null),
    poolLengthM: poolLength,
    lapCount: laps.isEmpty ? null : laps.length.toDouble(),
    avgSwolf: swolf,
  );

  // Provenance.
  final provenance = _provenance(w, primary, start, durS);
  final id = activityIdFor(
    sourceId: provenance.first.sourceId,
    externalId: provenance.first.externalId,
    startUtc: start,
  );

  var movingTimeS = durS > 0 ? (durS * (0.93 + r.nextDouble() * 0.07)).floorToDouble() : 0.0;
  var privacyTrim = ActivityPrivacy.defaultRouteTrimMeters;
  var offset = w.utcOffset ??
      const [0, 60, 120, -300, 330, -480, 540][r.nextInt(7)];
  var mergeNotes = <String>[
    if (w.group > 1 && r.nextInt(3) == 0) 'summaryDisagreement:distanceM',
  ];

  if (w.zeroDur) {
    movingTimeS = 0;
  }
  if (w.maxKeys) {
    summary = const ActivitySummary(
      distanceM: 10000000,
      ascentM: 100000,
      descentM: 100000,
      avgSpeedMps: 120,
      avgCadence: 400,
      avgPowerW: 5000,
      normalizedPowerW: 5000,
      activeEnergyKcal: 50000,
      steps: 1000000,
      strokeCount: 100000,
      poolLengthM: 1000,
      lapCount: 1000,
      avgSwolf: 300,
    );
    movingTimeS = 604800;
    privacyTrim = 2000;
    offset = 840;
    mergeNotes = [for (var k = 0; k < 64; k++) 'summaryDisagreement:n$k'];
  }
  if (w.allZero) {
    summary = const ActivitySummary(
      distanceM: 0,
      ascentM: 0,
      descentM: 0,
      avgSpeedMps: 0,
      avgCadence: 0,
      avgPowerW: 0,
      normalizedPowerW: 0,
      activeEnergyKcal: 0,
      steps: 0,
      strokeCount: 0,
      poolLengthM: 0,
      lapCount: 0,
      avgSwolf: 0,
    );
    movingTimeS = 0;
    privacyTrim = 0;
    offset = 0;
    mergeNotes = const [];
  }
  if (w.boundsE14) {
    summary = const ActivitySummary(
      avgSpeedMps: 120,
      ascentM: 100000,
      steps: 1000000,
    );
  }

  return ActivitySession(
    id: id,
    sport: w.sport,
    startUtc: start,
    endUtc: start.add(Duration(seconds: durS)),
    utcOffsetMinutes: offset,
    movingTimeS: movingTimeS,
    summary: summary,
    streams: streams,
    laps: laps,
    provenance: w.maxKeys
        ? [
            for (var k = 0; k < 64; k++)
              SourceRecord(
                sourceId: 'src-$k',
                sourceKind: SourceKind.values[k % 4],
                importedAt: DateTime.utc(2026, 6, 1, 0, 0, k),
                externalId: 'max-$k',
              ),
          ]
        : provenance,
    privacy: ActivityPrivacy(routeTrimMeters: privacyTrim),
    mergeNotes: mergeNotes,
  );
}

double pow10(int n) {
  var p = 1.0;
  for (var i = 0; i < n; i++) {
    p *= 10;
  }
  return p;
}

List<int> _offsetsLike(Map<StreamKind, SampleStream> streams, int base) {
  final gps = streams[StreamKind.gps];
  if (gps != null) return gps.offsetsMs;
  return [for (var k = 0; k < base; k++) k * 1000];
}

(double, double) _rot(double hx, double hy, double a) {
  final a2 = a * a;
  final c = 1 - a2 / 2 + a2 * a2 / 24 - a2 * a2 * a2 / 720;
  final s = a - a2 * a / 6 + a2 * a2 * a / 120;
  final nx = hx * c - hy * s;
  final ny = hx * s + hy * c;
  final norm = _sqrt(nx * nx + ny * ny);
  return (nx / norm, ny / norm);
}

double _sqrt(double x) {
  // Newton iteration from a fixed start (exact enough, deterministic).
  var g = x > 1 ? x / 2 : 1.0;
  for (var i = 0; i < 40; i++) {
    g = (g + x / g) / 2;
  }
  return g;
}

double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Latitude with 10 decimals whose last four digits are the sentinel `7351`.
double _sentinelLat(double lat) {
  final m = (lat * 1e10).round();
  return ((m ~/ 10000) * 10000 + 7351) / 1e10;
}

SampleStream _hrStream(SplitMix64 r, int durS, String sourceId) {
  final drops = <(int, int)>[];
  if (durS > 200) {
    for (var k = 0; k < 3; k++) {
      final at = r.range(30, durS - 40);
      drops.add((at, at + r.range(5, 20)));
    }
  }
  bool dropped(int t) {
    for (final d in drops) {
      if (t >= d.$1 && t < d.$2) return true;
    }
    return false;
  }

  final base = r.range(95, 150).toDouble();
  final drift = r.range(10, 40).toDouble();
  final offs = <int>[];
  final vals = <double>[];
  for (var t = 0; t < durS; t++) {
    if (dropped(t)) continue;
    final v = _clampD(base + drift * t / durS + r.gauss() * 3, 40, 209);
    offs.add(t * 1000);
    vals.add(v.floorToDouble() + 0.25);
  }
  return SampleStream.checked(
    kind: StreamKind.heartRate,
    sourceId: sourceId,
    offsetsMs: offs,
    values: vals,
  );
}

List<SourceRecord> _provenance(
  _Spec w,
  (String, SourceKind, String?, String?) primary,
  DateTime start,
  int durS,
) {
  final end = start.add(Duration(seconds: durS));
  final out = <SourceRecord>[];
  String ext(int k) => w.fixedUuid && k == 0
      ? kFixedNativeUuid
      : (w.longSource && k == 1 ? 'séance-é-日本-${w.i}' : 'syn-${w.i}-$k');
  out.add(SourceRecord(
    sourceId: w.longSource ? 's${'x' * 63}' : primary.$1,
    sourceKind: primary.$2,
    importedAt: end.add(const Duration(minutes: 5)),
    deviceModel: primary.$3,
    appPackage: primary.$4,
    externalId: ext(0),
    fieldsContributed: [
      'distanceM',
      if (w.hr) 'heartRate',
      if (w.gps) 'gps',
    ],
  ));
  final others = [
    for (final s in _sources)
      if (s.$1 != primary.$1) s,
  ];
  for (var k = 1; k < w.group; k++) {
    final src = others[(w.i + k) % others.length];
    var kind = src.$2;
    var sid = src.$1;
    String? model = src.$3;
    String? pkg = src.$4;
    if (w.fileImportSlot == k) {
      kind = SourceKind.fileImport;
      sid = 'gpx-import';
      model = null;
      pkg = null;
    }
    if (w.echo && k == 1) {
      kind = SourceKind.platformHealth;
      sid = 'hc-android';
      model = 'Pixel Watch';
      pkg = 'com.fitness.app';
    }
    out.add(SourceRecord(
      sourceId: sid,
      sourceKind: kind,
      importedAt: end.add(Duration(minutes: 5 + k)),
      deviceModel: model,
      appPackage: pkg,
      externalId: w.dupExt ? 'dup-ext-1' : ext(k),
      fieldsContributed: const ['distanceM'],
    ));
  }
  if (w.dupExt) {
    // Two sources carry the same external id (exact-duplicate rule).
    out[0] = SourceRecord(
      sourceId: out[0].sourceId,
      sourceKind: out[0].sourceKind,
      importedAt: out[0].importedAt,
      deviceModel: out[0].deviceModel,
      appPackage: out[0].appPackage,
      externalId: 'dup-ext-1',
      fieldsContributed: out[0].fieldsContributed,
    );
    if (out.length == 1) {
      out.add(SourceRecord(
        sourceId: 'garmin-connect',
        sourceKind: SourceKind.vendorCloud,
        importedAt: end.add(const Duration(minutes: 6)),
        externalId: 'dup-ext-1',
        fieldsContributed: const ['distanceM'],
      ));
    }
  }
  if (w.longSource && out.length == 1) {
    out.add(SourceRecord(
      sourceId: 'garmin-connect',
      sourceKind: SourceKind.vendorCloud,
      importedAt: end.add(const Duration(minutes: 6)),
      externalId: ext(1),
      fieldsContributed: const ['distanceM'],
    ));
  }
  return out;
}

// ---------------------------------------------------------------------------
// Decorations, schema 1, candidates

ActivitySession _decorate(ActivitySession s, String kind, SplitMix64 r) {
  final dRaw = s.summary.distanceM;
  const needsDistance = {
    'explicit',
    'explicitCandidate',
    'override',
    'overrideCandidate',
    'explicitOverride',
    'fullRing',
    'legacyEdits',
  };
  if (dRaw == null && needsDistance.contains(kind)) return s;
  final d = dRaw ?? 1000;
  ActivitySummary withDistance(double v) => ActivitySummary.fromFieldMap(
      {...s.summary.toFieldMap(), 'distanceM': v});
  ExplicitValue explicit(double v, {double? atDerived, double? candidate}) =>
      ExplicitValue(
        value: v,
        atDerived: atDerived ?? d,
        editDerived: d,
        seq: 1,
        sourceCandidate: candidate,
      );
  const v1 = CalcVersions.current;
  final bump = ((d * 0.0123) * 10).round() / 10 + 11;
  switch (kind) {
    case 'explicit':
      return s.copyWith(
        explicitValues: {'distanceM': explicit(d + bump)},
        userEditCount: 1,
        editHistory: [EditHistoryEntry(field: 'distanceM', value: d + bump, seq: 1)],
        userEdits: {'distanceM': d + bump},
      );
    case 'explicitCandidate':
      return s.copyWith(
        summary: withDistance(d + 7.5),
        explicitValues: {
          'distanceM': explicit(d + bump, atDerived: d + 7.5, candidate: d + 7.5),
        },
        userEditCount: 1,
        editHistory: [EditHistoryEntry(field: 'distanceM', value: d + bump, seq: 1)],
      );
    case 'override':
      return s.copyWith(summaryOverrides: {
        'distanceM': SummaryOverride(
            value: d + bump, atComputed: d, atVersions: v1, atRev: 3),
      });
    case 'overrideCandidate':
      return s.copyWith(summary: withDistance(d + 4.5), summaryOverrides: {
        'distanceM': SummaryOverride(
            value: d + bump,
            atComputed: d + 4.5,
            atVersions: v1,
            atRev: 3,
            recalcCandidate: d + 4.5),
      });
    case 'explicitOverride':
      return s.copyWith(
        explicitValues: {'distanceM': explicit(d + bump)},
        summaryOverrides: {
          'distanceM': SummaryOverride(
              value: d + 2 * bump, atComputed: d + bump, atVersions: v1, atRev: 5),
        },
        userEditCount: 2,
        editHistory: [
          EditHistoryEntry(field: 'distanceM', value: d + bump, seq: 1),
        ],
      );
    case 'fullRing':
      return s.copyWith(
        explicitValues: {'distanceM': explicit(d + 64)},
        userEditCount: 64,
        editHistory: [
          for (var k = 1; k <= 64; k++)
            EditHistoryEntry(field: 'distanceM', value: d + k, seq: k),
        ],
      );
    case 'legacyEdits':
      return s.copyWith(userEdits: {'distanceM': d + 1, 'title': 'tempo run'});
    case 'versions':
      return s.copyWith(
          versions: const CalcVersions(
        formulaVersion: 'formula-0',
        metricDefinitionVersion: 'metrics-0',
        thresholdPolicyVersion: 'thresholds-0',
      ));
    case 'terms':
      return s.copyWith(sourceTermsSnapshot: 'terms-2026-10:${r.range(100, 999)}');
  }
  return s;
}

Map<String, dynamic> _toSchema1(ActivitySession s) {
  final m = Map<String, dynamic>.from(s.toJson());
  for (final k in const [
    'formulaVersion',
    'metricDefinitionVersion',
    'thresholdPolicyVersion',
    'sourceTermsSnapshot',
    'userEditCount',
    'editHistory',
    'explicitValues',
    'summaryOverrides',
  ]) {
    m.remove(k);
  }
  m['schema'] = 1;
  return m;
}

List<ActivitySession> _candidates(List<_Spec> specs, List<ActivitySession> sessions) {
  final out = <ActivitySession>[];
  for (final w in specs) {
    final v = sessions[w.i];
    out.add(v.copyWith(provenance: [v.provenance.first]));
    for (var k = 1; k < w.group && k < v.provenance.length; k++) {
      final p = v.provenance[k];
      final shift = w.echo && k == 1 ? 1 + (w.i % 28) : (w.i % 13) * 2;
      final start = v.startUtc.add(Duration(seconds: shift));
      final end = v.endUtc.add(Duration(seconds: shift));
      final d = v.summary.distanceM;
      out.add(ActivitySession(
        id: activityIdFor(
            sourceId: p.sourceId, externalId: p.externalId, startUtc: start),
        sport: v.sport,
        startUtc: start,
        endUtc: end,
        utcOffsetMinutes: v.utcOffsetMinutes,
        movingTimeS: v.movingTimeS,
        summary: ActivitySummary(
          distanceM: d == null ? null : (d * 1.01 * 10).round() / 10,
        ),
        provenance: [p],
      ));
    }
  }
  return out;
}

List<ActivitySession> _splitPair(List<_Spec> specs, List<ActivitySession> sessions) {
  final w = specs.firstWhere((w) =>
      w.sport == SportType.running && !w.special && !w.gps && !w.schema1);
  final v = sessions[w.i];
  final half = v.endUtc.difference(v.startUtc).inSeconds ~/ 2;
  final firstEnd = v.startUtc.add(Duration(seconds: half));
  final secondStart = firstEnd.add(const Duration(minutes: 2));
  ActivitySession part(String tag, DateTime a, DateTime b) => ActivitySession(
        id: activityIdFor(
            sourceId: 'split-src', externalId: 'split-$tag', startUtc: a),
        sport: SportType.running,
        startUtc: a,
        endUtc: b,
        summary: ActivitySummary(distanceM: (v.summary.distanceM ?? 2000) / 2),
        provenance: [
          SourceRecord(
            sourceId: 'split-src',
            sourceKind: SourceKind.vendorCloud,
            importedAt: b.add(const Duration(minutes: 5)),
            externalId: 'split-$tag',
          ),
        ],
      );
  return [
    part('a', v.startUtc, firstEnd),
    part('b', secondStart, secondStart.add(Duration(seconds: half))),
  ];
}
