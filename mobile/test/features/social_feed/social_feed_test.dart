import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/social_feed/data/social_feed_repository.dart';

void main() {
  group('MockSocialFeedRepository', () {
    test('seed has at least one post', () async {
      final repo = MockSocialFeedRepository();
      final feed = await repo.watchFeed().first;
      expect(feed, isNotEmpty);
    });

    test('post inserts at the top', () async {
      final repo = MockSocialFeedRepository();
      final p = await repo.post(
        authorUid: 'me',
        authorDisplay: 'Me',
        body: 'Hello world',
      );
      final feed = await repo.watchFeed().first;
      expect(feed.first.id, p.id);
      expect(feed.first.body, 'Hello world');
    });

    test('like increments + flips likedByMe', () async {
      final repo = MockSocialFeedRepository();
      final feed = await repo.watchFeed().first;
      final firstId = feed.first.id;
      final initialLikes = feed.first.likes;
      await repo.like(firstId, uid: 'me');
      final after = await repo.watchFeed().first;
      final updated = after.firstWhere((p) => p.id == firstId);
      expect(updated.likes, initialLikes + 1);
      expect(updated.likedByMe, isTrue);
    });

    test('unlike decrements (clamps at 0)', () async {
      final repo = MockSocialFeedRepository();
      final p = await repo.post(
        authorUid: 'me',
        authorDisplay: 'Me',
        body: 'x',
      );
      await repo.unlike(p.id, uid: 'me');
      final after = await repo.watchFeed().first;
      final updated = after.firstWhere((q) => q.id == p.id);
      expect(updated.likes, 0);
    });
  });
}
