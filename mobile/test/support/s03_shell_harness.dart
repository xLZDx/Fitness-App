import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/workouts/data/cue_player.dart';
import 'package:fitness_app/features/workouts/data/set_session.dart';
import 'package:fitness_app/features/workouts/state/rest_timer_providers.dart';
import 'package:fitness_app/features/workouts/state/set_timer_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_scaffold.dart';
import 'package:fitness_app/shared/widgets/main_shell.dart';
import 'package:fitness_app/shared/widgets/window_size.dart';

const List<String> kTabPaths = <String>[
  '/home',
  '/workouts',
  '/scan',
  '/progress',
  '/profile',
];

const SetPlan kTestSetPlan = SetPlan(
    sets: 2, workSeconds: 120, restSeconds: 30, readySeconds: 3, cueLead: 1);

/// Mutable clock for `restClockProvider`.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 17, 12);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// Presentation fake of the set timer (AC-ST-1..3 only).
class FakeSetTimer extends SetTimerController {
  FakeSetTimer(this.initial, {this.throwOnBuild = false});
  final SetTimerState initial;
  final bool throwOnBuild;
  @override
  SetTimerState build() {
    if (throwOnBuild) throw StateError('SECRET-CONTENT-123');
    return initial;
  }
}

class FakeRestTimer extends RestTimerController {
  FakeRestTimer(this.initial, {this.throwOnBuild = false});
  final RestTimerState initial;
  final bool throwOnBuild;
  @override
  RestTimerState build() {
    if (throwOnBuild) throw StateError('SECRET-CONTENT-123');
    return initial;
  }
}

SetTimerState setTimerState(SetPhase phase, {bool running = true, int left = 125}) =>
    SetTimerState(
      phase: phase,
      setNumber: 1,
      secondsLeft: left,
      totalSets: 2,
      progress: 0.2,
      running: running,
    );

/// Overrides that silence audio for the REAL set timer controller.
List<Override> realTimerOverrides(TestClock clock) => <Override>[
      cuePlayerProvider.overrideWithValue(SilentCuePlayer()),
      voiceCoachProvider
          .overrideWithValue(MockVoiceCoach(resolveText: (k) => k.name)),
      restClockProvider.overrideWithValue(clock.call),
    ];

const AuthUser kUserA = AuthUser(uid: 'uidA', displayName: 'A');
const AuthUser kUserB = AuthUser(uid: 'uidB', displayName: 'B');

class ShellFixture {
  ShellFixture(this.tester, this.router, this.clock, this.auth);
  final WidgetTester tester;
  final GoRouter router;
  final TestClock clock;
  final StreamController<AuthUser?> auth;

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MainShell)));

  String get location => router.routerDelegate.currentConfiguration.uri.path;

  Future<void> go(String path) async {
    router.go(path);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _tabPage(String path, int rows, bool useBody) {
  final List<Widget> kids = <Widget>[
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text('stub-$path', key: Key('page.title.$path')),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextButton(
        key: const Key('page.focusable'),
        onPressed: () {},
        child: const Text('x'),
      ),
    ),
    for (int i = 0; i < rows; i++)
      Padding(
        key: Key('row.$i'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const SizedBox(height: 80, child: Text('row')),
      ),
  ];
  return HudScreenBody(children: kids);
}

/// Pumps the real [MainShell] in a ShellRoute with stub tab pages and two
/// pushed routes. Window size is set through `tester.view` (DPR 1.0).
Future<ShellFixture> pumpShell(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double textScale = 1.0,
  Locale locale = const Locale('en'),
  String initial = '/home',
  List<Override> overrides = const <Override>[],
  bool disableAnimations = false,
  int rows = 3,
  Widget Function(String path)? pageFor,
  TestClock? clock,
  AuthUser? user = kUserA,
  bool windowScope = true,
  ValueNotifier<double>? scaleNotifier,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final TestClock c = clock ?? TestClock();
  final StreamController<AuthUser?> auth = StreamController<AuthUser?>.broadcast();
  addTearDown(auth.close);

  final GoRouter router = GoRouter(
    initialLocation: initial,
    routes: <RouteBase>[
      GoRoute(
        path: '/workout/:id',
        builder: (_, GoRouterState s) =>
            Scaffold(body: Text('workout-stub:${s.uri}')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('settings-stub')),
      ),
      ShellRoute(
        builder: (_, __, Widget child) => MainShell(child: child),
        routes: <RouteBase>[
          for (final String p in kTabPaths)
            GoRoute(
              path: p,
              pageBuilder: (_, GoRouterState s) => NoTransitionPage<void>(
                key: s.pageKey,
                child: pageFor != null ? pageFor(p) : _tabPage(p, rows, true),
              ),
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: <Override>[
      restClockProvider.overrideWithValue(c.call),
      authUserProvider.overrideWith((ref) async* {
        if (user != null) yield user;
        yield* auth.stream;
      }),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (BuildContext ctx, Widget? child) {
        final MediaQueryData mq = MediaQuery.of(ctx);
        Widget w = child ?? const SizedBox.shrink();
        if (windowScope) w = WindowSizeScope(child: w);
        if (scaleNotifier != null) {
          return ValueListenableBuilder<double>(
            valueListenable: scaleNotifier,
            builder: (BuildContext _, double sc, Widget? __) => MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(sc),
                disableAnimations: disableAnimations,
              ),
              child: w,
            ),
          );
        }
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: w,
        );
      },
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return ShellFixture(tester, router, c, auth);
}

Future<void> resizeTo(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// True when the primary focus sits under a widget with [key].
bool focusIsWithin(Key key) {
  final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget.key == key) return true;
  bool found = false;
  ctx.visitAncestorElements((Element e) {
    if (e.widget.key == key) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
