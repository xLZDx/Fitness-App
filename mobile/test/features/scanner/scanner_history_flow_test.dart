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
  final store = ScanHistoryStore(documents: docs);
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
}
