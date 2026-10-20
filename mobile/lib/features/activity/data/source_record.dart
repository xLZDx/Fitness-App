/// Where one piece of an activity came from (design s31.1). Pure Dart, no
/// Flutter imports.
library;

import 'source_kind.dart';

class SourceRecord {
  const SourceRecord({
    required this.sourceId,
    required this.sourceKind,
    required this.importedAt,
    this.deviceModel,
    this.appPackage,
    this.externalId,
    this.fieldsContributed = const [],
    this.rawRef,
    this.extras = const {},
  });

  /// Unknown JSON keys, kept so a round trip loses nothing (S02 design 3.3).
  final Map<String, dynamic> extras;

  static const Set<String> _knownKeys = {
    'sourceId',
    'sourceKind',
    'importedAt',
    'deviceModel',
    'appPackage',
    'externalId',
    'fieldsContributed',
    'rawRef',
  };

  final String sourceId;
  final SourceKind sourceKind;
  final DateTime importedAt;
  final String? deviceModel;

  /// The recording app, e.g. the package of a watch app that wrote the workout
  /// into the platform health store (used for echo detection).
  final String? appPackage;
  final String? externalId;
  final List<String> fieldsContributed;

  /// Reference to the retained original per-source session, so a merge can be
  /// undone.
  final String? rawRef;

  /// `sourceId` + `externalId`: the idempotency key of a re-import.
  String? get dedupKey => externalId == null ? null : '$sourceId|$externalId';

  SourceRecord withFields(List<String> fields) => SourceRecord(
        sourceId: sourceId,
        sourceKind: sourceKind,
        importedAt: importedAt,
        deviceModel: deviceModel,
        appPackage: appPackage,
        externalId: externalId,
        fieldsContributed: fields,
        rawRef: rawRef,
        extras: extras,
      );

  Map<String, dynamic> toJson() => {
        ...extras,
        'sourceId': sourceId,
        'sourceKind': sourceKind.name,
        'importedAt': importedAt.toUtc().toIso8601String(),
        if (deviceModel != null) 'deviceModel': deviceModel,
        if (appPackage != null) 'appPackage': appPackage,
        if (externalId != null) 'externalId': externalId,
        'fieldsContributed': fieldsContributed,
        if (rawRef != null) 'rawRef': rawRef,
      };

  static SourceRecord? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['sourceId'];
    final at = raw['importedAt'];
    if (id is! String || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    String? s(Object? v) => v is String ? v : null;
    final fields = raw['fieldsContributed'];
    return SourceRecord(
      sourceId: id,
      sourceKind: SourceKind.parse(raw['sourceKind']),
      importedAt: parsed.toUtc(),
      deviceModel: s(raw['deviceModel']),
      appPackage: s(raw['appPackage']),
      externalId: s(raw['externalId']),
      fieldsContributed: fields is List
          ? [for (final f in fields) if (f is String) f]
          : const [],
      rawRef: s(raw['rawRef']),
      extras: {
        for (final e in raw.entries)
          if (!_knownKeys.contains(e.key)) e.key.toString(): e.value,
      },
    );
  }
}
