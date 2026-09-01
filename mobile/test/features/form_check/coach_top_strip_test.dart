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
                    session: RepSessionState(
                      isArmed: container.read(_armedProvider),
                    ),
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

/// Same trick for the counter's armed flag, which now decides whether the band
/// carries the "stand tall to start counting" instruction.
final _armedProvider = Provider<bool>((_) => false);

ProviderContainer _container({
  PoseGateVerdict verdict = PoseGateVerdict.lowConfidence,
  bool showRepCount = true,
  bool armed = false,
  double? match,
}) {
  final c = ProviderContainer(overrides: [
    poseGateVerdictProvider.overrideWith((_) => verdict),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    _showRepCountProvider.overrideWithValue(showRepCount),
    _armedProvider.overrideWithValue(armed),
    if (match != null) poseMatchProvider.overrideWith((_) => match),
    // Camera mode, stated rather than inherited. The match readout only exists
    // against a target, and Gate A withdrew the target in avatar mode — which
    // became the default on 2026-08-15. A test about where the readout SITS has
    // to be in the view that has one.
    avatarModeProvider.overrideWith((_) => false),
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

  testWidgets('mid-set, with nothing to instruct, there is no band and the '
      'counter keeps its place', (tester) async {
    final c = _container(verdict: PoseGateVerdict.ok, armed: true);
    c.read(coachPhaseControllerProvider.notifier).start();

    await tester.pumpWidget(_harness(c));
    await tester.pump();

    expect(find.byKey(const Key('coach.readinessBand')), findsNothing);
    // The counter must not fall down the screen when its neighbour below
    // disappears: the whole point of a column is that removing the bottom row
    // leaves the top row where it was.
    //
    // Measured against the movement strip, which is present in every state,
    // rather than against a pixel constant. The constant this used to carry
    // (`< 60`) was a proxy for "still at the top", and G3 broke it by putting
    // a movement strip and a gauge label above the number — the counter had
    // not drifted at all, the thing above it had grown. Comparing the two
    // states directly does not work either: the band's presence is not the
    // only difference between them (the strip's live dot and the gauge's
    // phase caption both turn on mid-set), so that comparison would fail on
    // changes this test is not about.
    final strip = tester.getRect(find.byKey(const Key('form_check.hud.strip')));
    final gauge = tester.getRect(find.byKey(const Key('form_check.hud.reps')));
    final count = tester.getRect(find.byKey(const Key('form_check.rep_count')));
    expect(gauge.top - strip.bottom, lessThan(24),
        reason: 'the gauges fell away from the strip they hang under when the '
            'band left: strip $strip, gauge $gauge');
    expect(gauge.contains(count.center), isTrue,
        reason: 'and the number is still inside its own gauge: gauge $gauge, '
            'count $count');
  });

  testWidgets('mid-set, an unarmed counter is still explained — in the band, '
      'and only there', (tester) async {
    // The `armed: false` half of the case above, and the reason this test was
    // rewritten rather than left alone. "stand tall to start counting" used to
    // live inside the rep badge, where it sat directly above the band's own
    // "Ready. Start when you are." — the screen saying it was waiting for the
    // user and that it was not, eight pixels apart. It moved into the band, so
    // the two can no longer both be rendered; a frozen `0` mid-set must still
    // say why, which is what `RepSessionState.isArmed` was added for.
    final c = _container(verdict: PoseGateVerdict.ok);
    c.read(coachPhaseControllerProvider.notifier).start();

    await tester.pumpWidget(_harness(c));
    await tester.pump();

    final inBand = find.descendant(
      of: find.byKey(const Key('coach.readinessBand')),
      matching: find.byKey(const Key('form_check.waiting_for_top')),
    );
    expect(inBand, findsOneWidget);
    // And nowhere else: one message, one place.
    expect(find.byKey(const Key('form_check.waiting_for_top')), findsOneWidget);
  });

  testWidgets('a movement that counts nothing is never told to stand tall',
      (tester) async {
    // `showRepCountFor` refuses this movement, so "stand tall to start
    // counting" is an instruction to reach a number that was never going to
    // appear. The badge is replaced by the "counting is off" chip; the
    // instruction must not survive alongside it.
    await tester.pumpWidget(_harness(_container(
      verdict: PoseGateVerdict.ok,
      showRepCount: false,
    )));
    await tester.pump();

    expect(find.byKey(const Key('form_check.waiting_for_top')), findsNothing);
    expect(
        find.byKey(const Key('form_check.rep_count_not_tracked')), findsOneWidget,
        reason: 'positive control: this really is the not-counted branch');
  });
}
