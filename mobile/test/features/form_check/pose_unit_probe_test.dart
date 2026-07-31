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

PoseLandmark p(LandmarkType t, double x, double y) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: 0.9);

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

  test('reset returns the probe to the empty state', () {
    final probe = PoseUnitProbe();
    probe.observe(f({LandmarkType.leftHip: p(LandmarkType.leftHip, 0.2, 0.3)}));
    probe.reset();
    expect(probe.report, equals(PoseUnitReport.empty));
    expect(probe.report.summary, 'pose: no frames yet');
  });
}
