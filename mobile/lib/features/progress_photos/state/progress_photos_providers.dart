import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/camera/camera_session.dart';
import '../../auth/state/auth_providers.dart';
import '../data/aes_photo_cipher.dart';
import '../data/local_progress_photos_repository.dart';
import '../data/photo_directory.dart';
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

/// Builds the on-disk store for the SIGNED-IN account, or null when there is
/// no account to build one for.
///
/// A2-sec made both halves uid-scoped: the directory
/// (`<docs>/progress_photos/<uid>/`, see `photo_directory.dart`) and the key
/// (`progress_photos.key.v2.<uid>` in platform secure storage, see
/// [SecurePhotoKeyStore]). Watching [authUserProvider] rather than reading a
/// uid once is what makes a sign-out actually close the previous account's
/// store instead of leaving it live behind a stale provider.
///
/// Async because the documents directory, the migration and the Keystore are
/// all platform channels.
final progressPhotosStoreProvider = FutureProvider<PhotoStore?>((ref) async {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  // Signed out: no store at all, rather than a shared one. The repository
  // below falls back to the demo mock, which is what the banner already
  // describes, and no bytes are written anywhere they could outlive the
  // session.
  if (uid == null || uid.isEmpty) return null;

  final documents = await getApplicationDocumentsDirectory();
  final dir = await resolvePhotoDir(documents: documents, uid: uid);
  final key = await SecurePhotoKeyStore(uid: uid).loadOrCreate();
  return PhotoStore(dir: dir, cipher: AesPhotoCipher(key));
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
/// Two states reach it since A2-sec: the disk store has not resolved yet, or
/// there is no signed-in account to scope it to. The banner has to exist for
/// both — in either window a capture really does vanish on restart.
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
