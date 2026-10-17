import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/background/hud_sky.dart';
import '../../core/theme/hud_tokens.dart';
import '../../core/theme/hud_typography.dart';
import '../../features/auth/state/auth_providers.dart' show authUserProvider;
import '../../features/workouts/state/active_session_status.dart';
import 'dock_widgets.dart';
import 'hud/hud_scaffold.dart';
import 'hud/hud_side_rail.dart';
import 'shell_destinations.dart';
import 'shell_dock.dart';
import 'shell_layout.dart';
import 'window_size.dart';

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

/// Tabs on which the idle Record pill shows in the bar presentation (S-4).
const List<String> _kPillPaths = <String>['/home', '/workouts', '/progress'];

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
///
/// ## S03: two presentations of one shell
///
/// The destinations come from [kShellDestinations]. The window class decides
/// the presentation: the floating bottom bar plus a dock (Compact, Medium of
/// 480 dp height or more) or the side rail (Expanded, or Medium and short). The
/// `ShellRoute` child sits under ONE `GlobalKey` so a bar/rail swap keeps its
/// element and state (RV-6). `PopScope` and [_AnnounceShellCanPop] wrap the
/// whole thing and are NOT part of the swap.
///
/// Works without a `ProviderScope` (the Back-navigation gate test pumps it
/// bare): then there is no dock and the rail Record slot is an empty
/// placeholder.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  /// The one slot of the tab page across bar and rail presentations (RV-6).
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'shell.content');

  final RailWidthMemo _railMemo = RailWidthMemo();

  /// One focus node per destination, owned here so the focused destination
  /// keeps focus when the layout switches between rail and bar (AC-WS-5).
  final List<FocusNode> _destNodes = <FocusNode>[
    for (int i = 0; i < kShellDestinations.length; i++)
      FocusNode(debugLabel: 'shell.destination.$i'),
  ];
  bool? _lastRail;

  @override
  void dispose() {
    for (final FocusNode n in _destNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selected = shellDestinationIndexFor(location);
    if (kDebugMode) {
      debugPrint('TRACE stageG shell build location=$location');
    }

    final bool hasScope =
        context.getInheritedWidgetOfExactType<UncontrolledProviderScope>() !=
            null;

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
      child: hasScope
          // Only the coarse "is a session running" bool rebuilds the frame; the
          // seconds tick lives inside the strip widget (design 2.6).
          ? Consumer(
              builder: (BuildContext c, WidgetRef ref, Widget? _) {
                final bool hasSession = ref.watch(
                    activeSessionStatusProvider.select((s) => s != null));
                // AC-A11Y-4: one polite announcement per strip transition
                // (started, paused, resumed, ended). The 30-second tick never
                // fires.
                // A rest timer alone is not a workout starting or ending.
                bool restOnly(ActiveSessionStatus s) =>
                    s.state == ActiveSessionState.resting ||
                    s.state == ActiveSessionState.restFinished;
                ref.listen<ActiveSessionStatus?>(activeSessionStatusProvider,
                    (ActiveSessionStatus? prev, ActiveSessionStatus? next) {
                  final AppLocalizations l10n = AppLocalizations.of(c);
                  final String text;
                  if (next == null) {
                    // Ended: only for the signed-in owner (an account switch
                    // or sign-out also turns the status null, silently).
                    if (prev == null || restOnly(prev)) return;
                    final String? uid =
                        ref.read(authUserProvider).valueOrNull?.uid;
                    if (uid == null ||
                        uid.isEmpty ||
                        (prev.ownerUid.isNotEmpty && prev.ownerUid != uid)) {
                      return;
                    }
                    text = l10n.stripSessionEnded;
                  } else if (prev == null) {
                    if (restOnly(next)) return;
                    text = l10n.stripSessionStarted;
                  } else {
                    final bool wasPaused =
                        prev.state == ActiveSessionState.paused;
                    final bool isPaused =
                        next.state == ActiveSessionState.paused;
                    if (wasPaused == isPaused) return;
                    text = isPaused
                        ? l10n.stripPaused
                        : l10n.stripSessionResumed;
                  }
                  // ignore: deprecated_member_use
                  unawaited(SemanticsService.announce(
                      text, Directionality.of(c)));
                });
                return _frame(c, location, selected, hasSession, ref);
              },
            )
          : _frame(context, location, selected, false, null),
    );
  }

  double _railWidthFor(BuildContext context, WidgetRef? ref, Size size,
      AppLocalizations l10n) {
    final HudTokens t = context.hud;
    final TextStyle style = HudType.navLabel(t, color: t.textSecondary);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final RailLabelMeasurer measurer =
        ref == null ? measureRailLabel : ref.read(railLabelMeasurerProvider);
    final List<String> labels = <String>[
      for (final ShellDestination d in kShellDestinations)
        d.labelOf(l10n).toUpperCase(),
    ];
    final double widest = _railMemo.widest(
      localeTag: Localizations.localeOf(context).toLanguageTag(),
      textScaleKey: scaler.scale(10),
      fontFamily: style.fontFamily,
      labels: labels,
      measurerKey: measurer,
      measure: (String label) => measurer(label, style, scaler),
    );
    return resolveRailWidth(windowWidth: size.width, widestLabel: widest);
  }

  // ---- L4b mount points ----------------------------------------------------
  // Everything the dock widgets need is passed in here; the widgets themselves
  // (RecordPill, RecordingStrip, RailRecordSlot) live in dock_widgets.dart.

  /// Anchor of the rail Record slot: the Record sheet hangs at it on Expanded.
  final GlobalKey _railRecordKey = GlobalKey(debugLabel: 'shell.rail.record');

  void _openRecord(BuildContext context, WidgetRef? ref, {GlobalKey? anchorKey}) {
    // Seam for the Record sheet (lane L6): null until it is wired.
    ref
        ?.read(shellRecordSheetOpenerProvider)
        ?.call(context, anchorKey: anchorKey);
  }

  Widget _frame(BuildContext context, String location, int selected,
      bool hasSession, WidgetRef? ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final WindowSizeInfo info = WindowSizeInfo.of(context);
    final Size size = MediaQuery.sizeOf(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final bool rail = info.usesRail;
    if (_lastRail != null &&
        _lastRail != rail &&
        _destNodes.any((FocusNode n) => n.hasFocus) &&
        selected >= 0 &&
        selected < _destNodes.length) {
      // The old presentation held focus: give it to the same destination in
      // the new one once it is mounted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _destNodes[selected].requestFocus();
      });
    }
    _lastRail = rail;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final double safeStart = rtl ? pad.right : pad.left;

    void onSelect(int i) {
      if (kDebugMode) {
        debugPrint(
            'TRACE stageE navbar onSelect i=$i path=${kShellDestinations[i].path}');
      }
      context.go(kShellDestinations[i].path);
    }

    final List<HudNavItem> items = shellNavItems(l10n);
    final bool pillTab = _kPillPaths.any(location.startsWith);
    // A session of another account hides both strip and pill (F-11).
    final bool foreignOwner =
        ref?.watch(activeSessionForeignOwnerProvider) ?? false;
    final bool dockShown =
        !rail && (hasSession || (pillTab && !foreignOwner));
    final double dockBottom = HudTokens.navBarBottom +
        HudTokens.navBarHeight +
        pad.bottom +
        kShellDockGap;
    // Large text makes the full dock taller than the room: compact too (AC-ST-9).
    final bool compactDock =
        size.height - (dockBottom + kShellDockHeight) < 240 ||
            MediaQuery.textScalerOf(context).scale(1.0) > 1.5;
    final bool medium = info.sizeClass == WindowSizeClass.medium;

    final double railWidth =
        rail ? _railWidthFor(context, ref, size, l10n) : 0;
    final bool extended = rail && railWidth > kRailCompactWidth;

    Widget? bottomBar;
    if (!rail) {
      Widget bar = Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.navMainLabel,
        child: KeyedSubtree(
          key: const ValueKey<String>('shell.bottomBar'),
          child: HudNavBar(
            items: items,
            selectedIndex: selected,
            onSelect: onSelect,
            focusNodes: _destNodes,
          ),
        ),
      );
      if (medium) {
        // Capped at 560 dp and centred; heightFactor keeps the bar's own
        // height (a bare Center would take all the height it is offered).
        bar = Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kShellBarMaxWidth + 2 * HudTokens.navBarInset,
            ),
            child: bar,
          ),
        );
      }
      bottomBar = bar;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      // The rail has nothing under the body (risk R6).
      extendBody: !rail,
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
          child: Builder(
            builder: (BuildContext bodyContext) {
              // The body's own bottom padding: with `extendBody` it already
              // includes the bar, which is exactly what `HudScreenBody` read
              // before S03, so the bar-without-dock clearance is unchanged.
              final double innerBottom =
                  MediaQuery.paddingOf(bodyContext).bottom;
              final Widget content =
                  KeyedSubtree(key: _contentKey, child: widget.child);

              if (rail) {
                final double footprint =
                    safeStart + HudTokens.navBarInset + railWidth +
                        HudTokens.navBarInset;
                return ShellLayout(
                  info: info,
                  navigation: ShellNavigation.rail,
                  railWidth: railWidth,
                  railFootprint: footprint,
                  contentStartInset: footprint + 16,
                  bottomClearance: innerBottom + 24,
                  dockHeight: 0,
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(start: footprint),
                          child: content,
                        ),
                      ),
                      Positioned.directional(
                        textDirection: Directionality.of(bodyContext),
                        start: safeStart + HudTokens.navBarInset,
                        top: pad.top + HudTokens.navBarInset,
                        bottom: pad.bottom + HudTokens.navBarInset,
                        width: railWidth,
                        child: HudSideRail(
                          items: items,
                          selectedIndex: selected,
                          onSelect: onSelect,
                          focusNodes: _destNodes,
                          extended: extended,
                          shortWindow: info.isShort,
                          semanticsLabel: l10n.navMainLabel,
                          // Always mounted on all five tabs (contract 10.4).
                          recordSlot: ref == null
                              ? SizedBox(height: extended ? 56 : 64)
                              : KeyedSubtree(
                                  key: _railRecordKey,
                                  child: RailRecordSlot(
                                    extended: extended,
                                    onRecord: () => _openRecord(context, ref,
                                        anchorKey: _railRecordKey),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final Widget? dockChild = !dockShown
                  ? null
                  : (hasSession
                      ? RecordingStrip(compact: compactDock)
                      : RecordPill(
                          compact: compactDock,
                          onPressed: () => _openRecord(context, ref),
                        ));

              return ShellLayout(
                info: info,
                navigation: ShellNavigation.bar,
                railWidth: 0,
                railFootprint: 0,
                contentStartInset: 0,
                // Today's value, plus the dock and its gap while it shows.
                bottomClearance: HudTokens.navBarBottom +
                    HudTokens.navBarHeight +
                    innerBottom +
                    24 +
                    (dockShown ? kShellDockHeight + kShellDockGap : 0),
                dockHeight: dockShown ? kShellDockHeight : 0,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: content),
                    if (dockChild != null)
                      ShellDock(
                        bottomOffset: dockBottom,
                        maxWidth: medium ? kShellBarMaxWidth : double.infinity,
                        child: dockChild,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: bottomBar,
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
