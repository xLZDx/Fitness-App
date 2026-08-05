import 'dart:async';

import 'donor_wall_entry.dart';

/// Read + opt-in side of the donor wall.
///
/// `list()` is a public read (anyone can see the wall). `optIn()` flips
/// the user's preference; the actual write to Firestore is done by the
/// `optInDonorWall` Cloud Function which respects security rules.
abstract class DonorWallRepository {
  Future<List<DonorWallEntry>> list();
  Stream<List<DonorWallEntry>> watch();

  /// Opt-in (or update) the current user's wall entry.
  Future<void> optIn({
    required String displayName,
    String? message,
  });

  /// Opt-out — removes the current user from the wall.
  Future<void> optOut();
}

/// In-memory mock used for tests and the picker preview before Firestore
/// is wired into a build.
class MockDonorWallRepository implements DonorWallRepository {
  MockDonorWallRepository({List<DonorWallEntry>? seed})
      : _entries = List.of(seed ?? _defaultSeed) {
    _emit();
  }

  final List<DonorWallEntry> _entries;
  final StreamController<List<DonorWallEntry>> _ctrl =
      StreamController<List<DonorWallEntry>>.broadcast();
  String? _currentUid;

  void setCurrentUid(String? uid) => _currentUid = uid;

  void _emit() {
    final sorted = [..._entries]
      ..sort((a, b) {
        // Lifetime first, then most-recent.
        if (a.isLifetime != b.isLifetime) return a.isLifetime ? -1 : 1;
        return b.since.compareTo(a.since);
      });
    _ctrl.add(sorted);
  }

  @override
  Future<List<DonorWallEntry>> list() async {
    final sorted = [..._entries]
      ..sort((a, b) {
        if (a.isLifetime != b.isLifetime) return a.isLifetime ? -1 : 1;
        return b.since.compareTo(a.since);
      });
    return sorted;
  }

  @override
  Stream<List<DonorWallEntry>> watch() async* {
    yield await list();
    yield* _ctrl.stream;
  }

  @override
  Future<void> optIn({
    required String displayName,
    String? message,
  }) async {
    final uid = _currentUid;
    if (uid == null) {
      throw StateError('Sign in first to opt in to the donor wall.');
    }
    _entries.removeWhere((e) => e.uid == uid);
    _entries.add(DonorWallEntry(
      uid: uid,
      displayName: displayName.trim().isEmpty
          ? 'Anonymous supporter'
          : displayName.trim(),
      tier: 'supporter',
      since: DateTime.now(),
      message: message,
    ));
    _emit();
  }

  @override
  Future<void> optOut() async {
    final uid = _currentUid;
    if (uid == null) return;
    _entries.removeWhere((e) => e.uid == uid);
    _emit();
  }

  void dispose() => _ctrl.close();

  static List<DonorWallEntry> get _defaultSeed => [
        DonorWallEntry(
          uid: 'seed_1',
          displayName: 'A. Thompson',
          tier: 'sustainer',
          since: DateTime.now().subtract(const Duration(days: 120)),
          message: 'Keep it free. Always.',
          isLifetime: false,
        ),
        DonorWallEntry(
          uid: 'seed_2',
          displayName: 'M. Rivera',
          tier: 'supporter',
          since: DateTime.now().subtract(const Duration(days: 30)),
        ),
        DonorWallEntry(
          uid: 'seed_3',
          displayName: 'Anonymous supporter',
          tier: 'champion',
          since: DateTime.now().subtract(const Duration(days: 5)),
          isLifetime: true,
        ),
      ];
}

