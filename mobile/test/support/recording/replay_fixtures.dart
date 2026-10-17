// S04 replay fixtures and the replay driver (story S04-02, requirement
// S04-R-035). Tracks are generated deterministically from a fixed LCG; no
// Random, no DateTime.now. The driver feeds the SAME RecorderPipeline class
// that the live controller uses.
import 'dart:convert';
import 'dart:math' as math;

import 'package:fitness_app/features/recording/pipeline/geo.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/pipeline/recorded_track.dart';
import 'package:fitness_app/features/recording/pipeline/recorder_pipeline.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/pipeline/smoothing.dart';

/// Neutral, fixed origin (not a real private place).
const double kFixtureLat0 = 10.0;
const double kFixtureLon0 = 20.0;

/// First sample time of every fixture (so offset 0 is "Start").
const int kFixtureT0Ms = 1000;

/// Fixed linear congruential generator (a=1664525, c=1013904223, m=2^32).
class Lcg {
  Lcg(int seed) : _s = seed & 0xFFFFFFFF;
  int _s;
  int nextInt() {
    _s = (1664525 * _s + 1013904223) & 0xFFFFFFFF;
    return _s;
  }

  /// Uniform in [0, 1).
  double unit() => nextInt() / 4294967296.0;

  /// Uniform in [-1, 1).
  double sym() => unit() * 2 - 1;

  /// Uniform in [lo, hi).
  double range(double lo, double hi) => lo + unit() * (hi - lo);
}

class FixRow {
  const FixRow({
    required this.tMs,
    required this.lat,
    required this.lon,
    required this.acc,
    this.alt,
    this.speed,
    this.inject = '',
  });
  final int tMs;
  final double lat;
  final double lon;
  final double acc;
  final double? alt;
  final double? speed;

  /// '', 'drop', 'dup', 'back' or 'kill'.
  final String inject;

  FixRow copyWith({
    int? tMs,
    double? lat,
    double? lon,
    double? acc,
    String? inject,
  }) =>
      FixRow(
        tMs: tMs ?? this.tMs,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        acc: acc ?? this.acc,
        alt: alt,
        speed: speed,
        inject: inject ?? this.inject,
      );
}

class TrackFixture {
  TrackFixture(
    this.name,
    this.rows, {
    this.sport = 'walk',
    this.truthLengthM,
    this.truthMovingS,
    this.truthAscentM,
    this.truthDescentM,
    this.autoPause = true,
    this.injectedIndexes = const <int>{},
    this.keptBoundary = const <int>{},
    this.rejectedBoundary = const <int>{},
    this.notes = const <String, Object>{},
  });
  final String name;
  final List<FixRow> rows;
  final String sport;
  final double? truthLengthM;
  final double? truthMovingS;
  final double? truthAscentM;
  final double? truthDescentM;
  final bool autoPause;

  /// Indexes (into [rows]) of fixes that were injected as bad and must never
  /// be kept.
  final Set<int> injectedIndexes;

  /// Indexes of fixes exactly on a gate boundary that must be KEPT (accuracy
  /// 30.0 m, implied speed 29.5 m/s).
  final Set<int> keptBoundary;

  /// Indexes of fixes just beyond a gate boundary that must be REJECTED
  /// (accuracy 30.1 m, implied speed 30.5 m/s).
  final Set<int> rejectedBoundary;
  final Map<String, Object> notes;

  /// CSV in the format of the plan (section 2.1): header comment block with
  /// the truth keys, then `t_ms,lat,lon,acc_m,alt_m,speed_mps,inject`.
  String toCsv() {
    final b = StringBuffer();
    b.writeln('# fixture=$name');
    b.writeln('# sport=$sport');
    if (truthLengthM != null) b.writeln('# truth_length_m=$truthLengthM');
    if (truthMovingS != null) b.writeln('# truth_moving_s=$truthMovingS');
    if (truthAscentM != null) b.writeln('# truth_ascent_m=$truthAscentM');
    if (truthDescentM != null) b.writeln('# truth_descent_m=$truthDescentM');
    b.writeln('t_ms,lat,lon,acc_m,alt_m,speed_mps,inject');
    for (final r in rows) {
      b.writeln([
        r.tMs,
        r.lat.toStringAsFixed(7),
        r.lon.toStringAsFixed(7),
        r.acc.toStringAsFixed(2),
        r.alt == null ? '' : r.alt!.toStringAsFixed(2),
        r.speed == null ? '' : r.speed!.toStringAsFixed(2),
        r.inject,
      ].join(','));
    }
    return b.toString();
  }
}

/// A local-plane position builder. x is metres east, y is metres north of the
/// origin; conversion uses the same sphere as the calculators.
({double lat, double lon}) fixturePoint(double xEastM, double yNorthM) {
  final lat = kFixtureLat0 + yNorthM / kMetresPerDegree;
  final lon = kFixtureLon0 +
      xEastM / (kMetresPerDegree * cosLatDeg(kFixtureLat0));
  return (lat: lat, lon: lon);
}

/// Length of the polyline through [pts] (local metres) with the SAME haversine
/// as the calculators.
double polylineLengthM(List<({double x, double y})> pts) {
  var d = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final a = fixturePoint(pts[i - 1].x, pts[i - 1].y);
    final b = fixturePoint(pts[i].x, pts[i].y);
    d += haversineM(a.lat, a.lon, b.lat, b.lon);
  }
  return d;
}

FixRow _row(int tS, double x, double y,
    {double acc = 8,
    double? alt,
    double? speed,
    double nx = 0,
    double ny = 0,
    String inject = ''}) {
  final p = fixturePoint(x + nx, y + ny);
  return FixRow(
      tMs: kFixtureT0Ms + tS * 1000,
      lat: p.lat,
      lon: p.lon,
      acc: acc,
      alt: alt,
      speed: speed,
      inject: inject);
}

// ---------------------------------------------------------------- fixtures

/// 1000 m straight line, walk 1.4 m/s, 1 Hz, accuracy 5 to 12 m, LCG noise
/// up to [noiseM] m on each axis.
TrackFixture fNoiseLine({double noiseM = 8.0, int seed = 11}) {
  final rnd = Lcg(seed);
  final rows = <FixRow>[];
  const n = 715;
  for (var t = 0; t < n; t++) {
    final x = math.min(1.4 * t, 1000.0);
    rows.add(_row(t, x, 0,
        acc: rnd.range(5, 12),
        speed: 1.4,
        nx: rnd.sym() * noiseM,
        ny: rnd.sym() * noiseM));
  }
  final last = math.min(1.4 * (n - 1), 1000.0);
  return TrackFixture('F-noise-line', rows,
      truthLengthM: polylineLengthM([(x: 0, y: 0), (x: last, y: 0)]),
      truthMovingS: (n - 1).toDouble());
}

/// Noise-free straight constant-speed track; the basis of F-walk, F-run and
/// F-ride-30kmh.
TrackFixture _constantSpeed(String name, double mps, int seconds,
    {String sport = 'walk', double? alt}) {
  final rows = <FixRow>[];
  for (var t = 0; t <= seconds; t++) {
    rows.add(_row(t, mps * t, 0, acc: 6, speed: mps, alt: alt));
  }
  return TrackFixture(name, rows,
      sport: sport,
      truthLengthM: polylineLengthM([(x: 0, y: 0), (x: mps * seconds, y: 0)]),
      truthMovingS: seconds.toDouble());
}

/// Walk at 1.4 m/s for 20 min, after a slow start of 20 s at 0.9 m/s (so the
/// 10 m minimum-distance rule of the pace is visible in the first seconds).
TrackFixture fWalk() {
  final rows = <FixRow>[];
  var x = 0.0;
  for (var t = 0; t <= 1200; t++) {
    rows.add(_row(t, x, 0, acc: 6, speed: t < 20 ? 0.9 : 1.4));
    x += t < 20 ? 0.9 : 1.4;
  }
  return TrackFixture('F-walk', rows,
      truthLengthM:
          polylineLengthM([(x: 0, y: 0), (x: x - (1200 < 20 ? 0.9 : 1.4), y: 0)]),
      truthMovingS: 1200);
}
TrackFixture fRide30() =>
    _constantSpeed('F-ride-30kmh', 8.33, 1200, sport: 'ride');

/// Polyline with a 90-degree corner at (300, 0) and two shallow bends.
/// The apex is the raw corner point.
({TrackFixture fixture, int apexIndex, double apexLat, double apexLon})
    fTurns({int seed = 23}) {
  final rnd = Lcg(seed);
  final poly = <({double x, double y})>[
    (x: 0, y: 0),
    (x: 300, y: 0),
    (x: 300, y: 300),
    (x: 360, y: 340),
    (x: 440, y: 350),
  ];
  final rows = <FixRow>[];
  var t = 0;
  var apexIndex = -1;
  var carried = 0.0;
  for (var s = 1; s < poly.length; s++) {
    final a = poly[s - 1];
    final b = poly[s];
    final len = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    var d = carried;
    while (d < len) {
      final f = d / len;
      rows.add(_row(t, a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f,
          acc: 6, speed: 1.4, nx: rnd.sym() * 2, ny: rnd.sym() * 2));
      t++;
      d += 1.4;
    }
    carried = d - len;
    if (s == 1) apexIndex = rows.length; // first fix after the corner point
  }
  final apex = fixturePoint(300, 0);
  return (
    fixture: TrackFixture('F-turns', rows,
        truthLengthM: polylineLengthM(poly), truthMovingS: t.toDouble()),
    apexIndex: apexIndex,
    apexLat: apex.lat,
    apexLon: apex.lon,
  );
}

/// Expected structure of F-stop-go (see [fStopGo]).
class StopGoPlan {
  const StopGoPlan({
    required this.stop7StartS,
    required this.stop20StartS,
    required this.stop60StartS,
    required this.jitterStartS,
    required this.jitterEndS,
    required this.totalS,
  });
  final int stop7StartS;
  final int stop20StartS;
  final int stop60StartS;
  final int jitterStartS;
  final int jitterEndS;
  final int totalS;
}

({TrackFixture fixture, StopGoPlan plan}) fStopGo() {
  final rows = <FixRow>[];
  var t = 0;
  var x = 0.0;
  void walk(int secs) {
    for (var i = 0; i < secs; i++) {
      x += 1.4;
      rows.add(_row(t, x, 0, acc: 5, speed: 1.4));
      t++;
    }
  }

  void stop(int secs) {
    for (var i = 0; i < secs; i++) {
      rows.add(_row(t, x, 0, acc: 5, speed: 0.0));
      t++;
    }
  }

  void slow(int secs) {
    for (var i = 0; i < secs; i++) {
      x += 0.9;
      rows.add(_row(t, x, 0, acc: 5, speed: 0.9));
      t++;
    }
  }

  void jitter(int secs) {
    final rnd = Lcg(5);
    for (var i = 0; i < secs; i++) {
      final v = 0.6 + rnd.unit() * 0.3; // 0.6 .. 0.9
      x += v;
      rows.add(_row(t, x, 0, acc: 5, speed: v));
      t++;
    }
  }

  walk(30);
  final s7 = t;
  stop(7);
  walk(30);
  final s20 = t;
  stop(20);
  walk(30);
  final s60 = t;
  stop(60);
  slow(6);
  walk(30);
  final j0 = t;
  jitter(90);
  final j1 = t;
  walk(30);
  return (
    fixture: TrackFixture('F-stop-go', rows,
        truthMovingS: t.toDouble(), notes: {'stops': '7,20,60'}),
    plan: StopGoPlan(
        stop7StartS: s7,
        stop20StartS: s20,
        stop60StartS: s60,
        jitterStartS: j0,
        jitterEndS: j1,
        totalS: t),
  );
}

/// Ride, accuracy 8 m: [beforeS] seconds of fixes, 60 s with no delivery, then
/// fixes again 700 m on.
({TrackFixture fixture, int lastBeforeS, int firstAfterS, double gapJumpM})
    fTunnel({int beforeS = 60, int afterS = 60}) {
  final rows = <FixRow>[];
  const v = 8.33;
  var x = 0.0;
  var t = 0;
  for (var i = 0; i < beforeS; i++) {
    rows.add(_row(t, x, 0, acc: 8, speed: v));
    x += v;
    t++;
  }
  final lastBefore = t - 1;
  final lastX = x - v;
  t += 60; // 60 s with no delivery
  x = lastX + 700;
  final firstAfter = t;
  for (var i = 0; i < afterS; i++) {
    rows.add(_row(t, x, 0, acc: 8, speed: v));
    x += v;
    t++;
  }
  return (
    fixture: TrackFixture('F-tunnel', rows, sport: 'ride'),
    lastBeforeS: lastBefore,
    firstAfterS: firstAfter,
    gapJumpM: 700,
  );
}

/// Walk with accuracy spikes 45 to 120 m on 40 non-consecutive fixes.
TrackFixture fUrbanCanyon() {
  final rnd = Lcg(77);
  final rows = <FixRow>[];
  final injected = <int>{};
  final keptB = <int>{};
  final rejB = <int>{};
  for (var t = 0; t < 700; t++) {
    final spike = t >= 10 && t % 16 == 5 && injected.length < 40;
    if (spike) {
      injected.add(rows.length);
      rows.add(_row(t, 1.4 * t, 0,
          acc: rnd.range(45, 120),
          speed: 1.4,
          nx: rnd.sym() * 30,
          ny: rnd.sym() * 30));
    } else if (t == 100 || t == 200 || t == 300) {
      keptB.add(rows.length);
      rows.add(_row(t, 1.4 * t, 0, acc: 30.0, speed: 1.4));
    } else if (t == 150 || t == 250 || t == 350) {
      rejB.add(rows.length);
      rows.add(_row(t, 1.4 * t, 0, acc: 30.1, speed: 1.4));
    } else {
      rows.add(_row(t, 1.4 * t, 0, acc: rnd.range(5, 10), speed: 1.4));
    }
  }
  return TrackFixture('F-urban-canyon', rows,
      injectedIndexes: injected, keptBoundary: keptB, rejectedBoundary: rejB);
}

/// Walk with one fix 2 km away (implied about 2000 m/s) and one 50 m accuracy
/// fix.
TrackFixture fJump() {
  final rows = <FixRow>[];
  final injected = <int>{};
  final keptB = <int>{};
  final rejB = <int>{};
  // After t=60 the walker is displaced +29.5 m in one second (implied
  // 29.5 m/s, kept) and walks on from there.
  const shift = 28.1; // 29.5 - 1.4
  for (var t = 0; t < 240; t++) {
    final base = 1.4 * t + (t >= 60 ? shift : 0);
    if (t == 60) {
      keptB.add(rows.length);
      rows.add(_row(t, base, 0, acc: 6, speed: 1.4));
    } else if (t == 100) {
      injected.add(rows.length);
      rows.add(_row(t, base + 2000, 0, acc: 10, speed: 1.4));
    } else if (t == 150) {
      injected.add(rows.length);
      rows.add(_row(t, base, 0, acc: 50, speed: 1.4));
    } else if (t == 180) {
      // 30.5 m beyond the previous kept fix after 1 s: implied 30.5 m/s.
      rejB.add(rows.length);
      rows.add(_row(t, 1.4 * (t - 1) + shift + 30.5, 0, acc: 6, speed: 1.4));
    } else {
      rows.add(_row(t, base, 0, acc: 6, speed: 1.4));
    }
  }
  return TrackFixture('F-jump', rows,
      injectedIndexes: injected, keptBoundary: keptB, rejectedBoundary: rejB);
}

/// Staircase climb of 100 m (20 steps of 5 m), altitude noise 1 m.
/// [reversed] gives the downhill copy. [spike] adds one +100 m sample.
TrackFixture fClimb({bool reversed = false, bool spike = false, int seed = 3}) {
  final rnd = Lcg(seed);
  final rows = <FixRow>[];
  var t = 0;
  var level = 0.0;
  for (var step = 0; step < 20; step++) {
    for (var i = 0; i < 30; i++) {
      final a = 500 + level + rnd.sym() * 1.0;
      rows.add(_row(t, 1.4 * t, 0, acc: 6, speed: 1.4, alt: a));
      t++;
    }
    for (var i = 1; i <= 5; i++) {
      final a = 500 + level + i + rnd.sym() * 1.0;
      rows.add(_row(t, 1.4 * t, 0, acc: 6, speed: 1.4, alt: a));
      t++;
    }
    level += 5;
  }
  for (var i = 0; i < 30; i++) {
    final a = 500 + level + rnd.sym() * 1.0;
    rows.add(_row(t, 1.4 * t, 0, acc: 6, speed: 1.4, alt: a));
    t++;
  }
  var out = rows;
  if (reversed) {
    // Same positions and times, altitude sequence reversed.
    final alts = rows.map((r) => r.alt!).toList().reversed.toList();
    out = [
      for (var i = 0; i < rows.length; i++)
        FixRow(
            tMs: rows[i].tMs,
            lat: rows[i].lat,
            lon: rows[i].lon,
            acc: rows[i].acc,
            alt: alts[i],
            speed: rows[i].speed),
    ];
  }
  if (spike) {
    final k = out.length ~/ 2;
    final r = out[k];
    out = [...out];
    out[k] = FixRow(
        tMs: r.tMs,
        lat: r.lat,
        lon: r.lon,
        acc: r.acc,
        alt: r.alt! + 100,
        speed: r.speed);
  }
  return TrackFixture(
      spike
          ? 'F-climb-spike'
          : (reversed ? 'F-climb-reversed' : 'F-climb'),
      out,
      truthAscentM: reversed ? 0 : 100,
      truthDescentM: reversed ? 100 : 0);
}

/// 10 min flat walk, altitude noise plus or minus 4 m.
TrackFixture fFlatAltNoise() {
  final rnd = Lcg(9);
  final rows = <FixRow>[];
  for (var t = 0; t < 600; t++) {
    rows.add(_row(t, 1.4 * t, 0,
        acc: 6, speed: 1.4, alt: 100 + rnd.sym() * 4.0));
  }
  return TrackFixture('F-flat-alt-noise', rows,
      truthAscentM: 0, truthDescentM: 0);
}

/// Walk with the altitude column empty.
TrackFixture fNoAlt() {
  final rows = <FixRow>[
    for (var t = 0; t < 300; t++) _row(t, 1.4 * t, 0, acc: 6, speed: 1.4),
  ];
  return TrackFixture('F-no-alt', rows);
}

/// 600 s walk at 1 Hz with altitude.
TrackFixture fKillMidRun() {
  final rows = <FixRow>[
    for (var t = 0; t < 600; t++)
      _row(t, 1.4 * t, 0, acc: 6, speed: 1.4, alt: 200 + 0.01 * t),
  ];
  return TrackFixture('F-kill-mid-run', rows);
}

/// 10 min standing still with drift of 3 to 8 m and provider speed 0 to 0.4.
/// The first [movingS] seconds walk.
({TrackFixture fixture, int stillStartS}) fStill({int movingS = 60}) {
  final rnd = Lcg(31);
  final rows = <FixRow>[];
  for (var t = 0; t < movingS; t++) {
    rows.add(_row(t, 1.4 * t, 0, acc: 6, speed: 1.4));
  }
  final x0 = 1.4 * movingS;
  for (var t = movingS; t < 600; t++) {
    final mag = rnd.range(3, 8);
    final ang = rnd.unit() * 2 * math.pi;
    rows.add(_row(t, x0, 0,
        acc: rnd.range(5, 15),
        speed: rnd.range(0.0, 0.4),
        nx: mag * math.cos(ang),
        ny: mag * math.sin(ang)));
  }
  return (fixture: TrackFixture('F-still', rows), stillStartS: movingS);
}

/// 5 min walk with a backwards fix (3 s earlier than its predecessor), an
/// equal-time fix with a different position, then a forward device clock jump
/// of 1 h.
({
  TrackFixture fixture,
  int backwardsIndex,
  int equalIndex,
  int forwardIndex,
}) fClockJump() {
  final rows = <FixRow>[];
  var back = -1, eq = -1, fwd = -1;
  for (var t = 0; t < 300; t++) {
    var tMs = kFixtureT0Ms + t * 1000;
    if (t >= 200) tMs += 3600 * 1000; // device clock jumped forward 1 h
    final r = _row(t, 1.4 * t, 0, acc: 6, speed: 1.4);
    rows.add(FixRow(
        tMs: tMs,
        lat: r.lat,
        lon: r.lon,
        acc: r.acc,
        speed: r.speed));
    if (t == 100) {
      // Backwards: 3 s before the predecessor (t=100 -> time of t=97).
      back = rows.length;
      final p = fixturePoint(1.4 * t + 1.0, 3);
      rows.add(FixRow(
          tMs: tMs - 3000, lat: p.lat, lon: p.lon, acc: 6, speed: 1.4,
          inject: 'back'));
    }
    if (t == 150) {
      // Equal timestamp, different position.
      eq = rows.length;
      final p = fixturePoint(1.4 * t + 2.0, 2);
      rows.add(FixRow(
          tMs: tMs, lat: p.lat, lon: p.lon, acc: 6, speed: 1.4,
          inject: 'dup'));
    }
    if (t == 200) fwd = rows.length - 1;
  }
  return (
    fixture: TrackFixture('F-clock-jump', rows),
    backwardsIndex: back,
    equalIndex: eq,
    forwardIndex: fwd,
  );
}

/// The same fix delivered five times in a row, then normal fixes.
TrackFixture fDupFix() {
  final rows = <FixRow>[];
  for (var t = 0; t < 10; t++) {
    rows.add(_row(t, 1.4 * t, 0, acc: 6, speed: 1.4));
  }
  final dup = _row(10, 14.0, 0, acc: 6, speed: 1.4);
  for (var i = 0; i < 5; i++) {
    rows.add(i == 0 ? dup : dup.copyWith(inject: 'dup'));
  }
  for (var t = 11; t < 30; t++) {
    rows.add(_row(t, 1.4 * t, 0, acc: 6, speed: 1.4));
  }
  return TrackFixture('F-dup-fix', rows);
}

/// First fix looks fine (accuracy 10 m) but is 5 km from the true start; 120 s
/// of true fixes follow.
TrackFixture fBadAnchor() {
  final rows = <FixRow>[
    _row(0, 5000, 0, acc: 10, speed: 1.4),
    for (var t = 1; t <= 120; t++) _row(t, 1.4 * t, 0, acc: 8, speed: 1.4),
  ];
  return TrackFixture('F-bad-anchor', rows);
}

/// 60 s walk around the sentinel point 12.3456789, -98.7654321.
TrackFixture fSentinel() {
  final rows = <FixRow>[];
  for (var t = 0; t < 60; t++) {
    rows.add(FixRow(
        tMs: kFixtureT0Ms + t * 1000,
        lat: 12.3456789 + t * 1e-6,
        lon: -98.7654321 + t * 1e-6,
        acc: 6,
        speed: 1.4));
  }
  return TrackFixture('F-sentinel', rows);
}

/// 3600 s walk at 1 Hz.
TrackFixture fLong3600() {
  final rows = <FixRow>[
    for (var t = 0; t < 3600; t++) _row(t, 1.4 * t, 0, acc: 6, speed: 1.4),
  ];
  return TrackFixture('F-long-3600', rows);
}

/// 100 000 samples at 1 Hz with altitude and speed.
TrackFixture fHuge100k() {
  final rows = <FixRow>[];
  for (var t = 0; t < 100000; t++) {
    // A slow out-and-back loop keeps coordinates in range.
    final phase = (t % 20000) / 20000.0;
    final x = phase < 0.5 ? 1.4 * t % 14000 : 14000 - (1.4 * t % 14000);
    rows.add(_row(t, x, 0, acc: 6, speed: 1.4, alt: 100 + (t % 100) * 0.05));
  }
  return TrackFixture('F-100k', rows);
}

/// Real-shaped walk, 3 km, turns and slopes, spatially correlated AR(1) noise.
TrackFixture fWalkReal({double sigmaM = 2.5}) => _real(
    'F-walk-real',
    3000,
    1.4,
    seed: 41,
    sigma: sigmaM,
    accLo: 5,
    accHi: 15,
    stops: false);

/// Real-shaped ride, 10 km, with a descent at 12 m/s and stops.
TrackFixture fRideReal({double sigmaM = 2.5}) => _real(
    'F-ride-real',
    10000,
    8.0,
    seed: 43,
    sigma: sigmaM,
    accLo: 5,
    accHi: 15,
    stops: true);

TrackFixture _real(String name, double lengthM, double v,
    {required int seed,
    required double sigma,
    required double accLo,
    required double accHi,
    required bool stops}) {
  final rnd = Lcg(seed);
  // Route: a wandering polyline built from legs with heading changes.
  final pts = <({double x, double y})>[(x: 0, y: 0)];
  var heading = 0.0;
  var total = 0.0;
  while (total < lengthM) {
    final leg = math.min(rnd.range(150, 400), lengthM - total);
    heading += rnd.sym() * 1.1; // up to ~63 degrees per bend
    final p = pts.last;
    pts.add((
      x: p.x + leg * math.cos(heading),
      y: p.y + leg * math.sin(heading)
    ));
    total += leg;
  }
  // Walk the polyline with a speed profile, 1 Hz.
  final rows = <FixRow>[];
  var legIdx = 0;
  var legPos = 0.0;
  var t = 0;
  var ex = 0.0, ey = 0.0;
  const rho = 0.9;
  final innov = sigma * math.sqrt(1 - rho * rho);
  var stopLeft = 0;
  var travelled = 0.0;
  var nextStopAt = 1500.0;
  while (legIdx < pts.length - 1) {
    final a = pts[legIdx];
    final b = pts[legIdx + 1];
    final len = math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
    var speed = v * (0.85 + 0.3 * math.sin(t / 40.0));
    if (name == 'F-ride-real' && travelled > 6000 && travelled < 6600) {
      speed = 12.0; // descent
    }
    if (stops && stopLeft == 0 && travelled >= nextStopAt) {
      stopLeft = 20;
      nextStopAt += 2000;
    }
    final moving = stopLeft == 0;
    if (moving) {
      legPos += speed;
      travelled += speed;
    } else {
      stopLeft--;
      speed = 0;
    }
    if (legPos >= len) {
      legPos -= len;
      legIdx++;
      if (legIdx >= pts.length - 1) break;
    }
    final c = pts[legIdx];
    final d = pts[legIdx + 1];
    final l2 = math.sqrt(math.pow(d.x - c.x, 2) + math.pow(d.y - c.y, 2));
    final f = legPos / l2;
    ex = rho * ex + innov * rnd.sym() * 1.7;
    ey = rho * ey + innov * rnd.sym() * 1.7;
    rows.add(_row(t, c.x + (d.x - c.x) * f, c.y + (d.y - c.y) * f,
        acc: rnd.range(accLo, accHi),
        speed: speed,
        alt: 300 + 30 * math.sin(travelled / 800.0),
        nx: ex,
        ny: ey));
    t++;
  }
  // Truth: the noise-free positions that were sampled (polyline through them).
  final clean = <({double x, double y})>[];
  // Rebuild noise-free points deterministically by re-walking; simpler: take
  // the pts-based polyline up to the last sampled point.
  final lastRow = rows.last;
  clean.addAll(pts);
  // The walk ends inside the last leg; truth is the full-route length minus
  // the unwalked remainder, computed from the final sampled position.
  var remainder = 0.0;
  if (legIdx < pts.length - 1) {
    final c = pts[legIdx];
    final d = pts[legIdx + 1];
    remainder = math.sqrt(math.pow(d.x - c.x, 2) + math.pow(d.y - c.y, 2)) -
        legPos;
  }
  var routeLen = polylineLengthM(pts);
  // Rows were noise-free-sampled along the route, so the truth is the walked
  // route length. Pauses add repeated points (0 m).
  final truth = routeLen - remainder;
  // Silence unused warnings.
  assert(lastRow.tMs > 0 && clean.isNotEmpty);
  return TrackFixture(name, rows,
      sport: name == 'F-ride-real' ? 'ride' : 'walk', truthLengthM: truth);
}

/// All 21 fixtures of plan section 2.2, in a fixed order.
Map<String, TrackFixture Function()> allFixtureBuilders() => {
      'F-noise-line': () => fNoiseLine(),
      'F-turns': () => fTurns().fixture,
      'F-stop-go': () => fStopGo().fixture,
      'F-tunnel': () => fTunnel().fixture,
      'F-urban-canyon': () => fUrbanCanyon(),
      'F-jump': () => fJump(),
      'F-climb': () => fClimb(),
      'F-ride-30kmh': () => fRide30(),
      'F-walk': () => fWalk(),
      'F-kill-mid-run': () => fKillMidRun(),
      'F-still': () => fStill().fixture,
      'F-clock-jump': () => fClockJump().fixture,
      'F-dup-fix': () => fDupFix(),
      'F-flat-alt-noise': () => fFlatAltNoise(),
      'F-no-alt': () => fNoAlt(),
      'F-walk-real': () => fWalkReal(),
      'F-ride-real': () => fRideReal(),
      'F-long-3600': () => fLong3600(),
      'F-100k': () => fHuge100k(),
      'F-bad-anchor': () => fBadAnchor(),
      'F-sentinel': () => fSentinel(),
    };

// ------------------------------------------------------------------ replay

class ManualPause {
  const ManualPause(this.pauseAtMs, this.resumeAtMs);
  final int pauseAtMs;
  final int resumeAtMs;
}

class ReplayResult {
  ReplayResult(this.events, this.pipeline, this.elapsedMs, this.manualPauses,
      {this.timeline = const [], this.pace = const []});
  final List<PipelineEvent> events;

  /// State timeline: (entry offset ms, name) with names acquiring, recording,
  /// poorAccuracy, pausedAuto and pausedManual.
  final List<(int, String)> timeline;

  /// Pace samples: (offset ms, current pace s/km or null, speed m/s or null)
  /// at the first 40 s of the run and then every 300 s.
  final List<(int, double?, double?)> pace;
  final RecorderPipeline pipeline;
  final int elapsedMs;
  final List<TrackInterval> manualPauses;

  LiveMetrics get metrics => pipeline.metrics;

  List<FixKept> get kept => events.whereType<FixKept>().toList();
  List<FixRejected> get rejected => events.whereType<FixRejected>().toList();
  List<GapStarted> get gapStarts => events.whereType<GapStarted>().toList();
  List<GapEnded> get gapEnds => events.whereType<GapEnded>().toList();
  List<AutoPaused> get autoPauses => events.whereType<AutoPaused>().toList();
  List<AutoResumed> get autoResumes =>
      events.whereType<AutoResumed>().toList();

  RecordedTrack get track => RecordedTrack.fromEvents(
      events: events, elapsedMs: elapsedMs, manualPauses: manualPauses);

  /// Offsets (ms) of the kept samples, in order.
  List<int> get keptOffsets => kept.map((e) => e.sample.offsetMs).toList();
}

/// Replays [fx] through the real [RecorderPipeline]. A 1 s tick drives
/// `advanceTo` between fixes exactly like the controller's timer does.
/// Fix times become offsets via [kFixtureT0Ms] (offset 0 is Start).
ReplayResult replay(
  TrackFixture fx, {
  PipelineConfig config = const PipelineConfig(),
  bool? autoPause,
  SmoothingStrategy smoothing = const WeightedMovingAverageSmoothing(),
  List<ManualPause> manualPauses = const [],
  int? endAtMs,
  bool finish = true,
}) {
  final p = RecorderPipeline(
      config: config,
      autoPauseEnabled: autoPause ?? fx.autoPause,
      smoothing: smoothing);
  final events = <PipelineEvent>[];
  final pauses = [...manualPauses]
    ..sort((a, b) => a.pauseAtMs.compareTo(b.pauseAtMs));
  var pi = 0;
  var resumeAt = -1;
  var tick = 0;
  var last = 0;
  final timeline = <(int, String)>[];
  final pace = <(int, double?, double?)>[];
  String? lastName;

  void observe(int at) {
    final m = p.metrics;
    final name = m.manualPaused
        ? 'pausedManual'
        : m.autoPaused
            ? 'pausedAuto'
            : m.acquiring
                ? 'acquiring'
                : m.poorAccuracy
                    ? 'poorAccuracy'
                    : 'recording';
    if (name != lastName) {
      timeline.add((at, name));
      lastName = name;
    }
    if (at % 1000 == 0 && (at <= 40000 || at % 300000 == 0)) {
      // The tick at `at` runs before the fix of the same instant; the last
      // observation of an instant wins.
      if (pace.isNotEmpty && pace.last.$1 == at) pace.removeLast();
      pace.add((at, m.currentPaceSecPerKm, m.currentSpeedMps));
    }
  }

  void controlsUpTo(int t) {
    while (true) {
      if (resumeAt >= 0 && resumeAt <= t) {
        events.addAll(p.resumeManual(resumeAt));
        resumeAt = -1;
        continue;
      }
      if (resumeAt < 0 && pi < pauses.length && pauses[pi].pauseAtMs <= t) {
        events.addAll(p.pauseManual(pauses[pi].pauseAtMs));
        resumeAt = pauses[pi].resumeAtMs;
        pi++;
        continue;
      }
      break;
    }
  }

  void ticksUpTo(int t) {
    while (tick + kRecorderTickMsForReplay <= t) {
      tick += kRecorderTickMsForReplay;
      controlsUpTo(tick);
      events.addAll(p.advanceTo(tick));
      observe(tick);
    }
  }

  for (final r in fx.rows) {
    if (r.inject == 'drop') continue;
    final off = r.tMs - kFixtureT0Ms;
    if (endAtMs != null && off > endAtMs) break;
    ticksUpTo(off);
    controlsUpTo(off);
    final s = PipelineSample(
        offsetMs: off,
        lat: r.lat,
        lon: r.lon,
        accuracyM: r.acc,
        altitudeM: r.alt,
        speedMps: r.speed);
    events.addAll(p.addSample(s));
    observe(off);
    if (off > last) last = off;
  }
  final end = endAtMs ?? last;
  ticksUpTo(end);
  controlsUpTo(end);
  // Ensure an open manual pause is closed at the end for the track record.
  if (finish) p.finish(end);
  final mp = [
    for (final m in manualPauses)
      TrackInterval(m.pauseAtMs, math.min(m.resumeAtMs, end)),
  ];
  return ReplayResult(events, p, end, mp, timeline: timeline, pace: pace);
}

/// The controller's tick period (same constant as the live code uses).
const int kRecorderTickMsForReplay = 1000;

/// Serialises a replay result as stable JSON (sorted keys, fixed decimals) so
/// two runs are byte-equal.
String serialiseReplay(ReplayResult r) {
  String d(double? v, [int n = 3]) => v == null ? 'null' : v.toStringAsFixed(n);
  final m = r.metrics;
  final c = m.counters;
  final session = const SessionCalculator().compute(r.track);
  final map = <String, Object?>{
    'ascent': d(session.ascentM, 2),
    'autoPauseCount': r.autoPauses.length,
    'autoPauseDetected': r.autoPauses.map((e) => e.detectedAtMs).toList(),
    'autoPauseOffsets': r.autoPauses.map((e) => e.offsetMs).toList(),
    'autoResumeDetected': r.autoResumes.map((e) => e.detectedAtMs).toList(),
    'autoResumeOffsets': r.autoResumes.map((e) => e.offsetMs).toList(),
    'counters': {
      'accuracy': c.accuracy,
      'invalid': c.invalid,
      'nonMonotonic': c.nonMonotonic,
      'speed': c.speed,
    },
    'descent': d(session.descentM, 2),
    'distanceFinal': d(session.distanceM, 2),
    'distanceLive': d(m.distanceM, 2),
    'formulaVersion': '$kCalculatorVersionPrefix.${session.smoothingId}',
    'gaps': [
      for (var i = 0; i < r.gapStarts.length; i++)
        [
          r.gapStarts[i].offsetMs,
          i < r.gapEnds.length ? r.gapEnds[i].offsetMs : null
        ],
    ],
    'keptCount': m.keptCount,
    'movingTimeFinalS': d(session.movingTimeS, 1),
    'movingTimeLiveMs': m.movingTimeMs,
    'pace': [
      for (final e in r.pace) [e.$1, d(e.$2, 1), d(e.$3, 2)],
    ],
    'timeline': [
      for (final e in r.timeline) [e.$1, e.$2],
    ],
  };
  final keys = map.keys.toList()..sort();
  return const JsonEncoder.withIndent(' ')
      .convert({for (final k in keys) k: map[k]});
}
