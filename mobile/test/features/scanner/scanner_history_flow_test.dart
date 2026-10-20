import 'dart:io';
import 'dart:typed_data';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/scanner/history/scan_history_providers.dart';
import 'package:fitness_app/features/scanner/history/scan_history_store.dart';
import 'package:fitness_app/features/scanner/history/scan_record.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/recognition_history_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../helpers/test_app.dart';

/// Every scan is saved on the phone automatically (operator order 2026-10-14).
/// These drive the real ScannerPage through a gallery scan with the real store
/// in a temp directory: a cloud answer, an on-device fallback answer, a failed
/// scan, and what the user then opens or picks by hand.
class _Picker extends ImagePickerPlatform {
  _Picker(this.path);
  final String path;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile(path);
}

class _Service
    implements
        VisualEquipmentService,
        FallbackReportingRecogniser,
        RawAnswerReporting {
  _Service({this.offline = false, this.fail = false});
  final bool offline;
  final bool fail;

  @override
  bool lastAnsweredOffline = false;
  @override
  String? lastRawAnswer;

  @override
  Future<List<VisualMatch>> classifyFile(
      {required String path, int topK = 3}) async {
    if (fail) throw const VisualEquipmentException('boom');
    lastAnsweredOffline = offline;
    lastRawAnswer = offline ? null : '{"machine":"chest press machine"}';
    return const [
      VisualMatch(equipmentId: 'chest_press_machine', confidence: 0.62, labelHint: 'chest press machine'),
      VisualMatch(equipmentId: 'pec_deck', confidence: 0.41),
      VisualMatch(equipmentId: 'leg_press', confidence: 0.22),
      VisualMatch(equipmentId: 'elliptical', confidence: 0.12),
    ];
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Rig {
  _Rig(this.tester, this.store, this.landed);
  final WidgetTester tester;
  final ScanHistoryStore store;
  final List<String> landed;

  Future<List<ScanRecord>> records(
      {bool Function(List<ScanRecord>)? until}) async {
    // The save is fire-and-forget inside the fake-async zone: its isolate and
    // file-IO steps complete in real time, and each continuation then needs a
    // pump to run. Alternate the two until [until] holds (default: something
    // was saved) or ~4s have passed.
    var out = const <ScanRecord>[];
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      out = (await tester.runAsync(() => store.list('u1')))!;
      if (until != null ? until(out) : out.isNotEmpty) break;
    }
    return out;
  }

  Future<void> scan() async {
    final gallery = find.byKey(const Key('scan-recognise-gallery'));
    await tester.tap(gallery);
    await tester.pump();
    await tester.pump();
    await _settle(tester);
  }
}

Future<_Rig> _pump(WidgetTester tester, _Service service, Directory docs,
    File photo) async {
  final previous = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = _Picker(photo.path);
  addTearDown(() => ImagePickerPlatform.instance = previous);
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = AssetEquipmentRepository(languageCode: 'ru');
  await tester.runAsync(() => repo.listEquipment());
  final aliases = await tester.runAsync(EquipmentAliasIndex.load);
  final store =
      ScanHistoryStore(documents: docs, temporary: () async => docs);
  final landed = <String>[];
  final router = GoRouter(
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/scan',
        builder: (_, __) => const Scaffold(
            backgroundColor: Colors.transparent, body: ScannerPage()),
      ),
      GoRoute(
        path: '/equipment/:id',
        builder: (_, s) {
          landed.add(s.uri.toString());
          return EquipmentDetailPage(equipmentId: s.pathParameters['id']!);
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      equipmentRepositoryProvider.overrideWithValue(repo),
      equipmentAliasIndexProvider.overrideWith((ref) async => aliases!),
      recommendedExercisesProvider.overrideWith((ref, id) async =>
          const RecommendedExercises(items: [], hiddenForInjury: 0)),
      equipmentHeroImageProvider.overrideWith((ref, id) async => null),
      safetyContextProvider.overrideWith((_) async => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}))),
      recognitionHistoryRepositoryProvider
          .overrideWithValue(MockRecognitionHistoryRepository()),
      visualEquipmentServiceProvider.overrideWithValue(service),
      scanHistoryStoreProvider.overrideWithValue(store),
      scanHistoryUidProvider.overrideWithValue('u1'),
      scanBuildInfoProvider.overrideWithValue(
          const ScanBuildInfo(gitSha: 'abc1234', version: '1.0.0+14')),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await _settle(tester);
  return _Rig(tester, store, landed);
}

void main() {
  late Directory docs;
  late File photo;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('scan_flow_docs');
    photo = File('${docs.path}/gallery.jpg')
      ..writeAsBytesSync(
          Uint8List.fromList(img.encodeJpg(img.Image(width: 1800, height: 900))));
  });
  tearDown(() async {
    for (var i = 0; i < 6 && docs.existsSync(); i++) {
      try {
        docs.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
  });

  testWidgets('a CLOUD gallery scan is saved by itself: source, raw answer, '
      'all 4 candidates in order, build and the resized photo', (tester) async {
    final rig = await _pump(tester, _Service(), docs, photo);
    expect(await tester.runAsync(() => rig.store.list('u1')), isEmpty,
        reason: 'nothing before a scan');

    await rig.scan();
    final r = (await rig.records()).single;

    expect(r.source, ScanSource.gallery);
    expect(r.outcome, ScanOutcome.alternatives);
    expect(r.answeredBy, ScanAnsweredBy.cloud);
    expect(r.cloudAnswered, isTrue);
    expect(r.rawAnswer, '{"machine":"chest press machine"}');
    expect(r.candidates.map((c) => c.equipmentId),
        ['chest_press_machine', 'pec_deck', 'leg_press', 'elliptical']);
    expect(r.candidates.map((c) => c.confidence), [0.62, 0.41, 0.22, 0.12]);
    expect(r.candidates.every((c) => c.rating == null), isTrue,
        reason: 'rating is optional and starts empty');
    expect(r.appGitSha, 'abc1234');
    expect(r.hasPhoto, isTrue);
    final bytes = (await tester.runAsync(
        () async => (await rig.store.photoFile('u1', r.id))!.readAsBytes()))!;
    expect(img.decodeJpg(bytes)!.width, 1024,
        reason: 'the stored picture is the one sent to the cloud (<=1024px)');
  });

  testWidgets('an ON-DEVICE fallback scan is saved as on-device, no raw answer',
      (tester) async {
    final rig = await _pump(tester, _Service(offline: true), docs, photo);
    await rig.scan();
    final r = (await rig.records()).single;
    expect(r.answeredBy, ScanAnsweredBy.onDevice);
    expect(r.cloudAnswered, isFalse);
    expect(r.rawAnswer, isNull);
    expect(r.candidates, hasLength(4));
  });

  testWidgets('a scan that failed is saved too, with no candidates',
      (tester) async {
    final rig = await _pump(tester, _Service(fail: true), docs, photo);
    await rig.scan();
    final r = (await rig.records()).single;
    expect(r.outcome, ScanOutcome.failed);
    expect(r.answeredBy, ScanAnsweredBy.none);
    expect(r.candidates, isEmpty);
  });

  testWidgets('opening a candidate records which one the user chose',
      (tester) async {
    final rig = await _pump(tester, _Service(), docs, photo);
    await rig.scan();
    await tester.ensureVisible(find.text('Бабочка (пек-дек)'));
    await tester.tap(find.text('Бабочка (пек-дек)'));
    await _settle(tester);
    expect(rig.landed.single, startsWith('/equipment/pec_deck'));

    final r = (await rig.records(until: (l) => l.isNotEmpty && l.first.openedEquipmentId != null)).single;
    expect(r.openedEquipmentId, 'pec_deck');
    expect(r.pickedManually, isFalse);
  });

  testWidgets('a manual pick is recorded as manual on the same scan',
      (tester) async {
    final rig = await _pump(tester, _Service(), docs, photo);
    await rig.scan();
    final button = find.byKey(const Key('scan-pick-manually'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('scan-manual-pick-bench_press')));
    await _settle(tester);

    final r = (await rig.records(until: (l) => l.isNotEmpty && l.first.openedEquipmentId != null)).single;
    expect(r.openedEquipmentId, 'bench_press');
    expect(r.pickedManually, isTrue);
  });

  testWidgets('two scans make two records, each with its own folder',
      (tester) async {
    final rig = await _pump(tester, _Service(), docs, photo);
    await rig.scan();
    await tester.tap(find.byKey(const Key('scan-recognise-camera'))); // scan again
    await _settle(tester);
    await rig.scan();
    final records = await rig.records(until: (l) => l.length >= 2);
    expect(records, hasLength(2));
    expect(records.map((r) => r.id).toSet(), hasLength(2));
  });

  group('optional OK / NOT OK marks on the candidate rows', () {
    Finder ok(String id) => find.byKey(Key('scan-rate-ok-$id'));
    Finder notOk(String id) => find.byKey(Key('scan-rate-notok-$id'));

    Future<CandidateRating?> savedRating(_Rig rig, String id) async {
      final r = (await rig.records(
          until: (l) => l.isNotEmpty))
          .first;
      return r.candidates.firstWhere((c) => c.equipmentId == id).rating;
    }

    testWidgets('every candidate shows both marks right after its % match',
        (tester) async {
      final rig = await _pump(tester, _Service(), docs, photo);
      await rig.scan();
      for (final id in ['chest_press_machine', 'pec_deck', 'leg_press', 'elliptical']) {
        await tester.ensureVisible(ok(id));
        expect(ok(id), findsOneWidget, reason: 'OK mark for $id');
        expect(notOk(id), findsOneWidget, reason: 'NOT OK mark for $id');
      }
      // Marks sit on the confidence line, to the right of the percentage.
      final pct = tester.getRect(find.text('41% confidence'));
      final mark = tester.getRect(ok('pec_deck'));
      expect(mark.left, greaterThanOrEqualTo(pct.right));
      expect((mark.center.dy - pct.center.dy).abs(), lessThan(20));
    });

    testWidgets('OK and NOT OK are saved with the scan; tapping again clears; '
        'a mark never opens the machine', (tester) async {
      final rig = await _pump(tester, _Service(), docs, photo);
      await rig.scan();
      await rig.records();

      await tester.ensureVisible(ok('pec_deck'));
      await tester.tap(ok('pec_deck'));
      await tester.pump();
      expect(rig.landed, isEmpty, reason: 'rating must not navigate');
      expect(
          tester.widget<Icon>(find.descendant(of: ok('pec_deck'), matching: find.byType(Icon))).icon,
          Icons.check_circle_rounded,
          reason: 'the active mark is drawn filled');
      expect(
          await (() async {
            for (var i = 0; i < 40; i++) {
              await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
              await tester.pump();
              final r = (await tester.runAsync(() => rig.store.list('u1')))!.first;
              if (r.candidates[1].rating != null) return r.candidates[1].rating;
            }
            return null;
          })(),
          CandidateRating.ok);

      // NOT OK replaces OK (one verdict per candidate)...
      await tester.tap(notOk('pec_deck'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
        final r = (await tester.runAsync(() => rig.store.list('u1')))!.first;
        if (r.candidates[1].rating == CandidateRating.notOk) break;
      }
      expect(await savedRating(rig, 'pec_deck'), CandidateRating.notOk);
      expect(await savedRating(rig, 'chest_press_machine'), isNull,
          reason: 'only the tapped candidate is rated');

      // ... and tapping the active mark again clears it.
      await tester.tap(notOk('pec_deck'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump();
        final r = (await tester.runAsync(() => rig.store.list('u1')))!.first;
        if (r.candidates[1].rating == null) break;
      }
      expect(await savedRating(rig, 'pec_deck'), isNull);
      expect(
          tester.widget<Icon>(find.descendant(of: notOk('pec_deck'), matching: find.byType(Icon))).icon,
          Icons.cancel_outlined);
    });

    testWidgets('rating is optional: an unrated candidate still opens its page',
        (tester) async {
      final rig = await _pump(tester, _Service(), docs, photo);
      await rig.scan();
      await tester.ensureVisible(find.text('Бабочка (пек-дек)'));
      await tester.tap(find.text('Бабочка (пек-дек)'));
      await _settle(tester);
      expect(rig.landed.single, startsWith('/equipment/pec_deck'));
    });

    testWidgets('a new scan starts with no marks', (tester) async {
      final rig = await _pump(tester, _Service(), docs, photo);
      await rig.scan();
      await tester.ensureVisible(ok('leg_press'));
      await tester.tap(ok('leg_press'));
      await tester.pump();
      expect(
          tester.widget<Icon>(find.descendant(of: ok('leg_press'), matching: find.byType(Icon))).icon,
          Icons.check_circle_rounded);
      await tester.tap(find.byKey(const Key('scan-recognise-camera'))); // scan again
      await _settle(tester);
      await rig.scan();
      await tester.ensureVisible(ok('leg_press'));
      expect(
          tester.widget<Icon>(find.descendant(of: ok('leg_press'), matching: find.byType(Icon))).icon,
          Icons.check_circle_outline_rounded,
          reason: 'the verdict of the previous scan must not carry over');
    });
  });
}
