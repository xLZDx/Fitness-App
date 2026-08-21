import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/scanner/widgets/scan_frame.dart';
import '../../helpers/test_app.dart';

/// R11c replaced the viewfinder's plain 75% outline with the design's corner
/// brackets, sweep line and analyzing pulse (`App.tsx:2592-2614`).
///
/// The pixels are not asserted — a golden of an animating frame over a camera
/// preview would be a test of the renderer. What IS asserted is everything the
/// widget decides: that it still covers exactly the crop the classifier
/// receives, that the two phases paint differently, that it keeps animating,
/// and that it tears its controller down.

Future<void> _pumpFrame(
  WidgetTester tester,
  ScanFramePhase phase, {
  double fraction = 0.75,
  bool disableAnimations = false,
}) async {
  Widget harness = testHarness(
    child: Center(
      child: SizedBox(
        width: 400,
        height: 400,
        child: ScanFrame(phase: phase, fraction: fraction),
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
  testWidgets('covers exactly the centre crop the classifier receives',
      (tester) async {
    await _pumpFrame(tester, ScanFramePhase.ready);

    final size = tester.getSize(find.descendant(
      of: find.byType(ScanFrame),
      matching: find.byType(CustomPaint),
    ).first);

    // 75% of the 400x400 parent. The fraction is load-bearing: it is the
    // crop `centre_crop.dart` hands the classifier, so "inside the brackets"
    // has to keep meaning "what gets classified" at any screen size.
    expect(size.width, closeTo(300, 0.5));
    expect(size.height, closeTo(300, 0.5));
  });

  testWidgets('an explicit fraction is honoured', (tester) async {
    await _pumpFrame(tester, ScanFramePhase.ready, fraction: 0.5);

    final size = tester.getSize(find.descendant(
      of: find.byType(ScanFrame),
      matching: find.byType(CustomPaint),
    ).first);
    expect(size.width, closeTo(200, 0.5));
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

  testWidgets('reduce motion freezes the sweep/pulse loop', (tester) async {
    // The sweep line and analyzing pulse are purely decorative, continuous,
    // looping motion over a live camera preview -- exactly what reduce motion
    // exists to suppress. The brackets and corner colour still say "ready" vs
    // "analyzing" without it.
    await _pumpFrame(tester, ScanFramePhase.ready, disableAnimations: true);
    final first = _paintOf(tester).painter!;

    await tester.pump(const Duration(milliseconds: 400));
    final later = _paintOf(tester).painter!;

    expect(later.shouldRepaint(first), isFalse,
        reason: 'reduce motion must stop the loop, not merely slow it');
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
