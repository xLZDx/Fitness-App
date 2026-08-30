import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/background/hud_sky.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../state/coach_phase_providers.dart';

/// The two cards the design puts in front of a coached set, and the reason the
/// camera is not open while either of them is on screen.
///
/// ## Why they are not an overlay
///
/// The obvious cheap version — draw these over the live preview and leave the
/// start lifecycle alone — was rejected on its content, not its cost. The
/// preparation card's own body text says the camera is used only during the
/// session, and its button says "open the camera". Drawn over a running
/// preview, both sentences are false. A card that lies about the camera is
/// worse than no card.
///
/// ## What it costs and what it buys
///
/// It moves the permission prompt from "arrived on the screen" to "asked for
/// the camera", which is the direction worth being wrong in, and it is what
/// `start_lifecycle_test.dart` was rewritten around.

/// Step one: what this is, before anything is running.
class _CoachCardScaffold extends StatelessWidget {
  const _CoachCardScaffold({
    required this.footer,
    this.onBack,
    required this.children,
  });

  final List<Widget> children;
  final Widget footer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      // A full-screen route pushed above `MainShell` (never one of its five
      // tabs), so it mounts its own sky rather than relying on an ancestor --
      // the same reason onboarding and Session each do the same
      // (`onboarding_page.dart:187-192`). Before this, these two cards were
      // the only screens in that group actually missing it: `FrostedScaffold`
      // itself is transparent by design, expecting a `HudSkyBackground`
      // ancestor to paint through it -- MainShell supplies one for every tab,
      // but this route sits outside the shell and had none, so the app's flat
      // theme colour showed through instead of a photo.
      body: HudSkyBackground(
        selection: HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
        child: FrostedScaffold(
          appBar: GlassAppBar(
            title: l10n.formcheckFormCoach,
            leading: onBack == null
                ? null
                : AppIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: l10n.commonBack,
                    onPressed: onBack,
                  ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 92, 20, 12),
                  children: children,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: footer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "what you get" or "how to stand" row.
class _CoachBullet extends StatelessWidget {
  const _CoachBullet({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HudPanel(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colors.accentPrimary),
            const SizedBox(width: 12),
            // Bug 5's lesson, applied before it can happen again: a Row with a
            // content-sized child clips instead of wrapping, and these strings
            // are translated.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colors.textSecondary)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A quiet block of small print. Used for the two camera-privacy sentences,
/// which are the only reason a user can decide whether to grant the camera at
/// all — so they are on screen BEFORE the prompt, not after it.
class _CoachFinePrint extends StatelessWidget {
  const _CoachFinePrint(this.text, {this.cardKey});

  final String text;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HudPanel(
      key: cardKey,
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colors.textSecondary,
          height: 1.5,
        ),
      ),
    );
  }
}

/// Phase [CoachPhase.launch]: what the coach does, and what it needs.
class CoachLaunchCard extends ConsumerWidget {
  const CoachLaunchCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _CoachCardScaffold(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPrimaryButton(
            key: const Key('coach.intro.start'),
            label: l10n.formcheckIntroStart,
            onPressed: () =>
                ref.read(coachPhaseControllerProvider.notifier).toPreparation(),
          ),
          const SizedBox(height: 4),
          AppTertiaryButton(
            key: const Key('coach.intro.later'),
            label: l10n.formcheckIntroLater,
            onPressed: () => GoRouter.of(context).pop(),
          ),
        ],
      ),
      children: [
        Text(l10n.formcheckIntroBody,
            key: const Key('coach.intro.body'),
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colors.textSecondary, height: 1.6)),
        const SizedBox(height: 20),
        _CoachBullet(icon: Icons.tag, title: l10n.formcheckIntroFeatureReps),
        _CoachBullet(
            icon: Icons.chat_bubble_outline,
            title: l10n.formcheckIntroFeatureCues),
        _CoachBullet(
            icon: Icons.insights_outlined,
            title: l10n.formcheckIntroFeatureSummary),
        const SizedBox(height: 6),
        _CoachFinePrint(l10n.formcheckIntroPrivacy,
            cardKey: const Key('coach.intro.privacy')),
      ],
    );
  }
}

/// Phase [CoachPhase.preparation]: how to stand, and the button that finally
/// asks for the camera.
class CoachPreparationCard extends ConsumerWidget {
  const CoachPreparationCard({super.key, required this.onOpenCamera});

  /// Opens the camera. Owned by the page, which holds the service handle and
  /// the lifecycle token; this card only says when.
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return _CoachCardScaffold(
      onBack: () => ref.read(coachPhaseControllerProvider.notifier).toLaunch(),
      footer: AppPrimaryButton(
        key: const Key('coach.prep.openCamera'),
        label: l10n.formcheckPrepOpenCamera,
        onPressed: onOpenCamera,
      ),
      children: [
        HudPanel(
          key: const Key('coach.prep.angle'),
          radius: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.accessibility_new,
                  size: 34, color: theme.colors.accentPrimary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.formcheckPrepAngleLabel.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        )),
                    const SizedBox(height: 4),
                    Text(l10n.formcheckPrepAngleValue,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    // Ours, not the prototype's. Its coach screen is authored
                    // front-on (`EXERCISE_ANGLE = 'front'`), and this app's
                    // targets are authored as side views -- the same mismatch
                    // that had the coach telling the operator he had not
                    // reached a shape he could not reach from where he stood.
                    Text(l10n.formcheckStandSideOn,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colors.textSecondary,
                          height: 1.5,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(l10n.formcheckPrepHeading.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            )),
        const SizedBox(height: 10),
        _CoachBullet(
            icon: Icons.straighten,
            title: l10n.formcheckPrepDistance,
            subtitle: l10n.formcheckPrepDistanceSub),
        _CoachBullet(
            icon: Icons.smartphone,
            title: l10n.formcheckPrepMount,
            subtitle: l10n.formcheckPrepMountSub),
        _CoachBullet(
            icon: Icons.light_mode_outlined,
            title: l10n.formcheckPrepLight,
            subtitle: l10n.formcheckPrepLightSub),
        _CoachBullet(
            icon: Icons.checkroom,
            title: l10n.formcheckPrepClothing,
            subtitle: l10n.formcheckPrepClothingSub),
        const SizedBox(height: 6),
        _CoachFinePrint(l10n.formcheckIntroPrivacy,
            cardKey: const Key('coach.prep.privacy')),
      ],
    );
  }
}
