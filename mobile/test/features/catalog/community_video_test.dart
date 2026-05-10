import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/catalog/data/community_video.dart';
import 'package:fitness_app/features/catalog/data/community_video_repository.dart';

void main() {
  group('MockCommunityVideoRepository', () {
    test('submitted videos default to pending status', () async {
      final repo = MockCommunityVideoRepository();
      final v = await repo.submit(
        exerciseId: 'squat',
        url: 'https://example.com/v.mp4',
        contributorUid: 'u1',
        contributorDisplay: 'Anon',
      );
      expect(v.status, CommunityVideoStatus.pending);
      final pending =
          await repo.list(status: CommunityVideoStatus.pending);
      expect(pending.length, 1);
    });

    test('approve transitions pending → approved + records moderator',
        () async {
      final repo = MockCommunityVideoRepository();
      final v = await repo.submit(
        exerciseId: 'squat',
        url: 'https://example.com/v.mp4',
        contributorUid: 'u1',
        contributorDisplay: 'Anon',
      );
      await repo.approve(v.id, moderatorUid: 'mod1');
      final pending =
          await repo.list(status: CommunityVideoStatus.pending);
      final approved =
          await repo.list(status: CommunityVideoStatus.approved);
      expect(pending, isEmpty);
      expect(approved.length, 1);
      expect(approved.first.moderatorUid, 'mod1');
    });

    test('reject records reason in notes', () async {
      final repo = MockCommunityVideoRepository();
      final v = await repo.submit(
        exerciseId: 'squat',
        url: 'https://example.com/v.mp4',
        contributorUid: 'u1',
        contributorDisplay: 'Anon',
      );
      await repo.reject(v.id, moderatorUid: 'mod1', reason: 'Blurry.');
      final rejected =
          await repo.list(status: CommunityVideoStatus.rejected);
      expect(rejected.length, 1);
      expect(rejected.first.notes, 'Blurry.');
    });
  });

  group('CommunityVideo JSON', () {
    test('round-trips the full record', () {
      final original = CommunityVideo(
        id: 'cv1',
        exerciseId: 'squat',
        url: 'https://example.com/v.mp4',
        contributorUid: 'u1',
        contributorDisplay: 'Anon',
        submittedAt: DateTime.utc(2026, 5, 1),
        status: CommunityVideoStatus.approved,
        notes: 'Looks great',
        lengthSeconds: 30,
        moderatorUid: 'mod1',
        moderatedAt: DateTime.utc(2026, 5, 2),
      );
      final back = CommunityVideo.fromJson('cv1', original.toJson());
      expect(back.exerciseId, original.exerciseId);
      expect(back.status, CommunityVideoStatus.approved);
      expect(back.moderatorUid, 'mod1');
    });
  });
}
