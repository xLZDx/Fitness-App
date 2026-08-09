import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'glass_nav_bar.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _paths = [
    '/home',
    '/scan',
    '/workouts',
    '/progress',
    '/profile'
  ];

  /// Built per-build rather than held as a `static final`: the labels are
  /// localised, so they have to be resolved against the current locale. A
  /// static list would freeze whichever language happened to load first.
  /// The prototype draws its five tabs with geometric glyphs — `⊞ ◎ ◈ ↗ ○`.
  /// Two of those are exact shapes Material also ships, and they are used:
  /// `⊞` is a 2×2 grid and `◉` is a ring around a dot. Two are placeholders
  /// carrying no meaning at all — a bare diamond for Workouts, a bare circle
  /// for Profile — and copying those would ship an icon that tells the user
  /// nothing; those two keep a meaningful outline icon at the same visual
  /// weight. The divergence is here, in writing, rather than discovered later
  /// as a mismatch against the reference frames.
  static List<GlassNavItem> _itemsFor(AppLocalizations l10n) => <GlassNavItem>[
        GlassNavItem(icon: Icons.grid_view_outlined, label: l10n.homeHome),
        GlassNavItem(
          icon: Icons.radio_button_checked,
          // `scannerScan` ("Распознавание" / "Recognition") is the page's
          // title and stays that. A nav label is one word wide: on the
          // operator's phone the long form wrapped to two lines and pushed
          // the tab out of line with its neighbours.
          label: l10n.navScan,
          raised: true,
        ),
        // Same split as `navScan`, for the same reason: `workoutsTrain`
        // ("Тренировка") is the Workouts page's own title, and the tab names a
        // section, which the prototype labels "Тренировки".
        GlassNavItem(icon: Icons.fitness_center, label: l10n.navWorkouts),
        GlassNavItem(icon: Icons.north_east, label: l10n.progressProgress),
        GlassNavItem(icon: Icons.person_outline, label: l10n.profileProfile),
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
