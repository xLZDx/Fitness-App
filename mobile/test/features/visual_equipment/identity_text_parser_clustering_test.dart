import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/identity_text_parser.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_text_evidence.dart';

MachineTextLine _line(String text, double left, double top, double width, double height) =>
    MachineTextLine(
      text: text,
      bounds: Rect.fromLTWH(left, top, width, height),
    );

void main() {
  group('clusterLines', () {
    test('empty input yields no clusters', () {
      expect(clusterLines(const []), isEmpty);
    });

    test('a single line is its own single cluster', () {
      final lines = [_line('LEG PRESS', 50, 100, 200, 40)];
      final clusters = clusterLines(lines);
      expect(clusters, hasLength(1));
      expect(clusters.single, hasLength(1));
    });

    test('closely-spaced lines merge into one cluster', () {
      final lines = [
        _line('LEG PRESS', 50, 100, 200, 40),
        _line('MAX 200 KG', 50, 150, 200, 40),
      ];
      final clusters = clusterLines(lines);
      expect(clusters, hasLength(1));
      expect(clusters.single, hasLength(2));
    });

    test('widely-separated lines form separate clusters', () {
      final lines = [
        _line('LEG PRESS', 50, 100, 200, 40),
        _line('MAX 200 KG', 50, 150, 200, 40),
        _line('TREADMILL T5', 50, 900, 150, 30),
      ];
      final clusters = clusterLines(lines);
      expect(clusters, hasLength(2));
      final sizes = clusters.map((c) => c.length).toList()..sort();
      expect(sizes, [1, 2]);
    });

    test('three widely-separated lines form three clusters', () {
      final lines = [
        _line('A', 0, 0, 100, 30),
        _line('B', 0, 500, 100, 30),
        _line('C', 0, 1000, 100, 30),
      ];
      final clusters = clusterLines(lines);
      expect(clusters, hasLength(3));
    });
  });

  group('determineOwnership', () {
    test('no clusters yields an empty primary and no secondary', () {
      final ownership = determineOwnership(const []);
      expect(ownership.primary, isEmpty);
      expect(ownership.secondary, isNull);
      expect(ownership.ambiguous, isFalse);
    });

    test('a single cluster is the primary with no secondary', () {
      final clusters = [
        [_line('LEG PRESS', 50, 100, 200, 40)],
      ];
      final ownership = determineOwnership(clusters);
      expect(ownership.primary, clusters.single);
      expect(ownership.secondary, isNull);
      expect(ownership.ambiguous, isFalse);
    });

    test('a much larger cluster is the confident primary; the small one is not ambiguous', () {
      final primaryCluster = [
        _line('LEG PRESS', 0, 0, 200, 40),
        _line('MAX 200 KG', 0, 50, 200, 40),
      ];
      final neighbourCluster = [
        _line('TREADMILL T5', 0, 500, 150, 30),
      ];
      final ownership = determineOwnership([primaryCluster, neighbourCluster]);
      expect(ownership.primary, primaryCluster);
      expect(ownership.secondary, neighbourCluster);
      expect(ownership.ambiguous, isFalse);
    });

    test('two near-tied clusters are reported ambiguous', () {
      final clusterA = [_line('9NPL', 0, 0, 200, 40)];
      final clusterB = [_line('8TRX', 0, 400, 175, 40)];
      final ownership = determineOwnership([clusterA, clusterB]);
      expect(ownership.secondary, isNotNull);
      expect(ownership.ambiguous, isTrue);
    });

    test('the larger of two near-tied clusters is still reported as primary', () {
      final clusterA = [_line('9NPL', 0, 0, 200, 40)];
      final clusterB = [_line('8TRX', 0, 400, 175, 40)];
      final ownership = determineOwnership([clusterA, clusterB]);
      expect(ownership.primary, clusterA);
      expect(ownership.secondary, clusterB);
    });
  });
}
