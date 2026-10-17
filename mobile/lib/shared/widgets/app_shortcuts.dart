/// Keyboard shortcuts of the app (contract 10.9; design 2.6, S03-17).
///
/// `AppShortcuts` is supplied once, in the `builder:` of `MaterialApp.router`,
/// so it sits ABOVE the navigator. It therefore reads `appRouterProvider`
/// through Riverpod and reaches a context under the navigator through the
/// router's own navigator key; it needs no router context of its own.
///
/// ## Bindings (modifier = Cmd on iOS and macOS, Ctrl elsewhere)
///
///  * modifier + 1..5: Home, Workouts, Scan, Progress, Profile (the order of
///    `kShellDestinations`). Only while the current route is a shell route
///    (DT-17-4): on the workout player, the scanner or any pushed page they do
///    nothing.
///  * modifier + Shift + R: Record. While a session shows in the strip it opens
///    the strip destination and never a second start surface (DT-11-2);
///    otherwise it calls [shellRecordSheetOpenerProvider]. With the GPS
///    recorder on ([gpsRecorderEnabledProvider]) it always opens the sheet,
///    whose GPS row reads Open recording during a session (S04-24 AC-6).
///    A session of another account blocks it in every case.
///  * modifier + Shift + M: the mode switcher, through
///    [modeSwitcherOpenerProvider] (lane L6 sets it; null until then).
///  * modifier + `[`: Back with the result of system Back (F3). On a non-home
///    tab it goes to `/home`; on a pushed page it pops it; on `/home` it does
///    nothing, so a shortcut never quits the app.
///  * Cmd + `,` (iOS and macOS only): pushes `/settings`.
///
/// Esc is NOT bound here: the open surface closes itself, and Esc never
/// navigates back.
///
/// ## Guards
///
/// Nothing fires while an editable text has focus, or while the open-surface
/// depth ([openSurfaceDepthProvider]) is above zero. Known limit: a legacy
/// dialog that does not go through `AdaptiveSurface` is not counted, so a
/// shortcut can still act beneath it (design 2.6).
///
/// ## Focus
///
/// `CallbackShortcuts` sits under an autofocus root `Focus` (RV-18d), so the
/// shortcuts work from the first frame, before the user clicks anything. The
/// root does not steal focus from a child that takes it later.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../features/workouts/state/active_session_status.dart';
import 'adaptive_surface.dart';
import 'dock_widgets.dart' show openActiveSessionDestination;
import 'shell_destinations.dart';
import 'shell_dock.dart';

/// Opens the mode switcher S-3. Same shape as [ShellRecordSheetOpener]: the
/// switcher belongs to lane L6, which overrides this provider when its widget
/// exists. Null (default) makes modifier + Shift + M do nothing.
typedef ModeSwitcherOpener = void Function(BuildContext context);

final Provider<ModeSwitcherOpener?> modeSwitcherOpenerProvider =
    Provider<ModeSwitcherOpener?>((Ref ref) => null);

/// Wraps [child] (the router's navigator) with the keyboard shortcut layer.
class AppShortcuts extends ConsumerStatefulWidget {
  const AppShortcuts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShortcuts> createState() => _AppShortcutsState();
}

class _AppShortcutsState extends ConsumerState<AppShortcuts> {
  final FocusNode _root = FocusNode(debugLabel: 'app.shortcuts.root');

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  static bool _isApple(TargetPlatform p) =>
      p == TargetPlatform.macOS || p == TargetPlatform.iOS;

  /// True while a text field has keyboard focus.
  static bool _editableFocused() {
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// Runs [action] with a context under the navigator, unless a guard holds.
  void _guarded(void Function(BuildContext navContext, GoRouter router) action) {
    if (!mounted) return;
    if (_editableFocused()) return;
    if (ref.read(openSurfaceDepthProvider) > 0) return;
    final GoRouter router = ref.read(appRouterProvider);
    final BuildContext? navContext = router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null || !navContext.mounted) return;
    action(navContext, router);
  }

  /// The TOPMOST route (a page pushed with `router.push` counts); `uri.path`
  /// is only the base location of the match list and ignores pushed pages.
  static String _location(GoRouter router) =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  static bool _isShellRoute(String path) =>
      kShellDestinations.any((ShellDestination d) => d.path == path);

  void _goTab(int index) {
    _guarded((BuildContext navContext, GoRouter router) {
      if (!_isShellRoute(_location(router))) return;
      final String target = kShellDestinations[index].path;
      if (_location(router) == target) return;
      router.go(target);
    });
  }

  void _record() {
    _guarded((BuildContext navContext, GoRouter router) {
      // A session of another account blocks every Record entry point.
      if (ref.read(activeSessionForeignOwnerProvider)) return;
      // With the GPS recorder on, the sheet stays openable during a session:
      // its GPS row reads Open recording (S04-D UX8, S04-24 AC-6), so the
      // shortcut opens the sheet and not a second start surface.
      if (ref.read(activeSessionStatusProvider) != null &&
          !ref.read(gpsRecorderEnabledProvider)) {
        openActiveSessionDestination(
            navContext, ref.read(activeSessionDestinationProvider));
        return;
      }
      ref.read(shellRecordSheetOpenerProvider)?.call(navContext);
    });
  }

  void _switcher() {
    _guarded((BuildContext navContext, GoRouter router) {
      ref.read(modeSwitcherOpenerProvider)?.call(navContext);
    });
  }

  void _back() {
    _guarded((BuildContext navContext, GoRouter router) {
      final String path = _location(router);
      if (_isShellRoute(path)) {
        // Same as the shell's Back rule (F3): a non-home tab steps to /home,
        // and /home stays (a shortcut never quits the app).
        if (path != '/home') router.go('/home');
        return;
      }
      final NavigatorState? navigator = router.routerDelegate.navigatorKey.currentState;
      if (navigator != null && navigator.canPop()) navigator.pop();
    });
  }

  void _settings() {
    _guarded((BuildContext navContext, GoRouter router) {
      router.push('/settings');
    });
  }

  @override
  Widget build(BuildContext context) {
    final TargetPlatform platform = Theme.of(context).platform;
    final bool apple = _isApple(platform);

    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, meta: apple, control: !apple, shift: shift);

    final List<LogicalKeyboardKey> digits = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];

    final Map<ShortcutActivator, VoidCallback> bindings =
        <ShortcutActivator, VoidCallback>{
      for (int i = 0; i < digits.length; i++) key(digits[i]): () => _goTab(i),
      key(LogicalKeyboardKey.keyR, shift: true): _record,
      key(LogicalKeyboardKey.keyM, shift: true): _switcher,
      key(LogicalKeyboardKey.bracketLeft): _back,
      if (apple) key(LogicalKeyboardKey.comma): _settings,
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _root,
        autofocus: true,
        // The root only receives keys that nothing deeper handled; it is not a
        // tab stop of its own.
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}
