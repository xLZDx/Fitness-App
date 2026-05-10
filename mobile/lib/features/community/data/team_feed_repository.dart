import 'team_feed.dart';

abstract class TeamFeedRepository {
  Stream<List<TeamFeedPost>> watchTeamFeed(String teamId);

  /// Trainer-only. Cloud Function rules enforce the role check.
  Future<TeamFeedPost> postUpdate({
    required String teamId,
    required String authorUid,
    required String authorName,
    required String body,
    String? title,
    String? imageUrl,
    String? workoutTemplateId,
  });

  Future<void> react({
    required String postId,
    required String emoji,
    required int delta,
  });

  Future<TeamFeedComment> comment({
    required String postId,
    required String authorUid,
    required String authorName,
    required String body,
  });
}

class MockTeamFeedRepository implements TeamFeedRepository {
  final Map<String, List<TeamFeedPost>> _byTeam = {};
  final Map<String, List<TeamFeedComment>> _commentsByPost = {};
  int _seq = 0;

  @override
  Stream<List<TeamFeedPost>> watchTeamFeed(String teamId) async* {
    yield _byTeam[teamId] ?? const [];
  }

  @override
  Future<TeamFeedPost> postUpdate({
    required String teamId,
    required String authorUid,
    required String authorName,
    required String body,
    String? title,
    String? imageUrl,
    String? workoutTemplateId,
  }) async {
    final post = TeamFeedPost(
      id: 'post_${++_seq}',
      teamId: teamId,
      authorUid: authorUid,
      authorName: authorName,
      body: body,
      createdAt: DateTime.now(),
      title: title,
      imageUrl: imageUrl,
      workoutTemplateId: workoutTemplateId,
    );
    final list = _byTeam.putIfAbsent(teamId, () => <TeamFeedPost>[]);
    list.insert(0, post);
    return post;
  }

  @override
  Future<void> react({
    required String postId,
    required String emoji,
    required int delta,
  }) async {
    for (final list in _byTeam.values) {
      final i = list.indexWhere((p) => p.id == postId);
      if (i < 0) continue;
      final p = list[i];
      final map = Map<String, int>.from(p.reactionCounts);
      map[emoji] = ((map[emoji] ?? 0) + delta).clamp(0, 1 << 30);
      list[i] = TeamFeedPost(
        id: p.id,
        teamId: p.teamId,
        authorUid: p.authorUid,
        authorName: p.authorName,
        body: p.body,
        createdAt: p.createdAt,
        title: p.title,
        imageUrl: p.imageUrl,
        workoutTemplateId: p.workoutTemplateId,
        reactionCounts: map,
        commentCount: p.commentCount,
        isPinned: p.isPinned,
      );
    }
  }

  @override
  Future<TeamFeedComment> comment({
    required String postId,
    required String authorUid,
    required String authorName,
    required String body,
  }) async {
    final c = TeamFeedComment(
      id: 'cmt_${++_seq}',
      postId: postId,
      authorUid: authorUid,
      authorName: authorName,
      body: body,
      createdAt: DateTime.now(),
    );
    _commentsByPost.putIfAbsent(postId, () => <TeamFeedComment>[]).add(c);
    return c;
  }
}
