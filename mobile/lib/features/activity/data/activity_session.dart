/// One activity session, sport-agnostic (design s31.1). Pure Dart, no Flutter
/// imports.
///
/// All times are UTC; `utcOffsetMinutes` is stored for display only. Units are
/// canonical SI and are never converted here.
///
/// Schema 2 (S02 design 3.3) adds the A-5 provenance strings and the record
/// state behind the cloud summary (`explicitValues`, `summaryOverrides`, the
/// saturating `userEditCount` and the edit history ring). A record whose
/// schema is above [kActivitySchema] is read-only: it keeps every unknown key
/// and is never written back at a lower schema.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'activity_summary.dart';
import 'activity_versions.dart';
import 'lap.dart';
import 'sample_stream.dart';
import 'source_record.dart';
import 'sport_type.dart';
import 'summary_fields.dart';
import 'summary_overrides.dart';

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
    this.schema = kActivitySchema,
    List<String> mergeNotes = const [],
    Map<String, dynamic> extras = const {},
    this.formulaVersion = kFormulaVersion,
    this.metricDefinitionVersion = kMetricDefinitionVersion,
    this.thresholdPolicyVersion = kThresholdPolicyVersion,
    this.sourceTermsSnapshot,
    Map<String, ExplicitValue> explicitValues = const {},
    Map<String, SummaryOverride> summaryOverrides = const {},
    int userEditCount = 0,
    List<EditHistoryEntry> editHistory = const [],
    List<String> readDiagnostics = const [],
  })  : startUtc = startUtc.toUtc(),
        endUtc = endUtc.toUtc(),
        streams = Map.unmodifiable(streams),
        laps = List.unmodifiable(laps),
        provenance = List.unmodifiable(provenance),
        userEdits = Map.unmodifiable(userEdits),
        mergeNotes = List.unmodifiable(mergeNotes),
        extras = Map.unmodifiable(extras),
        explicitValues = Map.unmodifiable(explicitValues),
        summaryOverrides = Map.unmodifiable(summaryOverrides),
        userEditCount = userEditCount < 0
            ? 0
            : (userEditCount > kUserEditCountCap
                ? kUserEditCountCap
                : userEditCount),
        editHistory = List.unmodifiable(trimEditHistory(editHistory)),
        readDiagnostics = List.unmodifiable(readDiagnostics);

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

  /// A-5 calculation versions the record was derived under.
  final String formulaVersion;
  final String metricDefinitionVersion;
  final String thresholdPolicyVersion;

  /// A-5 terms-version id or hash; never the terms text.
  final String? sourceTermsSnapshot;

  /// Canonical user-chosen values, at most one per summary field. The ONLY
  /// input of the summary projection besides the raw derivation (design 3.2).
  final Map<String, ExplicitValue> explicitValues;

  /// Cloud values adopted for derived fields (design 3.2 rule 1).
  final Map<String, SummaryOverride> summaryOverrides;

  /// Saturating number of explicit edit operations, capped at 64.
  final int userEditCount;

  /// Device-only history ring (newest 64), informational; never read by the
  /// projection.
  final List<EditHistoryEntry> editHistory;

  /// Problems met while reading (not serialised, not part of equality), e.g.
  /// `streamDropped:gps`.
  final List<String> readDiagnostics;

  int get durationMs => endUtc.difference(startUtc).inMilliseconds;

  /// True for a record written by a newer app (schema above [kActivitySchema]).
  /// Such a record is never written back by this build.
  bool get isReadOnly => schema > kActivitySchema;

  /// The calculation versions this record is derived under.
  CalcVersions get calcVersions => CalcVersions(
        formulaVersion: formulaVersion,
        metricDefinitionVersion: metricDefinitionVersion,
        thresholdPolicyVersion: thresholdPolicyVersion,
      );

  /// Pace is derived, never stored: seconds per kilometre from the average
  /// speed, or null without one.
  double? get paceSecPerKm {
    final v = summary.avgSpeedMps;
    return v == null || v <= 0 ? null : 1000 / v;
  }

  ActivitySession copyWith({
    SportType? sport,
    double? movingTimeS,
    ActivitySummary? summary,
    Map<StreamKind, SampleStream>? streams,
    List<Lap>? laps,
    List<SourceRecord>? provenance,
    Map<String, Object?>? userEdits,
    ActivityPrivacy? privacy,
    int? schema,
    List<String>? mergeNotes,
    Map<String, dynamic>? extras,
    CalcVersions? versions,
    String? sourceTermsSnapshot,
    Map<String, ExplicitValue>? explicitValues,
    Map<String, SummaryOverride>? summaryOverrides,
    int? userEditCount,
    List<EditHistoryEntry>? editHistory,
  }) =>
      ActivitySession(
        id: id,
        sport: sport ?? this.sport,
        startUtc: startUtc,
        endUtc: endUtc,
        utcOffsetMinutes: utcOffsetMinutes,
        movingTimeS: movingTimeS ?? this.movingTimeS,
        summary: summary ?? this.summary,
        streams: streams ?? this.streams,
        laps: laps ?? this.laps,
        provenance: provenance ?? this.provenance,
        userEdits: userEdits ?? this.userEdits,
        privacy: privacy ?? this.privacy,
        schema: schema ?? this.schema,
        mergeNotes: mergeNotes ?? this.mergeNotes,
        extras: extras ?? this.extras,
        formulaVersion: versions?.formulaVersion ?? formulaVersion,
        metricDefinitionVersion:
            versions?.metricDefinitionVersion ?? metricDefinitionVersion,
        thresholdPolicyVersion:
            versions?.thresholdPolicyVersion ?? thresholdPolicyVersion,
        sourceTermsSnapshot: sourceTermsSnapshot ?? this.sourceTermsSnapshot,
        explicitValues: explicitValues ?? this.explicitValues,
        summaryOverrides: summaryOverrides ?? this.summaryOverrides,
        userEditCount: userEditCount ?? this.userEditCount,
        editHistory: editHistory ?? this.editHistory,
        readDiagnostics: readDiagnostics,
      );

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
    'formulaVersion',
    'metricDefinitionVersion',
    'thresholdPolicyVersion',
    'sourceTermsSnapshot',
    'explicitValues',
    'summaryOverrides',
    'userEditCount',
    'editHistory',
  };

  /// Extras key that keeps the original text of an unknown sport name.
  static const String unknownSportKey = 'unknownSport';

  /// The record as stored. A record read at a schema above [kActivitySchema]
  /// keeps its own schema number here (never lowered); use [toWritableJson]
  /// to persist.
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
        'formulaVersion': formulaVersion,
        'metricDefinitionVersion': metricDefinitionVersion,
        'thresholdPolicyVersion': thresholdPolicyVersion,
        if (sourceTermsSnapshot != null)
          'sourceTermsSnapshot': sourceTermsSnapshot,
        if (explicitValues.isNotEmpty)
          'explicitValues':
              encodeSorted<ExplicitValue>(explicitValues, (e) => e.toJson()),
        if (summaryOverrides.isNotEmpty)
          'summaryOverrides':
              encodeSorted<SummaryOverride>(summaryOverrides, (e) => e.toJson()),
        'userEditCount': userEditCount,
        if (editHistory.isNotEmpty)
          'editHistory': [for (final e in editHistory) e.toJson()],
      };

  /// The map to persist, or null for a read-only (newer-schema) record, which
  /// must never be rewritten by this build.
  Map<String, dynamic>? toWritableJson() => isReadOnly ? null : toJson();

  /// Tolerant read: an unknown sport degrades to `other` (the original text is
  /// kept in [extras]), unknown keys are kept in [extras], invalid streams are
  /// dropped with a diagnostic. Null when the id or the times are unreadable or
  /// the end precedes the start. Run `ActivityMigration.migrate` first for
  /// older schemas.
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
    final diagnostics = <String>[];
    final streams = <StreamKind, SampleStream>{};
    final rawStreams = raw['streams'];
    for (final s in (rawStreams is List ? rawStreams : const [])) {
      final parsed = SampleStream.tryFromJson(s);
      if (parsed != null) {
        streams[parsed.kind] = parsed;
      } else {
        final kind = s is Map ? s['kind'] : null;
        diagnostics.add('streamDropped:${kind is String ? kind : 'unknown'}');
      }
    }
    final edits = raw['userEdits'];
    final extras = <String, dynamic>{
      for (final e in raw.entries)
        if (!_knownKeys.contains(e.key)) e.key.toString(): e.value,
    };
    final sportRaw = raw['sport'];
    final sport = SportType.parse(sportRaw);
    if (sportRaw is String && sportRaw != sport.name) {
      extras[unknownSportKey] = sportRaw;
    }
    String version(Object? v, String fallback) =>
        v is String && kVersionStringPattern.hasMatch(v) ? v : fallback;
    final terms = raw['sourceTermsSnapshot'];
    final counter = raw['userEditCount'];
    return ActivitySession(
      id: id,
      sport: sport,
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
        for (final l in (raw['laps'] is List ? raw['laps'] as List : const []))
          if (Lap.tryFromJson(l) case final lap?) lap,
      ],
      provenance: [
        for (final p
            in (raw['provenance'] is List ? raw['provenance'] as List : const []))
          if (SourceRecord.tryFromJson(p) case final rec?) rec,
      ],
      userEdits: edits is Map
          ? {for (final e in edits.entries) e.key.toString(): e.value}
          : const {},
      privacy: ActivityPrivacy.fromJson(raw['privacy']),
      schema: raw['schema'] is num ? (raw['schema'] as num).toInt() : 1,
      mergeNotes: [
        for (final n
            in (raw['mergeNotes'] is List ? raw['mergeNotes'] as List : const []))
          if (n is String) n,
      ],
      extras: extras,
      formulaVersion: version(raw['formulaVersion'], kFormulaVersion),
      metricDefinitionVersion:
          version(raw['metricDefinitionVersion'], kMetricDefinitionVersion),
      thresholdPolicyVersion:
          version(raw['thresholdPolicyVersion'], kThresholdPolicyVersion),
      sourceTermsSnapshot:
          terms is String && kSourceTermsPattern.hasMatch(terms) ? terms : null,
      explicitValues: readExplicitValues(raw['explicitValues']),
      summaryOverrides: readSummaryOverrides(raw['summaryOverrides']),
      userEditCount: counter is num && counter.isFinite ? counter.toInt() : 0,
      editHistory: readEditHistory(raw['editHistory']),
      readDiagnostics: diagnostics,
    );
  }

  /// Deep equality by canonical JSON (deterministic key and list order).
  @override
  bool operator ==(Object other) =>
      other is ActivitySession && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}
