import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/social_feed_repository.dart';
import '../data/social_post.dart';

final socialFeedRepositoryProvider =
    Provider<SocialFeedRepository>((_) => MockSocialFeedRepository());

final socialFeedProvider = StreamProvider<List<SocialPost>>((ref) {
  return ref.watch(socialFeedRepositoryProvider).watchFeed();
});
