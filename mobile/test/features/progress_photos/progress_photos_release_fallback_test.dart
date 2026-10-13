import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/data/photo_key_store.dart';
import 'package:fitness_app/features/progress_photos/data/photo_store.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';

/// Release builds must never fall back to the Mock repository while the photo
/// store is loading, signed out or failed: the Mock showed an empty grid to a
/// user with real photos and accepted captures that vanish on restart.
ProviderContainer _container({
  required bool mockFallback,
  required Future<PhotoStore?> Function() store,
}) {
  final c = ProviderContainer(overrides: [
    progressPhotosMockFallbackProvider.overrideWithValue(mockFallback),
    progressPhotosStoreProvider.overrideWith((ref) => store()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('release + loading: explicit loading state, writes throw', () async {
    final gate = Completer<PhotoStore?>();
    final c = _container(mockFallback: false, store: () => gate.future);
    final repo = c.read(progressPhotosRepositoryProvider);
    expect(repo, isA<UnavailableProgressPhotosRepository>());
    expect((repo as UnavailableProgressPhotosRepository).loading, isTrue);
    expect(c.read(progressPhotosAreDemoProvider), isFalse);
    await expectLater(repo.takeShot(), throwsStateError);
    await expectLater(
        repo.save(Uint8List(0), angle: ProgressPhotoAngle.front),
        throwsStateError);
    await expectLater(repo.delete('x'), throwsStateError);
  });

  test('release + signed out: watch errors instead of an empty mock grid',
      () async {
    final c = _container(mockFallback: false, store: () async => null);
    await c.read(progressPhotosStoreProvider.future);
    final repo = c.read(progressPhotosRepositoryProvider);
    expect(repo, isA<UnavailableProgressPhotosRepository>());
    expect(repo, isNot(isA<MockProgressPhotosRepository>()));
    await expectLater(repo.watch(), emitsError(isA<StateError>()));
    expect(c.read(progressPhotosAreDemoProvider), isTrue);
  });

  test('release + store failure: error surfaces, no mock', () async {
    final c = _container(
        mockFallback: false,
        store: () async => throw PhotoKeyUnavailable('k', 'boom'));
    await c.read(progressPhotosStoreProvider.future).then((_) {}, onError: (_) {});
    final repo = c.read(progressPhotosRepositoryProvider);
    expect(repo, isA<UnavailableProgressPhotosRepository>());
    await expectLater(repo.takeShot(), throwsStateError);
    await expectLater(repo.watch(), emitsError(isA<StateError>()));
  });

  test('debug builds keep the Mock fallback', () async {
    final c = _container(mockFallback: true, store: () async => null);
    await c.read(progressPhotosStoreProvider.future);
    expect(c.read(progressPhotosRepositoryProvider),
        isA<MockProgressPhotosRepository>());
  });
}
