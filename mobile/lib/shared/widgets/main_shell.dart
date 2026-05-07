import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import 'glass_nav_bar.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _paths = ['/home', '/scan', '/workouts', '/progress', '/profile'];

  static final _items = <GlassNavItem>[
    const GlassNavItem(
      icon: Icons.home_outlined,
      iconSelected: Icons.home_rounded,
      label: 'Home',
      gradient: [AppPalette.auroraPink, AppPalette.auroraViolet],
    ),
    const GlassNavItem(
      icon: Icons.qr_code_scanner_outlined,
      iconSelected: Icons.qr_code_scanner,
      label: 'Scan',
      gradient: [AppPalette.auroraViolet, AppPalette.auroraBlue],
    ),
    const GlassNavItem(
      icon: Icons.fitness_center_outlined,
      iconSelected: Icons.fitness_center,
      label: 'Train',
      gradient: [AppPalette.auroraBlue, AppPalette.auroraTeal],
    ),
    const GlassNavItem(
      icon: Icons.trending_up_outlined,
      iconSelected: Icons.trending_up,
      label: 'Progress',
      gradient: [AppPalette.auroraTeal, AppPalette.auroraLime],
    ),
    const GlassNavItem(
      icon: Icons.person_outline,
      iconSelected: Icons.person,
      label: 'Profile',
      gradient: [AppPalette.auroraPeach, AppPalette.auroraPink],
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: child,
      bottomNavigationBar: GlassNavBar(
        items: _items,
        selectedIndex: selected,
        onSelect: (i) => context.go(_paths[i]),
      ),
    );
  }
}
