import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/live_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';

void main() {
  group('live recognition lifecycle', () {
    // Regression: liveRecognitionProvider used to be keep-alive, so the
    // camera kept streaming after the user left the Scan tab — indicator lit,
    // battery draining, classifier running on frames nobody sees.
    test('releases the camera when the last listener goes away', () async {
      final svc = MockLiveEquipmentService();
      addTearDown(svc.dispose);
      final container = ProviderContainer(overrides: [
        liveEquipmentServiceProvider.overrideWithValue(svc),
        liveModeEnabledProvider.overrideWith((_) => true),
      ]);
      addTearDown(container.dispose);

      final sub = container.listen(liveRecognitionProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(svc.isRunning, isTrue, reason: 'listener present -> streaming');

      sub.close();
      // autoDispose tears down on the next microtask turn.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(svc.isRunning, isFalse,
          reason: 'no listeners -> camera must be released');
    });

    test('live mode off never starts the camera', () async {
      final svc = MockLiveEquipmentService();
      addTearDown(svc.dispose);
      final container = ProviderContainer(overrides: [
        liveEquipmentServiceProvider.overrideWithValue(svc),
      ]);
      addTearDown(container.dispose);

      container.listen(liveRecognitionProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(svc.isRunning, isFalse);
    });

    test('toggling off releases the camera without disposing the provider',
        () async {
      final svc = MockLiveEquipmentService();
      addTearDown(svc.dispose);
      final container = ProviderContainer(overrides: [
        liveEquipmentServiceProvider.overrideWithValue(svc),
      ]);
      addTearDown(container.dispose);

      container.listen(liveRecognitionProvider, (_, __) {});
      container.read(liveModeEnabledProvider.notifier).state = true;
      await Future<void>.delayed(Duration.zero);
      expect(svc.isRunning, isTrue);

      container.read(liveModeEnabledProvider.notifier).state = false;
      await Future<void>.delayed(Duration.zero);
      expect(svc.isRunning, isFalse);
    });
  });
}
