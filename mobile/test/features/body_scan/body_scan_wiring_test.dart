import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/wiring/body_scan_wiring.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_repository.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/firestore_body_scan_repository.dart';
import 'package:fitness_app/features/nutrition_plan/state/review_scheduler.dart';

import 'support/driver_harness.dart';

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        for (final p in ['/', '/progress', '/other'])
          GoRoute(path: p, builder: (_, __) => const SizedBox()),
      ],
    );

ProviderContainer _wired({FakeRunner? runner, GoRouter? router}) {
  final c = ProviderContainer(overrides: [
    weeklyReviewTriggersProvider.overrideWith((ref) {}),
    appRouterProvider.overrideWithValue(router ?? _router()),
    bodyScanRunnerProvider.overrideWithValue(runner),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('bodyScanRootOverrides', () {
    test('flag off: only the three port bindings, no Firestore overrides', () {
      expect(bodyScanRootOverrides(flags: const BodyScanFlags()), hasLength(3));
    });

    test('flag on: adds the repository and settings store bindings', () {
      expect(
          bodyScanRootOverrides(flags: const BodyScanFlags(cloudPhotos: true)),
          hasLength(5));
    });

    test('flag on and signed out: in-memory repository and settings store',
        () async {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        ...bodyScanRootOverrides(
            flags: const BodyScanFlags(cloudPhotos: true)),
      ]);
      addTearDown(c.dispose);
      c.listen(authUserProvider, (_, __) {});
      await _settle();
      expect(c.read(bodyScanRepositoryProvider), isA<InMemoryBodyScanRepository>());
      expect(c.read(bodyScanSettingsStoreProvider),
          isA<InMemoryBodyScanSettingsStore>());
      expect(c.read(bodyScanRepositoryProvider),
          isNot(isA<FirestoreBodyScanRepository>()));
    });

    test('flag off never touches the Firestore bindings', () {
      final c = ProviderContainer(
          overrides: bodyScanRootOverrides(flags: const BodyScanFlags()));
      addTearDown(c.dispose);
      expect(c.read(bodyScanRepositoryProvider), isA<InMemoryBodyScanRepository>());
      expect(c.read(bodyScanSettingsStoreProvider),
          isA<InMemoryBodyScanSettingsStore>());
    });
  });

  group('scan done bridge to the weekly review', () {
    test('each completed scan bumps the nutrition scanDone signal once',
        () async {
      final c = _wired(runner: FakeRunner());
      c.read(bodyScanRootWiringProvider);
      expect(c.read(scanDoneSignalProvider), 0);
      c.read(scanCompletedProvider.notifier).state++;
      await _settle();
      expect(c.read(scanDoneSignalProvider), 1);
      c.read(scanCompletedProvider.notifier).state++;
      await _settle();
      expect(c.read(scanDoneSignalProvider), 2);
    });

    test('no completion, no signal', () async {
      final c = _wired(runner: FakeRunner());
      c.read(bodyScanRootWiringProvider);
      await _settle();
      expect(c.read(scanDoneSignalProvider), 0);
    });
  });

  group('runner resume wiring', () {
    test('a present runner is resumed once on start', () async {
      final runner = FakeRunner();
      final c = _wired(runner: runner);
      c.read(bodyScanRootWiringProvider);
      await _settle();
      expect(runner.calls, ['resume']);
    });

    test('signed out (no runner) does nothing and does not throw', () async {
      final c = _wired();
      expect(() => c.read(bodyScanRootWiringProvider), returnsNormally);
      await _settle();
    });

    test('entering /progress resumes; staying or other routes do not',
        () async {
      final runner = FakeRunner();
      final router = _router();
      final c = _wired(runner: runner, router: router);
      c.read(bodyScanRootWiringProvider);
      await _settle();
      runner.calls.clear();

      router.go('/other');
      await _settle();
      expect(runner.calls, isEmpty);

      router.go('/progress');
      await _settle();
      expect(runner.calls, ['resume']);

      router.go('/progress');
      await _settle();
      expect(runner.calls, ['resume'], reason: 'not re-entered');

      router.go('/other');
      router.go('/progress');
      await _settle();
      expect(runner.calls, ['resume', 'resume']);
    });
  });

}
