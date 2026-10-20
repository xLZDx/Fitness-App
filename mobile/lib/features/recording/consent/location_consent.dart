/// The location consent model (S04 design 6.2, S04-21, S04-R-026). Pure Dart.
///
/// One record per purpose holds purpose, timestamp, text version and state.
/// The `backgroundLocation` row exists in the schema and is written only if the
/// background-location branch is built (S04-18 branch B).
library;

import 'dart:convert';

/// What the consent is for.
enum LocationConsentPurpose {
  locationWhileRecording('location_while_recording'),
  backgroundLocation('background_location');

  const LocationConsentPurpose(this.wireName);

  /// The stable name stored on the device.
  final String wireName;

  static LocationConsentPurpose? fromWire(Object? raw) {
    for (final p in values) {
      if (p.wireName == raw) return p;
    }
    return null;
  }
}

/// `none` means the user was never asked; it behaves like a withdrawal for
/// Start (no recording) but is shown differently (S04-D 18.1).
enum ConsentState {
  none,
  granted,
  withdrawn;

  static ConsentState fromWire(Object? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return ConsentState.none;
  }
}

/// One stored consent decision.
class ConsentRecord {
  const ConsentRecord({
    required this.purpose,
    required this.state,
    required this.textVersion,
    required this.timestampUtcMs,
    this.grantedAtUtcMs,
  });

  final LocationConsentPurpose purpose;
  final ConsentState state;

  /// The version of the consent wording shown when the decision was made.
  final String textVersion;

  /// UTC milliseconds of this decision (grant or withdrawal).
  final int timestampUtcMs;

  /// UTC milliseconds of the last grant; kept when the consent is withdrawn.
  final int? grantedAtUtcMs;

  Map<String, Object?> toJson() => {
        'purpose': purpose.wireName,
        'state': state.name,
        'textVersion': textVersion,
        'timestamp': timestampUtcMs,
        if (grantedAtUtcMs != null) 'grantedAt': grantedAtUtcMs,
      };

  /// Null when [raw] is not a well-formed record.
  static ConsentRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final purpose = LocationConsentPurpose.fromWire(raw['purpose']);
    final version = raw['textVersion'];
    final ts = raw['timestamp'];
    if (purpose == null || version is! String || ts is! int) return null;
    final granted = raw['grantedAt'];
    return ConsentRecord(
      purpose: purpose,
      state: ConsentState.fromWire(raw['state']),
      textVersion: version,
      timestampUtcMs: ts,
      grantedAtUtcMs: granted is int ? granted : null,
    );
  }

  @override
  String toString() => 'ConsentRecord(${purpose.wireName}, ${state.name})';
}

/// All consent rows of one account.
class LocationConsent {
  const LocationConsent([this.records = const {}]);

  /// No decision of any kind.
  static const LocationConsent none = LocationConsent();

  final Map<LocationConsentPurpose, ConsentRecord> records;

  ConsentRecord? recordOf(LocationConsentPurpose purpose) => records[purpose];

  ConsentState stateOf(LocationConsentPurpose purpose) =>
      records[purpose]?.state ?? ConsentState.none;

  /// The state of the one purpose Start needs.
  ConsentState get recordingState =>
      stateOf(LocationConsentPurpose.locationWhileRecording);

  /// Start and Resume need exactly this (design 6.2).
  bool get recordingGranted => recordingState == ConsentState.granted;

  LocationConsent withRecord(ConsentRecord record) =>
      LocationConsent({...records, record.purpose: record});

  /// Decodes the stored value. Anything unrecognised reads as no consent, so
  /// the user is asked again and nothing is recorded on a corrupt value.
  static LocationConsent decode(String? raw) {
    if (raw == null) return none;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return none;
      final list = data['records'];
      if (list is! List) return none;
      final out = <LocationConsentPurpose, ConsentRecord>{};
      for (final item in list) {
        final r = ConsentRecord.fromJson(item);
        if (r != null) out[r.purpose] = r;
      }
      return LocationConsent(out);
    } on FormatException {
      return none;
    }
  }

  String encode() => jsonEncode({
        'v': 1,
        'records': [for (final r in records.values) r.toJson()],
      });

  @override
  String toString() => 'LocationConsent(${records.length} records)';
}
