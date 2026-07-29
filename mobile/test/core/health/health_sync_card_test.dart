import 'package:flutter/material.dart';
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
  _FakeHealthService({this.failWith, this.throwWith, this.denyCleanly = false});

  /// When set, requestAuthorization returns denied and exposes this as
  /// [lastErrorMessage] — mirrors PlatformHealthService's caught-error path.
  final String? failWith;

  /// When set, requestAuthorization throws — exercises the notifier's
  /// catch path.
  final Object? throwWith;

  /// When true, requestAuthorization returns denied WITHOUT an error —
  /// a clean user "no" in the system permission sheet.
  final bool denyCleanly;

  HealthAuthStatus _status = HealthAuthStatus.notDetermined;
  String? _lastError;

  @override
  String? get lastErrorMessage => _lastError;

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
}
