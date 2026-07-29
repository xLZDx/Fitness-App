import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
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
            content: Text('Sign-in failed: $e'),
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
                          color: Colors.white,
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
                        color: scheme.onSurface.withValues(alpha: 0.70),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _GradientButton(
                      onTap: isLoading
                          ? null
                          : () => ref
                              .read(authActionProvider.notifier)
                              .signInAnonymously(),
                      label: isLoading ? 'Signing in…' : 'Continue',
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
              Text(
                AppLocalizations.of(context).authByContinuingYouAgreeToOur,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.60),
                ),
              ),
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
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (!loading) ...[
              const SizedBox(width: 8),
              Icon(icon, color: Colors.white, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
