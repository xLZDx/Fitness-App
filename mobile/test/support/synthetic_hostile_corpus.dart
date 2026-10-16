// The HOSTILE / future-schema set (S02 test plan 2.4, MAJOR-03). Test-only,
// pure, deterministic, SEPARATE from the 100 valid sessions: nothing here is
// ever mixed into the valid corpus, and the maps are hand-built literals (no
// production serialiser), so a reader bug cannot hide in the fixture.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_versions.dart';

import 'synthetic_activity_corpus.dart';

/// One of the 20 hostile maps with its literal expectation: does the tolerant
/// reader load it (`true`) or reject it (`false`).
class HostileCase {
  const HostileCase(this.name, this.raw, {required this.loads});

  final String name;
  final Object? raw;
  final bool loads;
}

String _hexId(int n) => 'act_${n.toRadixString(16).padLeft(40, '0')}';

/// A small, fully valid schema-2 stored map.
Map<String, dynamic> hostileBaseMap(int n, {int schema = 2}) => _loose({
      'id': _hexId(0xA000 + n),
      'sport': 'running',
      'startUtc': '2026-03-01T06:00:00.000Z',
      'endUtc': '2026-03-01T06:30:00.000Z',
      'utcOffsetMinutes': 60,
      'movingTimeS': 1700.0,
      'summary': {'distanceM': 5000.0, 'avgHrBpm': 150.25},
      'streams': [
        {
          'kind': 'gps',
          'unit': 'deg',
          'sourceId': 'phone',
          'offsetsMs': [0, 1000, 2000],
          'lats': [1.5000007351, 1.5000107351, 1.5000207351],
          'lons': [-27.5, -27.4999, -27.4998],
        },
        {
          'kind': 'heartRate',
          'unit': 'bpm',
          'sourceId': 'strap',
          'offsetsMs': [0, 1000, 2000],
          'values': [120.25, 121.25, 122.25],
        },
      ],
      'laps': [
        {
          'index': 0,
          'kind': 'auto',
          'startOffsetS': 0.0,
          'durationS': 300.0,
          'distanceM': 1000.0,
        },
      ],
      'provenance': [
        {
          'sourceId': 'garmin-connect',
          'sourceKind': 'vendorCloud',
          'importedAt': '2026-03-01T07:00:00.000Z',
          'externalId': 'h-$n',
          'fieldsContributed': ['distanceM'],
        },
      ],
      'userEdits': <String, dynamic>{},
      'privacy': {'routeTrimMeters': 200.0},
      'schema': schema,
      'mergeNotes': <String>[],
      'formulaVersion': kFormulaVersion,
      'metricDefinitionVersion': kMetricDefinitionVersion,
      'thresholdPolicyVersion': kThresholdPolicyVersion,
      'userEditCount': 0,
    });

/// Round-trips a literal through JSON so every nested map is a plain
/// `Map<String, dynamic>` (tests then add keys of any type to it).
Map<String, dynamic> _loose(Map<String, Object?> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

/// Minimal future-schema record (no defaulted keys), so a reader that returns
/// its input unchanged cannot equal the normalised output.
Map<String, dynamic> _minimalFuture(int n, int schema) => _loose({
      'id': _hexId(0xB000 + n),
      'sport': 'cycling',
      'startUtc': '2026-04-01T06:00:00.000Z',
      'endUtc': '2026-04-01T07:00:00.000Z',
      'schema': schema,
      'summary': {
        'distanceM': 20000.0,
        'aiCoachScore': 7,
      },
      'futureTopLevel': {
        'nested': [1, 2, 3],
        'flag': true,
      },
      'laps': [
        {
          'index': 0,
          'kind': 'auto',
          'startOffsetS': 0.0,
          'durationS': 600.0,
          'lapFuture': 'x',
        },
      ],
      'provenance': [
        {
          'sourceId': 'garmin-connect',
          'sourceKind': 'vendorCloud',
          'importedAt': '2026-04-01T08:00:00.000Z',
          'sourceFuture': 9,
        },
      ],
    });

class SyntheticHostile {
  SyntheticHostile._(this.named, this.maps20);

  /// The 9 named records: H-1 (1), H-2 (2), H-3 (4), H-4 (1), H-6 (schema 99).
  final Map<String, Map<String, dynamic>> named;

  /// The 20 hostile maps (H-5).
  final List<HostileCase> maps20;

  /// The ids of the named records (disjoint from the valid ids).
  List<String> get namedIds => [for (final m in named.values) m['id'] as String];

  String canonical() => canonicalJson({
        'named': named,
        'maps20': [
          for (final c in maps20) {'name': c.name, 'raw': c.raw, 'loads': c.loads},
        ],
      });

  String digest() => sha256Hex(canonical());

  static SyntheticHostile? _cached;

  static SyntheticHostile build() => _cached ??= _build();

  static SyntheticHostile buildFresh() => _build();
}

SyntheticHostile _build() {
  final named = <String, Map<String, dynamic>>{};

  // H-1: a stream with non-monotonic offsets inside an otherwise valid session.
  final h1 = hostileBaseMap(1);
  (h1['streams'] as List)[0] = {
    'kind': 'gps',
    'unit': 'deg',
    'sourceId': 'phone',
    'offsetsMs': [0, 2000, 1000],
    'lats': [1.5000007351, 1.5000107351, 1.5000207351],
    'lons': [-27.5, -27.4999, -27.4998],
  };
  named['H-1'] = h1;

  // H-2: two future-schema records.
  named['H-2a'] = _minimalFuture(1, 3);
  named['H-2b'] = _minimalFuture(2, 3)..['futureTopLevel'] = 'a string now';

  // H-3: four unknown sport strings.
  const unknown = ['futureSport7', 'kiteSurfing', 'Yoga', 'ultra-trail'];
  for (var k = 0; k < unknown.length; k++) {
    named['H-3${String.fromCharCode(97 + k)}'] =
        hostileBaseMap(10 + k)..['sport'] = unknown[k];
  }

  // H-4: unknown extra keys at session, summary, lap and source level.
  final h4 = hostileBaseMap(20);
  h4['sessionExtra'] = {'k': 'v'};
  (h4['summary'] as Map)['summaryExtra'] = 42;
  ((h4['laps'] as List)[0] as Map)['lapExtra'] = [1, 2];
  ((h4['provenance'] as List)[0] as Map)['sourceExtra'] = 'vendor-field';
  named['H-4'] = h4;

  // H-6: a schema 99 record (U03 companion).
  named['H-6'] = _minimalFuture(3, 99)..['unknownAtNinetyNine'] = {'deep': {'er': 1}};

  final deep = <String, dynamic>{};
  var cursor = deep;
  for (var k = 0; k < 200; k++) {
    final next = <String, dynamic>{};
    cursor['n'] = next;
    cursor = next;
  }

  Map<String, dynamic> base(int n) => hostileBaseMap(100 + n);

  final maps20 = <HostileCase>[
    const HostileCase('not-a-map-string', 'not a map', loads: false),
    const HostileCase('not-a-map-int', 42, loads: false),
    const HostileCase('null', null, loads: false),
    const HostileCase('list', <Object?>[1, 2], loads: false),
    const HostileCase('empty-map', <String, dynamic>{}, loads: false),
    HostileCase('id-is-int', base(6)..['id'] = 17, loads: false),
    HostileCase('start-missing', base(7)..remove('startUtc'), loads: false),
    HostileCase('start-garbage', base(8)..['startUtc'] = 'not-a-date', loads: false),
    HostileCase(
        'end-before-start',
        base(9)
          ..['endUtc'] = '2026-03-01T05:00:00.000Z',
        loads: false),
    HostileCase('bad-id-object', base(10)..['id'] = {'x': 1}, loads: false),
    HostileCase(
        'wrong-types-everywhere',
        base(11)
          ..['summary'] = 'str'
          ..['streams'] = 'str'
          ..['laps'] = 5
          ..['provenance'] = {}
          ..['privacy'] = 7
          ..['mergeNotes'] = 'x'
          ..['userEdits'] = [1]
          ..['utcOffsetMinutes'] = 'a'
          ..['movingTimeS'] = 'b'
          ..['explicitValues'] = 5
          ..['summaryOverrides'] = <Object?>[]
          ..['editHistory'] = 'x'
          ..['userEditCount'] = 'many',
        loads: true),
    HostileCase('unknown-sport', base(12)..['sport'] = 'futureSport7', loads: true),
    HostileCase(
        'unknown-stream-kind',
        base(13)
          ..['streams'] = [
            {
              'kind': 'teleport',
              'sourceId': 'x',
              'offsetsMs': [0, 1],
              'values': [1.0, 2.0],
            },
          ],
        loads: true),
    HostileCase(
        'summary-1e308',
        base(14)..['summary'] = {'distanceM': 1e308, 'avgSpeedMps': -1e308},
        loads: true),
    HostileCase(
        'huge-list',
        base(15)..['laps'] = List<Object?>.generate(30000, (i) => i),
        loads: true),
    HostileCase('schema-banana', base(16)..['schema'] = 'banana', loads: true),
    HostileCase('schema-negative', base(17)..['schema'] = -5, loads: true),
    HostileCase(
        'schema-infinite', base(18)..['schema'] = double.infinity, loads: true),
    HostileCase(
        'counter-huge-and-int-keys',
        <dynamic, dynamic>{...base(19), 'userEditCount': 999999, 1: 'int key'},
        loads: true),
    HostileCase('deep-nesting', base(20)..['deepExtra'] = deep, loads: true),
  ];
  return SyntheticHostile._(named, maps20);
}
