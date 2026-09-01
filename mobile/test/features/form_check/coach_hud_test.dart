import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/cue_text.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/form_check/widgets/coach_hud.dart';
import '../../helpers/test_app.dart';
import 'unscorable_frame_test.dart' show oneSquat;

/// Gate G3 — the live HUD.
///
/// The operator's brief for the redesign is a screenshot, and this gate is the
/// LAYOUT it specifies: a movement strip, two ring gauges, a cue chip over the
/// picture, the four trainer counters under it, and a weighted pair of set
/// controls at the bottom. What the gauges MEAN is unchanged from what the two
/// floating badges they replaced already showed; what the counters mean is G4,
/// which is why every one of them reads «—» here and is asserted to.
///
/// These tests assert the two things a screenshot cannot: that a number on a
/// gauge is distinguishable from the absence of one, and that a value nobody
/// has measured yet is never dressed up as a measurement.

Widget _strip(ProviderContainer container, {double width = 360}) =>
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
                    session: container.read(_sessionProvider),
                    showRepCount: container.read(_showRepCountProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

final _showRepCountProvider = Provider<bool>((_) => true);
final _sessionProvider =
    Provider<RepSessionState>((_) => const RepSessionState());

RepQuality _rep({required Map<String, int> severities}) => RepQuality(
      index: 1,
      startMs: 0,
      endMs: 1200,
      peakSignal: -0.3,
      severityByRule: severities,
    );

ProviderContainer _container({
  bool showRepCount = true,
  double? match,
  RepSessionState session = const RepSessionState(),
}) {
  final c = ProviderContainer(overrides: [
    poseGateVerdictProvider.overrideWith((_) => PoseGateVerdict.ok),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
    _showRepCountProvider.overrideWithValue(showRepCount),
    _sessionProvider.overrideWithValue(session),
    if (match != null) poseMatchProvider.overrideWith((_) => match),
  ]);
  addTearDown(c.dispose);
  return c;
}

Widget _page(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FormCheckPage(),
      ),
    );

ProviderContainer _pageContainer(List<PoseFrame> frames) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(frames)),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 60; i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  group('a gauge distinguishes a measurement from the absence of one', () {
    testWidgets(
        'the technique gauge carries a percentage only when there is one to '
        'carry', (tester) async {
      await tester.pumpWidget(_strip(_container(match: 0.94)));
      await tester.pump();

      expect(find.byKey(const Key('form_check.match')), findsOneWidget);
      expect(find.text('94'), findsOneWidget,
          reason: 'the reference sets the number and the % sign at different '
              'weights, so the value itself is "94"');
      expect(
          find.byKey(const Key('form_check.match_not_measured')), findsNothing);
    });

    testWidgets('and an em-dash under its own key when there is not',
        (tester) async {
      await tester.pumpWidget(_strip(_container()));
      await tester.pump();

      // The gauge is still THERE — the reference's layout does not reflow
      // around a missing reading — but nothing about it can be mistaken for a
      // score, and no test looking for a percentage will find one.
      expect(find.byKey(const Key('form_check.hud.technique')), findsOneWidget);
      expect(find.byKey(const Key('form_check.match')), findsNothing);
      expect(find.byKey(const Key('form_check.match_not_measured')),
          findsOneWidget);
    });

    testWidgets(
        'the same rule on the counter: a movement that cannot be counted '
        'shows no count', (tester) async {
      await tester.pumpWidget(_strip(_container(showRepCount: false)));
      await tester.pump();

      expect(find.byKey(const Key('form_check.rep_count')), findsNothing,
          reason: 'a zero here is a measurement, and nothing measured it');
      expect(find.byKey(const Key('form_check.rep_count_not_tracked')),
          findsOneWidget);
    });
  });

  testWidgets(
      'the technique gauge names the rule that spoiled the last rep, not the '
      'live frame', (tester) async {
    // Off the last COMPLETED rep by design: a caption recomputed thirty times
    // a second is not readable, and the reference's tag is a verdict on a
    // repetition rather than a running commentary.
    final session = RepSessionState(
      repCount: 1,
      reps: [
        _rep(severities: {'squat_depth': 2, 'torso_line': 0}),
      ],
    );
    await tester.pumpWidget(_strip(_container(match: 0.62, session: session)));
    await tester.pump();

    final l10n = await AppLocalizations.delegate.load(kTestLocale);
    expect(find.text(formRuleName(l10n, 'squat_depth')), findsOneWidget,
        reason: 'the WORST rule, not the first one in the map');
    expect(find.text(formRuleName(l10n, 'torso_line')), findsNothing,
        reason: 'and only that one — the gauge caption is one line');
  });

  group('the counters panel is honest about having nothing yet', () {
    testWidgets('every counter reads the not-measured dash', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: CoachCountersPanel()),
      ));
      await tester.pump();

      final l10n = await AppLocalizations.delegate.load(kTestLocale);
      for (final key in const [
        'form_check.hud.tempo',
        'form_check.hud.amplitude',
        'form_check.hud.symmetry',
        'form_check.hud.pause',
      ]) {
        // The key sits on the value Text itself, so this reads the very
        // string the user sees rather than asserting on a subtree.
        expect(tester.widget<Text>(find.byKey(Key(key))).data,
            l10n.formcheckHudNotMeasured,
            reason: '$key invented a value G4 has not measured yet');
      }
    });

    testWidgets('and shows a value the moment it is given one', (tester) async {
      // The positive control for the test above, which would otherwise pass on
      // a panel incapable of rendering anything at all.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: CoachCountersPanel(tempo: '2.0s', symmetry: '49/51'),
        ),
      ));
      await tester.pump();

      expect(find.text('2.0s'), findsOneWidget);
      expect(find.text('49/51'), findsOneWidget);
    });
  });

  testWidgets('a rule that watched a rep and passed gets its tick',
      (tester) async {
    _phoneSized(tester);
    final c = _pageContainer(oneSquat(0));
    await tester.pumpWidget(_page(c));
    await _settle(tester);

    final session = c.read(repSessionControllerProvider);
    expect(session.reps, isNotEmpty,
        reason: 'positive control: a rep really did complete');
    final passed = [
      for (final e in session.reps.last.severityByRule.entries)
        if (e.value <= 0) e.key,
    ]..sort();
    expect(passed, isNotEmpty,
        reason: 'positive control: at least one rule watched it and had '
            'nothing to say — severity 0 is a pass, not an absence');

    expect(find.byKey(const Key('form_check.hud.passed_rules')), findsOneWidget);
    expect(find.byKey(Key('form_check.hud.passed_rule.${passed.first}')),
        findsOneWidget);
    // Never more than two: the picture behind the chips is what the user came
    // to look at.
    expect(find.byType(CoachCueChip).evaluate().length, lessThanOrEqualTo(2));
  });

  testWidgets('once a rep completes the panel stops saying «—»',
      (tester) async {
    // G4's acceptance test at the surface the operator actually looks at. The
    // unit tests in `coach_counters_test.dart` prove each reading is a
    // measurement of what its label claims; this one proves the measurement
    // reaches the panel, which is a different failure and the one a screenshot
    // would show.
    _phoneSized(tester);
    final c = _pageContainer(oneSquat(0));
    await tester.pumpWidget(_page(c));
    await _settle(tester);

    expect(c.read(repSessionControllerProvider).reps, isNotEmpty,
        reason: 'positive control: a rep really did complete');

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    String read(String key) =>
        tester.widget<Text>(find.byKey(Key(key))).data ?? '';

    for (final key in const [
      'form_check.hud.tempo',
      'form_check.hud.amplitude',
      'form_check.hud.pause',
    ]) {
      expect(read(key), isNot(l10n.formcheckHudNotMeasured),
          reason: '$key is still blank after a completed repetition');
    }
    // Amplitude is a percentage of parallel, and this fixture stops with the
    // hip level with the knee — so it is near the top of the range, and a
    // panel printing a plausible-looking low number would be wrong in a way
    // "not an em-dash" cannot catch.
    final amplitude =
        int.parse(read('form_check.hud.amplitude').replaceAll('%', ''));
    expect(amplitude, greaterThan(80));
    expect(amplitude, lessThanOrEqualTo(100));
  });

  testWidgets('the set controls weight closing the set over pausing it',
      (tester) async {
    _phoneSized(tester);
    final c = _pageContainer(oneSquat(0));
    await tester.pumpWidget(_page(c));
    c.read(coachPhaseControllerProvider.notifier).start();
    await _settle(tester);

    final pause = tester.getRect(find.byKey(const Key('form_check.pause_set')));
    final close = tester.getRect(find.byKey(const Key('form_check.finish_set')));

    expect(close.width, greaterThan(pause.width * 2),
        reason: 'two equal halves said pausing a set and ending it were the '
            'same kind of choice: pause $pause, close $close');
    expect(pause.left, lessThan(close.left),
        reason: 'and the reference puts the square one first');
    // Still operable, and still the same callbacks: a restyle that quietly
    // stopped pausing the set would pass every geometric assertion above.
    await tester.tap(find.byKey(const Key('form_check.pause_set')));
    await tester.pump();
    expect(c.read(coachSessionProvider).phase, CoachPhase.paused);
    expect(find.byKey(const Key('form_check.resume_set')), findsOneWidget);
  });
}
