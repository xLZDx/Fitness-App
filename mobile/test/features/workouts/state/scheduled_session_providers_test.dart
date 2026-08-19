import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

void main() {
  group('scheduledSessionsProvider auth-restore window (MVP-1)', () {
    test('stays loading during the restore window, never a false empty list',
        () async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final container = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(container.dispose);

      final sub = container.listen(scheduledSessionsProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final duringRestore = container.read(scheduledSessionsProvider);
      expect(duringRestore.isLoading, isTrue,
          reason: 'a still-resolving auth stream must not be reported as '
              'signed-out (no scheduled sessions)');

      auth.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(scheduledSessionsProvider).valueOrNull, isEmpty);
    });
  });
}
