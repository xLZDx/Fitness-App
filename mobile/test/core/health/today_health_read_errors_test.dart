import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/health/health_models.dart';
import 'package:fitness_app/core/health/health_service.dart';
import 'package:fitness_app/core/health/state/health_providers.dart';
import 'package:fitness_app/core/health/widgets/health_sync_card.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

import '../../helpers/test_app.dart';

/// NEW-HEALTH-ERR. A failed read must reach the UI as an error rather than as
/// "no data today", and a permission revoked while the app runs must be
/// noticed the next time the today read comes back empty.
///
/// `PlatformHealthService.readSnapshots` itself (the `rethrow`) needs a live
/// `health` plugin and `Platform.isAndroid/isIOS`, which a host test cannot
/// provide; the providers and the card are what these tests drive.
class _ScriptedHealthService implements HealthService {
  _ScriptedHealthService({
    this.status = HealthAuthStatus.granted,
    this.today,
    this.readError,
  });

  HealthAuthStatus status;
  HealthSnapshot? today;
  Object? readError;

  int statusCalls = 0;
  int todayCalls = 0;

  @override
  String? get lastErrorMessage => null;

  @override
  Future<HealthAuthStatus> currentAuthStatus() async {
    statusCalls += 1;
    return status;
  }

  @override
  Future<HealthAuthStatus> requestAuthorization() async => status;

  @override
  Future<bool> platformSetupRequired() async => false;

  @override
  Future<void> openPlatformSetup() async {}

  @override
  Future<List<HealthSnapshot>> readSnapshots({
    required DateTime from,
    required DateTime to,
  }) async {
    if (readError != null) throw readError!;
    return today == null ? const [] : [today!];
  }

  @override
  Future<HealthSnapshot?> readTodaySnapshot() async {
    todayCalls += 1;
    if (readError != null) throw readError!;
    return today;
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutWrite workout) async => true;
}

ProviderContainer _container(_ScriptedHealthService service) {
  final c = ProviderContainer(
    overrides: [healthServiceProvider.overrideWithValue(service)],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _card(_ScriptedHealthService service) => ProviderScope(
      overrides: [healthServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: HealthSyncCard()),
      ),
    );

void main() {
  group('todayHealthProvider', () {
    test('a failed read is an error, not an empty "no data" value', () async {
      final service = _ScriptedHealthService(readError: StateError('hc down'));
      final c = _container(service);
      c.listen(todayHealthProvider, (_, __) {});

      await expectLater(c.read(todayHealthProvider.future),
          throwsA(isA<StateError>()));

      final state = c.read(todayHealthProvider);
      expect(state.hasError, isTrue);
      expect(state.hasValue, isFalse,
          reason: 'null would render as "No health data today"');
    });

    test('a snapshot passes through and does not re-check the auth status',
        () async {
      final snap = HealthSnapshot(dateUtc: _day, steps: 4200);
      final service = _ScriptedHealthService(today: snap);
      final c = _container(service);
      c.listen(healthAuthStatusProvider, (_, __) {});
      await c.read(healthAuthStatusProvider.future);
      c.listen(todayHealthProvider, (_, __) {});

      final got = await c.read(todayHealthProvider.future);
      await pumpEventQueue();

      expect(got?.steps, 4200);
      expect(service.statusCalls, 1, reason: 'only the initial cached read');
    });

    test('an empty read after a revoke refreshes the cached auth status',
        () async {
      final service = _ScriptedHealthService(status: HealthAuthStatus.granted);
      final c = _container(service);
      c.listen(healthAuthStatusProvider, (_, __) {});
      c.listen(todayHealthProvider, (_, __) {});
      expect(await c.read(healthAuthStatusProvider.future),
          HealthAuthStatus.granted);

      // Permission revoked in system settings while the app is running.
      service.status = HealthAuthStatus.notDetermined;
      c.invalidate(todayHealthProvider);
      expect(await c.read(todayHealthProvider.future), isNull);
      await pumpEventQueue();

      expect(await c.read(healthAuthStatusProvider.future),
          HealthAuthStatus.notDetermined,
          reason: 'the stale "granted" cache must have been invalidated');
    });

    test('an empty read with an unchanged status leaves the cache alone',
        () async {
      final service = _ScriptedHealthService(status: HealthAuthStatus.granted);
      final c = _container(service);
      c.listen(healthAuthStatusProvider, (_, __) {});
      await c.read(healthAuthStatusProvider.future);
      c.listen(todayHealthProvider, (_, __) {});

      expect(await c.read(todayHealthProvider.future), isNull);
      await pumpEventQueue();

      // 1 initial + 1 re-check inside the today read; no third read, which
      // would mean the auth provider was needlessly invalidated and refetched.
      expect(service.statusCalls, 2);
    });
  });

  group('HealthSyncCard', () {
    testWidgets('a failed read renders the failure, not "No health data"',
        (tester) async {
      final service = _ScriptedHealthService(readError: StateError('hc down'));
      await tester.pumpWidget(_card(service));
      await tester.pumpAndSettle();

      expect(find.textContaining('Health read failed:'), findsOneWidget);
      expect(find.textContaining('hc down'), findsOneWidget);
      expect(find.text('No health data for today yet.'), findsNothing);
    });

    testWidgets('a quiet day still shows the empty hint, not a failure',
        (tester) async {
      final service = _ScriptedHealthService();
      await tester.pumpWidget(_card(service));
      await tester.pumpAndSettle();

      expect(find.text('No health data for today yet.'), findsOneWidget);
      expect(find.textContaining('Health read failed:'), findsNothing);
    });

    testWidgets('a mid-session revoke flips the card to the ask CTA',
        (tester) async {
      final service = _ScriptedHealthService();
      await tester.pumpWidget(_card(service));
      await tester.pumpAndSettle();
      expect(find.text('No health data for today yet.'), findsOneWidget);

      service.status = HealthAuthStatus.notDetermined;
      final container = ProviderScope.containerOf(
          tester.element(find.byType(HealthSyncCard)));
      container.invalidate(todayHealthProvider);
      await tester.pumpAndSettle();

      expect(find.text('Connect Health'), findsOneWidget);
      expect(find.text('No health data for today yet.'), findsNothing);
    });
  });
}

final DateTime _day = DateTime.utc(2026, 10, 13);
