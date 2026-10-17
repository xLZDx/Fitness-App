// S03-01 onboarding hook (AC-CH-8c, 8d, DT-01-15): the real OnboardingPage in
// a stub GoRouter, a FakeModeStore with a write spy that shares a sequence
// clock with the router log. Oracle: S03_TEST_PLAN.md 2.2 (RV-1, RV-16).
import 'dart:async';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/onboarding/data/step_answered.dart';
import 'package:fitness_app/features/onboarding/onboarding_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/test_app.dart';
import '../../support/mode_fakes.dart';

class _Rig {
  _Rig(this.env, this.router, this.nav);
  final ModeEnv env;
  final GoRouter router;

  /// (sequence number, location) for every router change.
  final List<(int, String)> nav;
  String get location => router.routerDelegate.currentConfiguration.uri.path;
}

/// Bounded pumps: some onboarding steps run looping animations.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Future<_Rig> _pump(WidgetTester tester,
    {required String initial,
    FakeModeStore? store,
    SeqClock? clock,
    Completer<void>? readGate}) async {
  final c = clock ?? SeqClock();
  final fake = store ?? FakeModeStore(clock: c);
  if (readGate != null) fake.readGate = readGate;
  final env = ModeEnv(store: fake, initialUid: 'u1');
  env.profiles.emitNotOnboarded('u1');
  final nav = <(int, String)>[];
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
    GoRoute(
        path: '/onboarding/edit', builder: (_, __) => const OnboardingPage()),
    GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('home-stub'))),
    GoRoute(
        path: '/other',
        builder: (_, __) => const Scaffold(body: Text('other-stub'))),
  ]);
  addTearDown(router.dispose);
  router.routerDelegate.addListener(() => nav.add((
        c.next(),
        router.routerDelegate.currentConfiguration.uri.path,
      )));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: env.container,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
    ),
  ));
  await _settle(tester);
  return _Rig(env, router, nav);
}

/// Taps the primary button through every step; the last tap submits.
Future<void> _toLastStep(WidgetTester tester) async {
  for (var i = 0; i < kOnboardingOrder.length - 1; i++) {
    await tester.tap(find.byKey(const Key('onboarding.cta')));
    await _settle(tester);
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onboarding.cta')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late List<String> logs;
  late void Function(String? message, {int? wrapWidth}) savedDebugPrint;

  logs = [];

  // The foundation-var invariant is checked after the body: restore inside it.
  void _t(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      logs = [];
      savedDebugPrint = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      try {
        await body(tester);
      } finally {
        debugPrint = savedDebugPrint;
      }
    });
  }

  _t('AC-CH-8c finishing onboarding writes chooserStatus=pending '
      'BEFORE the router leaves for /home', (tester) async {
    final rig = await _pump(tester, initial: '/onboarding');
    await _toLastStep(tester);
    final gate = Completer<void>();
    rig.env.fake.writeGate = gate;
    await _submit(tester);
    await _settle(tester);
    // Held write: the router must still be on onboarding (write is awaited).
    expect(rig.location, '/onboarding',
        reason: 'navigation must wait behind the write (DT-01-8 seam)');
    expect(rig.env.fake.writes, isEmpty);
    gate.complete();
    await _settle(tester);
    expect(rig.location, '/home');
    final write = rig.env.fake.writes.single;
    expect(write.state.chooserStatus, ChooserStatus.pending);
    final homeEvent = rig.nav.firstWhere((e) => e.$2 == '/home');
    expect(write.seq, lessThan(homeEvent.$1),
        reason: 'the write must precede the navigation to /home');
  });

  _t('AC-CH-8d finishing from /onboarding/edit with a resolved '
      'status writes nothing', (tester) async {
    final store = FakeModeStore();
    store.stored['u1'] = ModeReadValue(ModeState(
        selectedMode: AppMode.body, chooserStatus: ChooserStatus.resolved));
    final rig = await _pump(tester, initial: '/onboarding/edit', store: store);
    await _toLastStep(tester);
    await _submit(tester);
    await _settle(tester);
    expect(rig.location, '/home');
    expect(store.writeCalls, 0);
    expect(rig.env.state.chooserStatus, ChooserStatus.resolved);
  });

  _t('AC-CH-8d the same with a migrated status', (tester) async {
    final store = FakeModeStore();
    store.stored['u1'] = ModeReadValue(ModeState(
        selectedMode: AppMode.train, chooserStatus: ChooserStatus.migrated));
    final rig = await _pump(tester, initial: '/onboarding/edit', store: store);
    await _toLastStep(tester);
    await _submit(tester);
    await _settle(tester);
    expect(rig.location, '/home');
    expect(store.writeCalls, 0);
    expect(rig.env.state.chooserStatus, ChooserStatus.migrated);
  });

  _t('DT-01-15 /hookThrows: a throwing store write still lets the '
      'user reach /home; the log is content-free', (tester) async {
    final rig = await _pump(tester, initial: '/onboarding');
    rig.env.fake.throwOnWrite = true;
    await _toLastStep(tester);
    await _submit(tester);
    await _settle(tester);
    expect(rig.location, '/home');
    expect(logs.any((l) => l.contains('StateError')), isTrue,
        reason: 'positive control: the failure is logged with its type');
    for (final l in logs) {
      expect(l.contains('store write threw'), isFalse,
          reason: 'exception message leaked: $l');
    }
  });

  _t('DT-01-15 /unmounted: the page is disposed while the mode '
      'state loads; no navigation to /home and no write follow',
      (tester) async {
    final gate = Completer<void>();
    final rig = await _pump(tester, initial: '/onboarding', readGate: gate);
    await _toLastStep(tester);
    await _submit(tester);
    rig.router.go('/other');
    await _settle(tester);
    expect(rig.location, '/other');
    gate.complete();
    await _settle(tester);
    expect(rig.location, '/other',
        reason: 'a disposed page must not navigate after the await');
    expect(find.text('home-stub'), findsNothing);
    expect(rig.env.fake.writeCalls, 0);
  });
}
