/// One activity session, sport-agnostic (design s31.1). Pure Dart, no Flutter
/// imports.
///
/// All times are UTC; `utcOffsetMinutes` is stored for display only. Units are
/// canonical SI and are never converted here.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'activity_summary.dart';
import 'lap.dart';
import 'sample_stream.dart';
import 'source_record.dart';
import 'sport_type.dart';

/// Privacy settings of a session (design 31.4): GPS is sensitive, so shared or
/// exported views trim this many metres from both ends of a route.
class ActivityPrivacy {
  const ActivityPrivacy({this.routeTrimMeters = defaultRouteTrimMeters});

  static const double defaultRouteTrimMeters = 200;

  final double routeTrimMeters;

  Map<String, dynamic> toJson() => {'routeTrimMeters': routeTrimMeters};

  static ActivityPrivacy fromJson(Object? raw) {
    if (raw is Map && raw['routeTrimMeters'] is num) {
      return ActivityPrivacy(
          routeTrimMeters: (raw['routeTrimMeters'] as num).toDouble());
    }
    return const ActivityPrivacy();
  }
}

/// The stable session id: `act_<sha1 of the canonical source key>`. The key is
/// `sourceId|externalId`, or `sourceId|start:<epoch ms>` when the source has no
/// external id. Identical across runs; differs when the external id differs.
String activityIdFor({
  required String sourceId,
  String? externalId,
  required DateTime startUtc,
}) {
  final key = externalId != null
      ? '$sourceId|$externalId'
      : '$sourceId|start:${startUtc.toUtc().millisecondsSinceEpoch}';
  return 'act_${sha1.convert(utf8.encode(key))}';
}

class ActivitySession {
  ActivitySession({
    required this.id,
    required this.sport,
    required DateTime startUtc,
    required DateTime endUtc,
    this.utcOffsetMinutes = 0,
    this.movingTimeS,
    this.summary = ActivitySummary.empty,
    Map<StreamKind, SampleStream> streams = const {},
    List<Lap> laps = const [],
    List<SourceRecord> provenance = const [],
    Map<String, Object?> userEdits = const {},
    this.privacy = const ActivityPrivacy(),
    this.schema = 1,
    List<String> mergeNotes = const [],
    Map<String, dynamic> extras = const {},
  })  : startUtc = startUtc.toUtc(),
        endUtc = endUtc.toUtc(),
        streams = Map.unmodifiable(streams),
        laps = List.unmodifiable(laps),
        provenance = List.unmodifiable(provenance),
        userEdits = Map.unmodifiable(userEdits),
        mergeNotes = List.unmodifiable(mergeNotes),
        extras = Map.unmodifiable(extras);

  final String id;
  final SportType sport;
  final DateTime startUtc;
  final DateTime endUtc;
  final int utcOffsetMinutes;
  final double? movingTimeS;
  final ActivitySummary summary;
  final Map<StreamKind, SampleStream> streams;
  final List<Lap> laps;
  final List<SourceRecord> provenance;

  /// Fields the user overrode (summary field name or `sport` -> value); they
  /// always win over any source on a re-merge.
  final Map<String, Object?> userEdits;
  final ActivityPrivacy privacy;
  final int schema;

  /// Human-neutral notes of the merge, e.g. `summaryDisagreement:distanceM`.
  final List<String> mergeNotes;

  /// Unknown JSON keys, kept so a round trip loses nothing.
  final Map<String, dynamic> extras;

  int get durationMs => endUtc.difference(startUtc).inMilliseconds;

  /// Pace is derived, never stored: seconds per kilometre from the average
  /// speed, or null without one.
  double? get paceSecPerKm {
    final v = summary.avgSpeedMps;
    return v == null || v <= 0 ? null : 1000 / v;
  }

  static const Set<String> _knownKeys = {
    'id',
    'sport',
    'startUtc',
    'endUtc',
    'utcOffsetMinutes',
    'movingTimeS',
    'summary',
    'streams',
    'laps',
    'provenance',
    'userEdits',
    'privacy',
    'schema',
    'mergeNotes',
  };

  Map<String, dynamic> toJson() => {
        ...extras,
        'id': id,
        'sport': sport.name,
        'startUtc': startUtc.toIso8601String(),
        'endUtc': endUtc.toIso8601String(),
        'utcOffsetMinutes': utcOffsetMinutes,
        if (movingTimeS != null) 'movingTimeS': movingTimeS,
        'summary': summary.toJson(),
        'streams': [
          for (final k in StreamKind.values)
            if (streams[k] != null) streams[k]!.toJson(),
        ],
        'laps': [for (final l in laps) l.toJson()],
        'provenance': [for (final p in provenance) p.toJson()],
        'userEdits': userEdits,
        'privacy': privacy.toJson(),
        'schema': schema,
        'mergeNotes': mergeNotes,
      };

  /// Tolerant read: an unknown sport degrades to `other`, unknown keys are
  /// kept in [extras], invalid streams are dropped. Null when the id or the
  /// times are unreadable or the end precedes the start.
  static ActivitySession? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final start = raw['startUtc'] is String
        ? DateTime.tryParse(raw['startUtc'] as String)
        : null;
    final end = raw['endUtc'] is String
        ? DateTime.tryParse(raw['endUtc'] as String)
        : null;
    if (id is! String || start == null || end == null || end.isBefore(start)) {
      return null;
    }
    final streams = <StreamKind, SampleStream>{};
    for (final s in (raw['streams'] as List?) ?? const []) {
      final parsed = SampleStream.tryFromJson(s);
      if (parsed != null) streams[parsed.kind] = parsed;
    }
    final edits = raw['userEdits'];
    return ActivitySession(
      id: id,
      sport: SportType.parse(raw['sport']),
      startUtc: start,
      endUtc: end,
      utcOffsetMinutes: raw['utcOffsetMinutes'] is num
          ? (raw['utcOffsetMinutes'] as num).toInt()
          : 0,
      movingTimeS:
          raw['movingTimeS'] is num ? (raw['movingTimeS'] as num).toDouble() : null,
      summary: ActivitySummary.fromJson(raw['summary']),
      streams: streams,
      laps: [
        for (final l in (raw['laps'] as List?) ?? const [])
          if (Lap.tryFromJson(l) case final lap?) lap,
      ],
      provenance: [
        for (final p in (raw['provenance'] as List?) ?? const [])
          if (SourceRecord.tryFromJson(p) case final rec?) rec,
      ],
      userEdits: edits is Map
          ? {for (final e in edits.entries) e.key.toString(): e.value}
          : const {},
      privacy: ActivityPrivacy.fromJson(raw['privacy']),
      schema: raw['schema'] is num ? (raw['schema'] as num).toInt() : 1,
      mergeNotes: [
        for (final n in (raw['mergeNotes'] as List?) ?? const [])
          if (n is String) n,
      ],
      extras: {
        for (final e in raw.entries)
          if (!_knownKeys.contains(e.key)) e.key.toString(): e.value,
      },
    );
  }

  /// Deep equality by canonical JSON (deterministic key and list order).
  @override
  bool operator ==(Object other) =>
      other is ActivitySession && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
