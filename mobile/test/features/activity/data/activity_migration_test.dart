// S02-01 U02 (schema 1 read), U03 (newer schema read-only), U04 (corrupt and
// unknown-schema tolerated, hostile set only), U12 (migration is total).
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/activity_migration.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/s02_fixtures.dart';
import '../../../support/synthetic_activity_corpus.dart';
import '../../../support/synthetic_hostile_corpus.dart';

void main() {
  final corpus = SyntheticCorpus.build();
  final hostile = SyntheticHostile.build();

  group('U02 schema 1 records load with the same summary values', () {
    test('a literal schema-1 map loads exactly and A-5 fields are defaulted', () {
      final map = <String, dynamic>{
        'id': 'act_1111111111111111111111111111111111111111',
        'sport': 'cycling',
        'startUtc': '2026-02-01T08:00:00.000Z',
        'endUtc': '2026-02-01T09:00:00.000Z',
        'utcOffsetMinutes': 120,
        'movingTimeS': 3500.0,
        'summary': {'distanceM': 25000.5, 'avgSpeedMps': 6.9, 'avgHrBpm': 140.25},
        'streams': <Object?>[],
        'laps': <Object?>[],
        'provenance': <Object?>[],
        'userEdits': {'distanceM': 25100.0},
        'privacy': {'routeTrimMeters': 300.0},
        'schema': 1,
        'mergeNotes': ['summaryDisagreement:distanceM'],
      };
      final before = jsonEncode(map);
      final s = ActivityMigration.read(map)!;
      expect(jsonEncode(map), before, reason: 'migrate must not mutate its input');
      expect(s.schema, 2);
      expect(s.sport, SportType.cycling);
      expect(s.summary.distanceM, 25000.5);
      expect(s.summary.avgSpeedMps, 6.9);
      expect(s.summary.avgHrBpm, 140.25);
      expect(s.movingTimeS, 3500.0);
      expect(s.utcOffsetMinutes, 120);
      expect(s.userEdits, {'distanceM': 25100.0});
      expect(s.privacy.routeTrimMeters, 300.0);
      expect(s.mergeNotes, ['summaryDisagreement:distanceM']);
      // A-5 fields defaulted to the literals of this build.
      expect(s.formulaVersion, 'formula-1');
      expect(s.metricDefinitionVersion, 'metrics-1');
      expect(s.thresholdPolicyVersion, 'thresholds-1');
      expect(s.sourceTermsSnapshot, isNull);
      expect(s.userEditCount, 0);
      expect(s.explicitValues, isEmpty);
      expect(s.summaryOverrides, isEmpty);
      expect(s.editHistory, isEmpty);
      expect(s.isReadOnly, isFalse);
    });

    test('invalid A-5 strings in a schema-1 map are replaced by the defaults', () {
      final map = <String, dynamic>{
        'id': 'act_2222222222222222222222222222222222222222',
        'sport': 'running',
        'startUtc': '2026-02-01T08:00:00.000Z',
        'endUtc': '2026-02-01T09:00:00.000Z',
        'schema': 1,
        'formulaVersion': 'has spaces and is far too long to be a version id',
        'metricDefinitionVersion': {'nested': 1},
        'thresholdPolicyVersion': '',
        'sourceTermsSnapshot': 'terms text with spaces',
      };
      final s = ActivityMigration.read(map)!;
      expect(s.formulaVersion, 'formula-1');
      expect(s.metricDefinitionVersion, 'metrics-1');
      expect(s.thresholdPolicyVersion, 'thresholds-1');
      expect(s.sourceTermsSnapshot, isNull);
    });

    test('the 5 corpus schema-1 records load with the original summary values',
        () {
      expect(corpus.schema1Maps, hasLength(5));
      for (final e in corpus.schema1Maps.entries) {
        final map = e.value;
        expect(map['schema'], 1);
        expect(map.containsKey('formulaVersion'), isFalse);
        expect(map.containsKey('userEditCount'), isFalse);
        final original = corpus.byId(e.key);
        final loaded = ActivityMigration.read(map)!;
        expect(loaded.schema, 2);
        expect(loaded.summary.toFieldMap(), original.summary.toFieldMap(),
            reason: e.key);
        expect(loaded.movingTimeS, original.movingTimeS);
        expect(loaded.laps.length, original.laps.length);
        expect(loaded.streams.length, original.streams.length);
        expect(loaded.provenance.length, original.provenance.length);
        expect(loaded.formulaVersion, 'formula-1');
        expect(loaded.metricDefinitionVersion, 'metrics-1');
        expect(loaded.thresholdPolicyVersion, 'thresholds-1');
        expect(loaded.userEditCount, 0);
        // The migrated record can be summarised for the cloud (rev 1).
        final cloud = ActivityCloudSummary.fromSession(loaded);
        expect(cloud['schema'], 2);
        expect(cloud['rev'], 1);
        expect(cloud['distanceM'], original.summary.distanceM);
      }
    });

    test('the schema chain is applied: a missing schema key reads as 1 and ends at 2',
        () {
      final m = <String, dynamic>{
        'id': 'act_3333333333333333333333333333333333333333',
        'startUtc': '2026-02-01T08:00:00.000Z',
        'endUtc': '2026-02-01T09:00:00.000Z',
      };
      expect(ActivityMigration.schemaOf(m), 1);
      final migrated = ActivityMigration.migrate(m);
      expect(migrated['schema'], 2);
      expect(migrated['formulaVersion'], 'formula-1');
      expect(migrated['userEditCount'], 0);
    });
  });

  group('U03 a newer schema is read-only', () {
    for (final name in const ['H-6', 'H-2a', 'H-2b']) {
      test('$name keeps every unknown key and is never written at a lower schema',
          () {
        final raw = hostile.named[name]!;
        final schema = raw['schema'] as int;
        expect(schema, greaterThan(2));
        final migrated = ActivityMigration.migrate(raw);
        expect(canonicalJson(migrated), canonicalJson(raw),
            reason: 'a newer record passes through migrate untouched');
        expect(migrated['schema'], schema);
        final s = ActivityMigration.read(raw)!;
        expect(s.isReadOnly, isTrue);
        expect(s.schema, schema);
        final stored = s.toJson();
        expect(stored['schema'], schema, reason: 'never lowered');
        for (final k in raw.keys) {
          if (const {'id', 'sport', 'startUtc', 'endUtc', 'schema', 'summary',
              'laps', 'provenance'}.contains(k)) {
            continue;
          }
          expect(stored.containsKey(k), isTrue, reason: 'unknown key $k lost');
          expect(canonicalJson(stored[k]), canonicalJson(raw[k]));
        }
        expect((raw['summary'] as Map).containsKey('aiCoachScore'), isTrue);
        expect(s.summary.extras['aiCoachScore'], 7);
        expect(s.laps.single.extras['lapFuture'], 'x');
        expect(s.provenance.single.extras['sourceFuture'], 9);
        // The writer refuses: no writable map, and no cloud summary.
        expect(s.toWritableJson(), isNull);
        expect(() => ActivityCloudSummary.fromSession(s), throwsStateError);
      });
    }

    test('schema 99 survives a full read-write cycle of its stored form', () {
      final raw = hostile.named['H-6']!;
      final first = ActivityMigration.read(raw)!;
      final again = ActivityMigration.read(first.toJson())!;
      expect(again.schema, 99);
      expect(canonicalJson(again.toJson()), canonicalJson(first.toJson()));
      expect(again.extras['unknownAtNinetyNine'], {'deep': {'er': 1}});
    });

    test('the current schema is writable (contrast)', () {
      final s = miniSession();
      expect(s.schema, 2);
      expect(s.isReadOnly, isFalse);
      expect(s.toWritableJson(), isNotNull);
    });
  });

  group('U04 corrupt and unknown-schema records are tolerated', () {
    test('the hostile set has exactly 20 maps and the expected load verdicts', () {
      expect(hostile.maps20, hasLength(20));
      expect(hostile.maps20.where((c) => !c.loads), hasLength(10));
    });

    for (final c in hostile.maps20) {
      test('migrate never throws and read matches the verdict: ${c.name}', () {
        late Map<String, dynamic> migrated;
        expect(() => migrated = ActivityMigration.migrate(c.raw), returnsNormally);
        expect(migrated, isA<Map<String, dynamic>>());
        ActivitySession? s;
        expect(() => s = ActivityMigration.read(c.raw), returnsNormally);
        expect(s != null, c.loads, reason: c.name);
      });
    }

    test('what the tolerant reader does with each loadable hostile map', () {
      ActivitySession read(String name) => ActivityMigration.read(
          hostile.maps20.firstWhere((c) => c.name == name).raw)!;
      final wrong = read('wrong-types-everywhere');
      expect(wrong.summary.toFieldMap().values.every((v) => v == null), isTrue);
      expect(wrong.streams, isEmpty);
      expect(wrong.laps, isEmpty);
      expect(wrong.provenance, isEmpty);
      expect(wrong.utcOffsetMinutes, 0);
      expect(wrong.movingTimeS, isNull);
      expect(wrong.userEditCount, 0);
      expect(wrong.explicitValues, isEmpty);

      final sport = read('unknown-sport');
      expect(sport.sport, SportType.other);
      expect(sport.extras['unknownSport'], 'futureSport7');

      final kind = read('unknown-stream-kind');
      expect(kind.streams, isEmpty);
      expect(kind.readDiagnostics, ['streamDropped:teleport']);

      final big = read('summary-1e308');
      expect(big.summary.distanceM, 1e308, reason: 'kept locally');
      final cloud = ActivityCloudSummary.fromSession(big);
      expect(cloud.containsKey('distanceM'), isFalse, reason: 'never above the rules bound');
      expect(cloud.containsKey('avgSpeedMps'), isFalse);

      expect(read('huge-list').laps, isEmpty);
      for (final n in const ['schema-banana', 'schema-negative', 'schema-infinite']) {
        expect(read(n).schema, 2, reason: n);
      }
      final counter = read('counter-huge-and-int-keys');
      expect(counter.userEditCount, 64);
      expect(counter.extras['1'], 'int key');
      final deep = read('deep-nesting');
      expect(deep.extras.containsKey('deepExtra'), isTrue);
    });

    test('a batch of 100 with 7 corrupt entries yields exactly 93 sessions', () {
      final corrupt = hostile.maps20.where((c) => !c.loads).take(7).map((c) => c.raw);
      final good = corpus.valid
          .where((s) => !corpus.schema1Maps.containsKey(s.id))
          .take(93)
          .map((s) => deepCopy(s.toJson()));
      final batch = <Object?>[...good, ...corrupt];
      SplitMix64(7).shuffle(batch);
      expect(batch, hasLength(100));
      final loaded = [
        for (final raw in batch)
          if (ActivityMigration.read(raw) case final s?) s,
      ];
      expect(loaded, hasLength(93));
      expect({for (final s in loaded) s.id}, hasLength(93));
    });
  });

  group('U12 migration is total (seeded fuzz of 1000 mutated maps)', () {
    // Small bases: the 100 valid records without their (large) streams, plus
    // the 5 stored schema-1 maps.
    final bases = <Map<String, dynamic>>[
      for (final s in corpus.valid)
        (deepCopy(corpus.schema1Maps[s.id] ?? s.toJson())..['streams'] = <Object?>[]),
    ];

    dynamic mutateValue(SplitMix64 r, dynamic v) {
      switch (r.nextInt(9)) {
        case 0:
          return null;
        case 1:
          return 'str${r.nextInt(100)}';
        case 2:
          return r.nextInt(1000) - 500;
        case 3:
          return [v];
        case 4:
          return {'x': v};
        case 5:
          return r.nextInt(2) == 0 ? double.nan : double.infinity;
        case 6:
          return 1e308;
        case 7:
          return true;
        default:
          return <Object?>[];
      }
    }

    void mutate(SplitMix64 r, Map<String, dynamic> m) {
      final keys = m.keys.toList();
      final key = keys[r.nextInt(keys.length)];
      switch (r.nextInt(4)) {
        case 0:
          m.remove(key);
        case 1:
          m[key] = mutateValue(r, m[key]);
        case 2:
          final inner = m[key];
          if (inner is Map && inner.isNotEmpty) {
            final ik = inner.keys.toList()[r.nextInt(inner.length)];
            if (r.nextInt(2) == 0) {
              inner.remove(ik);
            } else {
              inner[ik] = mutateValue(r, inner[ik]);
            }
          } else if (inner is List && inner.isNotEmpty) {
            final at = r.nextInt(inner.length);
            final elem = inner[at];
            if (elem is Map && elem.isNotEmpty) {
              final ik = elem.keys.toList()[r.nextInt(elem.length)];
              elem[ik] = mutateValue(r, elem[ik]);
            } else {
              inner[at] = mutateValue(r, elem);
            }
          } else {
            m[key] = mutateValue(r, inner);
          }
        default:
          // deeper nesting of a whole sub-tree
          var wrapped = m[key];
          for (var d = 0; d < 1 + r.nextInt(30); d++) {
            wrapped = {'n': wrapped};
          }
          m[key] = wrapped;
      }
      if (r.nextInt(4) == 0) {
        const schemas = <Object?>[0, -1, 1, 2, 3, 99, '2', null, 1.5, 1e308,
          double.nan, true, 'x'];
        m['schema'] = schemas[r.nextInt(schemas.length)];
      }
    }

    test('1000 mutants: no migrate step throws, output is a map at the right '
        'schema, newer records pass through, migrate is idempotent', () {
      final r = SplitMix64(kFuzzSeed);
      var oldSchemaInputs = 0, newerInputs = 0, tolerantReads = 0;
      for (var i = 0; i < 1000; i++) {
        final m = deepCopy(bases[r.nextInt(bases.length)]);
        for (var k = 0; k < 1 + r.nextInt(3); k++) {
          mutate(r, m);
        }
        final inputSchema = ActivityMigration.schemaOf(m);
        late Map<String, dynamic> out;
        try {
          out = ActivityMigration.migrate(m);
        } catch (e, st) {
          fail('migrate threw on mutant $i: $e\n$st');
        }
        if (inputSchema > 2) {
          newerInputs++;
          expect(canonicalJson(out), canonicalJson(m),
              reason: 'mutant $i: a newer record must pass through untouched');
        } else {
          oldSchemaInputs++;
          expect(out['schema'], 2, reason: 'mutant $i');
          if (inputSchema <= 1) {
            expect(out.containsKey('userEditCount'), isTrue, reason: 'mutant $i');
            expect(out['formulaVersion'], isA<String>(), reason: 'mutant $i');
          }
        }
        // idempotent
        expect(canonicalJson(ActivityMigration.migrate(out)), canonicalJson(out),
            reason: 'mutant $i');
        // the final stage never throws either
        try {
          final s = ActivitySession.tryFromJson(out);
          if (s != null) {
            tolerantReads++;
            expect(s.userEditCount, inInclusiveRange(0, 64));
            expect(s.editHistory.length, lessThanOrEqualTo(64));
          }
        } catch (e, st) {
          fail('tryFromJson threw on mutant $i: $e\n$st');
        }
      }
      // The fuzz must actually exercise the upgrade path and the pass-through.
      expect(oldSchemaInputs, greaterThan(500));
      expect(newerInputs, greaterThan(20));
      expect(tolerantReads, greaterThan(300));
    });

    test('the fuzz is deterministic: the same seed gives the same mutants', () {
      String run() {
        final r = SplitMix64(kFuzzSeed);
        final out = StringBuffer();
        for (var i = 0; i < 50; i++) {
          final m = deepCopy(bases[r.nextInt(bases.length)]);
          mutate(r, m);
          out.write(canonicalJson(ActivityMigration.migrate(m)));
        }
        return sha256Hex(out.toString());
      }

      expect(run(), run());
    });
  });
}
