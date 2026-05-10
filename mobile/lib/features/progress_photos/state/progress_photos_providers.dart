import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress_photo.dart';

/// Repository boundary. Mock used by default; production uses a Storage-
/// backed impl that uploads encrypted blobs.
abstract class ProgressPhotosRepository {
  Stream<List<ProgressPhoto>> watch();
  Future<ProgressPhoto> capture();
  Future<void> delete(String id);
}

class MockProgressPhotosRepository implements ProgressPhotosRepository {
  final List<ProgressPhoto> _photos = [];

  @override
  Stream<List<ProgressPhoto>> watch() async* {
    yield List.unmodifiable(_photos);
  }

  @override
  Future<ProgressPhoto> capture() async {
    final p = ProgressPhoto(
      id: 'p_${_photos.length + 1}',
      takenAt: DateTime.now(),
      storagePath: 'mock://${_photos.length + 1}.bin',
      keyFingerprint: 'mockfp',
    );
    _photos.add(p);
    return p;
  }

  @override
  Future<void> delete(String id) async {
    _photos.removeWhere((p) => p.id == id);
  }
}

final progressPhotosRepositoryProvider =
    Provider<ProgressPhotosRepository>((_) {
  return MockProgressPhotosRepository();
});

final progressPhotosProvider =
    StreamProvider<List<ProgressPhoto>>((ref) {
  return ref.watch(progressPhotosRepositoryProvider).watch();
});

class ProgressPhotosController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> capture() async {
    state = const AsyncValue.loading();
    try {
      await ref.read(progressPhotosRepositoryProvider).capture();
      ref.invalidate(progressPhotosProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> delete(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(progressPhotosRepositoryProvider).delete(id);
      ref.invalidate(progressPhotosProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final progressPhotosControllerProvider =
    NotifierProvider<ProgressPhotosController, AsyncValue<void>>(
        ProgressPhotosController.new);
