// S02-01 U01: exact round trip of the 100 VALID corpus sessions. Compares
// field by field against the ORIGINAL constructed object (not against a second
// toJson), so a writer that drops a field and a reader that defaults it cannot
// agree on the loss.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_migration.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/synthetic_activity_corpus.dart';

void _expectSame(ActivitySession back, ActivitySession s) {
  final why = s.id;
  expect(back.id, s.id, reason: why);
  expect(back.sport, s.sport, reason: why);
  expect(back.startUtc, s.startUtc, reason: why);
  expect(back.endUtc, s.endUtc, reason: why);
  expect(back.utcOffsetMinutes, s.utcOffsetMinutes, reason: why);
  expect(back.movingTimeS, s.movingTimeS, reason: why);
  expect(back.schema, s.schema, reason: why);
  // summary
  expect(back.summary.toFieldMap(), s.summary.toFieldMap(), reason: why);
  expect(back.summary.extras, s.summary.extras, reason: why);
  // streams, sample by sample
  expect(back.streams.keys.toSet(), s.streams.keys.toSet(), reason: why);
  for (final k in s.streams.keys) {
    final a = back.streams[k]!;
    final b = s.streams[k]!;
    expect(a.sourceId, b.sourceId, reason: '$why $k');
    expect(a.offsetsMs, b.offsetsMs, reason: '$why $k offsets');
    expect(a.values, b.values, reason: '$why $k values');
    expect(a.lats, b.lats, reason: '$why $k lats');
    expect(a.lons, b.lons, reason: '$why $k lons');
    expect(a.accuracies, b.accuracies, reason: '$why $k accuracies');
  }
  // laps
  expect(back.laps.length, s.laps.length, reason: why);
  for (var i = 0; i < s.laps.length; i++) {
    final a = back.laps[i];
    final b = s.laps[i];
    expect(
        [a.index, a.kind, a.startOffsetS, a.durationS, a.distanceM, a.avgHrBpm,
          a.strokeCount, a.strokeType],
        [b.index, b.kind, b.startOffsetS, b.durationS, b.distanceM, b.avgHrBpm,
          b.strokeCount, b.strokeType],
        reason: '$why lap $i');
    expect(a.extras, b.extras, reason: '$why lap $i extras');
  }
  // provenance
  expect(back.provenance.length, s.provenance.length, reason: why);
  for (var i = 0; i < s.provenance.length; i++) {
    final a = back.provenance[i];
    final b = s.provenance[i];
    expect(
        [a.sourceId, a.sourceKind, a.importedAt, a.deviceModel, a.appPackage,
          a.externalId, a.fieldsContributed.join(','), a.rawRef],
        [b.sourceId, b.sourceKind, b.importedAt, b.deviceModel, b.appPackage,
          b.externalId, b.fieldsContributed.join(','), b.rawRef],
        reason: '$why provenance $i');
  }
  // record state behind the summary
  expect(back.explicitValues, s.explicitValues, reason: why);
  expect(back.summaryOverrides, s.summaryOverrides, reason: why);
  expect(back.editHistory, s.editHistory, reason: why);
  expect(back.userEditCount, s.userEditCount, reason: why);
  expect(back.userEdits, s.userEdits, reason: why);
  expect(back.privacy.routeTrimMeters, s.privacy.routeTrimMeters, reason: why);
  expect(back.mergeNotes, s.mergeNotes, reason: why);
  expect(back.extras, s.extras, reason: why);
  expect(back.formulaVersion, s.formulaVersion, reason: why);
  expect(back.metricDefinitionVersion, s.metricDefinitionVersion, reason: why);
  expect(back.thresholdPolicyVersion, s.thresholdPolicyVersion, reason: why);
  expect(back.sourceTermsSnapshot, s.sourceTermsSnapshot, reason: why);
  expect(back.readDiagnostics, isEmpty, reason: why);
}

void main() {
  final corpus = SyntheticCorpus.build();

  group('U01 exact round trip of the 100 VALID sessions', () {
    test('the corpus under test is the valid set: 100 distinct ids, no hostile record',
        () {
      expect(corpus.valid, hasLength(100));
      expect({for (final s in corpus.valid) s.id}, hasLength(100));
      for (final s in corpus.valid) {
        expect(s.schema, lessThanOrEqualTo(2));
        expect(s.extras, isEmpty);
        expect(s.isReadOnly, isFalse);
        for (final st in s.streams.values) {
          for (var i = 1; i < st.offsetsMs.length; i++) {
            expect(st.offsetsMs[i], greaterThan(st.offsetsMs[i - 1]));
          }
        }
      }
    });

    test('the round trip is not vacuous: the corpus exercises every part', () {
      final v = corpus.valid;
      expect(v.where((s) => s.streams.containsKey(StreamKind.gps)), isNotEmpty);
      expect(v.where((s) => s.laps.isNotEmpty), isNotEmpty);
      expect(v.where((s) => s.explicitValues.isNotEmpty), isNotEmpty);
      expect(v.where((s) => s.summaryOverrides.isNotEmpty), isNotEmpty);
      expect(v.where((s) => s.editHistory.isNotEmpty), isNotEmpty);
      expect(v.where((s) => s.userEditCount == 64), isNotEmpty);
      expect(v.where((s) => s.sourceTermsSnapshot != null), isNotEmpty);
      expect(v.where((s) => s.userEdits.isNotEmpty), isNotEmpty);
      expect(v.where((s) => s.mergeNotes.isNotEmpty), isNotEmpty);
      expect(v.where((s) => s.provenance.length >= 2), isNotEmpty);
    });

    test('tryFromJson(migrate(toJson(s))) equals s, in memory and through JSON text',
        () {
      final schema1Ids = corpus.schema1Maps.keys.toSet();
      expect(schema1Ids, hasLength(5));
      for (final original in corpus.valid) {
        // For the 5 schema-1 records `s` is the object loaded from the schema-1
        // map (the map itself is U02).
        final s = schema1Ids.contains(original.id)
            ? ActivityMigration.read(corpus.schema1Maps[original.id])!
            : original;
        final direct = ActivitySession.tryFromJson(
            ActivityMigration.migrate(s.toJson()));
        expect(direct, isNotNull, reason: s.id);
        _expectSame(direct!, s);
        expect(direct, s, reason: s.id);
        final viaText = ActivitySession.tryFromJson(ActivityMigration.migrate(
            jsonDecode(jsonEncode(s.toJson()))));
        expect(viaText, isNotNull, reason: s.id);
        _expectSame(viaText!, s);
      }
    });

    test('a lost field would be caught: dropping userEditCount or a stream '
        'sample changes the comparison (negative control)', () {
      final s = corpus.valid.firstWhere((s) => s.userEditCount == 64);
      final tampered = Map<String, dynamic>.from(s.toJson())..['userEditCount'] = 3;
      final back = ActivitySession.tryFromJson(ActivityMigration.migrate(tampered))!;
      expect(back.userEditCount, isNot(s.userEditCount));
      expect(back == s, isFalse);
      final withGps = corpus.valid.firstWhere((x) => x.streams.containsKey(StreamKind.gps));
      final m = deepCopyJson(withGps.toJson());
      final streams = m['streams'] as List;
      final gps = streams.firstWhere((e) => e['kind'] == 'gps') as Map;
      (gps['lats'] as List)[0] = 1.0;
      final back2 = ActivitySession.tryFromJson(ActivityMigration.migrate(m))!;
      expect(back2 == withGps, isFalse);
    });
  });
}

Map<String, dynamic> deepCopyJson(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
