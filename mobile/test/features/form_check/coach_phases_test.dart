import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';

/// R11h gave the coach the design's stages (`App.tsx:4188-4197`). The
/// prototype fakes every one of them with `setTimeout`; this maps them onto
/// the gate verdicts the app already computes per frame, so what is pinned
/// here is the mapping and the folding, not a clock.
void main() {
  group('blockerFor', () {
    test('a scorable frame blocks nothing', () {
      expect(blockerFor(PoseGateVerdict.ok), CoachBlocker.none);
    });

    test('both "no usable body" verdicts collapse to one instruction', () {
      // The gate separates them because the RULES need the distinction; the
      // user is told the same thing either way.
      expect(blockerFor(PoseGateVerdict.missingJoints), CoachBlocker.noBody);
      expect(blockerFor(PoseGateVerdict.lowConfidence), CoachBlocker.noBody);
    });

    test('cropped and too-far stay apart -- opposite instructions', () {
      expect(blockerFor(PoseGateVerdict.outOfFrame), CoachBlocker.cropped);
      expect(
          blockerFor(PoseGateVerdict.implausibleGeometry), CoachBlocker.tooFar);
    });

    test('a unit mismatch is never presented as the user\'s fault', () {
      // `PoseGateVerdict.unitMismatch`'s own doc: no amount of stepping back
      // moves a coordinate from 300 to 0.5, so telling someone to move would
      // have them moving until they gave up, having done nothing wrong.
      expect(blockerFor(PoseGateVerdict.unitMismatch), CoachBlocker.sensorBug);
    });

    test('every verdict maps to something', () {
      for (final v in PoseGateVerdict.values) {
        expect(() => blockerFor(v), returnsNormally);
      }
    });
  });

  group('phaseAfterFrame', () {
    test('quality-check waits for a usable view, then is ready', () {
      expect(
        phaseAfterFrame(CoachPhase.qualityCheck, PoseGateVerdict.outOfFrame),
        CoachPhase.qualityCheck,
      );
      expect(
        phaseAfterFrame(CoachPhase.qualityCheck, PoseGateVerdict.ok),
        CoachPhase.ready,
      );
    });

    test('losing the view un-readies', () {
      // "Start when you are" over a frame that cannot be scored is an
      // invitation to a set nothing will count.
      expect(
        phaseAfterFrame(CoachPhase.ready, PoseGateVerdict.lowConfidence),
        CoachPhase.qualityCheck,
      );
    });

    test('calibration is never entered -- the app has no settling signal', () {
      // The design has a calibration bar; the prototype fills it with
      // `setInterval(() => p + 4, 60)`. This app does not fake it, so the
      // phase stays in the enum and out of the machine. See
      // `phaseAfterFrame`'s own doc.
      expect(
        phaseAfterFrame(CoachPhase.qualityCheck, PoseGateVerdict.ok),
        isNot(CoachPhase.calibration),
      );
      expect(
        phaseAfterFrame(CoachPhase.calibration, PoseGateVerdict.ok),
        CoachPhase.calibration,
      );
    });

    test('a verdict never moves the tap-driven phases', () {
      for (final p in [
        CoachPhase.launch,
        CoachPhase.selection,
        CoachPhase.active,
        CoachPhase.paused,
        CoachPhase.summary,
      ]) {
        expect(
          phaseAfterFrame(p, PoseGateVerdict.ok),
          p,
          reason: 'a verdict cannot know a button was pressed',
        );
      }
    });
  });

  group('countingIsLiveIn', () {
    test('the three phases where the user has not asked to be counted', () {
      // Stated as a full enumeration rather than as the three negatives, so
      // that a phase ADDED later has to be classified here deliberately
      // instead of inheriting "counts" from the default.
      const counts = {
        CoachPhase.qualityCheck: true,
        CoachPhase.calibration: true,
        CoachPhase.ready: true,
        CoachPhase.active: true,
        // The set is not running: the user said so.
        CoachPhase.paused: false,
        CoachPhase.summary: false,
        // Reached from the LIVE screen by pressing back, so a frame can still
        // be in flight when it is entered.
        CoachPhase.selection: false,
        // And `launch` really does answer "yes", which looks wrong and is not:
        // it is the DEFAULT phase, so it is the one every rep-counting test in
        // this feature runs under. Excluding it would silently disarm them
        // rather than tighten anything, and no frame can reach it in the app
        // -- the intro card returns before anything subscribes to the stream.
        CoachPhase.launch: true,
      };
      expect(counts.keys.toSet(), CoachPhase.values.toSet(),
          reason: 'a phase with no answer here is a phase nobody decided');
      counts.forEach((phase, expected) {
        expect(countingIsLiveIn(phase), expected, reason: '$phase');
      });
    });

    test('selection is excluded because back from a set lands there', () {
      // The specific case, spelled out because the table above would keep
      // passing if `selection` were excluded for some unrelated reason.
      // Stopping the camera is asynchronous, so frames already in flight are
      // delivered AFTER the phase has moved to `selection` -- without this
      // they would land on the counter of a set the user has walked away from.
      expect(countingIsLiveIn(CoachPhase.selection), isFalse);
    });
  });
}
