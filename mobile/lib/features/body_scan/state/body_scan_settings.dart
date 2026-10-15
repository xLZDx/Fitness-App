/// `users/{uid}/body_scan_settings/main` (design s5.2, s9): retention, cloud
/// consent and the paused flag. Client read/write, shape-validated by the
/// rules; `cloudConsent.acceptedAt` must equal the request time, so it is
/// written with a server timestamp and only when it changes (a write that
/// merely carries the old consent passes the rules unchanged).
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Retention choices in days; 0 = delete after analysis (default).
const List<int> kRetentionChoices = [0, 30, 90, 365];

/// The body-scan cloud consent text version the client knows. A material
/// change bumps it; the server compares against its own constant.
const int kBodyScanCloudConsentVersion = 1;

class BodyScanSettings {
  const BodyScanSettings({
    this.retentionDays = 0,
    this.cloudConsentVersion,
    this.paused = false,
  });

  final int retentionDays;

  /// Null = no cloud consent given.
  final int? cloudConsentVersion;
  final bool paused;

  /// True when the stored consent covers the current text.
  bool get hasCurrentConsent =>
      cloudConsentVersion != null &&
      cloudConsentVersion! >= kBodyScanCloudConsentVersion;

  BodyScanSettings copyWith({
    int? retentionDays,
    int? cloudConsentVersion,
    bool? paused,
    bool clearConsent = false,
  }) =>
      BodyScanSettings(
        retentionDays: retentionDays ?? this.retentionDays,
        cloudConsentVersion:
            clearConsent ? null : (cloudConsentVersion ?? this.cloudConsentVersion),
        paused: paused ?? this.paused,
      );

  /// Tolerant read: an unknown retention reads as 0 (delete after analysis).
  static BodyScanSettings fromJson(Object? raw) {
    if (raw is! Map) return const BodyScanSettings();
    final r = raw['retentionDays'];
    final consent = raw['cloudConsent'];
    final v = consent is Map ? consent['version'] : null;
    return BodyScanSettings(
      retentionDays: r is int && kRetentionChoices.contains(r) ? r : 0,
      cloudConsentVersion: v is int && v >= 1 ? v : null,
      paused: raw['paused'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BodyScanSettings &&
      other.retentionDays == retentionDays &&
      other.cloudConsentVersion == cloudConsentVersion &&
      other.paused == paused;

  @override
  int get hashCode => Object.hash(retentionDays, cloudConsentVersion, paused);
}

abstract class BodyScanSettingsStore {
  /// Replays the latest value; defaults while the document is absent.
  Stream<BodyScanSettings> watch();

  Future<void> setRetentionDays(int days);
  Future<void> setPaused(bool paused);

  /// Records consent [version] with a server timestamp.
  Future<void> acceptCloudConsent(int version);

  /// Withdraws consent (the key is removed, which means "no consent").
  Future<void> withdrawCloudConsent();
}

class FirestoreBodyScanSettingsStore implements BodyScanSettingsStore {
  FirestoreBodyScanSettingsStore({required this.uid, FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _doc => _db
      .collection('users')
      .doc(uid)
      .collection('body_scan_settings')
      .doc('main');

  @override
  Stream<BodyScanSettings> watch() =>
      _doc.snapshots().map((s) => BodyScanSettings.fromJson(s.data()));

  Future<void> _merge(Map<String, Object?> fields) =>
      _doc.set({'schema': 1, ...fields}, SetOptions(merge: true));

  @override
  Future<void> setRetentionDays(int days) {
    if (!kRetentionChoices.contains(days)) {
      throw ArgumentError.value(days, 'days', 'not an allowed retention');
    }
    return _merge({'retentionDays': days});
  }

  @override
  Future<void> setPaused(bool paused) => _merge({'paused': paused});

  @override
  Future<void> acceptCloudConsent(int version) => _merge({
        'cloudConsent': {
          'version': version,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
      });

  @override
  Future<void> withdrawCloudConsent() =>
      _doc.update({'cloudConsent': FieldValue.delete()});
}

class InMemoryBodyScanSettingsStore implements BodyScanSettingsStore {
  InMemoryBodyScanSettingsStore([BodyScanSettings initial = const BodyScanSettings()])
      : _value = initial;

  BodyScanSettings _value;
  final StreamController<BodyScanSettings> _changes =
      StreamController<BodyScanSettings>.broadcast();

  @override
  Stream<BodyScanSettings> watch() async* {
    yield _value;
    yield* _changes.stream;
  }

  void _set(BodyScanSettings v) {
    _value = v;
    _changes.add(v);
  }

  @override
  Future<void> setRetentionDays(int days) async {
    if (!kRetentionChoices.contains(days)) {
      throw ArgumentError.value(days, 'days', 'not an allowed retention');
    }
    _set(_value.copyWith(retentionDays: days));
  }

  @override
  Future<void> setPaused(bool paused) async => _set(_value.copyWith(paused: paused));

  @override
  Future<void> acceptCloudConsent(int version) async =>
      _set(_value.copyWith(cloudConsentVersion: version));

  @override
  Future<void> withdrawCloudConsent() async =>
      _set(_value.copyWith(clearConsent: true));
}
