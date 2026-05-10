import 'community_video.dart';

abstract class CommunityVideoRepository {
  /// Lists submissions with the given status, newest-first.
  Future<List<CommunityVideo>> list({
    required CommunityVideoStatus status,
    int limit = 50,
  });

  /// Submit a new video URL for [exerciseId]. The actual upload (file
  /// → Storage → URL) happens client-side; this records the resulting
  /// public URL in Firestore.
  Future<CommunityVideo> submit({
    required String exerciseId,
    required String url,
    required String contributorUid,
    required String contributorDisplay,
    String? notes,
    int? lengthSeconds,
  });

  /// Approve a pending submission. Callable from a moderator account
  /// only — Cloud Function rules enforce.
  Future<void> approve(String id, {required String moderatorUid});

  /// Reject a pending submission with a reason.
  Future<void> reject(
    String id, {
    required String moderatorUid,
    required String reason,
  });
}

class MockCommunityVideoRepository implements CommunityVideoRepository {
  final List<CommunityVideo> _all = [];
  int _seq = 0;

  @override
  Future<List<CommunityVideo>> list({
    required CommunityVideoStatus status,
    int limit = 50,
  }) async {
    final out = _all.where((v) => v.status == status).toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return out.take(limit).toList();
  }

  @override
  Future<CommunityVideo> submit({
    required String exerciseId,
    required String url,
    required String contributorUid,
    required String contributorDisplay,
    String? notes,
    int? lengthSeconds,
  }) async {
    final v = CommunityVideo(
      id: 'cv_${++_seq}',
      exerciseId: exerciseId,
      url: url,
      contributorUid: contributorUid,
      contributorDisplay: contributorDisplay,
      submittedAt: DateTime.now(),
      status: CommunityVideoStatus.pending,
      notes: notes,
      lengthSeconds: lengthSeconds,
    );
    _all.add(v);
    return v;
  }

  @override
  Future<void> approve(String id,
      {required String moderatorUid}) async {
    final i = _all.indexWhere((v) => v.id == id);
    if (i < 0) return;
    final v = _all[i];
    _all[i] = CommunityVideo(
      id: v.id,
      exerciseId: v.exerciseId,
      url: v.url,
      contributorUid: v.contributorUid,
      contributorDisplay: v.contributorDisplay,
      submittedAt: v.submittedAt,
      status: CommunityVideoStatus.approved,
      notes: v.notes,
      lengthSeconds: v.lengthSeconds,
      moderatorUid: moderatorUid,
      moderatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> reject(
    String id, {
    required String moderatorUid,
    required String reason,
  }) async {
    final i = _all.indexWhere((v) => v.id == id);
    if (i < 0) return;
    final v = _all[i];
    _all[i] = CommunityVideo(
      id: v.id,
      exerciseId: v.exerciseId,
      url: v.url,
      contributorUid: v.contributorUid,
      contributorDisplay: v.contributorDisplay,
      submittedAt: v.submittedAt,
      status: CommunityVideoStatus.rejected,
      notes: reason,
      lengthSeconds: v.lengthSeconds,
      moderatorUid: moderatorUid,
      moderatedAt: DateTime.now(),
    );
  }
}
