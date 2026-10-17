/// Routes added by sprint S03 (design 2.3, 2.6; contract 10.6, 12).
///
/// [s03Routes] is spliced into `app_router.dart` exactly once, as top-level
/// (non-shell) routes, so no rail or bar shows on them. They are not public
/// paths: the existing redirects send a signed-out user to `/login` and a
/// not-onboarded user to `/onboarding`; no redirect rule is added here.
///
/// Opening conventions (contract J1):
///  * the chooser is opened by `context.go(kModeChooserPath)` (replace), so
///    Back does not return to the empty Home behind it;
///  * the switcher's "See all modes" uses `context.push(kModeChooserPath)`.
///
/// ## Stub pages
///
/// The three pages below are blank placeholders. Lane L6 (chooser, questions)
/// and lane L9 (Sources) write the real pages in their own files; when those
/// files exist, only the marked `// PAGE SWAP` lines in this file change. The
/// router never changes again.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/modes/data/mode_models.dart';

/// `/mode-chooser`: the first-run mode chooser (S-1).
const String kModeChooserPath = '/mode-chooser';

/// `/mode-questions/:mode`: the per-mode questions (S-2).
const String kModeQuestionsTemplate = '/mode-questions/:mode';

/// `/sources`: the data sources panel (S-8).
const String kSourcesPath = '/sources';

/// The concrete location of the questions for [mode].
String modeQuestionsPath(AppMode mode) => '/mode-questions/${mode.name}';

/// Redirect rule of `/mode-questions/:mode` (RV-15, F-44).
///
/// Returns `/home` unless [rawMode] parses to an AVAILABLE [AppMode]. Pure and
/// side-effect free: a crafted link never writes anything. [table] defaults to
/// the one availability table of the mode data layer.
String? modeQuestionsRedirect(
  String? rawMode, {
  Map<AppMode, ModeAvailability> table = kDefaultModeAvailability,
}) {
  final AppMode? mode = AppMode.tryParse(rawMode);
  if (mode == null) return '/home';
  if (availabilityOfMode(mode, table: table) != ModeAvailability.available) {
    return '/home';
  }
  return null;
}

bool _reduced(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Page builder for the new full-screen routes.
///
/// When the platform asks for reduced motion the page appears and disappears
/// with no transition; otherwise it uses the same fade-and-rise as the
/// router's `_fadeThrough`, which ignores reduced motion (contract 12 audit).
/// The setting is read once for the durations and again, live, inside the
/// transition, so flipping it while the app runs is honoured.
CustomTransitionPage<void> noTransitionIfReduced(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final bool reduced = _reduced(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    child: child,
    transitionDuration:
        reduced ? Duration.zero : const Duration(milliseconds: 360),
    reverseTransitionDuration:
        reduced ? Duration.zero : const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondary, page) {
      if (_reduced(context)) return page;
      final CurvedAnimation curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final CurvedAnimation outgoing =
          CurvedAnimation(parent: secondary, curve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: FadeTransition(
          opacity: ReverseAnimation(outgoing),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: page,
          ),
        ),
      );
    },
  );
}

/// Builds the route list. [availability] is the table `/mode-questions/:mode`
/// validates against; production uses the default table.
List<RouteBase> buildS03Routes({
  Map<AppMode, ModeAvailability> availability = kDefaultModeAvailability,
}) {
  return <RouteBase>[
    GoRoute(
      path: kModeChooserPath,
      // PAGE SWAP (L6): replace `_ModeChooserStub()` with `ModeChooserPage()`.
      pageBuilder: (context, state) =>
          noTransitionIfReduced(context, state, const _ModeChooserStub()),
    ),
    GoRoute(
      path: kModeQuestionsTemplate,
      redirect: (context, state) => modeQuestionsRedirect(
        state.pathParameters['mode'],
        table: availability,
      ),
      // PAGE SWAP (L6): replace `_ModeQuestionsStub(mode: mode)` with
      // `ModeQuestionPage(mode: mode)`.
      pageBuilder: (context, state) {
        // The redirect already guarantees a parsable, available mode.
        final AppMode mode = AppMode.tryParse(state.pathParameters['mode'])!;
        return noTransitionIfReduced(
            context, state, _ModeQuestionsStub(mode: mode));
      },
    ),
    GoRoute(
      path: kSourcesPath,
      // PAGE SWAP (L9): replace `_SourcesStub()` with `SourcesPage()`.
      pageBuilder: (context, state) =>
          noTransitionIfReduced(context, state, const _SourcesStub()),
    ),
  ];
}

/// The list spliced into `app_router.dart`.
final List<RouteBase> s03Routes = buildS03Routes();

// Blank placeholders: no user-visible text, so no ARB key is needed.
class _ModeChooserStub extends StatelessWidget {
  const _ModeChooserStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(key: Key('s03.stub.modeChooser'), body: SizedBox.shrink());
}

class _ModeQuestionsStub extends StatelessWidget {
  const _ModeQuestionsStub({required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) => const Scaffold(
        key: Key('s03.stub.modeQuestions'),
        body: SizedBox.shrink(),
      );
}

class _SourcesStub extends StatelessWidget {
  const _SourcesStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(key: Key('s03.stub.sources'), body: SizedBox.shrink());
}
