import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/photo_timeline.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:fitness_app/features/progress_photos/widgets/photo_bitmap.dart';

/// P2c. The timeline built every month it had, and every tile it built
/// decrypted a blob and held a decoded bitmap. The cost of opening the screen
/// grew with how long the user had been using the feature, and none of it was
/// visible from a screenshot or from any existing test — no test rendered this
/// page with more than zero photos.
///
/// The counting repository below is the whole point: it makes "how much work
/// did opening this screen do" an assertable number.

/// A 1x1 PNG. Real bytes, because `Image.memory` decodes for real in a widget
/// test and an invalid buffer fails the test as an image-stream error rather
/// than as the thing under test.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _CountingRepo implements ProgressPhotosRepository {
  _CountingRepo(this.photos);

  final List<ProgressPhoto> photos;

  /// Every `bytesOf` call, in order. Duplicates matter: a repeat is a
  /// re-decrypt, which is what the family key regression looked like.
  final List<String> decrypted = [];

  Set<String> get distinct => decrypted.toSet();

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(photos);

  @override
  Future<Uint8List?> takeShot() async => throw UnimplementedError();

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async {
    decrypted.add(photo.id);
    return _png;
  }
}

/// Serves the list on demand, so a test can emit the SAME rows again as fresh
/// objects.
///
/// That is not a contrived scenario: `PhotoStore.index()` parses JSON off disk
/// and constructs new [ProgressPhoto] instances on every read, and anything
/// that captures or deletes invalidates the stream. Every shot re-emitted the
/// entire history as new objects.
class _ReemitRepo implements ProgressPhotosRepository {
  final _ctrl = StreamController<List<ProgressPhoto>>.broadcast();
  final List<String> decrypted = [];

  void emit(List<ProgressPhoto> photos) => _ctrl.add(photos);
  Future<void> close() => _ctrl.close();

  @override
  Stream<List<ProgressPhoto>> watch() => _ctrl.stream;

  @override
  Future<Uint8List?> takeShot() async => throw UnimplementedError();

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async {
    decrypted.add(photo.id);
    return _png;
  }
}

/// [count] photos, newest last, one per day back from a fixed date, all the
/// same angle so the compare card can find a pair.
List<ProgressPhoto> _history(int count) {
  final start = DateTime(2026, 1, 1);
  return [
    for (var i = 0; i < count; i++)
      ProgressPhoto(
        id: 'p$i',
        takenAt: start.add(Duration(days: i)),
        storagePath: 'x/p$i.bin',
        keyFingerprint: 'fp',
      ),
  ];
}

Widget _host(ProgressPhotosRepository repo) => ProviderScope(
      overrides: [
        progressPhotosRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProgressPhotosPage(),
      ),
    );

void main() {
  group('the timeline pages instead of rendering the whole history', () {
    testWidgets('opening it decrypts one page, not every photo', (tester) async {
      final repo = _CountingRepo(_history(45));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      // One page, plus the one extra the compare card needs: its "before" is
      // the OLDEST photo, which by definition is the end paging hides. The
      // "after" is the newest and is already on the first page.
      expect(repo.distinct.length, kPhotoPageSize + 1);
      expect(repo.distinct.length, lessThan(45));
    });

    testWidgets('no photo is decrypted twice', (tester) async {
      final repo = _CountingRepo(_history(45));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(repo.decrypted.length, repo.distinct.length);
    });

    testWidgets('re-reading the index does not re-decrypt what is on screen',
        (tester) async {
      final repo = _ReemitRepo();
      addTearDown(repo.close);
      await tester.pumpWidget(_host(repo));
      repo.emit(_history(4));
      await tester.pumpAndSettle();
      expect(repo.decrypted.length, 4);

      // The same four rows, rebuilt as new objects — what `index()` returns
      // after any capture or delete. Without value equality on ProgressPhoto
      // these are four new cache keys and the count doubles.
      repo.emit(_history(4));
      await tester.pumpAndSettle();
      expect(repo.decrypted.length, 4);
    });

    testWidgets('asking for more reveals the next page and then stops asking',
        (tester) async {
      final repo = _CountingRepo(_history(45));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      final more = find.byKey(const Key('photos.showMore'));
      expect(more, findsOneWidget);
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(repo.distinct.length, 45);
      // 45 < 30 + 30: the button is gone because there is nothing left behind
      // it, not because it was tapped.
      expect(find.byKey(const Key('photos.showMore')), findsNothing);
    });

    testWidgets('a short history never offers to show more', (tester) async {
      final repo = _CountingRepo(_history(4));
      await tester.pumpWidget(_host(repo));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('photos.showMore')), findsNothing);
      expect(repo.distinct.length, 4);
    });
  });

  group('newestMonths', () {
    test('keeps whole months and truncates the one that straddles the edge',
        () {
      final months = groupByMonth(_history(45));
      expect(totalPhotos(months), 45);

      final page = newestMonths(months, 30);
      expect(totalPhotos(page), 30);

      // Newest-first at both levels, so the truncated month loses its OLDEST
      // photos, and the page is exactly the 30 most recent overall.
      final flat = [for (final m in page) ...m.photos];
      final expected = [..._history(45)]
        ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
      expect(
        flat.map((p) => p.id).toList(),
        expected.take(30).map((p) => p.id).toList(),
      );
    });

    test('a page larger than the history returns the history', () {
      final months = groupByMonth(_history(5));
      expect(totalPhotos(newestMonths(months, 30)), 5);
    });

    test('a non-positive page is empty, not everything', () {
      final months = groupByMonth(_history(5));
      expect(newestMonths(months, 0), isEmpty);
      expect(newestMonths(months, -1), isEmpty);
    });
  });

  group('ProgressPhoto value equality', () {
    ProgressPhoto make({String id = 'p1', String note = 'n'}) => ProgressPhoto(
          id: id,
          takenAt: DateTime(2026, 1, 1),
          storagePath: 'x/$id.bin',
          keyFingerprint: 'fp',
          note: note,
        );

    test('two reconstructions of the same row are the same cache key', () {
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('a different id is a different photo', () {
      expect(make(id: 'p1') == make(id: 'p2'), isFalse);
    });

    test('metadata is part of identity, not ignored', () {
      expect(make(note: 'a') == make(note: 'b'), isFalse);
    });
  });

  group('decode width', () {
    testWidgets('the widget really asks the decoder for the smaller size',
        (tester) async {
      // Without this the group below only proves a pure function is correct,
      // and a `PhotoBitmap` that stopped calling it would still be green.
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 120,
                height: 160,
                child: PhotoBitmap(bytes: _png),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, 360);
    });

    testWidgets('bytes that will not decode say so instead of showing nothing',
        (tester) async {
      // Act gate, P2c. Callers tell a missing blob apart from a missing key
      // because those need different answers. Bytes that decrypt cleanly and
      // then fail to DECODE reach neither branch — before the errorBuilder
      // they rendered as an empty tile with no explanation.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Center(
            child: SizedBox(
              width: 120,
              height: 160,
              child: PhotoBitmap(bytes: Uint8List.fromList([1, 2, 3, 4])),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This photo could not be displayed.'), findsOneWidget);
    });

    test('is the physical width the pane actually occupies', () {
      expect(PhotoBitmap.decodeWidthFor(120, 3), 360);
    });

    test('never exceeds what the camera captured', () {
      // A wide pane on a dense screen: decoding past the source upscales and
      // costs the memory this exists to save.
      expect(PhotoBitmap.decodeWidthFor(400, 3), kMaxPhotoDecodeWidth);
    });

    test('is null when there is no real width to size to', () {
      expect(PhotoBitmap.decodeWidthFor(double.infinity, 3), isNull);
      expect(PhotoBitmap.decodeWidthFor(0, 3), isNull);
    });
  });
}
