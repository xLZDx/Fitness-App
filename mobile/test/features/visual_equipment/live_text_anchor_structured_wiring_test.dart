import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart'
    show InputImage;

import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_live_equipment_service.dart'
    show readTextForLiveAnchor;
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';

/// P2.G1: proves the live-scan path's `is StructuredTextRecogniser` adapter
/// (`readTextForLiveAnchor`, called from `MlKitLiveEquipmentService._anchorFromFrame`)
/// prefers the structured call when it is available, exactly mirroring the
/// photo-scan path in `text_anchor_structured_adapter_test.dart`.
///
/// `_anchorFromFrame` itself stays untestable end-to-end on a desktop runner
/// for the reason `live_text_anchor_test.dart`'s own header already states
/// (camera stream + native labeler, pre-existing and unrelated to this
/// gate); `readTextForLiveAnchor` is the exact probe it calls, extracted so
/// this gate's own wiring change is covered independently of that
/// constraint. A new file rather than an edit to `live_text_anchor_test.dart`,
/// so that pre-existing file's own git history stays untouched by this gate.

/// Tracks exactly which method [readTextForLiveAnchor] invoked --
/// [FakeStructuredTextRecogniser]'s shared counter cannot make that
/// distinction on its own, since it increments the same counter for every
/// method.
class _RecordingRecogniser implements StructuredTextRecogniser {
  _RecordingRecogniser(this.evidence);

  final MachineTextEvidence evidence;
  bool structuredFrameCalled = false;
  bool legacyFrameCalled = false;

  @override
  Future<MachineTextEvidence> readStructured(String path) async => evidence;

  @override
  Future<MachineTextEvidence> readStructuredFrame(InputImage input) async {
    structuredFrameCalled = true;
    return evidence;
  }

  @override
  Future<String> readText(String path) async => evidence.fullText;

  @override
  Future<String> readFrame(InputImage input) async {
    legacyFrameCalled = true;
    return evidence.fullText;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  final frame = InputImage.fromFilePath('/tmp/frame.jpg');

  group('readTextForLiveAnchor', () {
    test('a legacy-only recogniser is read via readFrame', () async {
      final legacy = FakeMachineTextRecogniser('LEG PRESS');

      final text = await readTextForLiveAnchor(legacy, frame);

      expect(text, 'LEG PRESS');
      expect(legacy.calls, 1);
    });

    test(
        'a structured recogniser is read via readStructuredFrame, and its '
        'fullText reaches the caller unchanged', () async {
      final structured = FakeStructuredTextRecogniser(
        const MachineTextEvidence(fullText: 'CABLE MACHINE', lines: []),
      );

      final text = await readTextForLiveAnchor(structured, frame);

      expect(text, 'CABLE MACHINE');
      expect(structured.calls, 1);
    });

    test(
        'a recogniser exposing both APIs is read via the structured one, '
        'never the legacy one', () async {
      final recorder = _RecordingRecogniser(
        const MachineTextEvidence(fullText: 'SQUAT RACK', lines: []),
      );

      final text = await readTextForLiveAnchor(recorder, frame);

      expect(text, 'SQUAT RACK');
      expect(recorder.structuredFrameCalled, isTrue);
      expect(recorder.legacyFrameCalled, isFalse);
    });
  });
}
