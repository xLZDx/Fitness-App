import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Profile'),
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
                    gradient: const LinearGradient(
                      colors: [
                        AppPalette.auroraPink,
                        AppPalette.auroraPeach,
                      ],
                    ),
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 36),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Guest user', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Sign in to sync progress',
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
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _profileTile(
                  context,
                  icon: Icons.assignment_outlined,
                  gradient: AppPalette.tileGradients[1],
                  title: 'Health questionnaire',
                  subtitle: 'Personalize recommendations',
                  onTap: () {},
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.favorite_outline,
                  gradient: AppPalette.tileGradients[0],
                  title: 'Connected devices',
                  subtitle: 'Watches, scales, heart rate',
                  onTap: () {},
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.workspace_premium_outlined,
                  gradient: AppPalette.tileGradients[3],
                  title: 'Subscription',
                  subtitle: 'Free trial',
                  onTap: () {},
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.settings_outlined,
                  gradient: AppPalette.tileGradients[2],
                  title: 'Settings',
                  subtitle: 'Theme, notifications, language',
                  onTap: () {},
                ),
                _divider(context),
                _profileTile(
                  context,
                  icon: Icons.logout,
                  gradient: AppPalette.tileGradients[4],
                  title: 'Sign out',
                  subtitle: 'See you soon',
                  onTap: () => context.go('/login'),
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
