import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/scanner/widgets/scan_frame.dart';
import '../../helpers/test_app.dart';

/// SCAN-G1 rebuilt the viewfinder frame at the reference's fixed geometry
/// (`Sunset.dc.html:187-191`, keyframes at line 18).
///
/// The pixels are not asserted here -- the reference-fidelity gate
/// (`tools/design/scan_fidelity_check.py`, `scan_reference_geometry_test.dart`)
/// does that against the rendered reference. What IS asserted is everything
/// the widget decides: the numbers it draws with are the reference's, the
/// two phases paint differently, it keeps animating, the sweep follows the
/// reference's keyframes and is invisible at t=0, reduce motion parks it
/// there, and it tears its controller down.

Future<void> _pumpFrame(
  WidgetTester tester,
  ScanFramePhase phase, {
  bool disableAnimations = false,
  bool sweepVisible = true,
}) async {
  Widget harness = testHarness(
    child: Center(
      child: SizedBox(
        width: 358,
        height: 230,
        child: ScanFrame(
          phase: phase,
          bracket: const Color(0xE6FFFFFF),
          accent: const Color(0xFFC9FF47),
          sweepVisible: sweepVisible,
        ),
      ),
    ),
  );
  if (disableAnimations) {
    harness = MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: harness,
    );
  }
  await tester.pumpWidget(harness);
  await tester.pump();
}

CustomPaint _paintOf(WidgetTester tester) => tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byType(ScanFrame),
            matching: find.byType(CustomPaint),
          )
          .first,
    );

void main() {
  test('draws with the reference numbers, not approximations of them', () {
    // Sunset.dc.html:187-190: `left/top/right/bottom:20px; width:34px;
    // height:34px; border:2px` (36px outer box); radii `15px` top-left,
    // `10px` elsewhere. Line 191: `left/right:20px; top:18px; height:2px`;
    // line 18: `translateY(196px)` over `3.4s`.
    expect(ScanFrame.inset, 20);
    expect(ScanFrame.arm, 36);
    expect(ScanFrame.stroke, 2);
    expect(ScanFrame.radiusTopLeft, 15);
    expect(ScanFrame.radiusOther, 10);
    expect(ScanFrame.sweepTop, 18);
    expect(ScanFrame.sweepHeight, 2);
    expect(ScanFrame.sweepTravel, 196);
    expect(ScanFrame.sweepPeriod, const Duration(milliseconds: 3400));
  });

  test('the sweep follows glassScan: invisible at both ends, full between', () {
    // `0% opacity 0; 12% 1; 88% 1; 100% 0`, `translateY(0 -> 196px)`.
    expect(scanSweepOpacity(0), 0);
    expect(scanSweepOpacity(0.12), closeTo(1, 1e-9));
    expect(scanSweepOpacity(0.5), 1);
    expect(scanSweepOpacity(0.88), 1);
    expect(scanSweepOpacity(1), closeTo(0, 1e-9));
    expect(scanSweepOpacity(0.06), inExclusiveRange(0, 1));
    expect(scanSweepOffset(0), 0);
    expect(scanSweepOffset(1), closeTo(196, 1e-9));
    expect(scanSweepOffset(0.5), closeTo(98, 1e-9),
        reason: 'ease-in-out is symmetric about the midpoint');
    expect(scanSweepOffset(0.25), lessThan(49),
        reason: 'eased, not linear: slow at the start');
  });

  testWidgets('fills the card it is given -- the frame is the card', (tester) async {
    await _pumpFrame(tester, ScanFramePhase.ready);
    final size = tester.getSize(find.descendant(
      of: find.byType(ScanFrame),
      matching: find.byType(CustomPaint),
    ).first);
    // No 75% fraction any more: the brackets sit a fixed 20px inside the
    // card's own edges, and the crop follows the brackets
    // (`viewfinderSourceRect`), not the other way round.
    expect(size, const Size(358, 230));
  });

  testWidgets('the two phases do not paint the same thing', (tester) async {
    await _pumpFrame(tester, ScanFramePhase.ready);
    final ready = _paintOf(tester).painter!;

    await _pumpFrame(tester, ScanFramePhase.analyzing);
    final analyzing = _paintOf(tester).painter!;

    expect(analyzing.shouldRepaint(ready), isTrue,
        reason: 'aiming and working must be visually distinguishable -- the '
            'plain outline this replaced looked identical in both, so a '
            'two-second classification read as a frozen screen');
  });

  testWidgets('keeps animating while it is on screen', (tester) async {
    await _pumpFrame(tester, ScanFramePhase.ready);
    final first = _paintOf(tester).painter!;

    await tester.pump(const Duration(milliseconds: 400));
    final later = _paintOf(tester).painter!;

    expect(later.shouldRepaint(first), isTrue,
        reason: 'a still sweep line is not a sweep line');
  });

  testWidgets('reduce motion parks the loop at t=0, where the sweep is unseen',
      (tester) async {
    // The sweep line and analyzing pulse are purely decorative, continuous,
    // looping motion over a live camera preview -- exactly what reduce motion
    // exists to suppress. Parked at t=0 rather than anywhere: the reference's
    // own keyframes put the sweep at opacity 0 there, so a reduced-motion
    // user sees the brackets alone, the same picture the reference renders
    // paused at its start.
    await _pumpFrame(tester, ScanFramePhase.ready, disableAnimations: true);
    final first = _paintOf(tester).painter!;

    await tester.pump(const Duration(milliseconds: 400));
    final later = _paintOf(tester).painter!;

    expect(later.shouldRepaint(first), isFalse,
        reason: 'reduce motion must stop the loop, not merely slow it');
  });

  testWidgets('sweepVisible=false paints a different frame', (tester) async {
    // Evidence mode (R1) hides the sweep; the flag has to reach the painter.
    await _pumpFrame(tester, ScanFramePhase.ready);
    final withSweep = _paintOf(tester).painter!;
    await _pumpFrame(tester, ScanFramePhase.ready, sweepVisible: false);
    final without = _paintOf(tester).painter!;
    // Compared at the same t (both freshly pumped), so the only difference
    // is the flag.
    expect(without.shouldRepaint(withSweep), isTrue);
  });

  testWidgets('disposes its controller when removed', (tester) async {
    await _pumpFrame(tester, ScanFramePhase.ready);
    // A leaked AnimationController fails the test binding on teardown, so
    // simply unmounting and settling is the assertion.
    await tester.pumpWidget(testHarness(child: const SizedBox.shrink()));
    await tester.pump();

    expect(find.byType(ScanFrame), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
