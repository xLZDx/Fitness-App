import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';

/// The anchor is only worth anything if it is IN the path a scan takes.
/// `machine_text_anchor_test.dart` proves the matching rules; this file proves
/// the controller actually consults them, prefers them when they are decisive,
/// and falls through to the classifier when they are not.
///
/// Both are needed. A pure function nobody calls passes its own tests forever.

/// Stands in for the real classifier and records whether it was consulted at
/// all — the assertion that separates "the anchor answered" from "the anchor
/// happened to agree".
class _RecordingClassifier implements VisualEquipmentService {
  _RecordingClassifier(this.result);

  final List<VisualMatch> result;
  int calls = 0;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    calls++;
    return result;
  }
}

/// Throws the way a missing OCR model does.
class _BrokenRecogniser implements MachineTextRecogniser {
  @override
  Future<String> readText(String path) async => throw Exception('no OCR model');

  @override
  Future<void> dispose() async {}
}

EquipmentItem _eq(String id, String name) => EquipmentItem(
      id: id,
      name: name,
      manufacturer: 'Any',
      category: 'strength',
      description: '',
    );

final _catalogue = [
  _eq('hip_abductor_adductor', 'Hip abductor / adductor'),
  _eq('leg_press', 'Leg press'),
  _eq('leg_curl', 'Leg curl'),
  _eq('leg_extension', 'Leg extension'),
  _eq('pec_deck', 'Pec deck'),
  _eq('treadmill', 'Treadmill'),
];

void main() {
  ProviderContainer containerWith({
    required MachineTextRecogniser? recogniser,
    required VisualEquipmentService classifier,
  }) {
    final c = ProviderContainer(overrides: [
      recogniseTimeoutProvider
          .overrideWithValue(const Duration(milliseconds: 200)),
      equipmentListProvider.overrideWith((_) async => _catalogue),
      machineTextRecogniserProvider.overrideWithValue(recogniser),
      visualEquipmentServiceProvider.overrideWithValue(classifier),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<ScanResult> scan(ProviderContainer c) async {
    // The catalogue is a FutureProvider; the anchor skips itself when it has
    // not resolved, so a test that did not await it would silently exercise
    // the fall-through path and prove nothing.
    await c.read(equipmentListProvider.future);
    await c
        .read(visualEquipmentControllerProvider.notifier)
        .classifyFilePath('/tmp/machine.jpg');
    return c.read(visualEquipmentControllerProvider).requireValue;
  }

  test('a machine that names itself is identified from the text, and the '
      'classifier is never consulted', () async {
    // Photo 20260730_135634. The v1 model called this `treadmill` at 0.892 and
    // v2 abstained; the machine has said "ABDUCTION / ADDUCTION" on its own
    // shroud the whole time.
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'treadmill', confidence: 0.89),
    ]);
    final c = containerWith(
      recogniser: FakeMachineTextRecogniser(
          'NAUTILUS\nINSPIRATION\nABDUCTION / ADDUCTION'),
      classifier: classifier,
    );

    final r = await scan(c);
    expect(r.outcome, ScanOutcome.confident);
    expect(r.matches.single.equipmentId, 'hip_abductor_adductor');
    expect(r.matches.single.labelHint, 'abduction adduction',
        reason: 'the user is shown what was read, so they can check it');
    expect(classifier.calls, 0,
        reason: 'a decisive reading must not be second-guessed by a 29-way '
            'softmax that has already been measured getting this wrong');
  });

  test('no text in the frame falls through to the classifier', () async {
    // The common case, and the one that must not regress: most photos have no
    // legible name in them.
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
    ]);
    final c = containerWith(
      recogniser: FakeMachineTextRecogniser(''),
      classifier: classifier,
    );

    final r = await scan(c);
    expect(classifier.calls, 1);
    expect(r.matches.single.equipmentId, 'leg_press');
  });

  test('text that names nothing we know falls through', () async {
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
    ]);
    final c = containerWith(
      recogniser: FakeMachineTextRecogniser('NAUTILUS INSPIRATION STRENGTH'),
      classifier: classifier,
    );

    final r = await scan(c);
    expect(classifier.calls, 1, reason: 'brand words identify nothing');
    expect(r.matches.single.equipmentId, 'leg_press');
  });

  test('text naming TWO machines defers to the classifier rather than '
      'picking one', () async {
    // Photo 20260730_135552: Leg Curl and Leg Extension stand side by side and
    // both placards are readable. The anchor must not break that tie itself.
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'leg_curl', confidence: 0.7),
    ]);
    final c = containerWith(
      recogniser: FakeMachineTextRecogniser(
          'INSPIRATION Leg Curl    INSPIRATION Leg Extension'),
      classifier: classifier,
    );

    final r = await scan(c);
    expect(classifier.calls, 1);
    expect(r.matches.single.equipmentId, 'leg_curl');
  });

  test('a broken OCR model does not break a scan the classifier could answer',
      () async {
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'treadmill', confidence: 0.8),
    ]);
    final c = containerWith(
      recogniser: _BrokenRecogniser(),
      classifier: classifier,
    );

    final r = await scan(c);
    expect(r.outcome, isNot(ScanOutcome.failed),
        reason: 'the anchor is additive; its failure is not the scan\'s');
    expect(classifier.calls, 1);
    expect(r.matches.single.equipmentId, 'treadmill');
  });

  test('with no recogniser configured the pipeline is exactly as it was',
      () async {
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'pec_deck', confidence: 0.8),
    ]);
    final c = containerWith(recogniser: null, classifier: classifier);

    final r = await scan(c);
    expect(classifier.calls, 1);
    expect(r.matches.single.equipmentId, 'pec_deck');
  });
}
