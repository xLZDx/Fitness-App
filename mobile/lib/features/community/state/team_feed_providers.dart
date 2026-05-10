import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/team_feed.dart';
import '../data/team_feed_repository.dart';

final teamFeedRepositoryProvider = Provider<TeamFeedRepository>((ref) {
  return MockTeamFeedRepository();
});

final teamFeedProvider =
    StreamProvider.family<List<TeamFeedPost>, String>((ref, teamId) {
  return ref.watch(teamFeedRepositoryProvider).watchTeamFeed(teamId);
});
