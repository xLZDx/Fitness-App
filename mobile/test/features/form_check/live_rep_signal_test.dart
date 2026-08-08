import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/measured_rep_configs.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// R8 remainder: [liveRepSignalFor] is what [RepSessionController] actually
/// reads. Before this gate the controller built its counter with no signal
/// argument at all, so every movement silently ran [squatDepthSignal] — this
/// file is the regression test for that: it asserts on the SIGNAL/CONFIG the
/// live counter gets, not on [repSignalFor], which was already correct and
/// already tested and simply had nothing wired to it.
void main() {
  group('liveRepSignalFor', () {
    test('squat: unchanged, keeps squatDepthSignal + default config', () {
      final live = liveRepSignalFor(FormExercise.squat);
      final old = repSignalFor(FormExercise.squat);
      expect(live, isNotNull);
      // `repSignalFor(squat)` names `squatDepthSignal` directly (a top-level
      // function, one instance always), so identity IS meaningful here --
      // unlike `MeasuredRepConfig.signal` below, which is a getter that
      // builds a fresh closure per access.
      expect(live!.$1, same(old!.$1));
      expect(live.$2.topEnter, old.$2.topEnter);
      expect(live.$2.bottomEnter, old.$2.bottomEnter);
    });

    /// The three movements MM-Fit measured at or above the 80% holdout bar.
    /// Each must now run the MEASURED config, not the authored-shape one
    /// `rep_signals.dart` shipped on 2026-08-08 — the two disagree (measured
    /// numbers come from 6,160 real reps; the old ones from the demo shapes),
    /// so a passing test here is proof the switch happened, not a tautology.
    for (final tag in ['curl', 'overhead_press', 'lunge']) {
      test('$tag: switches to the MM-Fit measured config', () {
        final e = kPosePatternToExercise[tag]!;
        final measured = measuredRepConfigs[tag]!;
        expect(measured.countsReps, isTrue,
            reason: '$tag must clear the 80% bar for this test to be valid');

        final live = liveRepSignalFor(e);
        final legacy = repSignalFor(e);
        expect(live, isNotNull);
        // `MeasuredRepConfig.signal` is a getter -- every access, including
        // the one inside `liveRepSignalFor`, builds a fresh closure, so
        // identity is never meaningful here. The config values are: they are
        // computed once from fixed measured constants.
        final measuredConfig = measured.toConfig();
        expect(live!.$2.topEnter, measuredConfig.topEnter);
        expect(live.$2.bottomEnter, measuredConfig.bottomEnter);
        // Not a no-op: the measured thresholds actually differ from the
        // authored-shape ones they replace.
        expect(live.$2.topEnter, isNot(legacy!.$2.topEnter));
      });
    }

    /// `situp` and `pushup` were measured and came in under the 80% bar (41%
    /// and 29%). `counterFor` refuses both, and so must the live signal —
    /// falling back to whatever `repSignalFor` already did, not to nothing,
    /// so the frame pipeline (silhouette match, phase tracking) keeps running
    /// for these movements. Only the on-screen NUMBER is suppressed, via
    /// [showRepCountFor].
    test('situp: below the accuracy bar, falls back to the old signal', () {
      final measured = measuredRepConfigs['situp']!;
      expect(measured.countsReps, isFalse);
      final live = liveRepSignalFor(FormExercise.situp);
      final legacy = repSignalFor(FormExercise.situp);
      expect(live, isNotNull);
      expect(live!.$1, same(legacy!.$1));
      expect(live.$2.topEnter, legacy.$2.topEnter);
    });

    test('pushup: below the accuracy bar, stays uncountable', () {
      final measured = measuredRepConfigs['pushup']!;
      expect(measured.countsReps, isFalse);
      expect(liveRepSignalFor(FormExercise.pushup), isNull);
      expect(repSignalFor(FormExercise.pushup), isNull);
    });

    /// `hinge` has no MM-Fit equivalent at all (no deadlift in the dataset).
    /// It must keep running its old, authored-shape signal rather than lose
    /// its counter entirely.
    test('hinge: no measured entry exists, falls back to the old signal', () {
      expect(measuredRepConfigs.containsKey('hinge'), isFalse);
      final live = liveRepSignalFor(FormExercise.hinge);
      final legacy = repSignalFor(FormExercise.hinge);
      expect(live, isNotNull);
      expect(live!.$1, same(legacy!.$1));
    });
  });

  group('showRepCountFor', () {
    test('true for the movements with a measured, accurate counter', () {
      for (final e in [
        FormExercise.squat,
        FormExercise.curl,
        FormExercise.overheadPress,
        FormExercise.lunge,
      ]) {
        expect(showRepCountFor(e), isTrue, reason: e.name);
      }
    });

    test('false for the two movements measured below the accuracy bar', () {
      expect(showRepCountFor(FormExercise.situp), isFalse);
      expect(showRepCountFor(FormExercise.pushup), isFalse);
    });

    /// Unmeasured is not the same as inaccurate: hinge keeps showing its
    /// count because nothing contradicted it, unlike situp/pushup which were
    /// measured and found wanting.
    test('true for hinge, which was never measured, not found inaccurate',
        () {
      expect(showRepCountFor(FormExercise.hinge), isTrue);
    });

    test('false for deadlift, which has no signal at all', () {
      expect(showRepCountFor(FormExercise.deadlift), isFalse);
    });
  });
}
