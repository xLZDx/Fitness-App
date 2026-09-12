import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/visual_equipment/data/equipment_identity.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'package:fitness_app/features/visual_equipment/data/parsed_identity_text.dart';
import 'package:fitness_app/features/visual_equipment/state/equipment_identity_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart'
    show machineTextRecogniserProvider;
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// GPT-PM pre-commit review (this gate), finding #2: the rev4 plan's own
/// step 7 titles `WorkoutPlayerPage`'s identity handling "the in-workout
/// surface" and step 9's DoD requires OP-01/OP-02 on BOTH surfaces (the
/// scanner slot and this one) -- threading `scanId` with nothing rendered at
/// the end of it does not satisfy that. This proves the in-workout surface
/// actually renders, stays within a small bounded footprint when collapsed,
/// and that every OTHER (no-scanId) entry point is unaffected.

const _fakeEvidence = MachineTextEvidence(fullText: 'LIFE FITNESS 9NPH', lines: []);

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

ExerciseItem _rowExercise() => ExerciseItem.fromJson({
      'id': 'ea_row',
      'title': 'Bent-over Row',
      'durationMinutes': 10,
      'difficulty': 'beginner',
      'muscles': const ['back'],
      'steps': const ['Row'],
    });

EquipmentIdentity _identity(Map<String, dynamic> overrides) {
  final base = <String, dynamic>{
    'scanId': 'scan-1',
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
    'decision': 'MATCH',
    'identityLevel': 'EXACT_MODEL',
    'model': {
      'modelId': 'life-fitness-9nph-9-15',
      'catalogVersion': 'cv-test',
      'textSupportStatus': 'VERIFIED',
    },
    'verifierInvoked': false,
  }..addAll(overrides);
  return EquipmentIdentity.fromJson(base);
}

Widget _app(Widget child, {List<Override> identityOverrides = const []}) =>
    ProviderScope(
      overrides: [
        exerciseResolutionProvider.overrideWith(
            (ref, id) async => ExerciseResolution.found(_rowExercise())),
        authUserProvider.overrideWith((_) => Stream.value(
            const AuthUser(uid: 'u1', displayName: 'Tester'))),
        scheduledSessionsProvider.overrideWith((_) => Stream.value(const [])),
        workoutSessionsProvider.overrideWith((_) => Stream.value(const [])),
        ...identityOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  Future<void> tall(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets(
      'a resolved MATCH renders the badge, bounded to a small collapsed '
      'footprint', (t) async {
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', scanId: 'scan-1'),
      identityOverrides: [
        equipmentIdentityEnrichmentEnabledProvider.overrideWithValue(true),
        scanIdImagePathProvider
            .overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
        machineTextRecogniserProvider
            .overrideWithValue(_FakeStructuredRecogniser()),
        equipmentIdentityAskProvider.overrideWithValue(({
          required String scanId,
          required ParsedIdentityText evidence,
        }) async =>
            _identity({'scanId': scanId})),
      ],
    ));
    await t.pumpAndSettle();

    final badge = find.byKey(const Key('equipment-identity-badge'));
    expect(badge, findsOneWidget);

    // The "small fixed footprint" requirement (GPT-PM pre-commit review,
    // this gate): the COLLAPSED pill must stay small regardless of how tall
    // the rest of this 970-line page is. A real bounded-size assertion,
    // not a pixel-diff golden -- this repo's own documented font-rendering
    // environment issue (`core/DECISION_LOG.md`) would make a golden an
    // unreliable proof of exactly this claim on this machine, where a
    // numeric size bound is unaffected by font substitution.
    //
    // GPT-PM round-2 review: "small fixed badge size" (OP-02/T6) is a
    // footprint requirement, width included -- this page places the badge
    // as a direct `SmoothScrollList` (`ListView.builder`) item, which gives
    // every child a TIGHT, full-viewport-width constraint; without its own
    // width-loosening boundary the pill would stretch edge-to-edge even
    // though its content stays left-aligned. The test's own `tall()` helper
    // sets a 400-wide viewport, so a badge anywhere near that width would
    // prove the regression.
    // The keyed element includes the pill's own `EdgeInsets.only(top: 10)`
    // outer spacing on top of its `maxHeight: 60` bounded content, hence 70.
    final size = t.getSize(badge);
    expect(size.height, lessThanOrEqualTo(70));
    expect(size.width, lessThanOrEqualTo(220));
  });

  testWidgets(
      'no scanId (every pre-existing entry point): the in-workout identity '
      'slot renders nothing', (t) async {
    await tall(t);
    await t.pumpWidget(_app(const WorkoutPlayerPage(exerciseId: 'ea_row')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    expect(
      find.byKey(const Key('equipment-identity-need-more-view')),
      findsNothing,
    );
  });

  testWidgets(
      'scanId present but enrichment off (the real default): renders nothing',
      (t) async {
    await tall(t);
    await t.pumpWidget(_app(
      const WorkoutPlayerPage(exerciseId: 'ea_row', scanId: 'scan-1'),
      identityOverrides: [
        scanIdImagePathProvider
            .overrideWith((ref) => {'scan-1': '/tmp/photo.jpg'}),
      ],
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('equipment-identity-badge')), findsNothing);
    expect(
      find.byKey(const Key('equipment-identity-need-more-view')),
      findsNothing,
    );
  });
}
