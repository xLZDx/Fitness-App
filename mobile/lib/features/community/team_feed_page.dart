import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/demo_data_banner.dart';
import '../../shared/widgets/glass.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/team_feed.dart';
import 'state/team_feed_providers.dart';

/// Team feed page — Celebrity-tier feature.
///
/// Subscribers join a team (per-trainer Firestore subcollection) and see
/// the trainer's posts + react. Free users see a locked preview.
class TeamFeedPage extends ConsumerWidget {
  const TeamFeedPage({super.key, required this.teamId});

  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier == SubscriptionTier.celebrityTrainer;
    final feedAsync = ref.watch(teamFeedProvider(teamId));
    final isDemo = ref.watch(teamFeedIsDemoProvider);

    return FrostedScaffold(
      appBar:
          GlassAppBar(title: AppLocalizations.of(context).communityTeamFeed),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          DemoDataBanner(
            isDemo: isDemo,
            message: AppLocalizations.of(context).communityDemoFeed,
          ),
          if (!isPremium) ...[
            _LockedHero(),
            const SizedBox(height: 16),
          ],
          feedAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text(
                  AppLocalizations.of(context).communityCouldNotLoadFeed(e)),
            ),
            data: (posts) {
              if (posts.isEmpty) {
                return GlassCard(
                  child: Text(
                    isPremium
                        ? AppLocalizations.of(context).communityNoPostsYet
                        : 'Become a Sustainer to read what your coach is sharing.',
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                children: [
                  for (final p in posts) ...[
                    _PostCard(post: p, locked: !isPremium),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LockedHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(colors: [
                    AppPalette.auroraPeach,
                    AppPalette.auroraPink,
                  ]),
                ),
                child: const Icon(Icons.lock_outline,
                    color: AppSemanticColors.onGradientInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).communitySustainerTierFeed,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)
                .communityCoachesPostWeeklyWorkoutsMotivationNotes,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: AppPrimaryButton(
              onPressed: () => GoRouter.of(context).push('/subscription'),
              label: AppLocalizations.of(context).communityBecomeASustainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post, required this.locked});
  final TeamFeedPost post;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppPalette.auroraPink,
                child: Text(
                  post.authorName.isEmpty ? '?' : post.authorName[0],
                  style: const TextStyle(
                    color: AppSemanticColors.onGradientInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.authorName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      _ago(l10n, post.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.isPinned) const Icon(Icons.push_pin_outlined, size: 16),
            ],
          ),
          const SizedBox(height: 10),
          if (post.title != null) ...[
            Text(post.title!,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
          ],
          Text(
            locked
                ? AppLocalizations.of(context).communitySustainerOnlyPost
                : post.body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
          if (!locked) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in post.reactionCounts.entries)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${entry.key} ${entry.value}'),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_reaction_outlined, size: 16),
                  label: Text(AppLocalizations.of(context).communityReact),
                  onPressed: () => ref
                      .read(teamFeedRepositoryProvider)
                      .react(postId: post.id, emoji: '🔥', delta: 1),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _ago(AppLocalizations l10n, DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return l10n.commonMinutesAgo(d.inMinutes);
    if (d.inHours < 24) return l10n.commonHoursAgo(d.inHours);
    return l10n.commonDaysAgoShort(d.inDays);
  }
}
