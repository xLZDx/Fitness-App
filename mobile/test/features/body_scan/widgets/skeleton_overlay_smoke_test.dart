import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/widgets/skeleton_overlay.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';

/// Records the draw calls the painter makes.
class _Rec implements Canvas {
  final List<(Offset, Offset, Paint)> lines = [];
  final List<(Offset, double, Paint)> circles = [];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((p1, p2, Paint()..color = paint.color..style = paint.style));

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add((c, radius, Paint()..color = paint.color..style = paint.style));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

PoseLandmark _lm(LandmarkType t, double x, double y, [double l = 0.9]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: l);

PoseFrame _frame(Map<LandmarkType, PoseLandmark> m, {double aspect = 0.5}) =>
    PoseFrame(timestampMs: 0, aspectRatio: aspect, landmarks: m);

/// Shoulders, hips and one leg: 4 joints per side where given.
PoseFrame _torso({double rightL = 0.9, double aspect = 0.5}) => _frame({
      LandmarkType.leftShoulder: _lm(LandmarkType.leftShoulder, 0.1, 0.2),
      LandmarkType.rightShoulder:
          _lm(LandmarkType.rightShoulder, 0.4, 0.2, rightL),
      LandmarkType.leftHip: _lm(LandmarkType.leftHip, 0.15, 0.5),
      LandmarkType.rightHip: _lm(LandmarkType.rightHip, 0.35, 0.5, rightL),
    }, aspect: aspect);

const _size = Size(200, 400);

_Rec _paint(PoseFrame f, {required bool ready, Color color = Colors.green}) {
  final rec = _Rec();
  SkeletonPainter(frame: f, ready: ready, color: color).paint(rec, _size);
  return rec;
}

void main() {
  group('geometry', () {
    test('ready: one solid line per bone whose both joints are visible', () {
      final rec = _paint(_torso(), ready: true);
      // shoulder-shoulder, 2x shoulder-hip, hip-hip.
      expect(rec.lines, hasLength(4));
      expect(rec.circles, hasLength(4));
    });

    test('landmark maps to (x / aspect * width, y * height)', () {
      final rec = _paint(_torso(aspect: 0.5), ready: true);
      final shoulderLine = rec.lines.firstWhere(
          (l) => l.$1 == const Offset(0.1 / 0.5 * 200, 0.2 * 400));
      expect(shoulderLine.$2, const Offset(0.4 / 0.5 * 200, 0.2 * 400));
      expect(rec.circles.map((c) => c.$1), contains(const Offset(60, 200)),
          reason: 'left hip: 0.15 / 0.5 * 200 = 60, 0.5 * 400 = 200');
    });

    test('landmarks below the likelihood floor are not drawn', () {
      expect(kSkeletonMinLikelihood, 0.3);
      final low = _paint(_torso(rightL: 0.29), ready: true);
      // Only the left shoulder + left hip remain: one bone, two joints.
      expect(low.circles, hasLength(2));
      expect(low.lines, hasLength(1));
      final edge = _paint(_torso(rightL: 0.3), ready: true);
      expect(edge.circles, hasLength(4), reason: 'exactly at the floor is drawn');
    });

    test('an empty frame draws nothing', () {
      final rec = _paint(_frame({}), ready: true);
      expect(rec.lines, isEmpty);
      expect(rec.circles, isEmpty);
    });

    test('arm and leg bones are included when their joints exist', () {
      final f = _frame({
        LandmarkType.leftShoulder: _lm(LandmarkType.leftShoulder, 0.1, 0.2),
        LandmarkType.leftElbow: _lm(LandmarkType.leftElbow, 0.1, 0.3),
        LandmarkType.leftWrist: _lm(LandmarkType.leftWrist, 0.1, 0.4),
        LandmarkType.leftHip: _lm(LandmarkType.leftHip, 0.1, 0.5),
        LandmarkType.leftKnee: _lm(LandmarkType.leftKnee, 0.1, 0.7),
        LandmarkType.leftAnkle: _lm(LandmarkType.leftAnkle, 0.1, 0.9),
      });
      // sh-elbow, elbow-wrist, sh-hip, hip-knee, knee-ankle
      expect(_paint(f, ready: true).lines, hasLength(5));
    });
  });

  group('readiness is not conveyed by colour alone', () {
    test('ready: solid bones, filled joints', () {
      final rec = _paint(_torso(), ready: true);
      expect(rec.circles.every((c) => c.$3.style == PaintingStyle.fill), isTrue);
      final shoulder = rec.lines.first;
      expect((shoulder.$2 - shoulder.$1).distance, closeTo(120, 0.001),
          reason: 'one full-length segment per bone');
    });

    test('not ready: dashed bones (many short segments), hollow joints', () {
      final rec = _paint(_torso(), ready: false);
      expect(rec.circles.every((c) => c.$3.style == PaintingStyle.stroke),
          isTrue);
      expect(rec.lines.length, greaterThan(4 * 3));
      expect(rec.lines.every((l) => (l.$2 - l.$1).distance <= 8.0 + 1e-9),
          isTrue,
          reason: 'dash length is 8 px');
      // The first dash of the shoulder bone starts on the joint.
      expect(rec.lines.first.$1, const Offset(0.1 / 0.5 * 200, 80));
      // 120 px bone: dashes at 0, 14, 28 ... -> 9 dashes (last one at 112).
      final shoulderDashes = rec.lines
          .where((l) => l.$1.dy == 80 && l.$2.dy == 80)
          .toList();
      expect(shoulderDashes, hasLength(9));
    });

    test('the given colour is applied to lines and joints', () {
      final rec = _paint(_torso(), ready: true, color: const Color(0xFF123456));
      expect(rec.lines.every((l) => l.$3.color.value == 0xFF123456),
          isTrue);
      expect(rec.circles.every((c) => c.$3.color.value == 0xFF123456),
          isTrue);
    });
  });

  group('shouldRepaint', () {
    final f = _torso();
    SkeletonPainter p(PoseFrame fr, bool ready, Color c) =>
        SkeletonPainter(frame: fr, ready: ready, color: c);

    test('unchanged inputs do not repaint; any change does', () {
      final base = p(f, true, Colors.green);
      expect(base.shouldRepaint(p(f, true, Colors.green)), isFalse);
      expect(base.shouldRepaint(p(f, false, Colors.green)), isTrue);
      expect(base.shouldRepaint(p(f, true, Colors.red)), isTrue);
      expect(base.shouldRepaint(p(_torso(), true, Colors.green)), isTrue,
          reason: 'a new frame object is new data');
    });
  });

  group('widget', () {
    Widget host(PoseFrame? f, bool ready) => MaterialApp(
        home: Scaffold(body: SizedBox(
            width: 200,
            height: 400,
            child: SkeletonOverlay(frame: f, ready: ready))));

    testWidgets('null frame renders nothing', (tester) async {
      await tester.pumpWidget(host(null, false));
      expect(find.byKey(const Key('scan.skeleton')), findsNothing);
    });

    testWidgets('with a frame: painted, decorative, ignores pointers',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(_torso(), true));
      expect(find.byKey(const Key('scan.skeleton')), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byKey(const Key('scan.skeleton')),
              matching: find.byType(IgnorePointer)),
          findsWidgets);
      expect(
          find.ancestor(
              of: find.byKey(const Key('scan.skeleton')),
              matching: find.byType(ExcludeSemantics)),
          findsWidgets);
      final labels = <String>[];
      final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
      void visit(SemanticsNode node) {
        if (node.label.isNotEmpty) labels.add(node.label);
        node.visitChildren((c) {
          visit(c);
          return true;
        });
      }

      visit(root);
      expect(labels, isEmpty, reason: 'the overlay adds no semantics');
      handle.dispose();
    });

    testWidgets('a tap passes through the overlay to what is below', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(
                child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand())),
            Positioned.fill(child: SkeletonOverlay(frame: _torso(), ready: true)),
          ]),
        ),
      ));
      await tester.tapAt(const Offset(100, 100));
      expect(taps, 1);
    });
  });
}
