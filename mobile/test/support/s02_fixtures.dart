// Small hand-built fixtures shared by the S02 Dart unit tests. Test-only.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';

const String kMiniId = 'act_0000000000000000000000000000000000000001';

final DateTime kMiniStart = DateTime.utc(2026, 5, 1, 6);

/// A small session without streams; `distanceM` and `movingTimeS` are the
/// fields most override tests move.
ActivitySession miniSession({
  String id = kMiniId,
  SportType sport = SportType.running,
  double? distanceM = 4800,
  double? movingTimeS = 1700,
  double? ascentM,
  Map<StreamKind, SampleStream> streams = const {},
  List<Lap> laps = const [],
  List<SourceRecord> provenance = const [],
  List<String> mergeNotes = const [],
}) =>
    ActivitySession(
      id: id,
      sport: sport,
      startUtc: kMiniStart,
      endUtc: kMiniStart.add(const Duration(minutes: 30)),
      movingTimeS: movingTimeS,
      summary: ActivitySummary(distanceM: distanceM, ascentM: ascentM),
      streams: streams,
      laps: laps,
      provenance: provenance,
      mergeNotes: mergeNotes,
    );

/// `jsonEncode` of a cloud summary (DateTime values become ISO strings).
String jsonSummary(Map<String, Object?> summary) => jsonEncode(
      summary,
      toEncodable: (o) {
        if (o is DateTime) return o.toUtc().toIso8601String();
        throw ArgumentError('unexpected value ${o.runtimeType} in a summary');
      },
    );

/// A deep copy of a JSON-like map through the wire format.
Map<String, dynamic> deepCopy(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

SourceRecord miniSource({
  String sourceId = 'garmin-connect',
  SourceKind kind = SourceKind.vendorCloud,
  String? externalId = 'e1',
}) =>
    SourceRecord(
      sourceId: sourceId,
      sourceKind: kind,
      importedAt: DateTime.utc(2026, 5, 1, 7),
      externalId: externalId,
      fieldsContributed: const ['distanceM'],
    );
