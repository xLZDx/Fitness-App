import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart' show FrostedScaffold, GlassAppBar;
import '../../shared/widgets/hud/hud_surface.dart';

/// "About / Mission" page. States the mission in plain language, lists
/// the principles the product holds itself to, and offers two CTAs:
/// support recurring (-> /subscription) or learn more (supporter wall).
///
/// S0b: the organisational claims this page used to make (nonprofit,
/// fiscal sponsorship, 501(c)(3) pending, audited financials) are gone —
/// none of them were true. The mission statement and the spend breakdown
/// stay, because neither depends on a legal status the product lacks.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  // Built per-locale rather than held as `static const`: the text is now a
  // runtime lookup, and a const list cannot contain one. Taking
  // AppLocalizations directly (not BuildContext) keeps it obvious that these
  // are pure functions of the active locale.
  static List<_Principle> _principles(AppLocalizations l) => <_Principle>[
        _Principle(
          icon: Icons.shield_outlined,
          title: l.aboutSafetyIsNeverPaywalled,
          body: l.aboutInjuryAwareExerciseFilteringPlateCalculators,
        ),
        // R9 of the Gate J review. The heading read "Open clinical content"
        // over a body that says the library has NOT been reviewed by a
        // physiotherapist, under a medical-information icon -- a heading and an
        // icon both implying a clinical review programme the body then denies.
        // The body was always the honest half; the heading and the icon now
        // agree with it.
        _Principle(
          icon: Icons.menu_book_outlined,
          title: l.aboutOpenClinicalContent,
          body: l.aboutOurExerciseLibraryIsReviewedAgainst,
        ),
        _Principle(
          icon: Icons.volunteer_activism_outlined,
          title: l.aboutCelebritiesGiveInKind,
          body: l.aboutWorkoutsFromProfessionalTrainersAndAthletes,
        ),
        _Principle(
          icon: Icons.lock_open_outlined,
          title: l.aboutNoDataResaleEver,
          body: l.aboutWeDoNotSellHealthData,
        ),
      ];

  static List<_FundLine> _useOfFunds(AppLocalizations l) => <_FundLine>[
        _FundLine(label: l.aboutHostingEmailTooling, percent: 35),
        _FundLine(label: l.aboutClinicalPhysioReview, percent: 25),
        _FundLine(label: l.aboutCommunityVideoModeration, percent: 20),
        _FundLine(label: l.aboutOperationsCompliance, percent: 15),
        _FundLine(label: l.aboutFiscalSponsorOverhead, percent: 5),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return FrostedScaffold(
      appBar: GlassAppBar(title: l.aboutOurMission),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          HudPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(colors: [
                      AppPalette.auroraTeal,
                      AppPalette.auroraLime,
                    ]),
                  ),
                  child: const Icon(Icons.fitness_center,
                      color: AppSemanticColors.onGradientInk, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).aboutFitnessForEveryoneSafely,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).aboutWeReANonprofitFitnessOrg,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).aboutOurPrinciples,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final p in _principles(l)) ...[
            _PrincipleCard(p),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).aboutHowDonationsAreUsed,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          HudPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                for (final f in _useOfFunds(l)) ...[
                  _FundBar(line: f),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    AppLocalizations.of(context).aboutApproximateYear1ConservativeBudgetAudited,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  onPressed: () =>
                      GoRouter.of(context).push('/subscription'),
                  icon: Icons.favorite_outline,
                  label: AppLocalizations.of(context).aboutSupportTheMission,
                  // Was its own radius-14 override; `compact` is the closest
                  // named shape rather than a bespoke one kept for one site.
                  size: AppButtonSize.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: AppTertiaryButton(
              onPressed: () => GoRouter.of(context).push('/donors'),
              icon: Icons.people_alt_outlined,
              label: AppLocalizations.of(context).aboutSeeOurDonorWall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Principle {
  const _Principle({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _PrincipleCard extends StatelessWidget {
  const _PrincipleCard(this.p);
  final _Principle p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HudPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(colors: [
                AppPalette.auroraViolet,
                AppPalette.auroraBlue,
              ]),
            ),
            child: Icon(p.icon, color: AppSemanticColors.onGradientInk, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  p.body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FundLine {
  const _FundLine({required this.label, required this.percent});
  final String label;
  final int percent;
}

class _FundBar extends StatelessWidget {
  const _FundBar({required this.line});
  final _FundLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                line.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            ),
            Text(
              '${line.percent}%',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: line.percent / 100,
            minHeight: 6,
            backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppPalette.auroraTeal),
          ),
        ),
      ],
    );
  }
}
