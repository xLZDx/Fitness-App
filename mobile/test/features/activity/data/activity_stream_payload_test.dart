// S02-01 U08 (heart rate never in the cloud payload), U09 (device-only kinds),
// U32 (meta content and the closed builder).
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_migration.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_stream_payload.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/s02_fixtures.dart';
import '../../../support/synthetic_activity_corpus.dart';

const _offs = [0, 1000, 2000];
const _all = {...StreamKind.values};

SampleStream _vals(StreamKind k, List<double> v) => SampleStream.checked(
    kind: k, sourceId: 'dev-1', offsetsMs: _offs, values: v);

/// A session carrying every stream kind, heart-rate sentinels everywhere and
/// HR-named keys in every extras map.
ActivitySession _loaded() => ActivitySession(
      id: kMiniId,
      sport: SportType.cycling,
      startUtc: kMiniStart,
      endUtc: kMiniStart.add(const Duration(minutes: 10)),
      streams: {
        StreamKind.gps: SampleStream.checked(
          kind: StreamKind.gps,
          sourceId: 'dev-1',
          offsetsMs: _offs,
          lats: const [2.1000007351, 2.1000107351, 2.1000207351],
          lons: const [-27.1, -27.2, -27.3],
          accuracies: const [3, 4, 5],
        ),
        StreamKind.altitude: _vals(StreamKind.altitude, const [10, 11, 12]),
        StreamKind.speed: _vals(StreamKind.speed, const [3, 4, 5]),
        StreamKind.heartRate: _vals(StreamKind.heartRate, const [173.25, 172.25, 171.25]),
        StreamKind.cadence: _vals(StreamKind.cadence, const [80, 81, 82]),
        StreamKind.power: _vals(StreamKind.power, const [200, 210, 220]),
        StreamKind.strokeRate: _vals(StreamKind.strokeRate, const [20, 21, 22]),
        StreamKind.temperature: _vals(StreamKind.temperature, const [15, 16, 17]),
      },
      laps: const [
        Lap(
          index: 0,
          kind: LapKind.manual,
          startOffsetS: 0,
          durationS: 60,
          distanceM: 500,
          avgHrBpm: 173.25,
          strokeCount: 3,
          strokeType: StrokeType.free,
          extras: {'hr': 150, 'heartRate': 151, 'MaxHR': 152, 'avgHrBpm2': 1},
        ),
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
          rawRef: 'raw/1',
          extras: const {'hr': 150, 'heartRate': 160, 'HeartRate': 1},
        ),
      ],
      userEdits: const {'distanceM': 123.0},
      mergeNotes: const ['summaryDisagreement:distanceM'],
    ).copyWith(editHistory: const [], userEditCount: 3);

bool _hrKey(String k) {
  final l = k.toLowerCase();
  return l.contains('hr') || l.contains('heart');
}

void _noHrKeys(Object? v, String path) {
  if (v is Map) {
    for (final e in v.entries) {
      expect(_hrKey(e.key.toString()), isFalse, reason: '$path.${e.key}');
      _noHrKeys(e.value, '$path.${e.key}');
    }
  } else if (v is List) {
    for (var i = 0; i < v.length; i++) {
      _noHrKeys(v[i], '$path[$i]');
    }
  }
}

void main() {
  final corpus = SyntheticCorpus.build();

  group('U08 heart rate never reaches the cloud payload', () {
    test('allowedKinds = all 8 kinds still yields no heartRate, no lap HR, no sentinel',
        () {
      final p = ActivityStreamPayload.fromSession(_loaded(), allowedKinds: _all);
      final json = p.toJson();
      expect((json['kinds'] as Map).containsKey('heartRate'), isFalse);
      final text = jsonEncode(json);
      expect(text.contains('173.25'), isFalse);
      expect(text.contains('172.25'), isFalse);
      expect(p.laps, hasLength(1));
      expect(p.laps.single.containsKey('avgHrBpm'), isFalse);
      _noHrKeys(json, r'$');
      // Contrast: the local record does carry the sentinel.
      expect(jsonEncode(_loaded().toJson()).contains('173.25'), isTrue);
    });

    test('HR-named keys in a lap, a provenance record and a GPS sample map are dropped',
        () {
      final p = ActivityStreamPayload.fromSession(_loaded(), allowedKinds: _all);
      expect(p.laps.single.keys.toSet(),
          {'index', 'kind', 'startOffsetS', 'durationS', 'distanceM', 'strokeCount', 'strokeType'});
      expect(p.provenance.single.containsKey('hr'), isFalse);
      expect(p.provenance.single.containsKey('heartRate'), isFalse);
      // A corrupted stored session whose GPS sample map carries an extra hr key.
      final m = deepCopy(_loaded().toJson());
      final gps = (m['streams'] as List).firstWhere((e) => e['kind'] == 'gps') as Map;
      gps['hr'] = [150, 151, 152];
      gps['heartRate'] = 1;
      final s = ActivityMigration.read(m)!;
      final q = ActivityStreamPayload.fromSession(s, allowedKinds: _all);
      final out = jsonEncode(q.toJson());
      expect(out.contains('"hr"'), isFalse);
      expect(out.contains('heartRate'), isFalse);
      _noHrKeys(q.toJson(), r'$');
    });

    test('meta never holds userEdits, explicitValues, mergeNotes', () {
      final json = ActivityStreamPayload.fromSession(_loaded(), allowedKinds: _all).toJson();
      expect((json['meta'] as Map).keys.toSet(), {'laps', 'provenance'});
      expect(json.keys.toSet(), {'schema', 'kinds', 'meta'});
      final text = jsonEncode(json);
      for (final k in const ['userEdits', 'explicitValues', 'mergeNotes',
        'editHistory', 'summaryOverrides', 'userEditCount']) {
        expect(text.contains(k), isFalse, reason: k);
      }
      expect(text.contains('summaryDisagreement'), isFalse);
    });

    test('over the whole corpus no heart-rate value or key appears', () {
      for (final s in corpus.valid) {
        final json = ActivityStreamPayload.fromSession(s, allowedKinds: _all).toJson();
        final text = jsonEncode(json);
        final hr = s.streams[StreamKind.heartRate];
        if (hr != null) {
          expect(RegExp(r'"heartRate"').hasMatch(text), isFalse, reason: s.id);
        }
        for (final lap in (json['meta'] as Map)['laps'] as List) {
          expect((lap as Map).containsKey('avgHrBpm'), isFalse, reason: s.id);
        }
        _noHrKeys(json, s.id);
      }
    });
  });

  group('U09 cadence, power, strokeRate, temperature stay device-only', () {
    test('with all 8 kinds allowed only gps, altitude, speed are output', () {
      final p = ActivityStreamPayload.fromSession(_loaded(), allowedKinds: _all);
      expect(p.kinds.keys.toSet(), {'gps', 'altitude', 'speed'});
      final text = jsonEncode(p.toJson());
      expect(text.contains('"cadence"'), isFalse);
      expect(text.contains('"power"'), isFalse);
      expect(text.contains('"strokeRate"'), isFalse);
      expect(text.contains('"temperature"'), isFalse);
    });

    test('the default allows exactly the three cloud kinds; a narrower set narrows',
        () {
      expect(kCloudStreamKinds, {StreamKind.gps, StreamKind.altitude, StreamKind.speed});
      expect(ActivityStreamPayload.fromSession(_loaded()).kinds.keys.toSet(),
          {'gps', 'altitude', 'speed'});
      expect(
          ActivityStreamPayload.fromSession(_loaded(), allowedKinds: {StreamKind.gps})
              .kinds
              .keys,
          ['gps']);
      expect(ActivityStreamPayload.fromSession(_loaded(), allowedKinds: {}).kinds, isEmpty);
    });

    test('over the corpus every output kind is in the allowed trio', () {
      var withPower = 0;
      for (final s in corpus.valid) {
        if (s.streams.containsKey(StreamKind.power)) withPower++;
        final p = ActivityStreamPayload.fromSession(s, allowedKinds: _all);
        expect({...p.kinds.keys}.difference({'gps', 'altitude', 'speed'}), isEmpty);
      }
      expect(withPower, 15, reason: 'the control: devices-only kinds do exist locally');
    });
  });

  group('U32 closed builder', () {
    test('provenance keys are the closed set; rawRef and extras do not leave', () {
      final p = ActivityStreamPayload.fromSession(_loaded());
      expect(p.provenance.single.keys.toSet(), {
        'sourceId', 'sourceKind', 'importedAt', 'deviceModel', 'appPackage',
        'externalId', 'fieldsContributed',
      });
    });

    test('strings that are coordinate-like or fail their pattern are dropped; '
        'a record with an unusable required field is dropped whole', () {
      ActivitySession withProv(SourceRecord r) =>
          miniSession().copyWith(provenance: [r]);
      SourceRecord rec({String? model, String? ext, DateTime? at, String id = 'src-1'}) =>
          SourceRecord(
            sourceId: id,
            sourceKind: SourceKind.vendorCloud,
            importedAt: at ?? DateTime.utc(2026, 5, 1, 7),
            deviceModel: model,
            externalId: ext,
            fieldsContributed: const ['distanceM', 'bad name', '51.5007'],
          );
      var p = ActivityStreamPayload.fromSession(
          withProv(rec(model: 'Watch 4.10', ext: '51.5007,-0.1276')));
      expect(p.provenance.single.containsKey('deviceModel'), isFalse);
      expect(p.provenance.single.containsKey('externalId'), isFalse);
      expect(p.provenance.single['fieldsContributed'], ['distanceM']);
      p = ActivityStreamPayload.fromSession(withProv(rec(model: 'Forerunner 245', ext: 'séance-é')));
      expect(p.provenance.single['deviceModel'], 'Forerunner 245');
      expect(p.provenance.single.containsKey('externalId'), isFalse);
      p = ActivityStreamPayload.fromSession(withProv(rec(id: 'bad id!')));
      expect(p.provenance, isEmpty);
      p = ActivityStreamPayload.fromSession(
          withProv(rec(at: DateTime.utc(2026, 5, 1, 7, 0, 0, 123))));
      expect(p.provenance.single['importedAt'], '2026-05-01T07:00:00Z');
    });

    test('an unknown lap kind becomes auto and an unknown stroke type is dropped',
        () {
      final m = deepCopy(_loaded().toJson());
      final lap = (m['laps'] as List).single as Map;
      lap['kind'] = 'warpDrive';
      lap['strokeType'] = 'dolphin';
      final p = ActivityStreamPayload.fromSession(ActivityMigration.read(m)!);
      expect(p.laps.single['kind'], 'auto');
      expect(p.laps.single.containsKey('strokeType'), isFalse);
    });

    test('a stream whose sourceId the server would reject stays device-only', () {
      final s = miniSession(streams: {
        StreamKind.altitude: SampleStream.checked(
            kind: StreamKind.altitude,
            sourceId: 'phone at 51.5007',
            offsetsMs: const [0, 1],
            values: const [1, 2]),
      });
      expect(ActivityStreamPayload.fromSession(s).kinds, isEmpty);
    });
  });
}
