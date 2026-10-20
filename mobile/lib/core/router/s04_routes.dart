/// Routes added by sprint S04 (GPS recorder; S04-25, S04-12, S04-33).
///
/// [buildS04Routes] is spliced into `app_router.dart` exactly once as top-level
/// (non-shell) routes. With the recorder flag off it returns an empty list, so
/// the route table is exactly the S03 one. They are not public paths: the
/// existing redirects send a signed-out user to `/login`.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/recording/pages/gps_recording_page.dart';
import '../../features/workouts/state/active_session_status.dart'
    show kActiveSessionDefaultDestination, kGpsRecordingDestination;
import 's03_routes.dart' show noTransitionIfReduced;

/// The manual-entry location the recording page pushes by default. No dedicated
/// manual-entry page exists in S04, so it forwards to the workouts tab.
const String kGpsManualEntryPath = '/record/manual';

/// `/record/gps?mode=resume` opens the Start screen in resume mode (RS-8).
bool gpsResumeModeOf(GoRouterState state) =>
    state.uri.queryParameters['mode'] == 'resume';

List<RouteBase> buildS04Routes({required bool enabled}) {
  if (!enabled) return const <RouteBase>[];
  return <RouteBase>[
    GoRoute(
      path: kGpsRecordingDestination,
      pageBuilder: (context, state) => noTransitionIfReduced(
        context,
        state,
        GpsRecordingPage(
          resumeMode: gpsResumeModeOf(state),
          onAddManually: () => context.go(kActiveSessionDefaultDestination),
          onOpenWorkout: () => context.go(kActiveSessionDefaultDestination),
          onOpenPrivacySettings: () => context.push('/settings'),
          onClose: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
    ),
    GoRoute(
      path: kGpsManualEntryPath,
      redirect: (context, state) => kActiveSessionDefaultDestination,
    ),
  ];
}
