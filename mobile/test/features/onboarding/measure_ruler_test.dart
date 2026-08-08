import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/onboarding/data/body_metrics.dart';
import 'package:fitness_app/features/onboarding/widgets/measure_ruler.dart';
import '../../helpers/test_app.dart';

/// R11b replaced the onboarding's number keyboards with the design's rulers.
/// The scale arithmetic is pinned without a gesture; the widget is then driven
/// by a real drag to prove the two agree.

void main() {
  group('RulerScale', () {
    const cm = RulerScale(min: 120, max: 220, step: 1, pixelsPerStep: 12);
    const kg = RulerScale(min: 35, max: 200, step: 0.5, pixelsPerStep: 12);

    test('maps a value to an offset and back', () {
      expect(cm.offsetFor(120), 0);
      expect(cm.offsetFor(175), (175 - 120) * 12);
      expect(cm.valueAt(cm.offsetFor(175)), 175);
    });

    test('snaps to the step -- a drag cannot produce 71.4837 kg', () {
      // Two thirds of a step along: rounds to the nearer legal value.
      expect(kg.valueAt(kg.offsetFor(72) + 8), 72.5);
      expect(kg.valueAt(kg.offsetFor(72) + 4), 72.0);
    });

    test('half-kilo steps stay exact after many of them', () {
      // `min + steps * step` rather than repeated addition: the latter
      // accumulates dust and 72.50000000000001 formats differently the moment
      // anyone asks for more precision.
      var v = kg.min;
      for (var i = 0; i < 75; i++) {
        v = kg.valueAt(kg.offsetFor(v) + kg.pixelsPerStep);
      }
      expect(v, 72.5);
    });

    test('clamps at both ends', () {
      expect(cm.valueAt(-500), 120);
      expect(cm.valueAt(cm.extent + 500), 220);
      expect(cm.offsetFor(1750), cm.extent,
          reason: 'a ruler cannot express 1750 cm; a number field could');
    });
  });

  group('MeasureRuler', () {
    testWidgets('an unanswered ruler rests at the midpoint without claiming '
        'the user chose it', (tester) async {
      double? reported;
      await tester.pumpWidget(testHarness(
        child: MeasureRuler(
          value: null,
          min: 120,
          max: 220,
          unit: 'cm',
          onChanged: (v) => reported = v,
        ),
      ));
      await tester.pump();

      expect(find.text('170 cm'), findsOneWidget);
      expect(reported, isNull, reason: 'resting is not answering');
    });

    testWidgets('a drag reports a snapped value', (tester) async {
      final reported = <double>[];
      await tester.pumpWidget(testHarness(
        child: MeasureRuler(
          value: 175,
          min: 120,
          max: 220,
          unit: 'cm',
          onChanged: reported.add,
        ),
      ));
      await tester.pump();

      // Dragging left raises the value: the scale moves under a fixed needle.
      // The exact landing point is not asserted — `tester.drag` swallows
      // `kTouchSlop` before the gesture starts, so the travelled distance is
      // 60 minus a framework constant. What the scale does with a distance is
      // pinned exactly in the `RulerScale` group above; what matters here is
      // that the widget and the scale agree on direction and legality.
      await tester.drag(find.byType(MeasureRuler), const Offset(-60, 0));
      await tester.pump();

      expect(reported, isNotEmpty);
      expect(reported.last, greaterThan(175));
      expect(reported.every((v) => v == v.roundToDouble()), isTrue,
          reason: 'every reported centimetre is a whole one');
    });

    testWidgets('a tap commits the resting value', (tester) async {
      double? reported;
      await tester.pumpWidget(testHarness(
        child: MeasureRuler(
          value: null,
          min: 35,
          max: 200,
          step: 0.5,
          unit: 'kg',
          onChanged: (v) => reported = v,
        ),
      ));
      await tester.pump();

      await tester.tap(find.byType(MeasureRuler));
      await tester.pump();

      expect(reported, 117.5,
          reason: 'someone who agrees with where it sits should not have to '
              'jiggle it to answer');
    });

    testWidgets('an external value change moves the needle', (tester) async {
      // The defect `GlassTextField` had before the audit: a control keeping
      // its own copy and drifting from the draft it is meant to show.
      var value = 175.0;
      late StateSetter rebuild;
      await tester.pumpWidget(testHarness(
        child: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return MeasureRuler(
            value: value,
            min: 120,
            max: 220,
            unit: 'cm',
            onChanged: (_) {},
          );
        }),
      ));
      await tester.pump();
      expect(find.text('175 cm'), findsOneWidget);

      rebuild(() => value = 190);
      await tester.pump();

      expect(find.text('190 cm'), findsOneWidget);
    });
  });

  group('body metrics', () {
    test('BMI is null until both numbers exist', () {
      expect(bmiFor(heightCm: null, weightKg: 72), isNull);
      expect(bmiFor(heightCm: 175, weightKg: null), isNull);
      expect(bmiFor(heightCm: 0, weightKg: 72), isNull,
          reason: 'a card reading "0.0" states a false measurement');
    });

    test('BMI matches the definition', () {
      expect(bmiFor(heightCm: 180, weightKg: 81)!, closeTo(25.0, 0.05));
    });

    test('the bands are the conventional ones', () {
      expect(bandFor(17), BmiBand.underweight);
      expect(bandFor(22), BmiBand.healthy);
      expect(bandFor(27), BmiBand.overweight);
      expect(bandFor(31), BmiBand.obese);
      // Boundaries land in the higher band, as the WHO table defines them.
      expect(bandFor(18.5), BmiBand.healthy);
      expect(bandFor(25), BmiBand.overweight);
      expect(bandFor(30), BmiBand.obese);
    });

    test('the weight delta is signed and null-safe', () {
      expect(weightDelta(currentKg: 80, targetKg: 74), -6);
      expect(weightDelta(currentKg: 70, targetKg: 76), 6);
      expect(weightDelta(currentKg: null, targetKg: 74), isNull);
    });
  });
}
