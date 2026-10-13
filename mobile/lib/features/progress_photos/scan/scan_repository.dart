import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/progress_photos_providers.dart';
import 'scan_models.dart';
import 'scan_store.dart';

/// Persistence boundary for guided scans.
///
/// Photos are saved and deleted through the existing progress-photo path;
/// this only owns the encrypted landmark sidecar of each scan.
abstract class ScanRepository {
  /// All readable scans, newest first.
  Future<List<ScanRecord>> list();

  Future<void> save(ScanRecord r);

  /// Deletes the scan's landmark sidecar. The photos are NOT touched here.
  Future<void> delete(String id);
}

/// Resolves the signed-in account's photo store lazily, so a synchronous
/// provider can sit in front of the asynchronous store.
class LocalScanRepository implements ScanRepository {
  LocalScanRepository(this._store);

  /// Null when signed out.
  final Future<ScanStore?> Function() _store;

  Future<ScanStore> _require() async {
    final s = await _store();
    if (s == null) {
      throw StateError('Scans are unavailable: sign in to use them.');
    }
    return s;
  }

  @override
  Future<List<ScanRecord>> list() async {
    final s = await _store();
    if (s == null) return const [];
    return s.list();
  }

  @override
  Future<void> save(ScanRecord r) async => (await _require()).save(r);

  @override
  Future<void> delete(String id) async => (await _require()).delete(id);
}

final scanRepositoryProvider = Provider<ScanRepository>((ref) {
  // Watching the future makes a sign-out / account switch rebuild the
  // repository instead of leaving the previous account's store live.
  final photoStore = ref.watch(progressPhotosStoreProvider.future);
  return LocalScanRepository(() async {
    final store = await photoStore;
    if (store == null) return null;
    return ScanStore(dir: store.dir, cipher: store.cipher);
  });
});

/// Saved scans, newest first. Invalidate after a save or delete.
final scanHistoryProvider = FutureProvider<List<ScanRecord>>((ref) async {
  return ref.watch(scanRepositoryProvider).list();
});
