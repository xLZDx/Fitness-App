// S02 test epic 3, U24: the design 9 consent matrix, cloud-upload columns.
//
// There is no separate "policy" class in the S02 build: the cloud-stream
// column is enforced by `ActivityStreamPayload.fromSession` (the caller passes
// `allowedKinds`: the empty set stands for "cloudStreams consent off", every
// kind for "consent on and no filtering by the caller") and the cloud-summary
// column by `ActivityCloudSummary.fromSession`. The matrix below is the
// literal table of design 9, one row per (source kind, datatype, consent).
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_stream_payload.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

const _offs = [0, 1000, 2000];

SampleStream _vals(StreamKind k, String src, List<double> v) =>
    SampleStream.checked(kind: k, sourceId: src, offsetsMs: _offs, values: v);

ActivitySession _session(SourceKind kind, Set<StreamKind> kinds) {
  const src = 'dev-1';
  final start = DateTime.utc(2026, 5, 1, 6);
  return ActivitySession(
    id: 'act_${'0' * 39}1',
    sport: SportType.running,
    startUtc: start,
    endUtc: start.add(const Duration(minutes: 10)),
    summary: const ActivitySummary(distanceM: 3000, avgHrBpm: 161.75, maxHrBpm: 190),
    streams: {
      for (final k in kinds)
        k: k == StreamKind.gps
            ? SampleStream.checked(
                kind: k,
                sourceId: src,
                offsetsMs: _offs,
                lats: const [2.1000007351, 2.1000107351, 2.1000207351],
                lons: const [-27.1, -27.2, -27.3])
            : _vals(k, src, k == StreamKind.heartRate ? const [161.75, 160.75, 159.75] : const [5, 6, 7]),
    },
    provenance: [
      SourceRecord(
          sourceId: src,
          sourceKind: kind,
          importedAt: start.add(const Duration(hours: 1)),
          externalId: 'e1'),
    ],
  );
}

Set<String> _cloudKinds(ActivitySession s, Set<StreamKind> allowed) =>
    ActivityStreamPayload.fromSession(s, allowedKinds: allowed).kinds.keys.toSet();

/// Design 9 matrix, cloud stream column. Each row:
/// (source kind, datatype present, consent on) -> allowed kind names.
/// `fileImport` has no S02 import, so it has no GPS rows ("n/a").
final List<(SourceKind, StreamKind, bool, Set<String>)> _matrix = [
  // Native recording (companionApp 'app'): GPS only with consent.
  (SourceKind.companionApp, StreamKind.gps, true, {'gps'}),
  (SourceKind.companionApp, StreamKind.gps, false, {}),
  (SourceKind.companionApp, StreamKind.heartRate, true, {}),
  (SourceKind.companionApp, StreamKind.heartRate, false, {}),
  // platformHealth: GPS only if present, same consent; HR never.
  (SourceKind.platformHealth, StreamKind.gps, true, {'gps'}),
  (SourceKind.platformHealth, StreamKind.gps, false, {}),
  (SourceKind.platformHealth, StreamKind.heartRate, true, {}),
  (SourceKind.platformHealth, StreamKind.heartRate, false, {}),
  // bleSensor: HR never; cadence / power stay device-only (DQ-2).
  (SourceKind.bleSensor, StreamKind.heartRate, true, {}),
  (SourceKind.bleSensor, StreamKind.cadence, true, {}),
  (SourceKind.bleSensor, StreamKind.power, true, {}),
  (SourceKind.bleSensor, StreamKind.speed, true, {'speed'}),
  // vendorCloud: same rules as above.
  (SourceKind.vendorCloud, StreamKind.gps, true, {'gps'}),
  (SourceKind.vendorCloud, StreamKind.gps, false, {}),
  (SourceKind.vendorCloud, StreamKind.heartRate, true, {}),
  (SourceKind.vendorCloud, StreamKind.altitude, true, {'altitude'}),
];

void main() {
  group('U24 cloud stream column', () {
    for (final row in _matrix) {
      final (kind, data, consent, expected) = row;
      test('${kind.name} / ${data.name} / consent ${consent ? 'on' : 'off'}', () {
        final s = _session(kind, {data});
        final allowed = consent ? {...StreamKind.values} : <StreamKind>{};
        expect(_cloudKinds(s, allowed), expected);
      });
    }

    test('the payload text never carries the HR sentinel, for any source kind',
        () {
      for (final kind in SourceKind.values) {
        final s = _session(kind, {...StreamKind.values});
        final text = jsonEncode(ActivityStreamPayload.fromSession(s,
                allowedKinds: {...StreamKind.values})
            .toJson());
        expect(text, isNot(contains('161.75')), reason: kind.name);
        expect(text, isNot(contains('heartRate')), reason: kind.name);
        expect(text, isNot(contains('avgHrBpm')), reason: kind.name);
      }
    });

    test('with every kind listed only gps, altitude and speed ever go out', () {
      for (final kind in SourceKind.values) {
        final s = _session(kind, {...StreamKind.values});
        expect(_cloudKinds(s, {...StreamKind.values}), {'gps', 'altitude', 'speed'},
            reason: kind.name);
        expect(_cloudKinds(s, <StreamKind>{}), isEmpty, reason: kind.name);
      }
    });
  });

  group('U24 cloud summary column', () {
    test('scalars only, never an HR key, for every source kind', () {
      for (final kind in SourceKind.values) {
        final s = _session(kind, {...StreamKind.values});
        final sum = ActivityCloudSummary.fromSession(s);
        expect(sum.containsKey('avgHrBpm'), isFalse, reason: kind.name);
        expect(sum.containsKey('maxHrBpm'), isFalse, reason: kind.name);
        expect(sum['distanceM'], 3000, reason: 'non-HR scalars are sent');
        expect(sum['hasRoute'], true);
      }
    });
  });
}
