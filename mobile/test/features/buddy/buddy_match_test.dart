import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/buddy/data/buddy_match.dart';

void main() {
  group('rankBuddies', () {
    final me = BuddyProfile(
      uid: 'me',
      displayName: 'Me',
      gymId: 'gymA',
      experienceLevel: 'intermediate',
      preferredGoals: const ['hypertrophy', 'mobility'],
    );

    test('drops self + different-gym candidates', () {
      final list = rankBuddies(me, [
        me,
        BuddyProfile(
          uid: 'other',
          displayName: 'Other',
          gymId: 'gymB',
          experienceLevel: 'intermediate',
          preferredGoals: const ['hypertrophy'],
        ),
      ]);
      expect(list, isEmpty);
    });

    test('same gym + same level + shared goal scores >= 0.9', () {
      final list = rankBuddies(me, [
        BuddyProfile(
          uid: 'twin',
          displayName: 'Twin',
          gymId: 'gymA',
          experienceLevel: 'intermediate',
          preferredGoals: const ['hypertrophy', 'mobility'],
        ),
      ]);
      expect(list, isNotEmpty);
      expect(list.first.score, greaterThanOrEqualTo(0.9));
    });

    test('partial overlap scores between 0.4 and 0.9', () {
      final list = rankBuddies(me, [
        BuddyProfile(
          uid: 'samegym',
          displayName: 'OnlyGym',
          gymId: 'gymA',
          experienceLevel: 'beginner',
          preferredGoals: const ['fat_loss'],
        ),
      ]);
      expect(list.first.score, 0.4);
    });
  });
}
