import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/team_feed.dart';
import '../data/team_feed_repository.dart';

final teamFeedRepositoryProvider = Provider<TeamFeedRepository>((ref) {
  return MockTeamFeedRepository();
});

/// True while [teamFeedRepositoryProvider] is still the mock.
///
/// Posts live in one instance's in-memory map, keyed by team, and vanish on
/// restart -- a Celebrity-tier subscriber posting or reading here has no way
/// to know the feed is not actually backed by anything. Same self-removing
/// shape as the other two demo flags in this remediation round: the day
/// `main.dart` binds a Firestore-backed repository, this goes false.
final teamFeedIsDemoProvider = Provider<bool>((ref) {
  return ref.watch(teamFeedRepositoryProvider) is MockTeamFeedRepository;
});

final teamFeedProvider =
    StreamProvider.family<List<TeamFeedPost>, String>((ref, teamId) {
  return ref.watch(teamFeedRepositoryProvider).watchTeamFeed(teamId);
});
