import 'dart:async';

import 'social_post.dart';

abstract class SocialFeedRepository {
  Stream<List<SocialPost>> watchFeed();
  Future<SocialPost> post({
    required String authorUid,
    required String authorDisplay,
    required String body,
    String? workoutLogId,
  });
  Future<void> like(String postId, {required String uid});
  Future<void> unlike(String postId, {required String uid});
}

class MockSocialFeedRepository implements SocialFeedRepository {
  final List<SocialPost> _posts = _seed();
  final StreamController<List<SocialPost>> _ctrl =
      StreamController<List<SocialPost>>.broadcast();
  int _seq = 100;

  static List<SocialPost> _seed() {
    final now = DateTime.now();
    return [
      SocialPost(
        id: 's1',
        authorUid: 'u1',
        authorDisplay: 'A. Thompson',
        body: 'Hit a 100kg squat for the first time today 🏋️',
        createdAt: now.subtract(const Duration(hours: 2)),
        likes: 12,
      ),
      SocialPost(
        id: 's2',
        authorUid: 'u2',
        authorDisplay: 'M. Rivera',
        body: '4 weeks back from a low-back strain. Pain-free deadlifts.',
        createdAt: now.subtract(const Duration(hours: 8)),
        likes: 22,
      ),
    ];
  }

  @override
  Stream<List<SocialPost>> watchFeed() async* {
    yield List.unmodifiable(_posts);
    yield* _ctrl.stream;
  }

  @override
  Future<SocialPost> post({
    required String authorUid,
    required String authorDisplay,
    required String body,
    String? workoutLogId,
  }) async {
    final p = SocialPost(
      id: 's${++_seq}',
      authorUid: authorUid,
      authorDisplay: authorDisplay,
      body: body,
      createdAt: DateTime.now(),
      workoutLogId: workoutLogId,
    );
    _posts.insert(0, p);
    _ctrl.add(List.unmodifiable(_posts));
    return p;
  }

  @override
  Future<void> like(String postId, {required String uid}) async {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    _posts[i] =
        _posts[i].copyWith(likes: _posts[i].likes + 1, likedByMe: true);
    _ctrl.add(List.unmodifiable(_posts));
  }

  @override
  Future<void> unlike(String postId, {required String uid}) async {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    _posts[i] = _posts[i].copyWith(
      likes: (_posts[i].likes - 1).clamp(0, 1 << 30),
      likedByMe: false,
    );
    _ctrl.add(List.unmodifiable(_posts));
  }
}
