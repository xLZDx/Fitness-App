import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import 'glass_nav_bar.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _paths = ['/home', '/scan', '/workouts', '/progress', '/profile'];

  /// Built per-build rather than held as a `static final`: the labels are
  /// localised, so they have to be resolved against the current locale. A
  /// static list would freeze whichever language happened to load first.
  static List<GlassNavItem> _itemsFor(AppLocalizations l10n) => <GlassNavItem>[
        GlassNavItem(
          icon: Icons.home_outlined,
          iconSelected: Icons.home_rounded,
          label: l10n.homeHome,
          gradient: const [AppPalette.auroraPink, AppPalette.auroraViolet],
        ),
        GlassNavItem(
          icon: Icons.qr_code_scanner_outlined,
          iconSelected: Icons.qr_code_scanner,
          label: l10n.scannerScan,
          gradient: const [AppPalette.auroraViolet, AppPalette.auroraBlue],
        ),
        GlassNavItem(
          icon: Icons.fitness_center_outlined,
          iconSelected: Icons.fitness_center,
          label: l10n.workoutsTrain,
          gradient: const [AppPalette.auroraBlue, AppPalette.auroraTeal],
        ),
        GlassNavItem(
          icon: Icons.trending_up_outlined,
          iconSelected: Icons.trending_up,
          label: l10n.progressProgress,
          gradient: const [AppPalette.auroraTeal, AppPalette.auroraLime],
        ),
        GlassNavItem(
          icon: Icons.person_outline,
          iconSelected: Icons.person,
          label: l10n.profileProfile,
          gradient: const [AppPalette.auroraPeach, AppPalette.auroraPink],
        ),
      ];

  int _indexFor(String location) {
    final i = _paths.indexWhere((p) => location.startsWith(p));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selected = _indexFor(location);

    return PopScope(
      // Tab routes replace each other (`context.go`), so the shell is always
      // the bottom entry of the root navigator: an unhandled system Back
      // here would close the app. Allow that only on /home; on any other
      // tab intercept Back and step to /home instead. Detail pages are
      // pushed ABOVE the shell on the root navigator, so their pops hit the
      // top route first and are never intercepted by this scope.
      canPop: location == '/home',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: child,
        bottomNavigationBar: GlassNavBar(
          items: _itemsFor(AppLocalizations.of(context)),
          selectedIndex: selected,
          onSelect: (i) => context.go(_paths[i]),
        ),
      ),
    );
  }
}
