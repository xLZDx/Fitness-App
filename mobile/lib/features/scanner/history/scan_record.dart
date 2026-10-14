import 'dart:convert';

import '../../visual_equipment/data/scan_outcome.dart';
import '../../visual_equipment/data/visual_equipment_match.dart';

/// Where a scan came from.
enum ScanSource { camera, gallery, live }

/// How a scan was answered. `none` is a scan that produced no answer (timeout,
/// failure, nothing found) -- it is still recorded, because "what did the app
/// do with this photo" is exactly what the history is for.
enum ScanAnsweredBy { cloud, onDevice, printedText, none }

/// The user's optional verdict on one candidate. Absent (null) is the default
/// and the cleared state; it never blocks anything.
enum CandidateRating { ok, notOk }

String _ratingName(CandidateRating r) => r == CandidateRating.ok ? 'ok' : 'not_ok';

CandidateRating? ratingByName(Object? name) {
  switch (name) {
    case 'ok':
      return CandidateRating.ok;
    case 'not_ok':
      return CandidateRating.notOk;
  }
  return null;
}

/// One machine the app offered for a scan, with the user's rating of it.
class ScanCandidate {
  const ScanCandidate({
    required this.equipmentId,
    required this.confidence,
    this.labelHint,
    this.matchSource = MatchSource.classifier,
    this.rating,
  });

  final String equipmentId;
  final double confidence;

  /// The model's own name for it (or the phrase read off the machine).
  final String? labelHint;
  final MatchSource matchSource;
  final CandidateRating? rating;

  ScanCandidate withRating(CandidateRating? r) => ScanCandidate(
        equipmentId: equipmentId,
        confidence: confidence,
        labelHint: labelHint,
        matchSource: matchSource,
        rating: r,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'equipmentId': equipmentId,
        'confidence': confidence,
        'labelHint': labelHint,
        'matchSource': matchSource.name,
        'rating': rating == null ? null : _ratingName(rating!),
      };

  static ScanCandidate fromJson(Map<String, dynamic> j) => ScanCandidate(
        equipmentId: j['equipmentId'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        labelHint: j['labelHint'] as String?,
        matchSource: MatchSource.values.firstWhere(
          (s) => s.name == j['matchSource'],
          orElse: () => MatchSource.classifier,
        ),
        rating: ratingByName(j['rating']),
      );
}

/// Everything saved about one scan, ON THE PHONE ONLY.
///
/// Operator order 2026-10-14: every scan is kept automatically so the
/// operator can compare what the model said with what the machine really was.
/// Never uploaded: the store writes to app-private storage, the folder is
/// excluded from Android backup and removed by the account-deletion wipe.
class ScanRecord {
  const ScanRecord({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.outcome,
    required this.answeredBy,
    this.rawAnswer,
    this.candidates = const <ScanCandidate>[],
    this.openedEquipmentId,
    this.pickedManually = false,
    this.hasPhoto = false,
    this.appGitSha = 'unknown',
    this.appVersion = 'unknown',
  });

  static const String schema = 'scan_record/v1';
  static const String photoFileName = 'photo.jpg';

  final String id;
  final DateTime timestamp;
  final ScanSource source;
  final ScanOutcome outcome;
  final ScanAnsweredBy answeredBy;

  /// What the cloud model replied, verbatim (null when the cloud did not
  /// answer or the answer came from elsewhere).
  final String? rawAnswer;

  /// Every candidate shown, in the order shown, with the user's ratings.
  final List<ScanCandidate> candidates;

  /// The machine the user opened from the list, or chose manually.
  final String? openedEquipmentId;
  final bool pickedManually;

  /// Whether `photo.jpg` sits next to the record (live readings have none).
  final bool hasPhoto;
  final String appGitSha;
  final String appVersion;

  /// True when the cloud model produced the answer; false for the on-device
  /// fallback, a printed-text read, or no answer at all.
  bool get cloudAnswered => answeredBy == ScanAnsweredBy.cloud;

  ScanCandidate? get top => candidates.isEmpty ? null : candidates.first;

  ScanRecord copyWith({
    List<ScanCandidate>? candidates,
    String? openedEquipmentId,
    bool? pickedManually,
  }) =>
      ScanRecord(
        id: id,
        timestamp: timestamp,
        source: source,
        outcome: outcome,
        answeredBy: answeredBy,
        rawAnswer: rawAnswer,
        candidates: candidates ?? this.candidates,
        openedEquipmentId: openedEquipmentId ?? this.openedEquipmentId,
        pickedManually: pickedManually ?? this.pickedManually,
        hasPhoto: hasPhoto,
        appGitSha: appGitSha,
        appVersion: appVersion,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schema,
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'source': source.name,
        'outcome': outcome.name,
        'answeredBy': answeredBy.name,
        'cloudAnswered': cloudAnswered,
        'rawAnswer': rawAnswer,
        'candidates': <Object?>[for (final c in candidates) c.toJson()],
        'openedEquipmentId': openedEquipmentId,
        'pickedManually': pickedManually,
        'photo': hasPhoto ? photoFileName : null,
        'app': <String, Object?>{'gitSha': appGitSha, 'version': appVersion},
      };

  String encode() => jsonEncode(toJson());

  static ScanRecord fromJson(Map<String, dynamic> j) {
    final app = (j['app'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ScanRecord(
      id: j['id'] as String,
      timestamp: DateTime.parse(j['timestamp'] as String).toUtc(),
      source: ScanSource.values.firstWhere((s) => s.name == j['source'],
          orElse: () => ScanSource.camera),
      outcome: ScanOutcome.values.firstWhere((s) => s.name == j['outcome'],
          orElse: () => ScanOutcome.failed),
      answeredBy: ScanAnsweredBy.values.firstWhere(
          (s) => s.name == j['answeredBy'],
          orElse: () => ScanAnsweredBy.none),
      rawAnswer: j['rawAnswer'] as String?,
      candidates: <ScanCandidate>[
        for (final c in (j['candidates'] as List? ?? const <Object?>[]))
          ScanCandidate.fromJson((c as Map).cast<String, dynamic>()),
      ],
      openedEquipmentId: j['openedEquipmentId'] as String?,
      pickedManually: j['pickedManually'] as bool? ?? false,
      hasPhoto: j['photo'] != null,
      appGitSha: app['gitSha'] as String? ?? 'unknown',
      appVersion: app['version'] as String? ?? 'unknown',
    );
  }
}
