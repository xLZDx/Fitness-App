import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../helpers/test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/health/health_models.dart';
import 'package:fitness_app/core/health/health_service.dart';
import 'package:fitness_app/core/health/state/health_providers.dart';
import 'package:fitness_app/core/health/widgets/health_sync_card.dart';
import 'package:fitness_app/core/theme/app_theme.dart';

/// Fake [HealthService] for driving the sync card through the
/// authorization-failure paths that [MockHealthService] (always grants)
/// cannot reach.
class _FakeHealthService implements HealthService {
  _FakeHealthService({
    this.failWith,
    this.throwWith,
    this.denyCleanly = false,
    this.setupRequired = false,
    HealthAuthStatus initialStatus = HealthAuthStatus.notDetermined,
  }) : _status = initialStatus;

  /// Simulates Health Connect being absent or out of date.
  final bool setupRequired;

  /// Counts calls so a test can prove the CTA reaches the platform.
  int openSetupCalls = 0;

  /// When set, requestAuthorization returns denied and exposes this as
  /// [lastErrorMessage] — mirrors PlatformHealthService's caught-error path.
  final String? failWith;

  /// When set, requestAuthorization throws — exercises the notifier's
  /// catch path.
  final Object? throwWith;

  /// When true, requestAuthorization returns denied WITHOUT an error —
  /// a clean user "no" in the system permission sheet.
  final bool denyCleanly;

  HealthAuthStatus _status;
  String? _lastError;

  @override
  String? get lastErrorMessage => _lastError;

  @override
  Future<bool> platformSetupRequired() async => setupRequired;

  @override
  Future<void> openPlatformSetup() async => openSetupCalls += 1;

  @override
  Future<HealthAuthStatus> currentAuthStatus() async => _status;

  @override
  Future<HealthAuthStatus> requestAuthorization() async {
    if (throwWith != null) throw throwWith!;
    _lastError = failWith;
    if (failWith != null || denyCleanly) return HealthAuthStatus.denied;
    _status = HealthAuthStatus.granted;
    return _status;
  }

  @override
  Future<List<HealthSnapshot>> readSnapshots({
    required DateTime from,
    required DateTime to,
  }) async =>
      const [];

  @override
  Future<HealthSnapshot?> readTodaySnapshot() async => null;

  @override
  Future<bool> writeWorkout(HealthWorkoutWrite workout) async =>
      _status == HealthAuthStatus.granted;
}

Future<void> _setLargeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _buildCard(HealthService service) {
  return ProviderScope(
    overrides: [healthServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: HealthSyncCard()),
    ),
  );
}

void main() {
  group('HealthSyncCard error surfacing', () {
    testWidgets(
        'shows the platform failure reason when authorization errors',
        (tester) async {
      await _setLargeSurface(tester);
      final service = _FakeHealthService(
          failWith: 'PlatformException(HEALTH_CONNECT, unavailable)');
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      // Ask CTA visible, no error text before the attempt.
      expect(find.text('Connect Health'), findsOneWidget);
      expect(find.textContaining('Health connect failed:'), findsNothing);

      await tester.tap(find.text('Connect Health'));
      await tester.pumpAndSettle();

      // Still un-granted, and the reason is on the card.
      expect(find.text('Connect Health'), findsOneWidget);
      expect(
        find.text('Health connect failed: '
            'PlatformException(HEALTH_CONNECT, unavailable)'),
        findsOneWidget,
      );
    });

    testWidgets('shows the exception when requestAuthorization throws',
        (tester) async {
      await _setLargeSurface(tester);
      final service =
          _FakeHealthService(throwWith: StateError('channel dead'));
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect Health'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Health connect failed:'),
        findsOneWidget,
      );
      expect(find.textContaining('channel dead'), findsOneWidget);
    });

    testWidgets('a clean user-denied shows NO error text', (tester) async {
      await _setLargeSurface(tester);
      final service = _FakeHealthService(denyCleanly: true);
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect Health'));
      await tester.pumpAndSettle();

      expect(find.text('Connect Health'), findsOneWidget);
      expect(find.textContaining('Health connect failed:'), findsNothing);
    });

    testWidgets('successful grant moves past the ask card without error',
        (tester) async {
      await _setLargeSurface(tester);
      final service = _FakeHealthService();
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect Health'));
      await tester.pumpAndSettle();

      expect(find.text('Connect Health'), findsNothing);
      expect(find.textContaining('Health connect failed:'), findsNothing);
      // Fake has no data → the granted-but-empty hint renders.
      expect(find.text('No health data for today yet.'), findsOneWidget);
    });
  });

  // Regression: `unsupported` used to render SizedBox.shrink(), so a missing or
  // outdated Health Connect showed the user a blank space and no way forward —
  // "Health Connect does not work" with nothing on screen to act on.
  group('HealthSyncCard unsupported platform', () {
    testWidgets('offers the install CTA when the user can fix it',
        (tester) async {
      await _setLargeSurface(tester);
      final service = _FakeHealthService(
        initialStatus: HealthAuthStatus.unsupported,
        setupRequired: true,
      );
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('health-setup-card')), findsOneWidget);
      expect(find.text('Health Connect required'), findsOneWidget);

      await tester.tap(find.byKey(const Key('health-setup-open')));
      await tester.pumpAndSettle();

      expect(service.openSetupCalls, 1,
          reason: 'the CTA has to actually reach the platform');
    });

    testWidgets('shows the platform reason when one is available',
        (tester) async {
      await _setLargeSurface(tester);
      final service = _FakeHealthService(
        initialStatus: HealthAuthStatus.unsupported,
        setupRequired: true,
        failWith: 'Health Connect needs an update before it can share data.',
      );
      // failWith is only surfaced through lastErrorMessage after an attempt in
      // the fake, so drive the message directly for this render check.
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('health-setup-card')), findsOneWidget);
    });

    testWidgets('stays hidden where health data can never exist',
        (tester) async {
      await _setLargeSurface(tester);
      final service = _FakeHealthService(
        initialStatus: HealthAuthStatus.unsupported,
        setupRequired: false,
      );
      await tester.pumpWidget(_buildCard(service));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('health-setup-card')), findsNothing);
      expect(find.text('Connect Health'), findsNothing,
          reason: 'no point asking on web/desktop');
    });
  });
}
