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
        body: _AnnounceShellCanPop(
          // Measured on the operator's S23 (2026-08-13): Back on a non-home
          // tab threw the app out to the launcher on the FIRST press, while
          // the PopScope above says it handles that case and the widget test
          // driving `popRoute()` agreed. Both were right about Dart; Android
          // was simply never asking Dart.
          //
          // `WidgetsApp` reports the framework's ability to handle Back to the
          // platform via `SystemNavigator.setFrameworkHandlesBack`, driven by
          // whatever `NavigationNotification` reached it LAST (app.dart:1367).
          // The shell route's own notification carries `canHandlePop: true` —
          // correct — but the ShellRoute's nested Navigator holds exactly one
          // route (tabs replace each other with `go`), so it dispatches
          // `canHandlePop: false`, which bubbles straight past this widget:
          // `PopScope` registers a `PopEntry` on its route, it does not listen
          // to notifications. Last word `false` -> Android keeps Back ->
          // activity finishes without Dart ever being consulted.
          //
          // The fix is the same one `Navigator.build` applies to its own
          // subtree (navigator.dart:5645-5659): intercept a `false` from below
          // and re-dispatch `true` when THIS level can handle the pop.
          canHandlePop: location != '/home',
          child: child,
        ),
        bottomNavigationBar: GlassNavBar(
          items: _itemsFor(AppLocalizations.of(context)),
          selectedIndex: selected,
          onSelect: (i) => context.go(_paths[i]),
        ),
      ),
    );
  }
}

/// Re-states a subtree's `NavigationNotification` as "this level can handle a
/// pop" when the level below says it cannot.
///
/// A notification is a one-way message: the widget it passes through cannot
/// amend it, only stop it and send a replacement. That is exactly what
/// `Navigator` does for nested navigators, and what a shell that intercepts
/// Back has to do for the navigator nested inside it — otherwise the inner
/// navigator's `false` is the last thing the platform hears.
class _AnnounceShellCanPop extends StatelessWidget {
  const _AnnounceShellCanPop({required this.canHandlePop, required this.child});

  final bool canHandlePop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: (NavigationNotification notification) {
        // Already `true`, or this level genuinely cannot help: let it pass
        // unchanged, so an ancestor still gets its say.
        if (notification.canHandlePop || !canHandlePop) return false;
        const NavigationNotification(canHandlePop: true).dispatch(context);
        return true;
      },
      child: child,
    );
  }
}
