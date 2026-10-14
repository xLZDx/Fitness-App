import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';

class _TwoPhotos implements ProgressPhotosRepository {
  static final _photos = [
    ProgressPhoto(
        id: 'a',
        takenAt: DateTime(2026, 8, 1),
        storagePath: 'x',
        keyFingerprint: 'k'),
    ProgressPhoto(
        id: 'b',
        takenAt: DateTime(2026, 9, 20),
        storagePath: 'y',
        keyFingerprint: 'k'),
  ];
  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(_photos);
  @override
  Future<Uint8List?> takeShot() async => null;
  @override
  Future<ProgressPhoto> save(Uint8List bytes,
          {required ProgressPhotoAngle angle,
          double? weightKg,
          String? note}) async =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async =>
      throw StateError('no pixels');
}

Future<GoRouter> _pump(WidgetTester tester, ScanAccess access) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => ProgressPhotosPage()),
    GoRoute(
        path: '/photos/compare',
        builder: (_, __) => const Scaffold(body: Text('COMPARE SCREEN'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      progressPhotosRepositoryProvider.overrideWithValue(_TwoPhotos()),
      scanAccessProvider.overrideWithValue(access),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  const link = Key('photos.compare.openScanCompare');

  testWidgets('old compare card links to the scan compare screen when allowed',
      (tester) async {
    await _pump(tester, ScanAccess.allowed);
    expect(find.byKey(const Key('photos.compare')), findsOneWidget);
    await tester.ensureVisible(find.byKey(link));
    await tester.tap(find.byKey(link));
    await tester.pumpAndSettle();
    expect(find.text('COMPARE SCREEN'), findsOneWidget);
  });

  testWidgets('no link when scan access is not allowed', (tester) async {
    await _pump(tester, ScanAccess.needsSupporter);
    expect(find.byKey(const Key('photos.compare')), findsOneWidget);
    expect(find.byKey(link), findsNothing);
  });
}
