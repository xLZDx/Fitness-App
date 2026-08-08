import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/glass.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      if (!mounted) return;
      // Hand off to /home — the router's auth-aware redirect rewrites
      // to /login when no one is signed in yet.
      context.go('/home');
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    final scale = Tween<double>(begin: 0.92, end: 1.0).animate(fade);

    return FrostedScaffold(
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LogoOrb(),
                const SizedBox(height: 28),
                Text(
                  l10n.appTitle,
                  style:
                      Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.splashTagline,
                  style:
                      Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: context.colors.textSecondary,
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoOrb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        // R9: first frame the app shows, moved off the pre-R9 pink/violet
        // logo mark onto the design's lime family.
        gradient: const LinearGradient(
          colors: [AppPalette.auroraLime, AppPalette.auroraLimeDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppPalette.auroraLime.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: const Icon(Icons.fitness_center, size: 60, color: AppSemanticColors.onGradientInk),
    );
  }
}
