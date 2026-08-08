import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/camera/camera_session.dart';
import '../data/aes_photo_cipher.dart';
import '../data/local_progress_photos_repository.dart';
import '../data/photo_key_store.dart';
import '../data/photo_store.dart';
import '../data/photo_timeline.dart';
import '../data/progress_photo.dart';

/// Repository boundary. Bound to [LocalProgressPhotosRepository] once
/// [progressPhotosStoreProvider] resolves; the mock covers the window before
/// that and the tests that do not care about disk.
abstract class ProgressPhotosRepository {
  Stream<List<ProgressPhoto>> watch();

  /// Returns null when the user cancelled the camera.
  Future<ProgressPhoto?> capture({ProgressPhotoAngle angle});

  Future<void> delete(String id);

  /// Decrypted pixels for one photo.
  Future<Uint8List> bytesOf(ProgressPhoto photo);
}

class MockProgressPhotosRepository implements ProgressPhotosRepository {
  final List<ProgressPhoto> _photos = [];

  @override
  Stream<List<ProgressPhoto>> watch() async* {
    yield List.unmodifiable(_photos);
  }

  @override
  Future<ProgressPhoto?> capture({
    ProgressPhotoAngle angle = ProgressPhotoAngle.front,
  }) async {
    final p = ProgressPhoto(
      id: 'p_${_photos.length + 1}',
      takenAt: DateTime.now(),
      storagePath: 'mock://${_photos.length + 1}.bin',
      keyFingerprint: 'mockfp',
      angle: angle,
    );
    _photos.add(p);
    return p;
  }

  @override
  Future<void> delete(String id) async {
    _photos.removeWhere((p) => p.id == id);
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async {
    // The mock never had pixels. Returning an empty list would render as a
    // broken image with no explanation; throwing is what the demo banner
    // above the grid is already telling the user to expect.
    throw StateError('Demo photos have no pixels.');
  }
}

/// Builds the on-disk store. Async because both the documents directory and
/// the key come from platform channels.
final progressPhotosStoreProvider = FutureProvider<PhotoStore>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  final key = await PrefsPhotoKeyStore().loadOrCreate();
  return PhotoStore(
    dir: Directory('${dir.path}/progress_photos'),
    cipher: AesPhotoCipher(key),
  );
});

/// The camera used for progress shots.
///
/// Its own session rather than a share of `scanCameraSessionProvider`: the
/// scanner's session is front-or-back depending on what it is doing and is
/// started and stopped by the scanner's own page lifecycle. Borrowing it would
/// couple a photo capture to whether the user had recently scanned a machine.
final progressPhotoCameraProvider = Provider<CameraSession>((ref) {
  final session = CameraSession();
  ref.onDispose(session.dispose);
  return session;
});

final progressPhotosRepositoryProvider =
    Provider<ProgressPhotosRepository>((ref) {
  final store = ref.watch(progressPhotosStoreProvider).valueOrNull;
  if (store == null) return MockProgressPhotosRepository();
  return LocalProgressPhotosRepository(
    store: store,
    source: CameraSessionPhotoSource(ref.watch(progressPhotoCameraProvider)),
  );
});

/// True while [progressPhotosRepositoryProvider] is still the mock.
///
/// It now means "the disk store has not resolved yet", which is a much
/// shorter window than it used to be — but the banner still has to exist,
/// because in that window a capture really does vanish on restart.
final progressPhotosAreDemoProvider = Provider<bool>((ref) {
  return ref.watch(progressPhotosRepositoryProvider)
      is MockProgressPhotosRepository;
});

final progressPhotosProvider = StreamProvider<List<ProgressPhoto>>((ref) {
  return ref.watch(progressPhotosRepositoryProvider).watch();
});

/// Timeline sections, newest month first.
final photoMonthsProvider = Provider<List<PhotoMonth>>((ref) {
  final photos = ref.watch(progressPhotosProvider).valueOrNull ?? const [];
  return groupByMonth(photos);
});

/// The pair the compare card opens on, or null when nothing is comparable.
final defaultComparePairProvider = Provider<ComparePair?>((ref) {
  final photos = ref.watch(progressPhotosProvider).valueOrNull ?? const [];
  return defaultComparePair(photos);
});

/// Decrypted pixels for one photo. Keyed by id so two tiles showing the same
/// photo share one decrypt.
final photoBytesProvider =
    FutureProvider.family<Uint8List, ProgressPhoto>((ref, photo) async {
  return ref.watch(progressPhotosRepositoryProvider).bytesOf(photo);
});

class ProgressPhotosController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> capture({
    ProgressPhotoAngle angle = ProgressPhotoAngle.front,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(progressPhotosRepositoryProvider).capture(angle: angle);
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
