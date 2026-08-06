import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';
import 'state/auth_providers.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = ref.watch(authActionProvider);
    final isLoading = action.isLoading;

    ref.listen<AsyncValue<void>>(authActionProvider, (prev, next) {
      next.whenOrNull(error: (e, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(AppLocalizations.of(context).authSignInFailed(e)),
          ),
        );
      });
    });

    return FrostedScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),
              GlassCard(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            colors: [
                              AppPalette.auroraPink,
                              AppPalette.auroraViolet,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppPalette.auroraViolet
                                  .withValues(alpha: 0.45),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.fitness_center,
                          size: 40,
                          color: AppSemanticColors.onGradientInk,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      AppLocalizations.of(context).authWelcome,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context).authSignInToScanEquipmentTrack,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _GradientButton(
                      onTap: isLoading
                          ? null
                          : () => ref
                              .read(authActionProvider.notifier)
                              .signInAnonymously(),
                      label: isLoading ? AppLocalizations.of(context).authSigningIn : AppLocalizations.of(context).commonContinue,
                      icon: Icons.arrow_forward_rounded,
                      loading: isLoading,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => ref
                              .read(authActionProvider.notifier)
                              .signInWithGoogle(),
                      icon: const Icon(Icons.g_mobiledata, size: 30),
                      label: Text(AppLocalizations.of(context).authContinueWithGoogle),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Was a Text() naming "Terms and Privacy Policy" with no route
              // either word led to -- the exact shape S0a spent two gates
              // removing from the injury filter. Both are now real links.
              _TermsAndPrivacyLine(theme: theme, scheme: scheme),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onTap,
    required this.label,
    required this.icon,
    this.loading = false,
  });

  final VoidCallback? onTap;
  final String label;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: disabled
                ? [
                    AppPalette.auroraPink.withValues(alpha: 0.55),
                    AppPalette.auroraViolet.withValues(alpha: 0.55),
                  ]
                : const [AppPalette.auroraPink, AppPalette.auroraViolet],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: AppPalette.auroraViolet.withValues(alpha: 0.45),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppSemanticColors.onGradientInk),
                ),
              )
            else
              Text(
                label,
                style: const TextStyle(
                  color: AppSemanticColors.onGradientInk,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (!loading) ...[
              const SizedBox(width: 8),
              Icon(icon, color: AppSemanticColors.onGradientInk, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _TermsAndPrivacyLine extends StatelessWidget {
  const _TermsAndPrivacyLine({required this.theme, required this.scheme});
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final linkStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
    );
    final plainStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.authByContinuingYouAgree, style: plainStyle),
          // `Semantics(button: true, link: true)`, matching GlassCard's own
          // fix for the same gap elsewhere in the app (`glass.dart`): a bare
          // `GestureDetector` gives a ripple-free tap target with no
          // announcement at all, which is a strange thing to ship on the one
          // screen whose whole job is informed consent.
          Semantics(
            button: true,
            link: true,
            label: l10n.legalTermsOfService,
            child: GestureDetector(
              key: const Key('login-terms-link'),
              onTap: () => context.push('/terms'),
              child: Text(l10n.legalTermsOfService, style: linkStyle),
            ),
          ),
          Text(l10n.authAnd, style: plainStyle),
          Semantics(
            button: true,
            link: true,
            label: l10n.legalPrivacyPolicy,
            child: GestureDetector(
              key: const Key('login-privacy-link'),
              onTap: () => context.push('/privacy'),
              child: Text(l10n.legalPrivacyPolicy, style: linkStyle),
            ),
          ),
          Text('.', style: plainStyle),
        ],
      ),
    );
  }
}
