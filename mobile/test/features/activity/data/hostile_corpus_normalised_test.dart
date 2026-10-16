// S02-01 U40: the HOSTILE / future-schema set against its committed expected
// NORMALISED state. Independent of U01, U27 and U28.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/activity_migration.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/s02_paths.dart';
import '../../../support/synthetic_activity_corpus.dart';
import '../../../support/synthetic_hostile_corpus.dart';

List<String> _sorted(Iterable<String> k) => k.toList()..sort();

/// The normalised view that the expected file pins.
Map<String, Object?> _normalise(ActivitySession s) => {
      'sport': s.sport.name,
      'schema': s.schema,
      'readOnly': s.isReadOnly,
      'streams': _sorted(s.streams.keys.map((k) => k.name)),
      'diagnostics': s.readDiagnostics,
      'topExtras': _sorted(s.extras.keys),
      'unknownSport': s.extras[ActivitySession.unknownSportKey],
      'summaryExtras': _sorted(s.summary.extras.keys),
      'lapExtras': _sorted({for (final l in s.laps) ...l.extras.keys}),
      'sourceExtras': _sorted({for (final p in s.provenance) ...p.extras.keys}),
    };

void main() {
  final hostile = SyntheticHostile.build();
  final expected = jsonDecode(supportFile('synthetic_hostile_expected.json').readAsStringSync())
      as Map<String, dynamic>;

  test('the expected file covers exactly the named records', () {
    expect(_sorted(expected.keys.where((k) => k != 'comment')), _sorted(hostile.named.keys));
    expect(hostile.named, hasLength(9));
  });

  for (final name in hostile.named.keys) {
    test('$name reads to its committed normalised state and differs from its source',
        () {
      final raw = hostile.named[name]!;
      final s = ActivityMigration.read(raw);
      expect(s, isNotNull, reason: name);
      expect(canonicalJson(_normalise(s!)), canonicalJson(expected[name]), reason: name);
      // A reader that returned its input unchanged would equal the source.
      expect(canonicalJson(s.toJson()), isNot(canonicalJson(raw)), reason: name);
    });
  }

  test('H-1 keeps the session, drops only the non-monotonic stream, raises a diagnostic',
      () {
    final s = ActivityMigration.read(hostile.named['H-1']!)!;
    expect(s.streams.keys.map((k) => k.name), ['heartRate']);
    expect(s.readDiagnostics, ['streamDropped:gps']);
    expect(s.summary.distanceM, 5000.0);
    expect(s.laps, hasLength(1));
    expect(ActivityCloudSummary.fromSession(s)['hasRoute'], false);
  });

  test('future-schema records are read-only and a write attempt emits nothing', () {
    for (final n in const ['H-2a', 'H-2b', 'H-6']) {
      final s = ActivityMigration.read(hostile.named[n]!)!;
      expect(s.toWritableJson(), isNull, reason: n);
      expect(s.toJson()['schema'], hostile.named[n]!['schema'], reason: n);
      expect(() => ActivityCloudSummary.fromSession(s), throwsStateError, reason: n);
      expect(canonicalJson(s.toJson()['futureTopLevel']),
          canonicalJson(hostile.named[n]!['futureTopLevel']), reason: n);
    }
  });

  test('unknown sport strings become other and the cloud summary neither '
      'carries the original string nor any unknown key', () {
    for (final n in const ['H-3a', 'H-3b', 'H-3c', 'H-3d', 'H-4']) {
      final s = ActivityMigration.read(hostile.named[n]!)!;
      final cloud = ActivityCloudSummary.fromSession(s);
      expect(cloud.keys.every(kSummaryAllowedKeys.contains), isTrue, reason: n);
      final text = jsonEncode(cloud, toEncodable: (o) => (o as DateTime).toIso8601String());
      for (final bad in const ['futureSport7', 'kiteSurfing', 'Yoga', 'ultra-trail',
        'sessionExtra', 'summaryExtra', 'lapExtra', 'sourceExtra', 'vendor-field']) {
        expect(text.contains(bad), isFalse, reason: '$n leaks $bad');
      }
      expect(cloud['sport'], s.sport.name);
    }
  });

  test('the stored form of a normalised record is stable (read twice)', () {
    for (final n in hostile.named.keys) {
      final once = ActivityMigration.read(hostile.named[n]!)!;
      final twice = ActivityMigration.read(once.toJson())!;
      // Diagnostics describe a read and are deliberately not persisted.
      expect(canonicalJson({..._normalise(twice), 'diagnostics': null}),
          canonicalJson({..._normalise(once), 'diagnostics': null}), reason: n);
      expect(twice.readDiagnostics, isEmpty);
    }
  });

  test('the hostile set is disjoint from the 100 valid ids', () {
    final valid = SyntheticCorpus.build().valid.map((s) => s.id).toSet();
    expect(valid.intersection(hostile.namedIds.toSet()), isEmpty);
    expect(hostile.namedIds.toSet(), hasLength(9));
  });
}
