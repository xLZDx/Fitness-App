import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/cue_text.dart';
import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import '../../helpers/test_app.dart';
import 'unscorable_frame_test.dart' show oneSquat;

/// Gate G7 — «со спокойными объяснениями что именно не так».
///
/// The cue on the picture is an instruction shouted mid-set and has to be
/// readable while moving. This is the other half: read afterwards, standing
/// still, with room for a reason and for the number the reason rests on.
///
/// The invariant these tests exist for is the one that is easy to lose:
/// **the coach explains only what it is entitled to judge.** Two of the three
/// shipped rules report their measurement at severity 0 for a documented
/// reason — the quantity is camera-dependent — and writing them an explanation
/// would be inventing a verdict the rule itself refuses to reach.

FormFeedback _fb(String rule, int severity, FormCueKey cue, {double? metric}) =>
    FormFeedback(rule: rule, severity: severity, cueKey: cue, metric: metric);

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(kTestLocale);

void main() {
  group('an explanation exists only where a verdict does', () {
    test('the one rule that can fault gets a real explanation', () async {
      final l10n = await _l10n();
      final text = formFaultExplanation(
          l10n,
          _fb('pushup.alignment', 2, FormCueKey.pushupAlignSagging,
              metric: 148));
      expect(text, isNotNull);
      expect(text!.length, greaterThan(60),
          reason: 'a calm explanation is a sentence with a reason in it, not '
              'a second copy of the four-word cue');
      expect(text, isNot(formCueText(l10n, FormCueKey.pushupAlignSagging)),
          reason: 'and it is not the cue itself repeated one panel lower');
    });

    test('a rule that reports without judging gets none, even handed a '
        'severity it is not entitled to', () async {
      // `SquatDepthClassifier.canFault` is false and every arm of its
      // `evaluate` returns severity 0: the quantity it compares is
      // camera-dependent. An explanation here would be a verdict the rule
      // declines to reach.
      //
      // Severity 2, deliberately, and this is the point of the test. The first
      // draft passed severity 0 and therefore only exercised the "nothing is
      // wrong" guard one line into the function — it kept passing when an
      // explanation WAS wired to `squatDepthHalf`, which is the defect it was
      // written to catch. The claim being made is about the cue, not about the
      // number beside it.
      final l10n = await _l10n();
      expect(
          formFaultExplanation(
              l10n, _fb('squat.depth', 2, FormCueKey.squatDepthHalf)),
          isNull);
      expect(
          formFaultExplanation(l10n,
              _fb('deadlift.hip_hinge', 2, FormCueKey.deadliftHipHingeDeep)),
          isNull);
    });

    test('and a clean repetition gets none either', () async {
      final l10n = await _l10n();
      expect(
          formFaultExplanation(
              l10n, _fb('pushup.alignment', 0, FormCueKey.pushupAlignStraight)),
          isNull);
    });
  });

  group('the measurement is the rule’s own, not a retyped one', () {
    test('the angle and the threshold both come from the classifier',
        () async {
      final l10n = await _l10n();
      final text = formFaultMeasurement(
          l10n,
          _fb('pushup.alignment', 2, FormCueKey.pushupAlignSagging,
              metric: 148.4));
      expect(text, isNotNull);
      expect(text, contains('148'));
      expect(
          text,
          contains(
              PushupAlignmentClassifier.straightMinDeg.toStringAsFixed(0)),
          reason: 'the target shown must be the constant the rule branches on '
              '— a threshold retyped into a translated sentence drifts from '
              'the rule silently');
    });

    test('a rule whose metric has no stated target shows no measurement',
        () async {
      // The squat's hip-minus-knee is a fraction of frame height whose meaning
      // changes with where the phone is standing. Printing it would lend it an
      // authority the rule itself declines.
      final l10n = await _l10n();
      expect(
          formFaultMeasurement(
              l10n, _fb('squat.depth', 2, FormCueKey.squatDepthHalf,
                  metric: -0.12)),
          isNull);
    });

    test('and a fault with no metric at all shows none', () async {
      final l10n = await _l10n();
      expect(
          formFaultMeasurement(
              l10n, _fb('pushup.alignment', 2, FormCueKey.pushupAlignSagging)),
          isNull);
    });
  });

  group('on the screen', () {
    Widget page(ProviderContainer c) => UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const FormCheckPage(),
          ),
        );

    ProviderContainer container([List<PoseFrame> frames = const []]) {
      final c = ProviderContainer(overrides: [
        poseDetectorServiceProvider
            .overrideWithValue(MockPoseDetectorService(frames)),
        coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    void phoneSized(WidgetTester t) {
      t.view.physicalSize = const Size(400, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }

    testWidgets('nothing is said until there is something to say',
        (tester) async {
      phoneSized(tester);
      await tester.pumpWidget(page(container()));
      await tester.pump();
      expect(find.byKey(const Key('form_check.explain')), findsNothing,
          reason: 'an empty card headed "what exactly is wrong" over a rep '
              'nobody faulted is the screen inventing a problem');
    });

    testWidgets('and a faulted repetition is explained, with its rule named '
        'in words', (tester) async {
      phoneSized(tester);
      final c = container(oneSquat(0));
      await tester.pumpWidget(page(c));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 33));
      }

      final cue = c.read(repSessionControllerProvider).lastRepCue;
      expect(cue, isNotNull, reason: 'positive control: a rep completed');
      expect(cue!.severity, greaterThan(0),
          reason: 'positive control: and it was faulted — this fixture does '
              'not reach the authored side-view target, which is asserted '
              'directly in one_cue_per_rep_test.dart');

      expect(find.byKey(const Key('form_check.explain')), findsOneWidget);

      // The rule NAME, in words. `silhouette.match` is synthesised outside the
      // classifier list, so `formRuleName` had no arm for it and the raw id
      // would have gone on screen — the exact defect that function exists to
      // prevent, found by this gate putting the name on screen for the first
      // time.
      final rule = tester
          .widget<Text>(find.byKey(const Key('form_check.explain.rule')))
          .data;
      expect(rule, isNot(contains('.')),
          reason: 'an internal rule id reached the user: $rule');
    });
  });
}
