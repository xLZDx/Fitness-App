import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_coordinate_space.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_unit_probe.dart';

/// The diagnostic that turns "what unit are these coordinates in" from an
/// argument into a measurement.
///
/// It is read off the operator's phone, so the two things worth pinning are
/// that it never prints nonsense (infinities from an empty accumulator) and
/// that it does not force the screen to repaint on every camera frame.

PoseLandmark p(LandmarkType t, double x, double y, {double likelihood = 0.9}) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: likelihood);

PoseFrame f(
  Map<LandmarkType, PoseLandmark> ls, {
  double aspectRatio = 0.5625,
  PoseCoordinateSpace? space = PoseCoordinateSpace.pixels,
}) =>
    PoseFrame(
      timestampMs: 0,
      landmarks: ls,
      aspectRatio: aspectRatio,
      sourceSpace: space,
    );

void main() {
  test('an unobserved probe says so instead of printing infinity', () {
    // min starts at +inf and max at -inf. Rendering that produces
    // "x Infinity..-Infinity", which reads as a crash to anyone holding the
    // phone and is the most likely state the screen is in at first glance.
    final probe = PoseUnitProbe();
    expect(probe.report.isEmpty, isTrue);
    expect(probe.report.summary, 'pose: no frames yet');
    expect(probe.report.summary, isNot(contains('Infinity')));
    expect(probe.report.summary, isNot(contains('NaN')));
  });

  test('a frame with no landmarks is not counted as evidence', () {
    final probe = PoseUnitProbe();
    probe.observe(f(const {}));
    expect(probe.report.isEmpty, isTrue,
        reason: 'n must count frames that carried a body, not frames that '
            'arrived -- otherwise a dead detector reports healthy numbers');
  });

  test('extents widen across frames and the summary reports them', () {
    final probe = PoseUnitProbe();
    probe.observe(f({
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 0.50),
    }));
    probe.observe(f({
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.10, 0.90),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.45, 0.60),
    }));

    final r = probe.report;
    expect(r.frames, 2);
    expect(r.minX, closeTo(0.10, 1e-12));
    expect(r.maxX, closeTo(0.45, 1e-12));
    expect(r.minY, closeTo(0.40, 1e-12));
    expect(r.maxY, closeTo(0.90, 1e-12));
    expect(r.summary, contains('n=2'));
    expect(r.summary, contains('pixels'));
    expect(r.summary, contains('bound 0.563'),
        reason: 'the x bound belongs next to the x range, so the reader does '
            'not have to remember what it was');
  });

  test('a mixed-space session is visible, not averaged away', () {
    // If the detector ever changed its mind mid-session, a fix that assumes one
    // space would be wrong half the time. The report has to show it.
    final probe = PoseUnitProbe();
    probe.observe(f({LandmarkType.leftHip: p(LandmarkType.leftHip, 0.2, 0.3)}));
    probe.observe(f(
      {LandmarkType.leftHip: p(LandmarkType.leftHip, 0.2, 0.3)},
      space: PoseCoordinateSpace.normalised,
    ));
    expect(probe.report.spaces.length, 2);
    expect(probe.report.summary, contains('pixels+normalised'));
  });

  test('an all-NaN frame never renders as Infinity', () {
    // The diagnostic is read off a phone screen. An all-NaN frame is one of the
    // two states that trip PoseGateVerdict.unitMismatch, so this is precisely
    // the moment the operator looks at this line -- and it used to answer with
    // "x Infinity..-Infinity", because the frame counter was incremented before
    // any coordinate had been folded in.
    final probe = PoseUnitProbe();
    probe.observe(f({
      LandmarkType.leftHip: p(LandmarkType.leftHip, double.nan, double.nan),
      LandmarkType.rightHip: p(LandmarkType.rightHip, double.nan, double.nan),
    }));
    expect(probe.report.isEmpty, isTrue,
        reason: 'a frame that contributed no coordinate is not evidence');
    expect(probe.report.summary, isNot(contains('Infinity')));
    expect(probe.report.summary, 'pose: no frames yet');
  });

  test('NaN is skipped rather than swallowing the whole range', () {
    final probe = PoseUnitProbe();
    probe.observe(f({
      LandmarkType.leftHip: p(LandmarkType.leftHip, double.nan, 0.40),
      LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 0.50),
    }));
    expect(probe.report.summary, isNot(contains('NaN')));
    expect(probe.report.minX, closeTo(0.30, 1e-12));
  });

  group('the report does not repaint the screen 30 times a second', () {
    // It is published to a StateProvider, which skips notifying when the new
    // value equals the old. That only helps if equality ignores the frame
    // counter, which ticks every single frame forever.

    test('equal extents compare equal even as the counter climbs', () {
      final probe = PoseUnitProbe();
      final ls = {
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 0.50),
      };
      probe.observe(f(ls));
      final first = probe.report;
      probe.observe(f(ls));
      final second = probe.report;

      expect(second.frames, greaterThan(first.frames));
      expect(second, equals(first),
          reason: 'a steady camera must stop notifying once the range settles');
      expect(second.hashCode, first.hashCode);
    });

    test('a widened extent DOES compare unequal', () {
      // The positive control. Without it the test above would also pass if
      // every report compared equal to every other, which would freeze the
      // diagnostic at its first value.
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 0.50),
      }));
      final before = probe.report;
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.05, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 0.50),
      }));
      expect(probe.report, isNot(equals(before)));
    });

    test('an empty report never equals a populated one', () {
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.0, 0.0),
      }));
      expect(probe.report, isNot(equals(PoseUnitReport.empty)),
          reason: 'a single landmark at the origin has zero extent, which is '
              'numerically identical to the empty report -- only isEmpty tells '
              'them apart');
    });
  });

  group('the two explanations for a wide range are told apart', () {
    // Gate B's whole question. The operator's device reported
    // `x -0.466..1.968 (bound 0.667) y -2.173..3.015` on a session that was
    // otherwise scoring, and a single extent over every landmark cannot say
    // whether that is a broken conversion or BlazePose extrapolating the joints
    // that left the frame. These two cases are those two worlds, built to be
    // indistinguishable on the OLD summary line and opposite on the new one.

    test('extrapolated joints leave the trusted extent in contract', () {
      // The benign world: the body is comfortably inside the frame, and the
      // wild numbers all belong to joints the detector is guessing at.
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 0.50),
        LandmarkType.leftAnkle:
            p(LandmarkType.leftAnkle, -0.47, 3.01, likelihood: 0.05),
        LandmarkType.rightAnkle:
            p(LandmarkType.rightAnkle, 1.97, -2.17, likelihood: 0.10),
      }));

      final r = probe.report;
      expect(r.minY, closeTo(-2.17, 1e-9),
          reason: 'positive control: the full extent really is far outside the '
              'contract, so this case is the one that used to be ambiguous');
      expect(r.trusted.minY, closeTo(0.40, 1e-9));
      expect(r.trusted.maxY, closeTo(0.50, 1e-9));
      expect(r.trustedOutOfContract, isFalse);
      expect(r.summary, contains('in contract'));
      expect(r.summary, isNot(contains('OUT OF CONTRACT')));
    });

    test('a confident joint outside the frame is called out', () {
      // The broken world. Same wild extent, but it belongs to a joint the
      // detector is sure about, which no amount of extrapolation explains.
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
        LandmarkType.rightHip: p(LandmarkType.rightHip, 0.30, 3.01),
      }));

      final r = probe.report;
      expect(r.trustedOutOfContract, isTrue);
      expect(r.summary, contains('OUT OF CONTRACT'));
    });

    test('x is judged against the frame ratio, not against 1', () {
      // x runs 0..aspectRatio by the isotropic contract, so a bare `> 1` test
      // would call a perfectly normal landscape frame broken and a portrait
      // one healthy at x = 0.9 when its bound is 0.5625.
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.90, 0.40),
      }, aspectRatio: 0.5625));
      expect(probe.report.trustedOutOfContract, isTrue,
          reason: 'x 0.90 is outside a 0.5625-wide frame');

      final wide = PoseUnitProbe();
      wide.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.90, 0.40),
      }, aspectRatio: 1.7778));
      expect(wide.report.trustedOutOfContract, isFalse,
          reason: 'the same x is well inside a landscape frame');
    });

    test('a session with nothing trusted says so instead of claiming health',
        () {
      // All guesses. "in contract" here would be a lie of omission: there is no
      // evidence either way, and reporting the benign verdict would retire a
      // question nobody answered.
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.2, 5.0, likelihood: 0.1),
      }));
      final r = probe.report;
      expect(r.trusted.isEmpty, isTrue);
      expect(r.trustedOutOfContract, isFalse);
      expect(r.summary, contains('none seen'));
      expect(r.summary, isNot(contains('in contract')));
    });

    test('a widening trusted extent still refreshes the line', () {
      // The full extent is held still on purpose, so the ONLY thing that
      // changes is the trusted box. If equality ignored it, the diagnostic
      // would freeze exactly when it began to matter.
      final probe = PoseUnitProbe();
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
        LandmarkType.leftAnkle:
            p(LandmarkType.leftAnkle, 0.10, 0.90, likelihood: 0.1),
      }));
      final before = probe.report;
      probe.observe(f({
        LandmarkType.leftHip: p(LandmarkType.leftHip, 0.20, 0.40),
        // Same coordinates as the guess above, now believed.
        LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.10, 0.90),
      }));
      final after = probe.report;

      expect(after.all, equals(before.all),
          reason: 'positive control: the full extent did NOT move, so the '
              'inequality below can only come from the trusted box');
      expect(after, isNot(equals(before)));
    });
  });

  test('reset returns the probe to the empty state', () {
    final probe = PoseUnitProbe();
    probe.observe(f({LandmarkType.leftHip: p(LandmarkType.leftHip, 0.2, 0.3)}));
    probe.reset();
    expect(probe.report, equals(PoseUnitReport.empty));
    expect(probe.report.summary, 'pose: no frames yet');
  });
}
