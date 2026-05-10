/// A community-contributed exercise demonstration video. Free workaround
/// for the $5–15k contracted-shoot path: anyone can submit, and a small
/// volunteer/staff queue moderates before the video shows up in the
/// public catalog.
class CommunityVideo {
  const CommunityVideo({
    required this.id,
    required this.exerciseId,
    required this.url,
    required this.contributorUid,
    required this.contributorDisplay,
    required this.submittedAt,
    required this.status,
    this.notes,
    this.lengthSeconds,
    this.moderatorUid,
    this.moderatedAt,
  });

  final String id;
  final String exerciseId;
  final String url;
  final String contributorUid;
  final String contributorDisplay;
  final DateTime submittedAt;
  final CommunityVideoStatus status;
  final String? notes;
  final int? lengthSeconds;
  final String? moderatorUid;
  final DateTime? moderatedAt;

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'url': url,
        'contributorUid': contributorUid,
        'contributorDisplay': contributorDisplay,
        'submittedAt': submittedAt.toIso8601String(),
        'status': status.name,
        if (notes != null) 'notes': notes,
        if (lengthSeconds != null) 'lengthSeconds': lengthSeconds,
        if (moderatorUid != null) 'moderatorUid': moderatorUid,
        if (moderatedAt != null) 'moderatedAt': moderatedAt!.toIso8601String(),
      };

  factory CommunityVideo.fromJson(String id, Map<String, dynamic> j) {
    return CommunityVideo(
      id: id,
      exerciseId: j['exerciseId'] as String? ?? '',
      url: j['url'] as String? ?? '',
      contributorUid: j['contributorUid'] as String? ?? '',
      contributorDisplay:
          j['contributorDisplay'] as String? ?? 'Anonymous',
      submittedAt: DateTime.tryParse(j['submittedAt'] as String? ?? '') ??
          DateTime.now(),
      status: CommunityVideoStatus.values.firstWhere(
        (s) => s.name == (j['status'] as String?),
        orElse: () => CommunityVideoStatus.pending,
      ),
      notes: j['notes'] as String?,
      lengthSeconds: (j['lengthSeconds'] as num?)?.toInt(),
      moderatorUid: j['moderatorUid'] as String?,
      moderatedAt: j['moderatedAt'] is String
          ? DateTime.tryParse(j['moderatedAt'] as String)
          : null,
    );
  }
}

enum CommunityVideoStatus {
  /// Awaiting moderator review.
  pending,

  /// Approved and visible in the public exercise library.
  approved,

  /// Rejected (with [CommunityVideo.notes] explaining why).
  rejected,

  /// Pulled from the catalog after publication. Stays in storage so we
  /// have an audit trail.
  retracted,
}
