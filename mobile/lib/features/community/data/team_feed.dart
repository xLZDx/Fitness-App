/// A trainer-authored post in a Celebrity-tier "team" feed. Subscribers
/// can react and (optionally) comment; trainers (and only trainers) post.
class TeamFeedPost {
  const TeamFeedPost({
    required this.id,
    required this.teamId,
    required this.authorUid,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.title,
    this.imageUrl,
    this.workoutTemplateId,
    this.reactionCounts = const {},
    this.commentCount = 0,
    this.isPinned = false,
  });

  final String id;
  final String teamId;
  final String authorUid;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final String? title;
  final String? imageUrl;

  /// If set, references a `workout_templates/{id}` document the
  /// subscriber can launch with one tap.
  final String? workoutTemplateId;

  /// Map of reaction emoji → count. Stored as a plain map so Firestore
  /// can update individual keys without rewriting the whole post.
  final Map<String, int> reactionCounts;

  final int commentCount;
  final bool isPinned;

  Map<String, dynamic> toJson() => {
        'teamId': teamId,
        'authorUid': authorUid,
        'authorName': authorName,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        if (title != null) 'title': title,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (workoutTemplateId != null)
          'workoutTemplateId': workoutTemplateId,
        if (reactionCounts.isNotEmpty) 'reactionCounts': reactionCounts,
        'commentCount': commentCount,
        if (isPinned) 'isPinned': true,
      };

  factory TeamFeedPost.fromJson(String id, Map<String, dynamic> j) {
    return TeamFeedPost(
      id: id,
      teamId: j['teamId'] as String? ?? '',
      authorUid: j['authorUid'] as String? ?? '',
      authorName: j['authorName'] as String? ?? 'Coach',
      body: j['body'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
          DateTime.now(),
      title: j['title'] as String?,
      imageUrl: j['imageUrl'] as String?,
      workoutTemplateId: j['workoutTemplateId'] as String?,
      reactionCounts:
          (j['reactionCounts'] as Map?)?.cast<String, int>() ?? const {},
      commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
      isPinned: j['isPinned'] == true,
    );
  }
}

class TeamFeedComment {
  const TeamFeedComment({
    required this.id,
    required this.postId,
    required this.authorUid,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String postId;
  final String authorUid;
  final String authorName;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'postId': postId,
        'authorUid': authorUid,
        'authorName': authorName,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };
}
