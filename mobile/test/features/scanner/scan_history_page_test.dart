import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/scanner/history/scan_history_page.dart';
import 'package:fitness_app/features/scanner/history/scan_history_providers.dart';
import 'package:fitness_app/features/scanner/history/scan_history_store.dart';
import 'package:fitness_app/features/scanner/history/scan_record.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../helpers/test_app.dart';

/// The "История сканов" screen: list, detail, rating from the detail, export
/// and clear. Real store in a temp directory, real catalogue names, the share
/// sheet and the export directory faked (both are platform seams).
class _Rig {
  _Rig(this.tester, this.store, this.shared);
  final WidgetTester tester;
  final ScanHistoryStore store;
  final List<List<File>> shared;

  /// Real file IO completes in real time and its continuations need a pump:
  /// alternate the two. With [until], stop as soon as it is true.
  Future<void> settle([int rounds = 10, bool Function()? until]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 60));
      if (until != null && until()) return;
    }
  }

  Future<void> waitFor(Finder f, [int rounds = 60]) =>
      settle(rounds, () => f.evaluate().isNotEmpty);

  Future<List<ScanRecord>> stored({String uid = 'u1'}) async =>
      (await tester.runAsync(() => store.list(uid)))!;
}

ScanRecord _rec(String id, DateTime at,
        {String top = 'leg_press',
        ScanAnsweredBy by = ScanAnsweredBy.cloud,
        ScanSource source = ScanSource.camera,
        String? raw = '{"machine":"leg press"}',
        List<ScanCandidate>? candidates}) =>
    ScanRecord(
      id: id,
      timestamp: at,
      source: source,
      outcome: ScanOutcome.alternatives,
      answeredBy: by,
      rawAnswer: raw,
      candidates: candidates ??
          <ScanCandidate>[
            ScanCandidate(equipmentId: top, confidence: 0.7),
            const ScanCandidate(equipmentId: 'pec_deck', confidence: 0.2),
          ],
      appGitSha: 'abc1234',
      appVersion: '1.0.0+14',
    );

Future<_Rig> _pump(
  WidgetTester tester,
  Directory docs, {
  required Future<void> Function(_Rig rig) seed,
  bool shareFails = false,
  String initial = '/scan-history',
}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = AssetEquipmentRepository(languageCode: 'ru');
  await tester.runAsync(() => repo.listEquipment());
  final store = ScanHistoryStore(documents: docs);
  final shared = <List<File>>[];
  final rig = _Rig(tester, store, shared);
  await seed(rig);

  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
          path: '/scan-history',
          builder: (_, __) => const ScanHistoryPage()),
      GoRoute(
          path: '/scan-history/:id',
          builder: (_, s) =>
              ScanHistoryDetailPage(scanId: s.pathParameters['id']!)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      equipmentRepositoryProvider.overrideWithValue(repo),
      equipmentHeroImageProvider.overrideWith((ref, id) async => null),
      scanHistoryStoreProvider.overrideWithValue(store),
      scanHistoryUidProvider.overrideWithValue('u1'),
      scanExportDirProvider.overrideWithValue(() async => docs),
      scanShareProvider.overrideWithValue((files) async {
        if (shareFails) throw StateError('no share sheet');
        shared.add(files);
      }),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await rig.settle(40, () => find.byType(ListView).evaluate().isNotEmpty || find.byKey(const Key('scan-history-empty')).evaluate().isNotEmpty);
  await rig.settle(10); // names, photos
  return rig;
}

Uint8List _jpeg() =>
    Uint8List.fromList(img.encodeJpg(img.Image(width: 64, height: 48)));

void main() {
  late Directory docs;
  final t0 = DateTime.utc(2026, 10, 14, 9);

  setUp(() => docs = Directory.systemTemp.createTempSync('scan_hist_ui'));
  tearDown(() async {
    for (var i = 0; i < 6 && docs.existsSync(); i++) {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  });

  Future<void> seedTwo(_Rig rig) async {
    await rig.tester.runAsync(() async {
      await rig.store.save('u1', _rec('older', t0), photo: _jpeg());
      await rig.store.save(
          'u1',
          _rec('newer', t0.add(const Duration(hours: 2)),
              top: 'treadmill',
              by: ScanAnsweredBy.onDevice,
              source: ScanSource.gallery,
              raw: null));
      await rig.store.setRating('u1', 'older', 'leg_press', CandidateRating.ok);
      await rig.store.setRating('u1', 'older', 'pec_deck', CandidateRating.notOk);
      await rig.store.save('u2', _rec('theirs', t0));
    });
  }

  testWidgets('lists this account\'s scans newest first with name, source, '
      'who answered, a thumbnail and the rating marks', (tester) async {
    await _pump(tester, docs, seed: seedTwo);

    expect(find.byKey(const Key('scan-history-row-newer')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-row-older')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-row-theirs')), findsNothing,
        reason: 'another account\'s history is never shown');
    final newerY = tester.getTopLeft(find.byKey(const Key('scan-history-row-newer'))).dy;
    final olderY = tester.getTopLeft(find.byKey(const Key('scan-history-row-older'))).dy;
    expect(newerY, lessThan(olderY), reason: 'newest first');

    // Names are the catalogue's Russian ones; the top candidate heads the row.
    expect(find.text('Беговая дорожка'), findsOneWidget);
    expect(find.text('Жим ногами'), findsOneWidget);
    expect(find.text('Gallery · On-device fallback answered', findRichText: false),
        findsNothing); // the line is multi-line text, asserted piecewise:
    final newerRow = find.byKey(const Key('scan-history-row-newer'));
    expect(find.descendant(of: newerRow, matching: find.textContaining('Gallery')),
        findsOneWidget);
    expect(find.descendant(of: newerRow, matching: find.textContaining('On-device fallback answered')),
        findsOneWidget);
    final olderRow = find.byKey(const Key('scan-history-row-older'));
    expect(find.descendant(of: olderRow, matching: find.textContaining('Cloud answered')),
        findsOneWidget);

    // Thumbnail: a real Image for the scan with a photo.
    expect(
        find.descendant(
            of: find.byKey(const Key('scan-history-photo-older')),
            matching: find.byType(Image)),
        findsOneWidget);
    // Rating marks for the rated candidates of "older" only.
    expect(find.byKey(const Key('scan-history-mark-older-leg_press')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-mark-older-pec_deck')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-mark-newer-treadmill')), findsNothing);
    expect(find.text('Scan history'), findsOneWidget);
  });

  testWidgets('an empty history explains itself and offers neither export nor '
      'clear', (tester) async {
    await _pump(tester, docs, seed: (_) async {});
    expect(find.byKey(const Key('scan-history-empty')), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const Key('scan-history-export'))).onPressed,
        isNull);
    expect(tester.widget<IconButton>(find.byKey(const Key('scan-history-clear'))).onPressed,
        isNull);
  });

  testWidgets('the detail shows the photo, every candidate, the raw model reply, '
      'what was opened and the build; ratings made there persist',
      (tester) async {
    final rig = await _pump(tester, docs, seed: seedTwo);
    await rig.tester.runAsync(() =>
        rig.store.setChoice('u1', 'older', 'bench_press', manual: true));
    // Re-open the list so it sees the choice, then tap the row.
    await tester.tap(find.byKey(const Key('scan-history-row-older')));
    await rig.settle();

    expect(find.byKey(const Key('scan-history-detail')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-detail-photo')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-candidate-leg_press')), findsOneWidget);
    expect(find.byKey(const Key('scan-history-candidate-pec_deck')), findsOneWidget);
    expect(tester.widget<SelectableText>(find.byKey(const Key('scan-history-detail-raw'))).data,
        '{"machine":"leg press"}');
    expect(
        tester.widget<Text>(find.byKey(const Key('scan-history-detail-build'))).data,
        'App build: 1.0.0+14 · abc1234');
    expect(find.byKey(const Key('scan-history-detail-answered')), findsOneWidget);

    // Rate from the detail: pec_deck currently NOT OK -> tap it to clear.
    await tester.tap(find.byKey(const Key('scan-history-rate-notok-pec_deck')));
    await rig.settle(14);
    final older = (await rig.stored()).firstWhere((r) => r.id == 'older');
    expect(older.candidates[1].rating, isNull);
    expect(older.candidates[0].rating, CandidateRating.ok, reason: 'untouched');
  });

  testWidgets('export writes one JSON plus the photos and hands exactly those '
      'files to the share sheet', (tester) async {
    final rig = await _pump(tester, docs, seed: seedTwo);
    await tester.tap(find.byKey(const Key('scan-history-export')));
    await rig.settle(60, () => rig.shared.isNotEmpty);

    expect(rig.shared, hasLength(1));
    final files = rig.shared.single;
    final json = files.firstWhere((f) => f.path.endsWith('scan_history.json'));
    expect(files.where((f) => f.path.endsWith('.jpg')), hasLength(1),
        reason: 'one scan has a photo');
    final body = jsonDecode(json.readAsStringSync()) as Map;
    expect(body['count'], 2, reason: 'only this account\'s two scans');
    final ids = (body['scans'] as List).map((s) => s['id']).toList();
    expect(ids, ['newer', 'older']);
    expect(ids, isNot(contains('theirs')));
  });

  testWidgets('a share sheet that fails says so, and nothing is lost',
      (tester) async {
    final rig = await _pump(tester, docs, seed: seedTwo, shareFails: true);
    await tester.tap(find.byKey(const Key('scan-history-export')));
    await rig.settle(60,
        () => find.text('Could not export the history.').evaluate().isNotEmpty);
    expect(find.text('Could not export the history.'), findsOneWidget);
    expect((await rig.stored()), hasLength(2));
  });

  testWidgets('clear history asks first; cancel keeps everything, confirm '
      'removes this account\'s scans and photos only', (tester) async {
    final rig = await _pump(tester, docs, seed: seedTwo);

    await tester.tap(find.byKey(const Key('scan-history-clear')));
    await rig.settle(4);
    expect(find.text('Clear scan history?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scan-history-clear-cancel')));
    await rig.settle(4);
    expect(await rig.stored(), hasLength(2), reason: 'cancel deletes nothing');

    await tester.tap(find.byKey(const Key('scan-history-clear')));
    await rig.settle(4);
    await tester.tap(find.byKey(const Key('scan-history-clear-confirm')));
    await rig.settle(16);

    expect(await rig.stored(), isEmpty);
    expect(find.byKey(const Key('scan-history-empty')), findsOneWidget);
    expect(await rig.stored(uid: 'u2'), hasLength(1),
        reason: 'another account\'s history is untouched');
    expect(Directory('${docs.path}/$kScanHistoryDir/u1').existsSync(), isFalse);
  });
}
