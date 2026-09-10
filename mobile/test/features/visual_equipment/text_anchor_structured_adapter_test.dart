import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' show InputImage;

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';

/// P2.G1: proves the photo-scan path's `is StructuredTextRecogniser` adapter
/// (`visual_equipment_providers.dart:_anchorOnPrintedText`) actually prefers
/// the structured call when it is available, and that the fullText it reads
/// reaches the anchor unchanged -- companion to `text_anchor_pipeline_test.dart`,
/// which covers the pre-existing legacy-only wiring and stays untouched by
/// this gate (a new file, not an edit, is how that untouched-ness is proven).

/// Stands in for the real classifier and records whether it was consulted at
/// all, same role as `text_anchor_pipeline_test.dart`'s own recorder.
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

/// Tracks EXACTLY which method the call site invoked -- the assertion that
/// proves the adapter takes the structured path when it is available, not
/// just that the two paths happen to produce the same text.
class _RecordingStructuredRecogniser implements StructuredTextRecogniser {
  _RecordingStructuredRecogniser(this.evidence);

  final MachineTextEvidence evidence;
  bool structuredCalled = false;
  bool legacyCalled = false;

  @override
  Future<MachineTextEvidence> readStructured(String path) async {
    structuredCalled = true;
    return evidence;
  }

  @override
  Future<MachineTextEvidence> readStructuredFrame(InputImage input) async {
    structuredCalled = true;
    return evidence;
  }

  @override
  Future<String> readText(String path) async {
    legacyCalled = true;
    return evidence.fullText;
  }

  @override
  Future<String> readFrame(InputImage input) async {
    legacyCalled = true;
    return evidence.fullText;
  }

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
    await c.read(equipmentListProvider.future);
    await c
        .read(visualEquipmentControllerProvider.notifier)
        .classifyFilePath('/tmp/machine.jpg');
    return c.read(visualEquipmentControllerProvider).requireValue;
  }

  test(
      'when the recogniser exposes structured capability, the structured '
      'method is used and fullText reaches the anchor unchanged', () async {
    // Same fixture as text_anchor_pipeline_test.dart's first test, proving
    // the structured path produces the identical outcome as the legacy path
    // -- P2.G1 must not change what the anchor decides, only how the text
    // got there.
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'treadmill', confidence: 0.89),
    ]);
    final recogniser = _RecordingStructuredRecogniser(
      const MachineTextEvidence(
        fullText: 'NAUTILUS\nINSPIRATION\nABDUCTION / ADDUCTION',
        lines: [],
      ),
    );
    final c = containerWith(recogniser: recogniser, classifier: classifier);

    final r = await scan(c);

    expect(recogniser.structuredCalled, isTrue,
        reason:
            'the is-probe must prefer the structured method when available');
    expect(recogniser.legacyCalled, isFalse,
        reason: 'the legacy String call must not also run when the '
            'structured call already succeeded');
    expect(r.outcome, ScanOutcome.confident);
    expect(r.matches.single.equipmentId, 'hip_abductor_adductor');
    expect(classifier.calls, 0);
  });

  test('a structured recogniser with empty fullText falls through to the '
      'classifier, exactly like the legacy empty-string case', () async {
    final classifier = _RecordingClassifier(const [
      VisualMatch(equipmentId: 'leg_press', confidence: 0.8),
    ]);
    final recogniser = _RecordingStructuredRecogniser(
      const MachineTextEvidence(fullText: '', lines: []),
    );
    final c = containerWith(recogniser: recogniser, classifier: classifier);

    final r = await scan(c);

    expect(recogniser.structuredCalled, isTrue);
    expect(classifier.calls, 1);
    expect(r.matches.single.equipmentId, 'leg_press');
  });
}
