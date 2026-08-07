import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart'
    show InputImage;

import 'package:fitness_app/features/visual_equipment/data/machine_text_anchor.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_text_recogniser.dart';

/// The live path's OCR seam cannot be driven end-to-end on a desktop runner:
/// `MlKitLiveEquipmentService` needs a camera stream and a native labeler.
/// What CAN be tested — and is where the interesting mistakes live — is the
/// decision the service makes from what OCR returned, and the cost budget it
/// keeps.
///
/// This file exercises that decision through the same pure function the
/// service calls, plus a faithful re-statement of the gating rules. It is NOT
/// a substitute for the service: `_anchorFromFrame` is thin on purpose so that
/// the part worth testing is the part that is testable.

const _catalogue = <String, String>{
  'hip_abductor_adductor': 'Hip abductor / adductor',
  'leg_curl': 'Leg curl',
  'leg_extension': 'Leg extension',
  'treadmill': 'Treadmill',
  'cable_machine': 'Cable machine',
};

/// Mirrors `MlKitLiveEquipmentService._anchorFromFrame`'s decision, so a
/// change to the rule that is not mirrored here shows up as a failing test
/// rather than as live mode quietly answering something else.
String? decide(String ocrText) {
  if (ocrText.trim().isEmpty) return null;
  final hits = matchMachineText(ocrText, catalogue: _catalogue);
  return hits.length == 1 ? hits.single.equipmentId : null;
}

void main() {
  group('live anchor — what the service does with what OCR returned', () {
    test('a machine that names itself is answered outright', () {
      // 20260730_135634. The classifier called this `treadmill` at 0.892.
      expect(decide('NAUTILUS INSPIRATION\nABDUCTION / ADDUCTION'),
          'hip_abductor_adductor');
    });

    test('no text in the viewfinder answers nothing', () {
      expect(decide(''), isNull);
      expect(decide('   \n  '), isNull);
    });

    test('brand text alone answers nothing', () {
      // Panning across a gym puts NAUTILUS in frame constantly. If that could
      // anchor, live mode would lock onto whatever phrase sorted first and
      // never let go.
      expect(decide('NAUTILUS'), isNull);
      expect(decide('STAR TRAC\nINSPIRATION STRENGTH'), isNull);
    });

    test('two machines in the viewfinder answer nothing', () {
      // Panning between the Leg Curl and the Leg Extension, which stand side
      // by side in the operator's gym (photo 20260730_135552). The classifier
      // and its smoother decide that one; the text must not.
      expect(decide('INSPIRATION LEG CURL   INSPIRATION LEG EXTENSION'),
          isNull);
    });

    test('a multi-exercise station is the station, not one exercise', () {
      expect(
          decide('NAUTILUS INSTINCT\nLunge Pulldown Shoulder Press '
              'Biceps Curl Torso Twist Ab Crunch'),
          'cable_machine');
    });
  });

  group('live anchor — cost', () {
    /// Re-states the service's frame gate: `_frameCount++ % ocrEveryNthFrame`.
    List<int> ocrFramesIn(int frames, int everyNth) {
      final fired = <int>[];
      for (var i = 0; i < frames; i++) {
        if (i % everyNth == 0) fired.add(i);
      }
      return fired;
    }

    test('OCR runs on one frame in eight, not on every frame', () {
      // OCR is a SECOND ML Kit call on a path that already drops frames to
      // keep up. Running it per frame would roughly double the cost of live
      // mode to re-read a decal that has not moved.
      expect(ocrFramesIn(80, 8), hasLength(10));
      expect(ocrFramesIn(80, 8).first, 0,
          reason: 'the first frame is read, so first answer is not delayed');
    });

    test('at the labeler cadence the first read is under a second', () {
      // The smoother's window is 6 frames and exists because the classifier
      // flickers. The anchor reads on frame 0 — there is nothing to smooth
      // about a name printed on a shroud.
      expect(ocrFramesIn(6, 8), [0]);
    });
  });

  group('FakeMachineTextRecogniser', () {
    test('answers frames as well as files, and counts both', () async {
      // The live path hands ML Kit an InputImage, the photo path a file path.
      // A fake that only implemented one would leave the live seam untested
      // while looking covered.
      final fake = FakeMachineTextRecogniser('LEG PRESS');
      expect(await fake.readText('/tmp/a.jpg'), 'LEG PRESS');
      expect(fake.calls, 1);

      final frame = InputImage.fromFilePath('/tmp/a.jpg');
      expect(await fake.readFrame(frame), 'LEG PRESS');
      expect(fake.calls, 2);
    });
  });
}
