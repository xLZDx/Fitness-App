import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/background/hud_sky.dart';
import 'hud/hud_scaffold.dart';

/// `--dart-define=HUD_PHASE=night` pins the background to one phase.
///
/// Exists because the readability of a dense surface depends on which
/// photograph is behind it, and the app picks that from the clock. Verifying a
/// fix against a dark, a medium and a bright scene therefore means moving the
/// clock — which a production Android image will not let `adb` do without
/// root. This selects a real phase through the real code path with a real
/// bundled asset; it fakes nothing, it only removes the wait.
///
/// Ignored outright in release: `kReleaseMode` is checked as well as the
/// define, so even a release build assembled with the flag set behaves
/// normally.
const String _phaseOverride = String.fromEnvironment('HUD_PHASE');

HudSkyPhase _phaseNow() {
  if (!kReleaseMode && _phaseOverride.isNotEmpty) {
    for (final HudSkyPhase p in HudSkyPhase.values) {
      if (p.key == _phaseOverride) return p;
    }
  }
  return HudSkyPhase.forTime(DateTime.now());
}

/// `--dart-define=HUD_PHOTO_SET=b` — same reasoning as [_phaseNow]. Set A
/// alone cannot reach `04_fuji_sakura` or `09_forest_lake`, the two scenes
/// that clamp [HudBackgroundProfile.denseSurfaceAlpha] at its ceiling; only
/// set B's `dawn`/`morning` do.
const String _photoSetOverride = String.fromEnvironment('HUD_PHOTO_SET');

HudPhotoSet _photoSetNow() =>
    !kReleaseMode && _photoSetOverride == 'b' ? HudPhotoSet.b : HudPhotoSet.a;

/// MVP Gate M1: the shell's chrome, rebuilt against the real HUD handoff
/// (`Fitness Glass Phone v1 - Sunset.dc.html`).
///
/// Two changes from the previous ([GlassNavBar]-based) shell, both the
/// handoff's own choice rather than a routing one — the five routes and what
/// each does are untouched, and `shellBottomObstruction` (`shell_insets.dart`)
/// reads the framework's own computed inset rather than either bar's fixed
/// height, so nothing anchored to the bottom of a tab (the scanner's sheet
/// included) needed to change for this swap:
///
///  * **`HudNavBar` replaces `GlassNavBar`.** No raised tab, no centre
///    affordance — selection is ink plus a 4px accent dot. See that widget's
///    own doc comment.
///  * **Tab order is Home · Workouts · Scan · Progress · Profile.** The old
///    shell put Scan second with a raised circle; the handoff puts it centre
///    among five equal tabs.
///
/// The photograph the whole interface floats on ([HudSkyBackground]) is
/// mounted here, once, for every tab — the handoff's own single phone frame.
/// The phase is derived from the real clock and nothing else: the background
/// SETTINGS screen that would let a user pick a scene or a density (D9) does
/// not exist yet, so the only honest default is "what time is it", not a
/// hard-coded scene.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  static const _paths = [
    '/home',
    '/workouts',
    '/scan',
    '/progress',
    '/profile',
  ];

  /// Built per-build rather than held as a `static final`: the labels are
  /// localised, so they have to be resolved against the current locale. A
  /// static list would freeze whichever language happened to load first.
  static List<HudNavItem> _itemsFor(AppLocalizations l10n) => <HudNavItem>[
        HudNavItem(icon: Icons.grid_view_rounded, label: l10n.homeHome),
        // `workoutsTrain` ("Тренировка") is the Workouts page's own title,
        // and the tab names a section, which the prototype labels
        // "Тренировки".
        HudNavItem(icon: Icons.fitness_center_rounded, label: l10n.navWorkouts),
        // `scannerScan` ("Распознавание" / "Recognition") is the page's own
        // title and stays that. A nav label is one word wide: on the
        // operator's phone the long form wrapped to two lines and pushed the
        // tab out of line with its neighbours.
        HudNavItem(icon: Icons.qr_code_scanner_rounded, label: l10n.navScan),
        HudNavItem(
            icon: Icons.show_chart_rounded, label: l10n.progressProgress),
        HudNavItem(
            icon: Icons.person_outline_rounded, label: l10n.profileProfile),
      ];

  int _indexFor(String location) {
    final i = _paths.indexWhere((p) => location.startsWith(p));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selected = _indexFor(location);
    // TRACE stageG -- SPTR_FINAL_AUTONOMOUS_PROGRAM section 5. Confirms this
    // shell actually rebuilds against the new location, i.e. the router
    // state change from a nav tap reached rendering. TEMPORARY.
    if (kDebugMode) {
      debugPrint('TRACE stageG shell build location=$location');
    }

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
        body: HudSkyBackground(
          selection: HudSkySelection(phase: _phaseNow(), photoSet: _photoSetNow()),
          child: _AnnounceShellCanPop(
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
        ),
        bottomNavigationBar: HudNavBar(
          items: _itemsFor(AppLocalizations.of(context)),
          selectedIndex: selected,
          onSelect: (i) {
            // TRACE stageE -- did the tap's onTap callback actually execute.
            // TEMPORARY, see _InputTraceListener in main.dart.
            if (kDebugMode) {
              debugPrint('TRACE stageE navbar onSelect i=$i path=${_paths[i]}');
            }
            context.go(_paths[i]);
          },
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
