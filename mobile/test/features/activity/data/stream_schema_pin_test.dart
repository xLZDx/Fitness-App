// S02-01 U37: the key sets and string patterns of the cloud stream payload are
// pinned by a fixture shared with the functions validator test.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_stream_payload.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/s02_fixtures.dart';
import '../../../support/s02_paths.dart';
import '../../../support/synthetic_activity_corpus.dart';

Map<String, dynamic> _fixture() => jsonDecode(repoFile(
        'functions/src/__tests__/activity/fixtures/stream_schema_keys.json')
    .readAsStringSync()) as Map<String, dynamic>;

Set<String> _set(Object? l) => {for (final e in l as List) e as String};

void main() {
  final fx = _fixture();
  const offs = [0, 1000];

  test('the fixture itself names no heart-rate key', () {
    void walk(Object? v) {
      if (v is Map) {
        for (final e in v.entries) {
          final k = e.key.toString().toLowerCase();
          expect(k.contains('hr') || k.contains('heart'), isFalse, reason: k);
          walk(e.value);
        }
      } else if (v is List) {
        for (final e in v) {
          if (e is String) {
            final l = e.toLowerCase();
            expect(l.contains('hr') || l.contains('heart'), isFalse, reason: e);
          }
          walk(e);
        }
      }
    }

    walk({...fx}..remove('comment')..remove('lapStringPatterns')..remove('provenanceStringPatterns'));
  });

  test('SampleStream.toJson key sets for gps, altitude and speed equal the fixture', () {
    final gps = SampleStream.checked(
      kind: StreamKind.gps,
      sourceId: 'phone',
      offsetsMs: offs,
      lats: const [1.0000007351, 1.0000107351],
      lons: const [-27.0, -27.1],
      accuracies: const [3, 4],
    ).toJson();
    final alt = SampleStream.checked(
        kind: StreamKind.altitude, sourceId: 'p', offsetsMs: offs, values: const [1, 2]).toJson();
    final spd = SampleStream.checked(
        kind: StreamKind.speed, sourceId: 'p', offsetsMs: offs, values: const [1, 2]).toJson();
    final keys = fx['streamKeys'] as Map;
    expect(gps.keys.toSet(), _set(keys['gps']));
    expect(alt.keys.toSet(), _set(keys['altitude']));
    expect(spd.keys.toSet(), _set(keys['speed']));
    expect(keys.keys.toSet(), {'gps', 'altitude', 'speed'});
    expect(kStreamKeys, {..._set(keys['gps']), 'values'});
  });

  test('the lap and provenance key sets of the client builder equal the fixture', () {
    final s = miniSession(
      laps: const [
        Lap(index: 0, kind: LapKind.auto, startOffsetS: 0, durationS: 5,
            distanceM: 10, avgHrBpm: 150.25, strokeCount: 2, strokeType: StrokeType.free),
      ],
      provenance: [
        SourceRecord(
          sourceId: 'garmin-connect',
          sourceKind: SourceKind.vendorCloud,
          importedAt: DateTime.utc(2026, 5, 1, 7),
          deviceModel: 'Forerunner 245',
          appPackage: 'com.garmin.connect',
          externalId: 'e-1',
          fieldsContributed: const ['distanceM'],
          rawRef: 'raw/x',
        ),
      ],
    );
    final p = ActivityStreamPayload.fromSession(s);
    expect(p.laps.single.keys.toSet(), _set(fx['lapKeys']));
    expect(p.provenance.single.keys.toSet(), _set(fx['provenanceKeys']));
    expect(kLapKeys.difference(_set(fx['lapKeys'])), isEmpty);
    expect(_set(fx['lapKeys']).difference(kLapKeys), isEmpty);
    expect(kProvenanceKeys, _set(fx['provenanceKeys']));
  });

  test('the Dart string patterns equal the fixture patterns', () {
    final prov = fx['provenanceStringPatterns'] as Map;
    for (final e in kProvenanceStringPatterns.entries) {
      expect(e.value.pattern, prov[e.key], reason: e.key);
    }
    expect(kFieldContributedPattern.pattern, fx['fieldContributedPattern']);
    expect(kCoordinateLike.pattern, fx['coordinateLike']);
  });

  test('client builder output for the whole corpus matches every fixture regex', () {
    final lapRe = {
      for (final e in (fx['lapStringPatterns'] as Map).entries)
        e.key as String: RegExp(e.value as String),
    };
    final provRe = {
      for (final e in (fx['provenanceStringPatterns'] as Map).entries)
        e.key as String: RegExp(e.value as String),
    };
    final fieldRe = RegExp(fx['fieldContributedPattern'] as String);
    final coord = RegExp(fx['coordinateLike'] as String);
    var laps = 0, provs = 0;
    for (final s in SyntheticCorpus.build().valid) {
      final p = ActivityStreamPayload.fromSession(s);
      for (final lap in p.laps) {
        laps++;
        for (final e in lapRe.entries) {
          final v = lap[e.key];
          if (v != null) {
            expect(e.value.hasMatch(v as String), isTrue, reason: '${s.id} lap ${e.key}=$v');
          }
        }
      }
      for (final rec in p.provenance) {
        provs++;
        for (final e in provRe.entries) {
          final v = rec[e.key];
          if (v != null) {
            expect(e.value.hasMatch(v as String), isTrue, reason: '${s.id} ${e.key}=$v');
            expect(coord.hasMatch(v), isFalse, reason: '${s.id} ${e.key}=$v coordinate-like');
          }
        }
        for (final f in rec['fieldsContributed'] as List) {
          expect(fieldRe.hasMatch(f as String), isTrue);
        }
      }
      for (final k in p.kinds.values) {
        expect(provRe['sourceId']!.hasMatch(k['sourceId'] as String), isTrue);
      }
    }
    expect(laps, greaterThan(500));
    expect(provs, greaterThan(100));
  });

  test('a renamed key would be caught (negative control on the comparison)', () {
    final s = SampleStream.checked(
        kind: StreamKind.altitude, sourceId: 'p', offsetsMs: offs, values: const [1, 2]).toJson();
    final renamed = {...s}..remove('offsetsMs');
    renamed['offsets'] = s['offsetsMs'];
    expect(renamed.keys.toSet(), isNot(_set((fx['streamKeys'] as Map)['altitude'])));
    expect(SportType.values, isNotEmpty);
  });
}
