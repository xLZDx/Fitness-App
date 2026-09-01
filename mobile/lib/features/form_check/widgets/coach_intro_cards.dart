import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/background/hud_sky.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/experimental_banner.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../subscription/data/subscription_models.dart';
import '../../subscription/state/subscription_providers.dart';

/// The one card the design puts in front of a coached set, and the reason the
/// camera is not open while it is on screen.
///
/// ## Why it is not an overlay
///
/// The obvious cheap version — draw this over the live preview and leave the
/// start lifecycle alone — was rejected on its content, not its cost. The body
/// text says the camera is used only during the session, and the button asks
/// for it. Drawn over a running preview, both sentences are false. A card that
/// lies about the camera is worse than no card.
///
/// ## Why it is ONE card and not two
///
/// It was two — "what this does" and then "how to stand" — and the operator
/// asked for them merged (2026-09-01), together with the two banners that used
/// to sit past the camera on the exercise picker: the experimental warning and
/// the sustainer-tier card. The reasoning is the same for all four pieces:
/// everything the user needs in order to DECIDE belongs before the camera
/// opens, and nothing that is merely a caveat belongs after it, where it reads
/// as an excuse rather than a warning.
///
/// ## What it costs and what it buys
///
/// It moves the permission prompt from "arrived on the screen" to "asked for
/// the camera", which is the direction worth being wrong in, and it is what
/// `start_lifecycle_test.dart` was rewritten around.

/// The page furniture every pre-camera card shares: sky, glass app bar, a
/// scrolling body and a pinned footer.
class _CoachCardScaffold extends StatelessWidget {
  const _CoachCardScaffold({required this.footer, required this.children});

  final List<Widget> children;
  final Widget footer;

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
          // No CUSTOM leading control any more. The old cards supplied one
          // because "back" meant the previous card in a two-step flow; with one
          // card there is no previous step. `AppBar`'s own automatic back
          // button stays -- it means "leave the coach", which is a real thing
          // to want and is what "Позже" does too. Said "no back arrow" in an
          // earlier draft, which was simply wrong: `automaticallyImplyLeading`
          // defaults to true and this route is pushed, so Flutter draws one.
          // Caught in review of this gate.
          appBar: GlassAppBar(title: l10n.formcheckFormCoach),
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
  const _CoachBullet(
      {super.key, required this.icon, required this.title, this.subtitle});

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

/// The sustainer-tier pitch, on the card the user reads before deciding.
///
/// It used to sit on the exercise picker, which is past the camera: by then the
/// user had already granted a permission for a feature they may not be able to
/// use. Public rather than private to this file because the picker's copy was
/// deleted when this one appeared, and one widget in one place is the point.
class CoachSustainerCard extends StatelessWidget {
  const CoachSustainerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return HudPanel(
      onTap: () => GoRouter.of(context).push('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.formcheckFormCoachIsASustainerBenefit,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          // Was a raw English literal quoting a competitor's hardware price.
          // Localized, and the unverifiable price claim dropped — what the
          // feature actually does is the honest version of the same pitch.
          Text(l10n.formcheckUpgradeSubtitle, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Phase [CoachPhase.launch]: everything the user needs before the camera.
///
/// What the coach does, what it cannot do, what it costs, how to stand — and
/// then the button that asks for the camera. Nothing is running while this is
/// on screen, which is what makes the privacy sentence at the bottom true at
/// the moment it is read rather than in retrospect.
class CoachIntroCard extends ConsumerWidget {
  const CoachIntroCard({super.key, required this.onOpenCamera});

  /// Opens the camera. Owned by the page, which holds the service handle and
  /// the lifecycle token; this card only says when.
  final VoidCallback onOpenCamera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isPremium =
        ref.watch(effectiveTierProvider) == SubscriptionTier.celebrityTrainer;

    return _CoachCardScaffold(
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPrimaryButton(
            key: const Key('coach.intro.openCamera'),
            label: l10n.formcheckPrepOpenCamera,
            onPressed: onOpenCamera,
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
        // A1. First, above the pitch: what the coach can and cannot tell you is
        // not a footnote under the offer to pay for it.
        ExperimentalBanner(
            key: const Key('coach.intro.experimental'),
            message: l10n.experimentalFormCoach),
        // The upsell, unlike the warning above it, waits for the subscription
        // stream: `entitlementResolvedProvider` is false until then, and
        // telling somebody who pays that they do not is worse than showing the
        // pitch a moment late. Consequence, accepted knowingly: a user who taps
        // the button faster than that stream answers never sees this card.
        // Review of this gate asked for the BUTTON to be blocked until
        // resolution instead; refused, because
        // `subscription_providers.dart:95-98` makes exactly the opposite
        // choice for exactly this provider -- "a feature that stays locked for
        // the half-second before the stream answers costs a flicker" -- and
        // gating a camera on a network round-trip is a worse failure than a
        // late pitch. The safety warning above is unconditional, which is the
        // part that actually had to precede the permission.
        if (!isPremium && ref.watch(entitlementResolvedProvider)) ...[
          const CoachSustainerCard(key: Key('coach.intro.sustainer')),
          const SizedBox(height: 16),
        ],
        Text(l10n.formcheckIntroBody,
            key: const Key('coach.intro.body'),
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colors.textSecondary, height: 1.6)),
        const SizedBox(height: 20),
        _CoachBullet(
            key: const Key('coach.intro.feature.reps'),
            icon: Icons.tag,
            title: l10n.formcheckIntroFeatureReps),
        _CoachBullet(
            key: const Key('coach.intro.feature.cues'),
            icon: Icons.chat_bubble_outline,
            title: l10n.formcheckIntroFeatureCues),
        _CoachBullet(
            key: const Key('coach.intro.feature.summary'),
            icon: Icons.insights_outlined,
            title: l10n.formcheckIntroFeatureSummary),
        const SizedBox(height: 20),
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
            key: const Key('coach.prep.distance'),
            icon: Icons.straighten,
            title: l10n.formcheckPrepDistance,
            subtitle: l10n.formcheckPrepDistanceSub),
        _CoachBullet(
            key: const Key('coach.prep.mount'),
            icon: Icons.smartphone,
            title: l10n.formcheckPrepMount,
            subtitle: l10n.formcheckPrepMountSub),
        _CoachBullet(
            key: const Key('coach.prep.light'),
            icon: Icons.light_mode_outlined,
            title: l10n.formcheckPrepLight,
            subtitle: l10n.formcheckPrepLightSub),
        _CoachBullet(
            key: const Key('coach.prep.clothing'),
            icon: Icons.checkroom,
            title: l10n.formcheckPrepClothing,
            subtitle: l10n.formcheckPrepClothingSub),
        const SizedBox(height: 6),
        _CoachFinePrint(l10n.formcheckIntroPrivacy,
            cardKey: const Key('coach.intro.privacy')),
      ],
    );
  }
}
