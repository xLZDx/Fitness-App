// T28 activity_models_test (ACT-01..ACT-04). Tolerant JSON, stream validity,
// canonical units with derived pace, stable session ids.
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/device_source.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 10, 10, 6, 0);
final _end = DateTime.utc(2026, 10, 10, 6, 10);

SampleStream _hr() => SampleStream.checked(
      kind: StreamKind.heartRate,
      sourceId: 'strap',
      offsetsMs: const [0, 1000, 2000],
      values: const [100, 110, 120],
    );

SampleStream _gps() => SampleStream.checked(
      kind: StreamKind.gps,
      sourceId: 'phone',
      offsetsMs: const [0, 1000],
      lats: const [51.5, 51.5001],
      lons: const [-0.12, -0.1201],
      accuracies: const [4.0, 5.0],
    );

ActivitySession _full() => ActivitySession(
      id: 'act_x',
      sport: SportType.running,
      startUtc: _start,
      endUtc: _end,
      utcOffsetMinutes: 120,
      movingTimeS: 590,
      summary: const ActivitySummary(
          distanceM: 10000, avgHrBpm: 150, avgSpeedMps: 2.5, steps: 9000),
      streams: {StreamKind.heartRate: _hr(), StreamKind.gps: _gps()},
      laps: const [
        Lap(
            index: 0,
            kind: LapKind.auto,
            startOffsetS: 0,
            durationS: 300,
            distanceM: 5000,
            avgHrBpm: 148,
            strokeCount: 12,
            strokeType: StrokeType.free),
      ],
      provenance: [
        SourceRecord(
          sourceId: 'garmin',
          sourceKind: SourceKind.companionApp,
          importedAt: DateTime.utc(2026, 10, 10, 7),
          deviceModel: 'Forerunner',
          externalId: 'g1',
          fieldsContributed: const ['heartRate'],
          rawRef: 'raw/1',
        ),
      ],
      userEdits: const {'distanceM': 10100.0},
      privacy: const ActivityPrivacy(routeTrimMeters: 300),
      schema: 2,
      mergeNotes: const ['summaryDisagreement:distanceM'],
    );

void main() {
  group('ACT-01 tolerant JSON', () {
    test('a full session round-trips to an equal session', () {
      final s = _full();
      final back = ActivitySession.tryFromJson(s.toJson())!;
      expect(back, s);
      expect(back.sport, SportType.running);
      expect(back.utcOffsetMinutes, 120);
      expect(back.movingTimeS, 590);
      expect(back.summary.distanceM, 10000);
      expect(back.streams[StreamKind.heartRate]!.values, [100, 110, 120]);
      expect(back.streams[StreamKind.gps]!.lats, [51.5, 51.5001]);
      expect(back.streams[StreamKind.gps]!.accuracies, [4.0, 5.0]);
      expect(back.laps.single.strokeType, StrokeType.free);
      expect(back.provenance.single.externalId, 'g1');
      expect(back.userEdits, {'distanceM': 10100.0});
      expect(back.privacy.routeTrimMeters, 300);
      expect(back.mergeNotes, ['summaryDisagreement:distanceM']);
    });
    test('the schema field is kept (2 stays 2) and defaults to 1', () {
      expect(ActivitySession.tryFromJson(_full().toJson())!.schema, 2);
      final j = _full().toJson()..remove('schema');
      expect(ActivitySession.tryFromJson(j)!.schema, 1);
    });
    test('an unknown sport string degrades to other', () {
      final j = _full().toJson()..['sport'] = 'quidditch';
      expect(ActivitySession.tryFromJson(j)!.sport, SportType.other);
      final k = _full().toJson()..['sport'] = 42;
      expect(ActivitySession.tryFromJson(k)!.sport, SportType.other);
    });
    test('unknown extra fields are ignored for behaviour but kept for the round trip', () {
      final j = _full().toJson()..['futureField'] = {'a': 1};
      final s = ActivitySession.tryFromJson(j)!;
      expect(s.extras['futureField'], {'a': 1});
      expect(s.toJson()['futureField'], {'a': 1});
      expect(s.sport, SportType.running);
    });
    test('missing optional summary fields read as null', () {
      final j = _full().toJson();
      j['summary'] = {'distanceM': 5000};
      final s = ActivitySession.tryFromJson(j)!;
      expect(s.summary.distanceM, 5000);
      expect(s.summary.avgHrBpm, isNull);
      expect(s.summary.ascentM, isNull);
      expect(s.summary.avgSwolf, isNull);
      expect(ActivitySession.tryFromJson({
        'id': 'a',
        'startUtc': _start.toIso8601String(),
        'endUtc': _end.toIso8601String(),
      })!.summary.toFieldMap().values.every((v) => v == null), isTrue);
    });
    test('only set summary fields are written', () {
      expect(const ActivitySummary(distanceM: 5).toJson(), {'distanceM': 5.0});
      expect(ActivitySummary.empty.toJson(), isEmpty);
      expect(ActivitySummary.fromJson('nonsense').toJson(), isEmpty);
      expect(ActivitySummary.fromJson({'distanceM': 'far'}).distanceM, isNull);
    });
    test('unreadable sessions are null: bad id, bad times, end before start, not a map', () {
      final ok = _full().toJson();
      expect(ActivitySession.tryFromJson(null), isNull);
      expect(ActivitySession.tryFromJson('x'), isNull);
      expect(ActivitySession.tryFromJson({...ok, 'id': 3}), isNull);
      expect(ActivitySession.tryFromJson({...ok, 'startUtc': 'soon'}), isNull);
      expect(ActivitySession.tryFromJson({...ok, 'endUtc': null}), isNull);
      expect(
          ActivitySession.tryFromJson(
              {...ok, 'endUtc': _start.subtract(const Duration(seconds: 1)).toIso8601String()}),
          isNull);
    });
    test('an invalid stream inside a session is dropped, the rest is kept', () {
      final j = _full().toJson();
      (j['streams'] as List).add({
        'kind': 'power',
        'sourceId': 'pm',
        'offsetsMs': [0, 0],
        'values': [1.0, 2.0],
      });
      final s = ActivitySession.tryFromJson(j)!;
      expect(s.streams.containsKey(StreamKind.power), isFalse);
      expect(s.streams.containsKey(StreamKind.heartRate), isTrue);
    });
    test('times are normalised to UTC', () {
      final s = ActivitySession(
          id: 'a',
          sport: SportType.other,
          startUtc: DateTime.parse('2026-10-10T08:00:00+02:00'),
          endUtc: DateTime.parse('2026-10-10T09:00:00+02:00'));
      expect(s.startUtc.isUtc, isTrue);
      expect(s.startUtc, DateTime.utc(2026, 10, 10, 6));
      expect(s.durationMs, 3600000);
    });
    test('Lap: unknown kind -> auto, unknown stroke -> null, missing timing -> null', () {
      final l = Lap.tryFromJson({
        'index': 1,
        'kind': 'weird',
        'startOffsetS': 10,
        'durationS': 20.5,
        'strokeType': 'dolphin',
      })!;
      expect(l.kind, LapKind.auto);
      expect(l.strokeType, isNull);
      expect(l.durationS, 20.5);
      expect(Lap.tryFromJson({'index': 1, 'startOffsetS': 1}), isNull);
      expect(Lap.tryFromJson('x'), isNull);
    });
    test('SourceRecord: unknown kind -> fileImport; missing id or import time -> null', () {
      final r = SourceRecord.tryFromJson({
        'sourceId': 's',
        'sourceKind': 'telepathy',
        'importedAt': '2026-10-10T07:00:00Z',
      })!;
      expect(r.sourceKind, SourceKind.fileImport);
      expect(r.dedupKey, isNull);
      expect(SourceRecord.tryFromJson({'importedAt': '2026-10-10T07:00:00Z'}), isNull);
      expect(SourceRecord.tryFromJson({'sourceId': 's', 'importedAt': 'x'}), isNull);
      expect(
          SourceRecord(
                  sourceId: 'a',
                  sourceKind: SourceKind.bleSensor,
                  importedAt: _start,
                  externalId: 'e')
              .dedupKey,
          'a|e');
    });
    test('ActivityPrivacy default trims 200 m; fromJson of junk gives the default', () {
      expect(const ActivityPrivacy().routeTrimMeters, 200);
      expect(ActivityPrivacy.defaultRouteTrimMeters, 200);
      expect(ActivityPrivacy.fromJson(null).routeTrimMeters, 200);
      expect(ActivityPrivacy.fromJson({'routeTrimMeters': 'a'}).routeTrimMeters, 200);
      expect(ActivityPrivacy.fromJson({'routeTrimMeters': 50}).routeTrimMeters, 50);
    });
    test('sport parsing and families', () {
      expect(SportType.parse('trailRunning'), SportType.trailRunning);
      expect(SportType.parse(null), SportType.other);
      expect(SportType.running.compatibleWith(SportType.trailRunning), isTrue);
      expect(SportType.cycling.compatibleWith(SportType.indoorCycling), isTrue);
      expect(SportType.cycling.compatibleWith(SportType.mountainBiking), isTrue);
      expect(SportType.indoorCycling.compatibleWith(SportType.mountainBiking), isTrue);
      expect(SportType.running.compatibleWith(SportType.cycling), isFalse);
      expect(SportType.swimmingPool.compatibleWith(SportType.swimmingOpenWater), isFalse);
      expect(SportType.swimmingPool.compatibleWith(SportType.swimmingPool), isTrue);
      expect(SportType.walking.compatibleWith(SportType.hiking), isFalse);
      expect(SportType.other.compatibleWith(SportType.other), isTrue);
    });
  });

  group('ACT-02 stream validity', () {
    SampleStream make(List<int> offsets, List<double> values) =>
        SampleStream.checked(
            kind: StreamKind.heartRate,
            sourceId: 's',
            offsetsMs: offsets,
            values: values);

    test('non-increasing offsets are rejected', () {
      expect(() => make([0, 2000, 1000], [1, 2, 3]), throwsArgumentError);
    });
    test('duplicate offsets are rejected', () {
      expect(() => make([0, 1000, 1000], [1, 2, 3]), throwsArgumentError);
    });
    test('strictly increasing offsets are accepted, including a single sample and none', () {
      expect(make([0, 1, 2], [1, 2, 3]).length, 3);
      expect(make([5], [1]).length, 1);
      expect(make(const [], const []).isEmpty, isTrue);
    });
    test('values / offsets length mismatch is rejected both ways', () {
      expect(() => make([0, 1000], [1]), throwsArgumentError);
      expect(() => make([0], [1, 2]), throwsArgumentError);
    });
    test('GPS: lats and lons must be parallel to the offsets', () {
      expect(
          () => SampleStream.checked(
              kind: StreamKind.gps,
              sourceId: 'p',
              offsetsMs: [0, 1000],
              lats: [1.0],
              lons: [1.0, 2.0]),
          throwsArgumentError);
      expect(
          () => SampleStream.checked(
              kind: StreamKind.gps,
              sourceId: 'p',
              offsetsMs: [0, 1000],
              lats: [1.0, 2.0],
              lons: [1.0]),
          throwsArgumentError);
    });
    test('GPS: an accuracy list of the wrong length is rejected; GPS never carries values', () {
      expect(
          () => SampleStream.checked(
              kind: StreamKind.gps,
              sourceId: 'p',
              offsetsMs: [0, 1000],
              lats: [1.0, 2.0],
              lons: [1.0, 2.0],
              accuracies: [3.0]),
          throwsArgumentError);
      expect(
          () => SampleStream.checked(
              kind: StreamKind.gps,
              sourceId: 'p',
              offsetsMs: [0],
              lats: [1.0],
              lons: [1.0],
              values: [5.0]),
          throwsArgumentError);
    });
    test('a non-GPS stream never carries lat/lon', () {
      expect(
          () => SampleStream.checked(
              kind: StreamKind.heartRate,
              sourceId: 'p',
              offsetsMs: [0],
              values: [1.0],
              lats: [1.0]),
          throwsArgumentError);
    });
    test('tryFromJson returns null instead of throwing for invalid data', () {
      expect(
          SampleStream.tryFromJson({
            'kind': 'heartRate',
            'sourceId': 's',
            'offsetsMs': [0, 0],
            'values': [1, 2],
          }),
          isNull);
      expect(SampleStream.tryFromJson({'kind': 'nope', 'sourceId': 's', 'offsetsMs': [0], 'values': [1]}), isNull);
      expect(SampleStream.tryFromJson({'kind': 'heartRate', 'sourceId': 3, 'offsetsMs': [0], 'values': [1]}), isNull);
      expect(SampleStream.tryFromJson({'kind': 'heartRate', 'sourceId': 's', 'offsetsMs': ['a'], 'values': [1]}), isNull);
      expect(SampleStream.tryFromJson({'kind': 'heartRate', 'sourceId': 's', 'offsetsMs': [0], 'values': ['x']}), isNull);
      expect(SampleStream.tryFromJson(null), isNull);
    });
    test('a valid stream survives a JSON round trip', () {
      final s = _gps();
      final back = SampleStream.tryFromJson(s.toJson())!;
      expect(back.offsetsMs, s.offsetsMs);
      expect(back.lats, s.lats);
      expect(back.lons, s.lons);
      expect(back.accuracies, s.accuracies);
      expect(back.kind, StreamKind.gps);
    });
    test('coverage: fraction of the session between first and last sample', () {
      final s = make([0, 480000], [1, 2]);
      expect(s.coverage(600000), closeTo(0.8, 1e-12));
      expect(s.coverage(0), 0);
      expect(make([0], [1]).coverage(1000), 0);
      expect(make([0, 900000], [1, 2]).coverage(600000), 1); // clamped
    });
    test('shifted drops samples that would land before the session start', () {
      final s = make([0, 1000, 2000], [1, 2, 3]).shifted(-1000);
      expect(s.offsetsMs, [0, 1000]);
      expect(s.values, [2, 3]);
      final later = make([0, 1000], [1, 2]).shifted(3000);
      expect(later.offsetsMs, [3000, 4000]);
    });
  });

  group('ACT-03 canonical units and derived pace', () {
    test('canonical unit per stream kind', () {
      expect({for (final k in StreamKind.values) k.name: k.unit}, {
        'heartRate': 'bpm',
        'speed': 'm/s',
        'cadence': 'rpm',
        'power': 'W',
        'altitude': 'm',
        'gps': 'deg',
        'strokeRate': 'strokes/min',
        'temperature': 'degC',
      });
      expect(_hr().toJson()['unit'], 'bpm');
    });
    test('values are stored exactly as given: no km or mile conversion', () {
      final s = ActivitySession(
        id: 'a',
        sport: SportType.running,
        startUtc: _start,
        endUtc: _end,
        summary: const ActivitySummary(distanceM: 10000, ascentM: 123.4),
      );
      final j = s.toJson();
      expect((j['summary'] as Map)['distanceM'], 10000);
      expect((j['summary'] as Map)['ascentM'], 123.4);
    });
    test('no pace field is stored anywhere in the JSON', () {
      final j = _full().toJson();
      expect(j.keys.where((k) => k.toLowerCase().contains('pace')), isEmpty);
      expect(
          (j['summary'] as Map).keys.where((k) => k.toString().toLowerCase().contains('pace')),
          isEmpty);
    });
    test('pace is derived from the average speed: 2.5 m/s = 400 s/km', () {
      expect(_full().paceSecPerKm, closeTo(400, 1e-9));
    });
    test('pace is null without a usable speed', () {
      final none = ActivitySession(
          id: 'a', sport: SportType.running, startUtc: _start, endUtc: _end);
      expect(none.paceSecPerKm, isNull);
      final zero = ActivitySession(
          id: 'a',
          sport: SportType.running,
          startUtc: _start,
          endUtc: _end,
          summary: const ActivitySummary(avgSpeedMps: 0));
      expect(zero.paceSecPerKm, isNull);
    });
  });

  group('ACT-04 stable session id', () {
    test('act_<sha1 of "sourceId|externalId">, independently computed', () {
      expect(
          activityIdFor(sourceId: 'garmin', externalId: 'abc', startUtc: _start),
          'act_4bfbb9abb0a6c9c732934b2c6ac9a5c037497719');
    });
    test('identical across calls for the same key', () {
      final a = activityIdFor(sourceId: 'garmin', externalId: 'abc', startUtc: _start);
      final b = activityIdFor(
          sourceId: 'garmin',
          externalId: 'abc',
          startUtc: _start.add(const Duration(days: 9)));
      expect(a, b); // the start time is irrelevant when an externalId exists
    });
    test('differs when externalId differs', () {
      expect(
          activityIdFor(sourceId: 'garmin', externalId: 'abd', startUtc: _start),
          'act_cd4ac070cde29f8c9671c1a984d7c4652e669d07');
    });
    test('differs when the source differs', () {
      expect(
          activityIdFor(sourceId: 'strava', externalId: 'abc', startUtc: _start),
          isNot(activityIdFor(sourceId: 'garmin', externalId: 'abc', startUtc: _start)));
    });
    test('without an externalId the key is sourceId|start:<epoch ms>', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1760000000000, isUtc: true);
      expect(activityIdFor(sourceId: 'phone', startUtc: t),
          'act_df1245f14f8db986ae92c75a40c9f26c6c1ae734');
    });
    test('the start instant is what counts, not the zone it is expressed in', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1760000000000, isUtc: true);
      expect(
          activityIdFor(sourceId: 'phone', startUtc: t.toLocal()),
          activityIdFor(sourceId: 'phone', startUtc: t));
    });
    test('different start instants give different ids when there is no externalId', () {
      final t = DateTime.utc(2026, 1, 1);
      expect(activityIdFor(sourceId: 'phone', startUtc: t),
          isNot(activityIdFor(sourceId: 'phone', startUtc: t.add(const Duration(milliseconds: 1)))));
    });
  });
}
