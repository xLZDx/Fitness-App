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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final user = ref.watch(authUserProvider).valueOrNull;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final onboarded = profile?.hasCompletedOnboarding ?? false;
    final sub = ref.watch(currentSubscriptionProvider).valueOrNull;
    final tier = ref.watch(effectiveTierProvider);

    final displayName = user?.displayName ?? 'Guest';
    final subtitle = onboarded
        ? 'Profile complete'
        : (user == null ? 'Sign in to sync progress' : 'Finish onboarding to unlock plans');

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
                  title:
                      onboarded ? 'Health questionnaire' : 'Complete questionnaire',
                  subtitle: onboarded ? 'Edit your answers' : 'Personalize your plan',
                  onTap: () => context.go('/onboarding'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.photo_library_outlined,
                  gradient: AppPalette.tileGradients[0],
                  title: AppLocalizations.of(context).profileProgressPhotos,
                  subtitle: AppLocalizations.of(context).profileEndToEndEncryptedOnYour,
                  onTap: () => context.push('/photos'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.people_alt_outlined,
                  gradient: AppPalette.tileGradients[2],
                  title: AppLocalizations.of(context).marketplaceCoaches,
                  subtitle: AppLocalizations.of(context).profileBrowse11Sessions15Fee,
                  onTap: () => context.push('/coaches'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.star_outline,
                  gradient: AppPalette.tileGradients[4],
                  title: AppLocalizations.of(context).celebrityplansCelebrityPlans,
                  subtitle: AppLocalizations.of(context).profileInKindDonatedProgrammes,
                  onTap: () => context.push('/celebrity-plans'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.forum_outlined,
                  gradient: AppPalette.tileGradients[3],
                  title: AppLocalizations.of(context).profileCommunity,
                  subtitle: AppLocalizations.of(context).profileHevyStyleSocialFeed,
                  onTap: () => context.push('/community'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.workspace_premium_outlined,
                  gradient: AppPalette.tileGradients[3],
                  title: AppLocalizations.of(context).profileSubscription,
                  subtitle: _subscriptionSubtitle(sub, tier),
                  onTap: () => context.push('/subscription'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.volunteer_activism_outlined,
                  gradient: AppPalette.tileGradients[0],
                  title: AppLocalizations.of(context).aboutOurMission,
                  subtitle: AppLocalizations.of(context).profileHowDonationsAreUsedDonorWall,
                  onTap: () => context.push('/about'),
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.settings_outlined,
                  gradient: AppPalette.tileGradients[2],
                  title: AppLocalizations.of(context).profileSettings,
                  subtitle: AppLocalizations.of(context).profileThemeNotificationsLanguage,
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
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.65),
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

  String _subscriptionSubtitle(Subscription? sub, SubscriptionTier tier) {
    if (sub == null || sub.status == SubscriptionStatus.none) {
      return 'Free · start a 14-day trial';
    }
    final tierLabel = switch (tier) {
      SubscriptionTier.free => 'Free',
      SubscriptionTier.standard => 'Standard',
      SubscriptionTier.celebrityTrainer => 'Celebrity trainer',
    };
    final statusLabel = switch (sub.status) {
      SubscriptionStatus.trial => 'Trial',
      SubscriptionStatus.active => 'Active',
      SubscriptionStatus.cancelled => 'Cancelling',
      SubscriptionStatus.expired => 'Expired',
      SubscriptionStatus.none => 'Free',
    };
    return '$tierLabel · $statusLabel';
  }

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 1,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.06),
        ),
      );
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});
  // Typed (not dynamic): enum extension getters like `ActivityLevel.name`
  // do not dispatch dynamically — `dynamic` here crashed the page with
  // NoSuchMethodError the moment activityLevel was set.
  final UserProfile profile;

  String _activityLabel() {
    final a = profile.personal.activityLevel;
    if (a == null) return '—';
    return a.name.replaceAllMapped(
        RegExp(r'([A-Z])'), (m) => ' ${m.group(0)!.toLowerCase()}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = profile.personal;
    final goalsList = <String>[
      if (profile.goals.weightLoss) 'Weight loss',
      if (profile.goals.muscleGain) 'Muscle gain',
      if (profile.goals.endurance) 'Endurance',
      if (profile.goals.strength) 'Strength',
      if (profile.goals.flexibility) 'Flexibility',
      if (profile.goals.generalFitness) 'General fitness',
    ];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).profileAtAGlance, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          _row(context, 'Age', p.age?.toString() ?? '—'),
          _row(context, 'Height',
              p.heightCm != null ? '${p.heightCm} cm' : '—'),
          _row(context, 'Weight',
              p.weightCurrentKg != null ? '${p.weightCurrentKg} kg' : '—'),
          _row(context, 'Activity', _activityLabel()),
          _row(context, 'Goals',
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
