import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/donor_wall/data/donor_wall_entry.dart';
import 'package:fitness_app/features/donor_wall/data/donor_wall_repository.dart';

void main() {
  group('DonorWallEntry JSON', () {
    test('round-trips with all optional fields', () {
      final original = DonorWallEntry(
        uid: 'u1',
        displayName: 'A. Donor',
        tier: 'sustainer',
        since: DateTime.utc(2026, 5, 1),
        message: 'Keep going.',
        isLifetime: true,
      );
      final back = DonorWallEntry.fromJson('u1', original.toJson());
      expect(back, original);
    });

    test('falls back to "Anonymous donor" on empty name', () {
      final back = DonorWallEntry.fromJson('u1', const {
        'displayName': '   ',
        'tier': 'supporter',
        'since': '2026-05-01T00:00:00.000Z',
      });
      expect(back.displayName, 'Anonymous donor');
    });
  });

  group('MockDonorWallRepository', () {
    test('opt-in inserts current user, sorted lifetime-first', () async {
      final repo = MockDonorWallRepository();
      repo.setCurrentUid('me');
      await repo.optIn(displayName: 'Me', message: 'hi');
      final list = await repo.list();
      expect(list.first.isLifetime, isTrue,
          reason: 'lifetime entry from seed sorts first');
      expect(list.any((e) => e.uid == 'me'), isTrue);
    });

    test('throws if no current uid is set', () async {
      final repo = MockDonorWallRepository();
      expect(
        () => repo.optIn(displayName: 'Anon'),
        throwsStateError,
      );
    });

    test('opt-out removes the user', () async {
      final repo = MockDonorWallRepository();
      repo.setCurrentUid('me');
      await repo.optIn(displayName: 'Me');
      await repo.optOut();
      final list = await repo.list();
      expect(list.any((e) => e.uid == 'me'), isFalse);
    });
  });
}
