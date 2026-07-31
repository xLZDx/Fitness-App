import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';

FormFeedback fb(int severity, FormCueKey cue) =>
    FormFeedback(rule: 'squat.depth', severity: severity, cueKey: cue);

void main() {
  group('CueGate', () {
    // Regression: the repeat filter ran BEFORE the interrupt check, so a
    // danger that persists across frames — which emits the SAME cue text
    // every frame — was spoken once and then silenced for the rest of the
    // dangerous streak. Reported by review, 2026-07-29.
    test('a persisting danger cue keeps being spoken, not silenced as a repeat',
        () {
      var now = 0;
      final gate = CueGate(clock: () => now);

      expect(gate.decide(fb(2, FormCueKey.squatDepthHalf)), CueDecision.preempt);

      // Same cue immediately after: throttled, not spoken twice in a frame.
      now = 200;
      expect(gate.decide(fb(2, FormCueKey.squatDepthHalf)), CueDecision.suppress);

      // Once the interrupt gap has passed it must speak again — the danger
      // has not gone away.
      now = 1400;
      expect(gate.decide(fb(2, FormCueKey.squatDepthHalf)), CueDecision.preempt,
          reason: 'a still-dangerous position must keep warning');
    });

    test('an ordinary repeated cue is still filtered as a repeat', () {
      var now = 0;
      final gate = CueGate(clock: () => now);
      expect(gate.decide(fb(1, FormCueKey.squatDepthAlmost)), CueDecision.speak);
      now = 5000; // well past minGapMs
      expect(gate.decide(fb(1, FormCueKey.squatDepthAlmost)), CueDecision.suppress,
          reason: 'nudges must not nag with identical text');
    });

    test('ordinary cues respect the 3s throttle', () {
      var now = 0;
      final gate = CueGate(clock: () => now);
      expect(gate.decide(fb(1, FormCueKey.squatDepthAlmost)), CueDecision.speak);
      now = 1000;
      expect(gate.decide(fb(1, FormCueKey.pushupAlignTuck)), CueDecision.suppress);
      now = 3100;
      expect(gate.decide(fb(1, FormCueKey.pushupAlignSagging)), CueDecision.speak);
    });

    test('a danger cue bypasses the ordinary throttle entirely', () {
      var now = 0;
      final gate = CueGate(clock: () => now);
      expect(gate.decide(fb(1, FormCueKey.squatDepthAlmost)), CueDecision.speak);
      now = 100; // far inside minGapMs
      expect(gate.decide(fb(2, FormCueKey.squatDepthHalf)), CueDecision.preempt);
    });

    test('severity 0 is never spoken', () {
      final gate = CueGate(clock: () => 0);
      expect(gate.decide(fb(0, FormCueKey.squatDepthGood)), CueDecision.suppress);
    });

    test('reset lets the same cue speak again', () {
      var now = 0;
      final gate = CueGate(clock: () => now);
      expect(gate.decide(fb(1, FormCueKey.squatDepthAlmost)), CueDecision.speak);
      gate.reset();
      now = 10;
      expect(gate.decide(fb(1, FormCueKey.squatDepthAlmost)), CueDecision.speak);
    });
  });
}
