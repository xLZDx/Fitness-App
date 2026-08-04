import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/community/data/team_feed.dart';
import 'package:fitness_app/features/community/data/team_feed_repository.dart';
import 'package:fitness_app/features/community/state/team_feed_providers.dart';
import 'package:fitness_app/features/community/team_feed_page.dart';

/// M0: posts through the mock repository live in one instance's in-memory
/// map, keyed by team, and vanish on restart. A Celebrity-tier subscriber
/// posting or reading here had no way to know the feed is not actually
/// backed by anything.

class _NeverPersists implements TeamFeedRepository {
  const _NeverPersists();
  @override
  Stream<List<TeamFeedPost>> watchTeamFeed(String teamId) =>
      Stream.value(const []);
  @override
  Future<TeamFeedPost> postUpdate({
    required String teamId,
    required String authorUid,
    required String authorName,
    required String body,
    String? title,
    String? imageUrl,
    String? workoutTemplateId,
  }) async =>
      throw UnimplementedError();
  @override
  Future<void> react({
    required String postId,
    required String emoji,
    required int delta,
  }) async {}
  @override
  Future<TeamFeedComment> comment({
    required String postId,
    required String authorUid,
    required String authorName,
    required String body,
  }) async =>
      throw UnimplementedError();
}

Widget _host({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TeamFeedPage(teamId: 'team_1'),
      ),
    );

void main() {
  testWidgets('the demo banner shows while the mock repository is bound',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    expect(find.textContaining('Demo feed'), findsOneWidget);
  });

  testWidgets('the banner is gone once a real repository is bound',
      (tester) async {
    await tester.pumpWidget(_host(overrides: [
      teamFeedRepositoryProvider.overrideWithValue(const _NeverPersists()),
    ]));
    await tester.pumpAndSettle();
    expect(find.textContaining('Demo feed'), findsNothing);
  });
}
