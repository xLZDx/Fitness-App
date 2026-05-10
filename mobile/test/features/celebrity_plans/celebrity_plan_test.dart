import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/celebrity_plans/data/celebrity_plan_repository.dart';

void main() {
  group('MockCelebrityPlanRepository', () {
    test('list returns at least one plan', () async {
      final repo = MockCelebrityPlanRepository();
      final plans = await repo.list();
      expect(plans, isNotEmpty);
    });

    test('byId resolves the seeded plan', () async {
      final repo = MockCelebrityPlanRepository();
      final p = await repo.byId('starter-strength-4w');
      expect(p, isNotNull);
      expect(p!.weeks, 4);
      expect(p.isInKindDonation, isTrue);
    });

    test('byId returns null for unknown id', () async {
      final repo = MockCelebrityPlanRepository();
      expect(await repo.byId('not-a-real-plan'), isNull);
    });
  });
}
