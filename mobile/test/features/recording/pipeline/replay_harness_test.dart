// S04-02 Replay harness and fixtures (R-035): rows DT-02-1 .. DT-02-6.
//
// The expected results live in test/support/recording/replay_expected.json.
// They are recorded ONCE from the first green head (plan 2.1 rule 3) with
//   flutter test --dart-define=S04_RECORD=true <this file>
// and are never regenerated to make a failing test pass. The truth assertions
// that carry the requirements live in the story files (smoothing, distance,
// elevation, ...); this file guards against drift and nondeterminism.
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/pipeline/elevation.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';
import '../../../support/recording/replay_fixtures.dart';
import '../../../support/recording/scan_support.dart';

const bool _record = bool.fromEnvironment('S04_RECORD');
const String _expectedPath = 'test/support/recording/replay_expected.json';

/// Fixtures that are replayed at full length for the expected file. F-100k is
/// replayed too (it is fast) but its expected entry is kept compact.
Map<String, String> _computeAll() {
  final out = <String, String>{};
  for (final e in allFixtureBuilders().entries) {
    out[e.key] = serialiseReplay(replay(e.value()));
  }
  return out;
}

const JsonEncoder _enc = JsonEncoder.withIndent(' ');

/// Expected results are stored as JSON objects (readable); they are re-encoded
/// with the same encoder that produced the replay string, so the comparison
/// stays byte-for-byte.
Map<String, String> _loadExpected() {
  final f = File(_expectedPath);
  if (!f.existsSync()) return {};
  final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return raw.map((k, v) => MapEntry(k, _enc.convert(v)));
}

void main() {
  if (_record) {
    test('RECORD expected files (S04_RECORD=true)', () {
      final all = _computeAll();
      final keys = all.keys.toList()..sort();
      final out = {for (final k in keys) k: jsonDecode(all[k]!)};
      File(_expectedPath).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(out)}\n');
    });
    return;
  }

  final expected = _loadExpected();

  group('DT-02-1 every fixture matches its stored result', () {
    for (final name in allFixtureBuilders().keys) {
      test('/$name', () {
        expect(expected.containsKey(name), isTrue,
            reason: 'expected-result entry missing for $name');
        final fx = allFixtureBuilders()[name]!();
        expect(serialiseReplay(replay(fx)), expected[name],
            reason: 'pipeline output drifted for $name');
      });
    }

    test('the fixture list is exactly the 21 of plan 2.2', () {
      expect(allFixtureBuilders().length, 21);
      expect(expected.keys.toSet(), allFixtureBuilders().keys.toSet(),
          reason: 'no stale or missing expected entry');
    });
  });

  group('DT-02-2 determinism', () {
    test('F-noise-line, F-stop-go and F-kill-mid-run twice and in reversed '
        'order give byte-equal output', () {
      final builders = {
        'F-noise-line': () => fNoiseLine(),
        'F-stop-go': () => fStopGo().fixture,
        'F-kill-mid-run': () => fKillMidRun(),
      };
      String run(String n) => serialiseReplay(replay(builders[n]!()));
      final first = {for (final n in builders.keys) n: run(n)};
      final second = {for (final n in builders.keys) n: run(n)};
      final reversed = {
        for (final n in builders.keys.toList().reversed) n: run(n)
      };
      for (final n in builders.keys) {
        expect(second[n], first[n], reason: '$n second run');
        expect(reversed[n], first[n], reason: '$n reversed order');
      }
      // The generators themselves are deterministic too.
      expect(fNoiseLine().toCsv(), fNoiseLine().toCsv());
    });
  });

  group('DT-02-3 the suite guards every threshold constant', () {
    String base(String name) => expected[name]!;

    String withConfig(String name, PipelineConfig c) =>
        serialiseReplay(replay(allFixtureBuilders()[name]!(), config: c));

    void mismatch(String label, String fixture, PipelineConfig cfg) {
      expect(withConfig(fixture, cfg), isNot(base(fixture)),
          reason: '$label: no stored expected file changes when the constant '
              'moves; the suite does not guard it');
    }

    test('/accuracy-30', () {
      mismatch('accuracy 29', 'F-urban-canyon',
          const PipelineConfig(maxAccuracyM: 29.0));
      mismatch('accuracy 31', 'F-urban-canyon',
          const PipelineConfig(maxAccuracyM: 31.0));
    });

    test('/speed-30', () {
      mismatch('speed 29', 'F-jump',
          const PipelineConfig(maxImpliedSpeedMps: 29.0));
      mismatch('speed 31', 'F-jump',
          const PipelineConfig(maxImpliedSpeedMps: 31.0));
    });

    test('/poor-10s', () {
      mismatch('poor 9 s', 'F-tunnel',
          const PipelineConfig(poorAccuracyAfterMs: 9000));
      mismatch('poor 11 s', 'F-tunnel',
          const PipelineConfig(poorAccuracyAfterMs: 11000));
    });

    test('/pause-enter-0.5-8s', () {
      mismatch('enter speed 0.9 (jitter span 0.6 to 0.9)', 'F-stop-go',
          const PipelineConfig(autoPauseBelowSpeedMps: 0.95));
      mismatch('enter speed 0.3', 'F-still',
          const PipelineConfig(autoPauseBelowSpeedMps: 0.3));
      mismatch('enter time 7 s', 'F-stop-go',
          const PipelineConfig(autoPauseEnterAfterMs: 7000));
      mismatch('enter time 9 s', 'F-stop-go',
          const PipelineConfig(autoPauseEnterAfterMs: 9000));
    });

    test('/pause-leave-1.0-3s', () {
      mismatch('leave speed 0.8', 'F-stop-go',
          const PipelineConfig(autoResumeSpeedMps: 0.8));
      mismatch('leave time 2 s', 'F-stop-go',
          const PipelineConfig(autoResumeAfterMs: 2000));
      mismatch('leave time 4 s', 'F-stop-go',
          const PipelineConfig(autoResumeAfterMs: 4000));
    });

    test('/hysteresis-3m (altitude constants have no pipeline seam: probed on '
        'the accumulator over the F-climb and F-flat-alt-noise fixtures)', () {
      double asc(TrackFixture fx, {double h = kAltitudeHysteresisM}) {
        final e = ElevationAccumulator(hysteresisM: h);
        for (final r in fx.rows) {
          e.add(r.tMs - kFixtureT0Ms, r.alt);
        }
        return e.ascentM! + e.descentM!;
      }

      for (final fx in [fClimb(), fFlatAltNoise()]) {
        final b = asc(fx);
        expect(asc(fx, h: 2.0), isNot(b), reason: '${fx.name} at 2 m');
        expect(asc(fx, h: 4.0), isNot(b), reason: '${fx.name} at 4 m');
      }
    });

    test('/pace-window-10s', () {
      mismatch('window 9 s', 'F-walk', const PipelineConfig(paceWindowMs: 9000));
      mismatch(
          'window 11 s', 'F-walk', const PipelineConfig(paceWindowMs: 11000));
    });

    test('/pace-min-10m', () {
      mismatch('min 9 m', 'F-walk',
          const PipelineConfig(paceMinMovingDistanceM: 9.0));
      mismatch('min 11 m', 'F-walk',
          const PipelineConfig(paceMinMovingDistanceM: 12.0));
    });
  });

  group('DT-02-4 the pipeline is deterministic by construction', () {
    test('no DateTime.now, Random, Stopwatch, unordered collection or timer in '
        'pipeline/', () {
      final hits = <String>[];
      final pipeline = recordingSources()
          .where((f) => f.path.contains('lib/features/recording/pipeline/'));
      expect(pipeline.length, greaterThanOrEqualTo(10));
      final banned = RegExp(
          r'DateTime\.now|\bRandom\b|Stopwatch|HashMap|HashSet|LinkedHashSet|Timer\b|Future\.delayed|DateTime\.fromMillisecondsSinceEpoch\(\s*DateTime');
      for (final f in pipeline) {
        if (banned.hasMatch(f.code)) hits.add(f.path);
        // Iterating a Set or the values of a Map could reach the output order.
        if (RegExp(r'for\s*\(\s*\w+\s+\w+\s+in\s+\w*(Set|\.keys|\.values)\b')
            .hasMatch(f.code)) {
          hits.add('${f.path} (unordered iteration)');
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('DT-02-5 fixture validator', () {
    for (final name in allFixtureBuilders().keys) {
      if (name == 'F-100k') continue; // checked once below, cheaper
      test('/$name', () => _validateFixture(allFixtureBuilders()[name]!()));
    }

    test('/F-100k (columns, range and time order)', () {
      final fx = fHuge100k();
      expect(fx.rows.length, 100000);
      var prev = -1;
      for (final r in fx.rows) {
        expect(r.tMs, greaterThan(prev));
        prev = r.tMs;
      }
      expect(fx.rows.first.alt, isNotNull);
      expect(fx.rows.first.speed, isNotNull);
    });

    test('the validator itself rejects a malformed CSV', () {
      final good = fNoAlt().toCsv();
      expect(() => _validateCsv(good.replaceFirst('t_ms,lat,lon,acc_m',
          't_ms,lat,lon,acc')), throwsA(anything));
      final lines = good.split('\n');
      // Swap two data rows: time order is broken without a back/dup mark.
      final i = lines.indexWhere((l) => l.startsWith('1000,'));
      final tmp = lines[i];
      lines[i] = lines[i + 1];
      lines[i + 1] = tmp;
      expect(() => _validateCsv(lines.join('\n')), throwsA(anything));
    });
  });

  group('DT-02-6 the replay driver and the live controller share one '
      'pipeline', () {
    test('exactly one RecorderPipeline class exists and only the controller '
        'constructs it in production code', () {
      final decls = <String>[];
      final ctors = <String>[];
      for (final f in allLibSources()) {
        if (RegExp(r'class\s+\w*Pipeline\w*\s+(extends|implements)\s+RecorderPipeline')
            .hasMatch(f.code)) {
          decls.add(f.path);
        }
        if (RegExp(r'\bRecorderPipeline\(').hasMatch(f.code) &&
            !f.path.endsWith('recorder_pipeline.dart')) {
          ctors.add(f.path);
        }
      }
      expect(decls, isEmpty, reason: 'no second pipeline implementation');
      expect(ctors, ['lib/features/recording/state/recorder_controller.dart']);
    });

    test('behavioural proof: the live controller and the replay driver give '
        'the same kept offsets, counters and distance on F-bad-anchor', () async {
      final fx = fBadAnchor();
      final r = replay(fx, finish: false);

      final w = RecorderWorld.create();
      await w.start(sport: SportType.walking);
      // Drive the controller with the same rows at the same offsets.
      for (final row in fx.rows) {
        final off = row.tMs - kFixtureT0Ms;
        final target = off - (w.nowMs - w.startMs);
        if (target > 0) await w.advance(Duration(milliseconds: target));
        await w.emit(Fix(
            timeUtcMs: w.startMs + off,
            latitude: row.lat,
            longitude: row.lon,
            accuracyMeters: row.acc,
            altitudeMeters: row.alt,
            speedMps: row.speed));
      }
      final live = w.state.metrics!;
      expect(live.keptCount, r.metrics.keptCount);
      expect(live.counters, r.metrics.counters);
      expect(live.distanceM, closeTo(r.metrics.distanceM, 1e-6));
      expect(w.journal.samples.map((s) => s.sample.offsetMs).toList(),
          r.keptOffsets);
      await w.dispose();
    });
  });
}

void _validateFixture(TrackFixture fx) {
  final csv = fx.toCsv();
  _validateCsv(csv);
  if (fx.truthLengthM != null) {
    expect(csv, contains('# truth_length_m='));
  }
  if (fx.truthAscentM != null) expect(csv, contains('# truth_ascent_m='));
  if (fx.truthDescentM != null) expect(csv, contains('# truth_descent_m='));
}

void _validateCsv(String csv) {
  final lines = csv.split('\n').where((l) => l.isNotEmpty).toList();
  final header = lines.indexWhere((l) => !l.startsWith('#'));
  if (header < 0) throw StateError('no header');
  if (lines[header] != 't_ms,lat,lon,acc_m,alt_m,speed_mps,inject') {
    throw StateError('columns not exact: ${lines[header]}');
  }
  var prev = -1;
  for (var i = header + 1; i < lines.length; i++) {
    final c = lines[i].split(',');
    if (c.length != 7) throw StateError('column count in line $i');
    final t = int.parse(c[0]);
    final lat = double.parse(c[1]);
    final lon = double.parse(c[2]);
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      throw StateError('coordinate out of range in line $i');
    }
    final mark = c[6];
    if (!{'', 'drop', 'dup', 'back', 'kill'}.contains(mark)) {
      throw StateError('unknown inject mark $mark');
    }
    if (t <= prev && mark != 'back' && mark != 'dup') {
      throw StateError('t_ms not increasing in line $i');
    }
    if (mark != 'back') prev = t > prev ? t : prev;
  }
}
