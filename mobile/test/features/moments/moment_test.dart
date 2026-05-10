import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/moments/data/moment.dart';
import 'package:fitness_app/features/moments/data/moment_repository.dart';

void main() {
  group('shouldShowDay3Welcome', () {
    final created = DateTime(2026, 5, 1, 9, 0);
    test('hides until 48h have passed', () {
      expect(
        shouldShowDay3Welcome(
          accountCreatedAt: created,
          launchCount: 5,
          alreadyShown: false,
          now: created.add(const Duration(hours: 47)),
        ),
        isFalse,
      );
    });

    test('hides until launch count >= 3', () {
      expect(
        shouldShowDay3Welcome(
          accountCreatedAt: created,
          launchCount: 2,
          alreadyShown: false,
          now: created.add(const Duration(days: 5)),
        ),
        isFalse,
      );
    });

    test('shows once both conditions are met', () {
      expect(
        shouldShowDay3Welcome(
          accountCreatedAt: created,
          launchCount: 3,
          alreadyShown: false,
          now: created.add(const Duration(hours: 48)),
        ),
        isTrue,
      );
    });

    test('never re-fires once shown', () {
      expect(
        shouldShowDay3Welcome(
          accountCreatedAt: created,
          launchCount: 50,
          alreadyShown: true,
          now: created.add(const Duration(days: 30)),
        ),
        isFalse,
      );
    });
  });

  group('shouldShowFirstInjuryFilter', () {
    test('shows on first use, hides after', () {
      expect(
        shouldShowFirstInjuryFilter(filterUsesCount: 1, alreadyShown: false),
        isTrue,
      );
      expect(
        shouldShowFirstInjuryFilter(filterUsesCount: 1, alreadyShown: true),
        isFalse,
      );
      expect(
        shouldShowFirstInjuryFilter(filterUsesCount: 0, alreadyShown: false),
        isFalse,
      );
    });
  });

  group('MockMomentRepository', () {
    test('bumpLaunchCount sets firstLaunchAt only on first call', () async {
      final fixed = DateTime(2026, 5, 10, 8);
      final repo = MockMomentRepository(clock: () => fixed);
      expect(await repo.firstLaunchAt(), isNull);
      await repo.bumpLaunchCount();
      expect(await repo.firstLaunchAt(), fixed);

      await repo.bumpLaunchCount();
      expect(await repo.firstLaunchAt(), fixed,
          reason: 'firstLaunchAt must not be overwritten');
      expect(await repo.launchCount(), 2);
    });

    test('hasShown / markShown round-trip', () async {
      final repo = MockMomentRepository();
      expect(await repo.hasShown(MomentId.day3Welcome), isFalse);
      await repo.markShown(MomentId.day3Welcome);
      expect(await repo.hasShown(MomentId.day3Welcome), isTrue);
    });
  });
}
