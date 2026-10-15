import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/demo_features.dart';
import '../../features/about/about_page.dart';
import '../../features/account_deletion/account_deletion_page.dart';
import '../../features/legal/privacy_page.dart';
import '../../features/legal/terms_page.dart';
import '../../features/licences/licences_page.dart';
import '../../features/ai_planner/ai_planner_page.dart';
import '../../features/auth/data/auth_user.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/state/auth_providers.dart';
import '../../features/catalog/contribute_video_page.dart';
import '../../features/catalog/moderation_page.dart';
import '../../features/celebrity_plans/celebrity_plans_page.dart';
import '../../features/community/team_feed_page.dart';
import '../../features/donor_wall/donor_wall_page.dart';
import '../../features/equipment/equipment_detail_page.dart';
import '../../features/equipment/exercise_page.dart';
import '../../features/equipment/workout_player_page.dart';
import '../../features/workouts/workout_summary_page.dart';
import '../../features/form_check/form_check_page.dart';
import '../../features/home/home_page.dart';
import '../../features/marketplace/marketplace_page.dart';
import '../../features/nutrition_plan/nutrition_profile_flow_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/data_export/backup_page.dart';
import '../../features/posture/posture_page.dart';
import '../../features/progress_photos/progress_photos_page.dart';
import '../../features/progress_photos/scan/ui/scan_capture_screen.dart';
import '../../features/progress_photos/scan/ui/scan_compare_screen.dart';
import '../../features/social_feed/social_feed_page.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/injuries_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/profile/state/profile_providers.dart';
import '../../features/progress/progress_page.dart';
import '../../features/scanner/scanner_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/subscription/subscription_page.dart';
import '../../features/workouts/workouts_page.dart';
import '../../shared/widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

// /licences is public: an attribution surface that requires a login is not a
// usable attribution surface.
const _publicPaths = {'/splash', '/login', '/about', '/donors', '/licences', '/terms', '/privacy'};

// CR-03. Authenticated account actions: reachable by any SIGNED-IN user
// before onboarding is finished, and never by a signed-out one (the sign-in
// rule above still runs first). Deleting the account you just created must not
// require completing a 10-step questionnaire. Exact matches only -- the page
// itself still demands recent re-authentication before it deletes anything.
const _accountActionPaths = {'/delete-account'};

/// Routes backed by Mock repositories; see `kDemoFeaturesEnabled`.
/// `/coaches` is deliberately absent: the marketplace has its own demo banner
/// and booking is disabled.
@visibleForTesting
bool isDemoGatedPath(String location) =>
    const {'/community', '/celebrity-plans', '/contribute', '/moderate'}
        .contains(location) ||
    location.startsWith('/team/');

/// Pure redirect resolution. Exposed for tests so the routing logic can be
/// validated without spinning up the full widget tree.
String? resolveRedirect({
  required bool isSignedIn,
  required bool isOnboarded,
  required String location,
  required bool isAnonymous,
  bool demoFeaturesEnabled = kDemoFeaturesEnabled,
}) {
  if (location == '/splash') return null;
  final isPublic = _publicPaths.contains(location);
  if (!isSignedIn && !isPublic) return '/login';
  // Demo-backed routes (Mock repositories) are unreachable when demo features
  // are off, so a deep link cannot bypass the hidden entry points. Runs after
  // the sign-in rule; `/home` then goes through the onboarding rules below.
  if (!demoFeaturesEnabled && isDemoGatedPath(location)) return '/home';
  // A guest reaching /login is the ONLY way to keep their data.
  //
  // `isSignedIn` is `user != null`, and an anonymous user is not null, so this
  // rule used to bounce a guest away from the one screen that can upgrade
  // them. The Google button there calls `linkWithCredential`, which keeps the
  // SAME uid and therefore every document under `users/{uid}` -- profile,
  // injuries, workout history, schedule. The only other route out of a guest
  // session is Sign out, which mints a fresh uid on the next sign-in and
  // orphans all of it, permanently and silently, because an anonymous account
  // has no credential to sign back into.
  //
  // So the redirect that looked like "you are already signed in, nothing to do
  // here" was closing the door on the one action that avoids data loss. A
  // signed-in ANONYMOUS user may reach /login; anybody with a real identity
  // still cannot, because for them it genuinely has nothing to offer.
  if (isSignedIn && !isAnonymous && location == '/login') {
    return isOnboarded ? '/home' : '/onboarding';
  }
  // /equipment/:id, /exercise/:id and /workout/:id are gated but accessible
  // without onboarding so a freshly scanned QR isn't dead-ended on its way
  // back from the camera.
  //
  // `/exercise/:id` joined this list the moment it existed (R3.2). It is the
  // route the machine page now opens, i.e. the first thing after a scan —
  // leaving it out would have bounced exactly the journey this exemption was
  // written for, and it would have looked like the scanner was broken.
  final isAccountAction = _accountActionPaths.contains(location);
  final isEquipmentOrWorkout = location.startsWith('/equipment/') ||
      location.startsWith('/exercise/') ||
      location.startsWith('/workout/');
  // A public path is public regardless of sign-in state, and this exclusion
  // is what makes that actually true rather than true-until-signed-in. Before
  // this, `/terms`/`/privacy`/`/about`/`/donors`/`/licences` were all listed
  // as public in `_publicPaths` but a signed-in, not-yet-onboarded user who
  // deep-linked to any of them was silently bounced to `/onboarding` anyway —
  // caught reviewing L0a, where it directly contradicted this file's own
  // "linked from Settings and login" claim for the new legal routes, and
  // equally true of the four routes that were already public.
  if (isSignedIn &&
      !isOnboarded &&
      location != '/onboarding' &&
      !isEquipmentOrWorkout &&
      !isAccountAction &&
      !isPublic) {
    return '/onboarding';
  }
  if (isSignedIn && isOnboarded && location == '/onboarding') {
    return '/home';
  }
  return null;
}

CustomTransitionPage<void> _fadeThrough(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final outgoing =
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
            child: child,
          ),
        ),
      );
    },
  );
}

/// Bridges multiple streams into a single [Listenable].
class _MultiSourceListenable extends ChangeNotifier {
  _MultiSourceListenable(List<Stream<dynamic>> streams) {
    for (final s in streams) {
      _subs.add(s.listen((_) => notifyListeners()));
    }
  }
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Forces a redirect re-evaluation without a stream event.
  void ping() => notifyListeners();

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Lifts the active user's profile stream into a single broadcast stream that
/// keeps emitting through sign-in/sign-out cycles. Used by the router's
/// refresh listenable so `/onboarding` redirects fire when the profile
/// is created or completed.
@visibleForTesting
Stream<dynamic> profileWatchOf(
  dynamic authRepo,
  ProfileRepository profileRepo,
) {
  // Forwarded into a controller rather than delegated with `yield*`.
  //
  // The `yield*` version parked here forever. A Firestore snapshot stream
  // never completes, so delegating to it meant the `await for` over
  // `authStateChanges()` never received another event: after the first
  // sign-in, no later auth change was ever processed and the previous
  // account's profile subscription was never cancelled. Sign out and in as
  // someone else and the router kept watching the old uid — a listener that
  // then fails the security rules and retries, while the new user's profile
  // was never watched at all, so `/onboarding` redirects stopped firing for
  // them.
  //
  // It also subscribed twice to the same stream, once for `sub` and once for
  // the delegation. That part cost nothing — `cloud_firestore` builds its
  // snapshot stream on a broadcast controller whose `onListen` fires only on
  // the transition from no subscribers to one, so both Dart subscriptions
  // shared a single native listener. Worth writing down because it looks like
  // a doubled read and is not.
  late StreamController<dynamic> out;
  StreamSubscription<dynamic>? authSub;
  StreamSubscription<dynamic>? profileSub;

  // CAND-01 (confirmed by a deterministic test, 2026-10-08). The auth callback
  // used to be a bare `async` closure, so with a slow subscription teardown
  // two quick auth events ran their bodies INTERLEAVED: the sign-out's
  // `profileSub = null` landed after B's `profileSub = watch(B)` and orphaned
  // B's live listener, which kept delivering a profile for a signed-out user.
  //
  // Two things close it, and both are needed:
  //  * events are handled strictly one after another (`chain`), so no body
  //    starts until the previous one has finished its await;
  //  * a generation number lets a body that finds itself superseded stop
  //    before it subscribes, and fences late emissions from an older account.
  var generation = 0;
  var closed = false;
  Future<void> chain = Future<void>.value();

  Future<void> stopWatchingProfile() async {
    // Detach first, then cancel: nothing else can see (or overwrite) the
    // subscription while the cancel is in flight.
    final old = profileSub;
    profileSub = null;
    await old?.cancel();
  }

  out = StreamController<dynamic>.broadcast(
    onListen: () {
      authSub = authRepo.authStateChanges().listen((dynamic user) {
        final gen = ++generation;
        chain = chain.then((_) async {
          try {
            // Its own guard: a throwing cancel of the OLD listener must not
            // skip subscribing the NEW user (profileSub is already detached).
            try {
              await stopWatchingProfile();
            } catch (e, st) {
              if (!closed) out.addError(e, st);
            }
            // A newer auth event arrived while the old listener was being
            // torn down, or the router is gone: it owns the next step.
            if (closed || gen != generation) return;
            if (user == null) {
              out.add(null);
              return;
            }
            profileSub = profileRepo.watch(user.uid as String).listen(
              (dynamic p) {
                if (!closed && gen == generation) out.add(p);
              },
              onError: (Object e, StackTrace st) {
                if (!closed && gen == generation) out.addError(e, st);
              },
            );
          } catch (e, st) {
            // Keep the chain alive: one failed teardown must not freeze every
            // later auth change.
            if (!closed) out.addError(e, st);
          }
        });
      });
    },
    onCancel: () async {
      closed = true;
      generation++;
      await authSub?.cancel();
      // Let an in-flight event finish so it cannot subscribe after this.
      await chain;
      await stopWatchingProfile();
    },
  );
  return out.stream;
}

/// How the router DERIVES the flags [resolveRedirect] decides on.
///
/// Split out of the `redirect` closure so the derivation is testable
/// without a widget tree. It is not a formality: [resolveRedirect] can be
/// perfectly correct about guests while the router never tells it who the
/// guest is, and a pure test of the decision cannot see that. Mounting the
/// real router to find out would mean building `/home`, i.e. the whole app
/// shell, inside a unit test. This is the seam between the two.
@visibleForTesting
String? redirectFor(
  dynamic authRepo,
  ProfileRepository profileRepo,
  String location, {
  // Whether the profile watch has delivered its first snapshot for the
  // current user. `cached()` is null both before that snapshot and when the
  // user genuinely has no profile document; only this flag tells them apart.
  bool profileLoaded = true,
  bool demoFeaturesEnabled = kDemoFeaturesEnabled,
}) {
  final AuthUser? user = authRepo.currentUser as AuthUser?;
  final profile = user == null ? null : profileRepo.cached(user.uid);
  final target = resolveRedirect(
    isSignedIn: user != null,
    isAnonymous: user?.provider == AuthProvider.anonymous,
    isOnboarded: profile?.hasCompletedOnboarding ?? false,
    location: location,
    demoFeaturesEnabled: demoFeaturesEnabled,
  );
  // Cold start: auth restored, profile snapshot not here yet. Sending the
  // user to /onboarding now would bounce an already-onboarded user through
  // the questionnaire, so hold on the splash route until it arrives.
  if (target == '/onboarding' &&
      user != null &&
      profile == null &&
      !profileLoaded) {
    return '/splash';
  }
  return target;
}

/// The application router. Reads auth state via Riverpod and redirects
/// users away from gated routes when they aren't signed in.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final profileStream = profileWatchOf(authRepo, profileRepo);

  // The uid whose profile snapshot (or error) has been delivered. Subscribed
  // BEFORE the refresh listenable so that, on a broadcast stream, it is
  // updated before the router re-runs its redirect for the same event.
  String? loadedUid;
  var held = false;
  Timer? holdTimer;
  late final _MultiSourceListenable profileListenable;
  void markLoaded(dynamic _) {
    loadedUid = (authRepo.currentUser as AuthUser?)?.uid;
  }

  final loadSub = profileStream.listen(markLoaded, onError: markLoaded);
  profileListenable = _MultiSourceListenable([
    authRepo.authStateChanges(),
    profileStream,
  ]);
  ref.onDispose(loadSub.cancel);
  ref.onDispose(() => holdTimer?.cancel());
  ref.onDispose(profileListenable.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: profileListenable,
    redirect: (context, state) {
      final uid = (authRepo.currentUser as AuthUser?)?.uid;
      final loaded = uid != null && loadedUid == uid;
      final location = state.matchedLocation;
      // The profile arrived while we were holding on the splash route: leave
      // it, and let the normal rules place the user from /home.
      if (held && location == '/splash' && (loaded || uid == null)) {
        held = false;
        holdTimer?.cancel();
        // A cancelled Timer is still non-null: clear it so a later hold
        // arms a fresh bound instead of `??=` keeping the dead one.
        holdTimer = null;
        return '/home';
      }
      final target = redirectFor(authRepo, profileRepo, location,
          profileLoaded: loaded,
          demoFeaturesEnabled: ref.read(demoFeaturesEnabledProvider));
      if (target == '/splash' && location != '/splash') {
        held = true;
        // A profile stream that never delivers must not strand the user on
        // the splash route: after the bound, decide with what is cached.
        holdTimer ??= Timer(const Duration(seconds: 5), () {
          holdTimer = null;
          loadedUid = (authRepo.currentUser as AuthUser?)?.uid;
          profileListenable.ping();
        });
      }
      return target;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, __) => _fadeThrough(const SplashPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, __) => _fadeThrough(const LoginPage()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, __) => _fadeThrough(const OnboardingPage()),
      ),
      // Distinct path so the "already onboarded -> /onboarding bounces to
      // /home" redirect below (a guard against landing an onboarded user
      // back in first-run onboarding via deep link/back button) does not
      // also block Profile's "edit your answers" tile, which deliberately
      // sends an onboarded user into the same page to revise a saved
      // answer -- OnboardingPage already resumes from the saved draft and
      // persists through the same profileSubmitProvider, so no new surface
      // is needed, only a way in that survives the redirect.
      GoRoute(
        path: '/onboarding/edit',
        pageBuilder: (_, __) => _fadeThrough(const OnboardingPage()),
      ),
      GoRoute(
        path: '/equipment/:id',
        pageBuilder: (_, state) => _fadeThrough(
          EquipmentDetailPage(
            equipmentId: state.pathParameters['id']!,
            // P2.G4: optional, present only when this page was reached from
            // a scan that resolved a server identity -- forwarded on to
            // `/exercise/:id` -> `/workout/:id` (see those routes' own
            // `scanId` params) so a later gate can correlate a scan with
            // what the user actually did with the equipment it identified.
            // Absent for every other entry point (the equipment list, a
            // deep link), exactly like `?day=` below is absent outside a
            // scheduled day.
            scanId: state.uri.queryParameters['scanId'],
          ),
        ),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (context, state) => ExercisePage(
          exerciseId: state.pathParameters['id']!,
          scanId: state.uri.queryParameters['scanId'],
        ),
      ),
      // No `:id`: the summary is of the DAY, not of one session. The app
      // writes one exercise per session (`workout_player_page.dart:265`), so a
      // per-session summary would say "1 упражнение" after every exercise —
      // see the note at the top of `day_result.dart`.
      GoRoute(
        path: '/workout-summary',
        builder: (context, state) => const WorkoutSummaryPage(),
      ),
      GoRoute(
        path: '/workout/:id',
        // `?day=` is optional and carries the scheduled day this exercise was
        // opened from. A query parameter rather than a second route, because
        // every existing link — the scanner, the AI planner, a deep link from
        // outside the app — stays valid and lands on exactly the page it
        // always did, with the day simply absent.
        pageBuilder: (_, state) => _fadeThrough(
          WorkoutPlayerPage(
            exerciseId: state.pathParameters['id']!,
            dayId: state.uri.queryParameters['day'],
            scanId: state.uri.queryParameters['scanId'],
          ),
        ),
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (_, __) => _fadeThrough(const SubscriptionPage()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (_, __) => _fadeThrough(const AboutPage()),
      ),
      GoRoute(
        path: '/licences',
        pageBuilder: (_, __) => _fadeThrough(const LicencesPage()),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (_, __) => _fadeThrough(const TermsPage()),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (_, __) => _fadeThrough(const PrivacyPage()),
      ),
      GoRoute(
        // Gated, and deliberately outside the shell: it is reached from
        // Profile and returns there, so the nav bar stays out of a form's way.
        path: '/injuries',
        pageBuilder: (_, __) => _fadeThrough(const InjuriesPage()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, __) => _fadeThrough(const SettingsPage()),
      ),
      GoRoute(
        // L0b. Reached from Settings, outside the shell for the same reason
        // /injuries is: it is a form-like flow, not a tab.
        path: '/delete-account',
        pageBuilder: (_, __) => _fadeThrough(const AccountDeletionPage()),
      ),
      GoRoute(
        path: '/donors',
        pageBuilder: (_, __) => _fadeThrough(const DonorWallPage()),
      ),
      GoRoute(
        path: '/plan',
        pageBuilder: (_, __) => _fadeThrough(const AiPlannerPage()),
      ),
      GoRoute(
        path: '/celebrity-plans',
        pageBuilder: (_, __) => _fadeThrough(const CelebrityPlansPage()),
      ),
      GoRoute(
        path: '/photos',
        pageBuilder: (_, __) => _fadeThrough(const ProgressPhotosPage()),
      ),
      GoRoute(
        // Guided self-timer body scan and the before/after compare. Both screens
        // gate themselves (age, Supporter, consent) through scanAccessProvider;
        // the redirect above already keeps signed-out and not-onboarded users out.
        path: '/photos/scan',
        pageBuilder: (_, __) => _fadeThrough(const ScanCaptureScreen()),
      ),
      GoRoute(
        path: '/photos/compare',
        pageBuilder: (_, __) => _fadeThrough(const ScanCompareScreen()),
      ),
      // C11. The "complete your nutrition profile" flow for users who already
      // finished onboarding. Only this path is registered here; the other
      // /nutrition* and /body-scan* paths are added by the commit that creates
      // each page.
      GoRoute(
        path: '/nutrition/profile',
        pageBuilder: (_, __) => _fadeThrough(const NutritionProfileFlowPage()),
      ),
      GoRoute(
        path: '/backup',
        pageBuilder: (_, __) => _fadeThrough(const BackupPage()),
      ),
      GoRoute(
        path: '/community',
        pageBuilder: (_, __) => _fadeThrough(const SocialFeedPage()),
      ),
      GoRoute(
        path: '/team/:teamId',
        pageBuilder: (_, state) => _fadeThrough(
          TeamFeedPage(teamId: state.pathParameters['teamId']!),
        ),
      ),
      GoRoute(
        path: '/form-check',
        pageBuilder: (_, __) => _fadeThrough(const FormCheckPage()),
      ),
      GoRoute(
        // Gated, outside the shell -- same reasoning as /form-check: this is
        // reached from a Home card and returns there, not a persistent tab.
        path: '/posture',
        pageBuilder: (_, __) => _fadeThrough(const PosturePage()),
      ),
      GoRoute(
        path: '/contribute',
        pageBuilder: (_, __) => _fadeThrough(const ContributeVideoPage()),
      ),
      GoRoute(
        path: '/moderate',
        pageBuilder: (_, __) => _fadeThrough(const CatalogModerationPage()),
      ),
      GoRoute(
        path: '/coaches',
        pageBuilder: (_, __) => _fadeThrough(const MarketplacePage()),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => _fadeThrough(const HomePage()),
          ),
          GoRoute(
            path: '/scan',
            pageBuilder: (_, __) => _fadeThrough(const ScannerPage()),
          ),
          GoRoute(
            path: '/workouts',
            pageBuilder: (_, __) => _fadeThrough(const WorkoutsPage()),
          ),
          GoRoute(
            path: '/progress',
            pageBuilder: (_, __) => _fadeThrough(const ProgressPage()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => _fadeThrough(const ProfilePage()),
          ),
        ],
      ),
    ],
  );
});

// Compatibility export so existing tests that imported the top-level
// `appRouter` keep working — they rebuild a fresh router via the provider.
GoRouter get appRouter => _legacyContainer.read(appRouterProvider);
final _legacyContainer = ProviderContainer();

/// Used to route the auth user type without forcing every consumer to
/// pull in the full provider file.
typedef AuthSnapshot = AuthUser?;
