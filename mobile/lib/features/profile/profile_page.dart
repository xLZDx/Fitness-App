import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../auth/state/auth_providers.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/profile_models.dart';
import 'state/profile_providers.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authUserProvider).valueOrNull;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final onboarded = profile?.hasCompletedOnboarding ?? false;
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
    final tier = ref.watch(effectiveTierProvider);
    final unresolved = ref.watch(unresolvedInjuryCountProvider);

    final displayName = user?.displayName ?? l10n.profileGuest;
    final subtitle = onboarded
        ? l10n.profileComplete
        : (user == null
            ? l10n.profileSignInToSync
            : l10n.profileFinishOnboarding);

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).profileProfile),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 120),
        children: [
          GlassCard(
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(colors: [
                      AppPalette.auroraPink,
                      AppPalette.auroraPeach,
                    ]),
                  ),
                  child:
                      const Icon(Icons.person, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (profile != null && onboarded) _ProfileSummary(profile: profile),
          if (profile != null && onboarded) const SizedBox(height: 16),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _profileTile(
                  context,
                  icon: Icons.assignment_outlined,
                  gradient: AppPalette.tileGradients[1],
                  title: onboarded
                      ? l10n.profileHealthQuestionnaire
                      : l10n.profileCompleteQuestionnaire,
                  subtitle: onboarded
                      ? AppLocalizations.of(context).profileEditYourAnswers
                      : AppLocalizations.of(context).profilePersonalizePlan,
                  onTap: () => context.go('/onboarding'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.healing_outlined,
                  gradient: AppPalette.tileGradients[2],
                  title: l10n.profileInjuries,
                  // Says the number when there is one. A tile that reads the
                  // same whether or not something needs attention is a tile
                  // nobody opens.
                  subtitle: unresolved > 0
                      ? l10n.profileInjuriesNeedArea(unresolved)
                      : l10n.profileInjuriesSubtitle,
                  // Its own route rather than a fix to the questionnaire tile
                  // above: that one routes to /onboarding, which
                  // resolveRedirect bounces straight back to /home for anyone
                  // who has onboarded, so it can reach no save at all.
                  onTap: () => context.push('/injuries'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.photo_library_outlined,
                  gradient: AppPalette.tileGradients[0],
                  title: AppLocalizations.of(context).profileProgressPhotos,
                  subtitle: AppLocalizations.of(context)
                      .profileEndToEndEncryptedOnYour,
                  onTap: () => context.push('/photos'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.people_alt_outlined,
                  gradient: AppPalette.tileGradients[2],
                  title: AppLocalizations.of(context).marketplaceCoaches,
                  subtitle:
                      AppLocalizations.of(context).profileBrowse11Sessions15Fee,
                  onTap: () => context.push('/coaches'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.star_outline,
                  gradient: AppPalette.tileGradients[4],
                  title:
                      AppLocalizations.of(context).celebrityplansCelebrityPlans,
                  subtitle: AppLocalizations.of(context)
                      .profileInKindDonatedProgrammes,
                  onTap: () => context.push('/celebrity-plans'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.forum_outlined,
                  gradient: AppPalette.tileGradients[3],
                  title: AppLocalizations.of(context).profileCommunity,
                  subtitle:
                      AppLocalizations.of(context).profileHevyStyleSocialFeed,
                  onTap: () => context.push('/community'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.workspace_premium_outlined,
                  gradient: AppPalette.tileGradients[3],
                  title: AppLocalizations.of(context).profileSubscription,
                  subtitle: _subscriptionSubtitle(l10n, sub, tier),
                  onTap: () => context.push('/subscription'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.volunteer_activism_outlined,
                  gradient: AppPalette.tileGradients[0],
                  title: AppLocalizations.of(context).aboutOurMission,
                  subtitle: AppLocalizations.of(context)
                      .profileHowDonationsAreUsedDonorWall,
                  onTap: () => context.push('/about'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.settings_outlined,
                  gradient: AppPalette.tileGradients[2],
                  title: AppLocalizations.of(context).profileSettings,
                  subtitle: AppLocalizations.of(context)
                      .profileThemeNotificationsLanguage,
                  onTap: () => context.push('/settings'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.logout,
                  gradient: AppPalette.tileGradients[4],
                  title: AppLocalizations.of(context).profileSignOut,
                  subtitle: AppLocalizations.of(context).profileSeeYouSoon,
                  onTap: () => ref.read(authActionProvider.notifier).signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTile(
    BuildContext context, {
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: gradient),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
          ],
        ),
      ),
    );
  }

  String _subscriptionSubtitle(
      AppLocalizations l10n, Subscription? sub, SubscriptionTier tier) {
    if (sub == null || sub.status == SubscriptionStatus.none) {
      return l10n.profileFreeStartTrial;
    }
    final tierLabel = switch (tier) {
      SubscriptionTier.free => l10n.profileTierFree,
      SubscriptionTier.standard => l10n.profileTierStandard,
      SubscriptionTier.celebrityTrainer => l10n.profileTierCelebrity,
    };
    final statusLabel = switch (sub.status) {
      SubscriptionStatus.trial => l10n.profileSubTrial,
      SubscriptionStatus.active => l10n.profileSubActive,
      SubscriptionStatus.cancelled => l10n.profileSubCancelling,
      SubscriptionStatus.expired => l10n.profileSubExpired,
      SubscriptionStatus.none => l10n.profileSubNone,
    };
    return '$tierLabel · $statusLabel';
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 1,
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      );
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});
  // Typed (not dynamic): enum extension getters like `ActivityLevel.name`
  // do not dispatch dynamically — `dynamic` here crashed the page with
  // NoSuchMethodError the moment activityLevel was set.
  final UserProfile profile;

  /// The activity level, looked up rather than derived.
  ///
  /// This used to build the label out of the enum's own name by inserting a
  /// space before every capital, which produced "moderately active" for free
  /// and produced it in English only -- and tied the interface to an
  /// identifier, so renaming the enum would have renamed what the user reads.
  String _activityLabel(AppLocalizations l10n) =>
      switch (profile.personal.activityLevel) {
        null => '—',
        ActivityLevel.sedentary => l10n.onbActivitySedentary,
        ActivityLevel.moderatelyActive => l10n.onbActivityModerate,
        ActivityLevel.active => l10n.onbActivityActive,
        ActivityLevel.veryActive => l10n.onbActivityVery,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = profile.personal;
    // The same six keys the onboarding chips use. A second translation of
    // "Muscle gain" would drift from the first the moment either is edited.
    final goalsList = <String>[
      if (profile.goals.weightLoss) l10n.onbGoalWeightLoss,
      if (profile.goals.muscleGain) l10n.onbGoalMuscleGain,
      if (profile.goals.endurance) l10n.onbGoalEndurance,
      if (profile.goals.strength) l10n.onbGoalStrength,
      if (profile.goals.flexibility) l10n.onbGoalFlexibility,
      if (profile.goals.generalFitness) l10n.onbGoalGeneral,
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).profileAtAGlance,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _row(context, l10n.profileRowAge, p.age?.toString() ?? '—'),
          _row(context, l10n.profileRowHeight,
              p.heightCm != null ? l10n.commonCentimetres(p.heightCm!) : '—'),
          _row(
              context,
              l10n.profileRowWeight,
              p.weightCurrentKg != null
                  ? l10n.commonKilograms('${p.weightCurrentKg}')
                  : '—'),
          _row(context, l10n.profileRowActivity, _activityLabel(l10n)),
          _row(context, l10n.profileRowGoals,
              goalsList.isEmpty ? '—' : goalsList.join(', ')),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.60),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
