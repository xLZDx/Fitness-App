import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/wear/wear_sync_service.dart';

void main() {
  group('WearWorkoutState message round-trip', () {
    test('toMessage / fromMessage preserves all fields', () {
      const state = WearWorkoutState(
        exerciseTitle: 'Squat',
        setNumber: 3,
        totalSets: 5,
        suggestedWeightKg: 80.0,
        restRemainingSeconds: 60,
        isResting: true,
      );
      final back = WearWorkoutState.fromMessage(state.toMessage());
      expect(back.exerciseTitle, state.exerciseTitle);
      expect(back.setNumber, state.setNumber);
      expect(back.totalSets, state.totalSets);
      expect(back.suggestedWeightKg, state.suggestedWeightKg);
      expect(back.restRemainingSeconds, state.restRemainingSeconds);
      expect(back.isResting, state.isResting);
    });

    test('fromMessage tolerates missing optional fields', () {
      final back = WearWorkoutState.fromMessage(const {
        'title': 'Pushup',
        'set': 1,
        'totalSets': 3,
        'rest': 0,
      });
      expect(back.suggestedWeightKg, isNull);
      expect(back.isResting, isFalse);
    });
  });

  group('MockWearSyncService', () {
    test('pushState records when paired', () async {
      final svc = MockWearSyncService();
      svc.paired = true;
      final ok = await svc.pushState(const WearWorkoutState(
        exerciseTitle: 'Squat',
        setNumber: 1,
        totalSets: 3,
        suggestedWeightKg: 60,
        restRemainingSeconds: 0,
      ));
      expect(ok, isTrue);
      expect(svc.pushed, hasLength(1));
    });

    test('pushState returns false when unpaired', () async {
      final svc = MockWearSyncService();
      final ok = await svc.pushState(const WearWorkoutState(
        exerciseTitle: 'X',
        setNumber: 1,
        totalSets: 1,
        suggestedWeightKg: 0,
        restRemainingSeconds: 0,
      ));
      expect(ok, isFalse);
    });
  });
}
