import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../helpers/test_app.dart';

/// H6: the delete confirm sheet + the flow behind `_PhotoTile.onLongPress`.
///
/// `runPhotoDeleteFlow` is tested directly, the same way `capture_flow_test`
/// tests `runPhotoCaptureFlow` — a button in a bare harness, not the real
/// grid, since nothing here reads the tile it was called from.

final _shotBytes = Uint8List.fromList(const [1, 2, 3, 4]);

final _photo = ProgressPhoto(
  id: 'p_1',
  takenAt: DateTime(2026, 8, 1),
  storagePath: 'test://1.bin',
  keyFingerprint: 'fp',
  angle: ProgressPhotoAngle.front,
);

class _RecordingRepo implements ProgressPhotosRepository {
  final List<String> deleted = [];
  Object? deleteFailsWith;

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);

  @override
  Future<Uint8List?> takeShot() async => null;

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async =>
      _photo;

  @override
  Future<void> delete(String id) async {
    if (deleteFailsWith != null) throw deleteFailsWith!;
    deleted.add(id);
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => _shotBytes;
}

Future<void> _host(WidgetTester tester, _RecordingRepo repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [progressPhotosRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => runPhotoDeleteFlow(context, ref, _photo),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('confirming deletes; the sheet asks first', (tester) async {
    final repo = _RecordingRepo();
    await _host(tester, repo);

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty,
        reason: 'the tap opens the confirm sheet, not the delete itself');
    expect(find.byKey(const Key('photos.delete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('photos.delete.confirm')));
    await tester.pumpAndSettle();

    expect(repo.deleted, ['p_1']);
  });

  testWidgets('cancel leaves the photo alone', (tester) async {
    final repo = _RecordingRepo();
    await _host(tester, repo);

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photos.delete.cancel')));
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty);
    expect(find.byKey(const Key('photos.delete')), findsNothing);
  });

  testWidgets('a failed delete is said out loud, not swallowed',
      (tester) async {
    final repo = _RecordingRepo()..deleteFailsWith = StateError('disk full');
    await _host(tester, repo);

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photos.delete.confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
