import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/state/ai_planner_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

void main() {
  group('generatedPlanProvider auth-restore window (MVP-1)', () {
    test('stays loading during the restore window, never a false null plan',
        () async {
      // Only authUserProvider needs overriding: on the buggy code, the
      // early `user == null` return fires before any of
      // generatedPlanProvider's other dependencies (equipment repo, fitness
      // profile, deload verdict) are ever read, so this reproduces/fixes
      // the defect in isolation from the rest of the plan-building pipeline.
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final container = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(container.dispose);

      final sub = container.listen(generatedPlanProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final duringRestore = container.read(generatedPlanProvider);
      expect(duringRestore.isLoading, isTrue,
          reason: 'a still-resolving auth stream must not be reported as '
              'signed-out (no plan)');
    });

    test('resolves to null for a genuinely signed-out user', () async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final container = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(container.dispose);

      final sub = container.listen(generatedPlanProvider, (_, __) {});
      addTearDown(sub.close);

      auth.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(generatedPlanProvider).valueOrNull, isNull);
    });
  });
}
