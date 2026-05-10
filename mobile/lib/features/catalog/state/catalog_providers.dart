import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/community_video.dart';
import '../data/community_video_repository.dart';

final communityVideoRepositoryProvider =
    Provider<CommunityVideoRepository>((_) {
  return MockCommunityVideoRepository();
});

final pendingSubmissionsProvider =
    FutureProvider<List<CommunityVideo>>((ref) {
  return ref
      .watch(communityVideoRepositoryProvider)
      .list(status: CommunityVideoStatus.pending);
});

final approvedSubmissionsProvider =
    FutureProvider<List<CommunityVideo>>((ref) {
  return ref
      .watch(communityVideoRepositoryProvider)
      .list(status: CommunityVideoStatus.approved);
});
