import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/photo_key_store.dart';
import 'package:fitness_app/features/progress_photos/data/photo_store.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';

/// R2-5: release semantics (Mock fallback off) with the real photo store
/// failing. Every repository operation throws, the Mock is never bound, and
/// the photos screen renders an explicit error instead of demo data.

final _photo = ProgressPhoto(
  id: 'p1',
  takenAt: DateTime(2026, 5, 1),
  storagePath: 'x.bin',
  keyFingerprint: 'fp',
  angle: ProgressPhotoAngle.front,
);

List<Override> _release({required Future<PhotoStore?> Function() store}) => [
      progressPhotosMockFallbackProvider.overrideWithValue(false),
      progressPhotosStoreProvider.overrideWith((ref) => store()),
    ];

Future<PhotoStore?> _failing() async =>
    throw PhotoKeyUnavailable('k', 'keystore down');

void main() {
  group('repository, store failed', () {
    late ProviderContainer c;
    late ProgressPhotosRepository repo;

    setUp(() async {
      c = ProviderContainer(overrides: _release(store: _failing));
      addTearDown(c.dispose);
      await c
          .read(progressPhotosStoreProvider.future)
          .then((_) {}, onError: (_) {});
      repo = c.read(progressPhotosRepositoryProvider);
    });

    test('is the Unavailable stand-in, never the Mock', () {
      expect(repo, isA<UnavailableProgressPhotosRepository>());
      expect(repo, isNot(isA<MockProgressPhotosRepository>()));
      expect((repo as UnavailableProgressPhotosRepository).loading, isFalse);
    });

    test('takeShot throws', () async {
      await expectLater(repo.takeShot(), throwsStateError);
    });

    test('save throws', () async {
      await expectLater(
          repo.save(Uint8List.fromList(const [1, 2, 3]),
              angle: ProgressPhotoAngle.front, weightKg: 80, note: 'n'),
          throwsStateError);
    });

    test('delete throws', () async {
      await expectLater(repo.delete('p1'), throwsStateError);
    });

    test('bytesOf throws', () async {
      await expectLater(repo.bytesOf(_photo), throwsStateError);
    });

    test('watch errors and never emits a photo list', () async {
      final values = <List<ProgressPhoto>>[];
      final errors = <Object>[];
      await repo
          .watch()
          .handleError(errors.add)
          .forEach(values.add);
      expect(values, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('the error names the cause', () async {
      await expectLater(
          repo.takeShot(),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('Progress photos are unavailable'))));
    });
  });

  group('repository, signed out (store resolves to null)', () {
    test('every write and read throws, nothing is kept', () async {
      final c = ProviderContainer(overrides: _release(store: () async => null));
      addTearDown(c.dispose);
      await c.read(progressPhotosStoreProvider.future);
      final repo = c.read(progressPhotosRepositoryProvider);
      expect(repo, isA<UnavailableProgressPhotosRepository>());
      await expectLater(repo.takeShot(), throwsStateError);
      await expectLater(
          repo.save(Uint8List(1), angle: ProgressPhotoAngle.side),
          throwsStateError);
      await expectLater(repo.delete('p1'), throwsStateError);
      await expectLater(repo.bytesOf(_photo), throwsStateError);
      await expectLater(repo.watch(), emitsError(isA<StateError>()));
    });
  });

  group('photos screen, store failed, release semantics', () {
    Widget host(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ProgressPhotosPage(),
          ),
        );

    testWidgets('shows an explicit error and no demo data', (tester) async {
      await tester.pumpWidget(host(_release(store: _failing)));
      await tester.pumpAndSettle();

      expect(find.textContaining('Progress photos are unavailable'),
          findsOneWidget);
      // No timeline body, no tiles, no capture button, no storage promise.
      expect(find.byKey(const Key('photos.body')), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byKey(const Key('photos.capture')), findsNothing);
      expect(find.textContaining('Encrypted on this phone'), findsNothing);
    });

    testWidgets('control: the debug Mock fallback DOES render the body',
        (tester) async {
      await tester.pumpWidget(host([
        progressPhotosMockFallbackProvider.overrideWithValue(true),
        progressPhotosStoreProvider.overrideWith((ref) => _failing()),
      ]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photos.body')), findsOneWidget);
      expect(find.textContaining('Progress photos are unavailable'),
          findsNothing);
    });
  });
}
