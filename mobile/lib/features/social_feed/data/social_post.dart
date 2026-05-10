/// Hevy-style global social-feed post. Distinct from the Celebrity-tier
/// team feed: anyone can post, anyone can follow, posts auto-link to
/// the workout the user just logged.
class SocialPost {
  const SocialPost({
    required this.id,
    required this.authorUid,
    required this.authorDisplay,
    required this.body,
    required this.createdAt,
    this.workoutLogId,
    this.likes = 0,
    this.likedByMe = false,
  });

  final String id;
  final String authorUid;
  final String authorDisplay;
  final String body;
  final DateTime createdAt;
  final String? workoutLogId;
  final int likes;
  final bool likedByMe;

  SocialPost copyWith({int? likes, bool? likedByMe}) => SocialPost(
        id: id,
        authorUid: authorUid,
        authorDisplay: authorDisplay,
        body: body,
        createdAt: createdAt,
        workoutLogId: workoutLogId,
        likes: likes ?? this.likes,
        likedByMe: likedByMe ?? this.likedByMe,
      );

  Map<String, dynamic> toJson() => {
        'authorUid': authorUid,
        'authorDisplay': authorDisplay,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        if (workoutLogId != null) 'workoutLogId': workoutLogId,
        'likes': likes,
      };

  factory SocialPost.fromJson(String id, Map<String, dynamic> j) {
    return SocialPost(
      id: id,
      authorUid: j['authorUid'] as String? ?? '',
      authorDisplay: j['authorDisplay'] as String? ?? 'Anonymous',
      body: j['body'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.now(),
      workoutLogId: j['workoutLogId'] as String?,
      likes: (j['likes'] as num?)?.toInt() ?? 0,
    );
  }
}
