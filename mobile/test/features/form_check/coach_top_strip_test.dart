import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import '../../helpers/test_app.dart';

/// The overlay above the camera used to draw two things in the same corner.
///
/// `CoachReadinessBand` wrapped itself in `Padding(all: 12)` and was dropped in
/// with `Align(topCenter)`; the rep badge used `Positioned(left: 12, top: 12)`.
/// Both statements were locally correct and together they put "Встаньте в кадр
/// так, чтобы вас было видно целиком" on top of the rep counter.
///
/// Nothing caught it. A Stack is *for* overlapping children — no overflow, no
/// exception, no failed assertion. Both the host suite and the on-device suite
/// read the widget tree, and the tree was right; only the pixels were wrong.
/// The operator's screenshot from a real phone is what found it.
///
/// So these tests assert on geometry, not on presence: `findsOneWidget` for
/// each would have passed happily the whole time.

/// The strip is pinned exactly as `FormCheckPage` pins it — `left/right/top: 12`
/// inside a Stack over the preview. Testing it in a bare Scaffold would test a
/// layout the app does not use.
Widget _harness(ProviderContainer container, {double width = 360}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 640,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: CoachTopStrip(
                    session: const RepSessionState(),
                    showRepCount: container.read(_showRepCountProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

/// Lets a test pick the counting/not-counting branch without reaching into the
/// page's own derivation, which needs a selected exercise and a live camera.
final _showRepCountProvider = Provider<bool>((_) => true);

ProviderContainer _container({
  PoseGateVerdict verdict = PoseGateVerdict.lowConfidence,
  bool showRepCount = true,
  double? match,
}) {
  final c = ProviderContainer(overrides: [
    poseGateVerdictProvider.overrideWith((_) => verdict),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    _showRepCountProvider.overrideWithValue(showRepCount),
    if (match != null) poseMatchProvider.overrideWith((_) => match),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// True when two rectangles share any area at all.
bool _overlaps(Rect a, Rect b) => a.overlaps(b);

void main() {
  testWidgets('the readiness band never overlaps the rep counter',
      (tester) async {
    await tester.pumpWidget(_harness(_container()));
    await tester.pump();

    final band = tester.getRect(find.byKey(const Key('coach.readinessBand')));
    final count = tester.getRect(find.byKey(const Key('form_check.rep_count')));

    expect(_overlaps(band, count), isFalse,
        reason: 'band $band and rep count $count share screen area — this is '
            'exactly the defect: two overlay children positioned '
            'independently from the same edge');
    expect(band.top, greaterThanOrEqualTo(count.bottom),
        reason: 'the band belongs BELOW the readouts it explains');
  });

  testWidgets('nor the "counting is off" badge that replaces the counter',
      (tester) async {
    await tester.pumpWidget(_harness(_container(showRepCount: false)));
    await tester.pump();

    final band = tester.getRect(find.byKey(const Key('coach.readinessBand')));
    final badge = tester
        .getRect(find.byKey(const Key('form_check.rep_count_not_tracked')));

    // The push-up branch. Both screenshots that exposed the bug were taken on
    // it, because its badge is the wider of the two and overlapped further.
    expect(_overlaps(band, badge), isFalse, reason: 'band $band, badge $badge');
  });

  testWidgets('nor the silhouette-match readout on the other side',
      (tester) async {
    await tester.pumpWidget(_harness(_container(match: 0.82)));
    await tester.pump();

    final band = tester.getRect(find.byKey(const Key('coach.readinessBand')));
    final match = tester.getRect(find.byKey(const Key('form_check.match')));
    final count = tester.getRect(find.byKey(const Key('form_check.rep_count')));

    expect(_overlaps(band, match), isFalse, reason: 'band $band, match $match');
    expect(_overlaps(count, match), isFalse,
        reason: 'the two readouts share a row and must not collide either');
  });

  testWidgets('the row of readouts survives the narrowest supported screen',
      (tester) async {
    // 320dp in Russian is where `/scan` lost its live toggle entirely. Same
    // shape here — two pills in one row — so the same failure is possible and
    // is pinned rather than assumed away.
    await tester.pumpWidget(_harness(_container(match: 0.99), width: 320));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'a RenderFlex overflow here means a readout is off-screen');
  });

  testWidgets('mid-set there is no band, and the counter keeps its place',
      (tester) async {
    final c = _container(verdict: PoseGateVerdict.ok);
    c.read(coachPhaseControllerProvider.notifier).start();

    await tester.pumpWidget(_harness(c));
    await tester.pump();

    expect(find.byKey(const Key('coach.readinessBand')), findsNothing);
    // The counter must not drift when its neighbour disappears: the whole point
    // of a column is that removing the bottom row leaves the top row where it
    // was. 12 from the parent's inset, and nothing else.
    final count = tester.getRect(find.byKey(const Key('form_check.rep_count')));
    expect(count.top, lessThan(60),
        reason: 'rep count fell down the screen when the band left: $count');
  });
}
