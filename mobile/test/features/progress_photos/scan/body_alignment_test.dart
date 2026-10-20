import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/scan/body_alignment.dart';

/// A standing figure in normalised frame coordinates.
const base = <BodyKeypoint, Point2>{
  BodyKeypoint.head: Point2(0.28, 0.12),
  BodyKeypoint.leftShoulder: Point2(0.20, 0.24),
  BodyKeypoint.rightShoulder: Point2(0.36, 0.24),
  BodyKeypoint.leftHip: Point2(0.23, 0.46),
  BodyKeypoint.rightHip: Point2(0.33, 0.46),
  BodyKeypoint.leftKnee: Point2(0.23, 0.64),
  BodyKeypoint.rightKnee: Point2(0.33, 0.64),
  BodyKeypoint.leftAnkle: Point2(0.23, 0.82),
  BodyKeypoint.rightAnkle: Point2(0.33, 0.82),
};

/// Points B would have so that [t] maps B onto [a] (inverse transform of a).
Map<BodyKeypoint, Point2> makeB(
  Map<BodyKeypoint, Point2> a,
  SimilarityTransform t,
) {
  final c = math.cos(t.rotation) * t.scale;
  final s = math.sin(t.rotation) * t.scale;
  final det = c * c + s * s;
  return {
    for (final e in a.entries)
      e.key: () {
        final dx = e.value.x - t.tx, dy = e.value.y - t.ty;
        return Point2((c * dx + s * dy) / det, (-s * dx + c * dy) / det);
      }(),
  };
}

void expectMaps(Map<BodyKeypoint, Point2> a, Map<BodyKeypoint, Point2> b,
    SimilarityTransform t, double tol) {
  for (final k in a.keys) {
    final m = t.apply(b[k]!);
    expect(m.x, closeTo(a[k]!.x, tol), reason: '$k x');
    expect(m.y, closeTo(a[k]!.y, tol), reason: '$k y');
  }
}

void main() {
  const truth =
      SimilarityTransform(scale: 1.3, rotation: 0.12, tx: 0.05, ty: -0.03);

  test('identical points give the identity transform and quality 1', () {
    final r = BodyAlignment.align(base, base);
    expect(r.isUsable, isTrue);
    expect(r.transform!.scale, closeTo(1, 1e-9));
    expect(r.transform!.rotation, closeTo(0, 1e-9));
    expect(r.transform!.tx, closeTo(0, 1e-9));
    expect(r.quality, closeTo(1, 1e-9));
    expect(r.rejected, isEmpty);
  });

  test('recovers a known scale/rotation/translation', () {
    final b = makeB(base, truth);
    final r = BodyAlignment.align(base, b);
    expect(r.isUsable, isTrue);
    expect(r.transform!.scale, closeTo(truth.scale, 1e-9));
    expect(r.transform!.rotation, closeTo(truth.rotation, 1e-9));
    expect(r.transform!.tx, closeTo(truth.tx, 1e-9));
    expect(r.transform!.ty, closeTo(truth.ty, 1e-9));
    expect(r.quality, closeTo(1, 1e-9));
    expectMaps(base, b, r.transform!, 1e-9);
  });

  test('pure scale (distance difference) is recovered without rotation', () {
    const t = SimilarityTransform(scale: 0.8, rotation: 0, tx: 0.1, ty: 0.2);
    final r = BodyAlignment.align(base, makeB(base, t));
    expect(r.transform!.scale, closeTo(0.8, 1e-9));
    expect(r.transform!.rotation.abs(), lessThan(1e-9));
  });

  test('small per-point noise stays within tolerance, quality stays high', () {
    final rnd = math.Random(7);
    final b = {
      for (final e in makeB(base, truth).entries)
        e.key: Point2(e.value.x + (rnd.nextDouble() - .5) * 0.006,
            e.value.y + (rnd.nextDouble() - .5) * 0.006),
    };
    final r = BodyAlignment.align(base, b);
    expect(r.isUsable, isTrue);
    expect(r.transform!.scale, closeTo(truth.scale, 0.03));
    expect(r.transform!.rotation, closeTo(truth.rotation, 0.03));
    expect(r.quality, greaterThan(0.8));
    expectMaps(base, b, r.transform!, 0.02);
  });

  test('partial keypoints (only some present in both) still align', () {
    final b = makeB(base, truth)
      ..remove(BodyKeypoint.head)
      ..remove(BodyKeypoint.leftKnee)
      ..remove(BodyKeypoint.rightKnee);
    final a = Map.of(base)..remove(BodyKeypoint.rightAnkle);
    final r = BodyAlignment.align(a, b);
    expect(r.isUsable, isTrue);
    expect(r.used, hasLength(5));
    expect(r.transform!.scale, closeTo(truth.scale, 1e-9));
  });

  test('one gross outlier is rejected and the fit stays on the truth', () {
    final b = makeB(base, truth);
    b[BodyKeypoint.leftKnee] = const Point2(0.9, 0.1); // detector blunder
    final r = BodyAlignment.align(base, b);
    expect(r.isUsable, isTrue);
    expect(r.rejected, [BodyKeypoint.leftKnee]);
    expect(r.transform!.scale, closeTo(truth.scale, 1e-9));
    expect(r.transform!.rotation, closeTo(truth.rotation, 1e-9));
    // Quality is penalised for the rejected point: 8 of 9 used.
    expect(r.quality, closeTo(8 / 9, 1e-9));
  });

  test('when no spare points exist an outlier cannot be removed: poor fit', () {
    final b = makeB(base, truth);
    b[BodyKeypoint.leftKnee] = const Point2(0.9, 0.1);
    final r = BodyAlignment.align(
      base,
      b,
      config: const AlignmentConfig(minKeypoints: 9),
    );
    expect(r.rejected, isEmpty);
    expect(
      r.failure == AlignmentFailure.implausible || r.quality < 0.5,
      isTrue,
    );
  });

  test('too few shared keypoints is refused', () {
    final b = makeB(base, truth);
    final tiny = {
      BodyKeypoint.leftShoulder: base[BodyKeypoint.leftShoulder]!,
      BodyKeypoint.rightShoulder: base[BodyKeypoint.rightShoulder]!,
      BodyKeypoint.leftHip: base[BodyKeypoint.leftHip]!,
    };
    final r = BodyAlignment.align(tiny, b);
    expect(r.failure, AlignmentFailure.tooFewKeypoints);
    expect(r.transform, isNull);
    expect(r.isUsable, isFalse);
    expect(
        BodyAlignment.align({}, {}).failure, AlignmentFailure.tooFewKeypoints);
  });

  test('disjoint keypoint sets count as too few', () {
    final a = {for (final k in BodyKeypoint.values.take(4)) k: base[k]!};
    final b = {for (final k in BodyKeypoint.values.skip(4)) k: base[k]!};
    expect(
        BodyAlignment.align(a, b).failure, AlignmentFailure.tooFewKeypoints);
  });

  test('all points coincident (degenerate) is refused', () {
    const p = Point2(0.5, 0.5);
    final same = {for (final k in BodyKeypoint.values) k: p};
    expect(
        BodyAlignment.align(same, base).failure, AlignmentFailure.degenerate);
    expect(
        BodyAlignment.align(base, same).failure, AlignmentFailure.degenerate);
  });

  test('NaN / infinite input is refused', () {
    final bad = Map.of(base)..[BodyKeypoint.head] = const Point2(double.nan, 0);
    expect(BodyAlignment.align(base, bad).failure, AlignmentFailure.degenerate);
    final inf = Map.of(base)
      ..[BodyKeypoint.head] = const Point2(double.infinity, 0);
    expect(BodyAlignment.align(inf, base).failure, AlignmentFailure.degenerate);
  });

  test('an implausible scale is refused rather than drawn', () {
    const t = SimilarityTransform(scale: 8, rotation: 0, tx: 0, ty: 0);
    final r = BodyAlignment.align(base, makeB(base, t));
    expect(r.failure, AlignmentFailure.implausible);
    expect(r.transform, isNull);
  });

  test('an implausible rotation is refused', () {
    const t = SimilarityTransform(scale: 1, rotation: 1.5, tx: 0, ty: 0);
    final r = BodyAlignment.align(base, makeB(base, t));
    expect(r.failure, AlignmentFailure.implausible);
  });

  test('un-flipped mirrored input fits visibly worse than a true match', () {
    // Geometry mirrored left-right while the labels stay: a similarity cannot
    // reflect, so the caller must un-mirror first (documented).
    final mirrored = {
      for (final e in base.entries) e.key: Point2(0.56 - e.value.x, e.value.y),
    };
    final r = BodyAlignment.align(base, mirrored);
    expect(!r.isUsable || r.quality < 0.9, isTrue);
  });
}
