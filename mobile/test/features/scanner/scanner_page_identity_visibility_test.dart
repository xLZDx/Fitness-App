import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../../helpers/test_app.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/scanner/scanner_page.dart';
import 'package:fitness_app/features/visual_equipment/data/equipment_identity.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/equipment_identity_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart'
    show machineTextRecogniserProvider, visualEquipmentServiceProvider;

/// GPT-PM pre-commit review (this gate), findings #1 and #3, verified against
/// real evidence before this remediation (`core/DECISION_LOG.md`):
///
/// #1 -- OP-01 requires a zero-evidence scan (server resolves `NOT_SUPPORTED`
/// with no `shadowCandidate` -- `exact_resolution_policy.ts`'s
/// `NOT_ELIGIBLE` -> orchestrator's `NOT_SUPPORTED`) to render IDENTICALLY to
/// enrichment being off entirely. Proven here at the real `ScannerPage`
/// integration point, not only the badge widget in isolation.
///
/// #3 -- identity-surface visibility must depend on the identity result
/// itself, never the GENERIC recognizer's `ScanOutcome` -- the two are
/// genuinely independent pipelines (OCR-driven exact resolution vs. general
/// visual matching), so a machine the generic recognizer cannot place
/// (`noEquipment`) can still have a placard the identity pipeline resolves.

const _fakeEvidence = MachineTextEvidence(fullText: 'LIFE FITNESS 9NPH', lines: []);

class _FakeImagePicker extends ImagePickerPlatform {
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    return XFile('/tmp/identity-visibility-$calls.jpg');
  }
}

/// Always answers with zero matches -- `ScanResult.noEquipment()`'s own
/// trigger (`scan_outcome.dart`: an empty ranked list resolves to
/// `noEquipment`). The GENERIC pipeline's answer for both integration cases
/// below; only the identity pipeline's answer differs between them.
class _EmptyMatchService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      const [];
}

/// A GENERIC classification the test controls the completion of, to prove
/// T2 (GPT-PM round-2 review, this gate): "UI renders type result before
/// identity resolves" -- `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_
/// AND_AC_DOD_2026-08-22.md`'s own binding DoD for P2.G4. The identity
/// pipeline is independent and can resolve faster than this.
class _DelayedMatchService implements VisualEquipmentService {
  final Completer<List<VisualMatch>> pending = Completer<List<VisualMatch>>();

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) =>
      pending.future;
}

class _FakeStructuredRecogniser implements StructuredTextRecogniser {
  @override
  Future<MachineTextEvidence> readStructured(String path) async => _fakeEvidence;
  @override
  Future<MachineTextEvidence> readStructuredFrame(InputImage input) async =>
      _fakeEvidence;
  @override
  Future<String> readText(String path) async => _fakeEvidence.fullText;
  @override
  Future<String> readFrame(InputImage input) async => _fakeEvidence.fullText;
  @override
  Future<void> dispose() async {}
}

EquipmentIdentity _identity(Map<String, dynamic> overrides) {
  final base = <String, dynamic>{
    'scanId': 'irrelevant-overwritten-by-real-scanId',
    'recognitionSessionId': 'session-1',
    'identityContractVersion': 'v1',
    'authority': {
      'catalogVersion': 'cv-test',
      'ocrVersion': 'p2g1-mlkit-latin-structured-v1',
      'textPolicyVersion': 'text-policy-v1',
      'fusionPolicyVersion': 'fusion-policy-v1',
      'identityPolicyVersion': 'identity-policy-v1',
    },
    'evidenceLane': 'TEXT_ONLY',
    'decision': 'NOT_SUPPORTED',
    'verifierInvoked': false,
  }..addAll(overrides);
  return EquipmentIdentity.fromJson(base);
}

Future<ProviderContainer> _pumpScanner(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/scan',
        builder: (_, __) => const Scaffold(
          backgroundColor: Colors.transparent,
          body: ScannerPage(),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  ));
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(ScannerPage)));
}

Future<void> _tapGallery(WidgetTester tester) async {
  final gallery = find.byKey(const Key('scan-recognise-gallery'));
  await tester.scrollUntilVisible(gallery, 120);
  await tester.tap(gallery);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
      'finding #1: enrichment-ON zero-evidence scan renders nothing (OP-01), '
      'same as enrichment disabled', (tester) async {
    final picker = _FakeImagePicker();
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previousPicker);

    // Enrichment ON, server genuinely resolves NOT_SUPPORTED with no
    // shadowCandidate -- the real zero-evidence/no-candidate answer.
    await _pumpScanner(tester, overrides: [
      equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
      visualEquipmentServiceProvider.overrideWithValue(_EmptyMatchService()),
      machineTextRecogniserProvider.overrideWithValue(_FakeStructuredRecogniser()),
      equipmentIdentityAskProvider.overrideWithValue(({
        required String scanId,
        required ParsedIdentityText evidence,
      }) async =>
          _identity({'scanId': scanId, 'decision': 'NOT_SUPPORTED'})),
    ]);
    await _tapGallery(tester);

    expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    expect(
        find.byKey(const Key('equipment-identity-need-more-view')), findsNothing);
  });

  testWidgets(
      'finding #1: enrichment-OFF (the real default) renders nothing -- the '
      'equivalence partner of the case above: neither state shows identity '
      'content for this scan', (tester) async {
    final picker = _FakeImagePicker();
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previousPicker);

    // No enrichment override at all -- production's real default (off), no
    // identity override even reachable.
    await _pumpScanner(tester, overrides: [
      visualEquipmentServiceProvider.overrideWithValue(_EmptyMatchService()),
    ]);
    await _tapGallery(tester);

    expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    expect(
        find.byKey(const Key('equipment-identity-need-more-view')), findsNothing);
  });

  testWidgets(
      'finding #3: generic noEquipment + identity MATCH still shows the badge',
      (tester) async {
    final picker = _FakeImagePicker();
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previousPicker);

    await _pumpScanner(tester, overrides: [
      equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
      // GENERIC pipeline says noEquipment (empty matches) -- the widget tree
      // must not use that to suppress an independently-resolved identity.
      visualEquipmentServiceProvider.overrideWithValue(_EmptyMatchService()),
      machineTextRecogniserProvider.overrideWithValue(_FakeStructuredRecogniser()),
      equipmentIdentityAskProvider.overrideWithValue(({
        required String scanId,
        required ParsedIdentityText evidence,
      }) async =>
          _identity({
            'scanId': scanId,
            'decision': 'MATCH',
            'identityLevel': 'EXACT_MODEL',
            'model': {
              'modelId': 'life-fitness-9nph-9-15',
              'catalogVersion': 'cv-test',
              'textSupportStatus': 'VERIFIED',
            },
          })),
    ]);
    await _tapGallery(tester);

    final badge = find.byKey(const Key('equipment-identity-badge'));
    expect(badge, findsOneWidget);
    // GPT-PM round-2 review, finding on #2's own remediation: the pill must
    // hug its own content width, not stretch to the enclosing Column's full
    // (stretch-aligned) width -- OP-02/T6's "small fixed badge size" is a
    // footprint requirement, width included.
    expect(tester.getSize(badge).width, lessThanOrEqualTo(220));
  });

  testWidgets(
      'T2: identity resolves before the generic scan settles -- no identity '
      'surface appears while loading, and it appears after settlement even '
      'for noEquipment', (tester) async {
    final picker = _FakeImagePicker();
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previousPicker);

    final delayed = _DelayedMatchService();
    await _pumpScanner(tester, overrides: [
      equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
      visualEquipmentServiceProvider.overrideWithValue(delayed),
      machineTextRecogniserProvider.overrideWithValue(_FakeStructuredRecogniser()),
      // The identity pipeline resolves immediately -- faster than the
      // generic classifier below, which the test holds open on purpose.
      equipmentIdentityAskProvider.overrideWithValue(({
        required String scanId,
        required ParsedIdentityText evidence,
      }) async =>
          _identity({
            'scanId': scanId,
            'decision': 'MATCH',
            'identityLevel': 'EXACT_MODEL',
            'model': {
              'modelId': 'life-fitness-9nph-9-15',
              'catalogVersion': 'cv-test',
              'textSupportStatus': 'VERIFIED',
            },
          })),
    ]);
    final gallery = find.byKey(const Key('scan-recognise-gallery'));
    await tester.scrollUntilVisible(gallery, 120);
    await tester.tap(gallery);
    // Deliberately NOT the usual `_tapGallery` (whose extra `pump()`s assume
    // the generic classification settles quickly) -- the generic future is
    // still pending here, so the identity result (already resolved) must
    // stay hidden regardless of how many frames are pumped.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);

    // Generic classification now settles to `noEquipment` (empty matches) --
    // finding #3's own fix means the already-resolved MATCH still surfaces.
    // Explicit pumps, not `pumpAndSettle`: the live viewfinder's warming
    // spinner animates continuously while on this page (see `_tapGallery`'s
    // own doc comment), so `pumpAndSettle` never returns here.
    delayed.pending.complete(const []);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('equipment-identity-badge')), findsOneWidget);
  });

  testWidgets(
      'finding #3: generic noEquipment + identity NEED_MORE_VIEW still shows '
      'the re-scan prompt', (tester) async {
    final picker = _FakeImagePicker();
    final previousPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = picker;
    addTearDown(() => ImagePickerPlatform.instance = previousPicker);

    await _pumpScanner(tester, overrides: [
      equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
      visualEquipmentServiceProvider.overrideWithValue(_EmptyMatchService()),
      machineTextRecogniserProvider.overrideWithValue(_FakeStructuredRecogniser()),
      equipmentIdentityAskProvider.overrideWithValue(({
        required String scanId,
        required ParsedIdentityText evidence,
      }) async =>
          _identity({'scanId': scanId, 'decision': 'NEED_MORE_VIEW'})),
    ]);
    await _tapGallery(tester);

    expect(find.byKey(const Key('equipment-identity-need-more-view')),
        findsOneWidget);
  });
}
