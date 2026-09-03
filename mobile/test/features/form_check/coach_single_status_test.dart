import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/form_check_page.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show faceSelfie, oneSquat, squatFrame;

/// One question, one answer, one place on the screen.
///
/// The defect this pins came from a real phone. In a single frame the coach
/// showed, top to bottom: "stand tall to start counting" inside the rep badge,
/// "Ready. Start when you are." in the band under it, "Can't place your torso —
/// step back so your shoulders and hips are both in view" across the middle,
/// and "Ready - do a rep." at the bottom. Four messages, three of which
/// disagreed about whether the coach could see the user at all.
///
/// None of the four widgets was buggy on its own. Each read a different signal
/// — `PoseGateVerdict.isScorable`, `blockerFor(verdict)`, `RepSessionState
/// .isArmed`, and `buildPoseAvatar`'s shoulder-and-hip requirement — and each
/// rendered whatever its own signal said. The gate can legitimately report `ok`
/// on a frame the avatar cannot draw, because `SquatDepthClassifier
/// .requiredLandmarks` is hips and knees while a spine needs a shoulder.
///
/// So the assertion here is not "widget X shows the right text". It is the
/// property that no combination of those signals can put two status messages on
/// screen at once. A per-widget test cannot express that, and four of them
/// passing is exactly the state the app was already in.

/// Every key that can carry a status message, across all four surfaces.
///
/// Listed exhaustively on purpose: a new status added without a thought for
/// this invariant will not appear here, the count assertions will not see it,
/// and the test will keep passing while the screen regains a second voice. The
/// comment is the guard — if you add a status, add it here.
const _statusKeys = <Key>[
  // The band, in priority order.
  Key('form_check.avatar_no_torso'),
  Key('form_check.gate_hint'),
  Key('form_check.waiting_for_top'),
  Key('coach.ready'),
  Key('coach.checking'),
  // The cue card.
  Key('form_check.rep_rejected'),
  Key('form_check.rep_clean'),
  Key('form_check.cue'),
];

final _avatar = find.byKey(const Key('form_check.avatar'));
final _skeleton = find.byKey(const Key('form_check.skeleton'));
final _silhouette = find.byKey(const Key('form_check.silhouette'));

List<String> _statuses(WidgetTester t) => [
      for (final k in _statusKeys)
        if (find.byKey(k).evaluate().isNotEmpty)
          (k as ValueKey<String>).value,
    ];

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

ProviderContainer _container(List<PoseFrame> frames, {bool skeleton = false}) {
  final c = ProviderContainer(overrides: [
    poseDetectorServiceProvider
        .overrideWithValue(MockPoseDetectorService(frames)),
    coachInitialPhaseProvider.overrideWithValue(CoachPhase.qualityCheck),
  ]);
  addTearDown(c.dispose);
  if (skeleton) c.read(showSkeletonProvider.notifier).state = true;
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

/// A whole body held at the bottom of a squat, forever.
///
/// Scorable — every joint a rule needs is present and plausible — but the
/// counter never sees the lifter at the top, so it never arms. That pair is
/// hard to reach by accident and is exactly the state the operator's first two
/// screenshots were in: a perfectly usable view whose rep count cannot move.
List<PoseFrame> _neverStandsUp() =>
    [for (var i = 0; i < 30; i++) squatFrame(i * 100, 0.71)];

/// Hips and knees only: the gate scores it, the avatar cannot build a spine
/// from it. Straight from `avatar_mode_test.dart`, where it pins the same
/// asymmetry from the avatar's side.
List<PoseFrame> _noShoulders() => [
      for (var i = 0; i < 30; i++)
        PoseFrame(timestampMs: i * 100, landmarks: {
          LandmarkType.leftHip: const PoseLandmark(
              type: LandmarkType.leftHip, x: 0.45, y: 0.58, likelihood: 0.95),
          LandmarkType.rightHip: const PoseLandmark(
              type: LandmarkType.rightHip, x: 0.55, y: 0.58, likelihood: 0.95),
          LandmarkType.leftKnee: const PoseLandmark(
              type: LandmarkType.leftKnee, x: 0.45, y: 0.74, likelihood: 0.95),
          LandmarkType.rightKnee: const PoseLandmark(
              type: LandmarkType.rightKnee, x: 0.55, y: 0.74, likelihood: 0.95),
        }),
    ];

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('the operator\'s frame: a body the avatar cannot place says so, '
      'and nothing else does', (t) async {
    _phoneSized(t);
    final c = _container(_noShoulders());
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(avatarModeProvider.notifier).state = true;
    await _settle(t);

    expect(c.read(latestPoseFrameProvider), isNotNull,
        reason: 'positive control: a pose really did arrive, so an empty '
            'status list below would mean silence, not "no input"');
    expect(c.read(avatarCannotPlaceBodyProvider), isTrue,
        reason: 'positive control: this is the state under test');

    expect(_statuses(t), ['form_check.avatar_no_torso']);
  });

  testWidgets('a usable view whose counter has not armed says one thing',
      (t) async {
    _phoneSized(t);
    final c = _container(_neverStandsUp());
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(repSessionControllerProvider).isArmed, isFalse,
        reason: 'positive control: the counter really is unarmed');

    // Before this gate the same state drew "stand tall to start counting" in
    // the badge AND "Ready. Start when you are." in the band directly below it.
    expect(_statuses(t), ['form_check.waiting_for_top']);
  });

  testWidgets('a blocked view silences the verdict on the last rep', (t) async {
    _phoneSized(t);
    // A real rep, then the body leaves and only a face is left. The verdict on
    // that rep stays true and stops being the thing worth reading.
    final c = _container([
      ...oneSquat(0),
      for (var i = 0; i < 20; i++) faceSelfie(10000 + i * 100),
    ]);
    await t.pumpWidget(_page(c));
    await _settle(t);

    final session = c.read(repSessionControllerProvider);
    expect(session.repCount, greaterThan(0),
        reason: 'positive control: a rep was counted, so there IS a verdict '
            'available to be wrongly shown');
    expect(coachStatusHasRepVerdict(session), isTrue,
        reason: 'positive control: the cue card has something to say');
    expect(c.read(poseGateVerdictProvider).isScorable, isFalse,
        reason: 'positive control: the view really is blocked');

    expect(_statuses(t), ['form_check.gate_hint']);
  });

  // The property, over every corner of the signal space this file can reach:
  // a body the avatar cannot use, a scorable body that never arms, a full rep,
  // no body at all, and a rep followed by the body leaving.
  //
  // One `testWidgets` per case, generated. The first version of this was a
  // `for` loop INSIDE a single test, re-pumping the page ten times against ten
  // fresh containers — and it was a decoy. Instrumenting it showed
  // `frame=false, reps=0, verdict=ok` on all ten iterations: after the first
  // `pumpWidget`, no pose ever reached the tree again, so the loop asserted
  // "at most one message" over ten copies of an idle screen. It passed with
  // the fix reverted, which is the definition of a test that proves nothing.
  // The positive control below is what makes that failure mode visible instead
  // of silent.
  for (final entry in <String, List<PoseFrame> Function()>{
    'no shoulders': _noShoulders,
    'never stands up': _neverStandsUp,
    'one full squat': () => oneSquat(0),
    'face only': () => [for (var i = 0; i < 20; i++) faceSelfie(i * 100)],
    'a rep, then gone': () => [
          ...oneSquat(0),
          for (var i = 0; i < 20; i++) faceSelfie(10000 + i * 100),
        ],
  }.entries) {
    for (final avatar in [false, true]) {
      testWidgets('at most one voice: ${entry.key}, avatar=$avatar', (t) async {
        _phoneSized(t);
        // The skeleton toggle is on for every case purely so
        // `latestPoseFrameProvider` is published whether or not the avatar is
        // — that provider is the control below. It draws no status of its own,
        // so it cannot affect what is being measured.
        final c = _container(entry.value(), skeleton: true);
        c.read(avatarModeProvider.notifier).state = avatar;
        await t.pumpWidget(_page(c));
        await _settle(t);

        expect(c.read(latestPoseFrameProvider), isNotNull,
            reason: 'positive control: poses must actually be reaching the '
                'tree, or this asserts one voice over an idle screen');

        expect(_statuses(t).length, lessThanOrEqualTo(1),
            reason: '${entry.key}, avatar=$avatar showed '
                '${_statuses(t)} — the screen has more than one voice again');

        // The same property, asserted on the two SURFACES rather than on the
        // messages they may contain. `_statusKeys` is a list maintained by
        // hand, and a message added without a line in it would slip past the
        // check above while being perfectly visible on screen. This cannot:
        // it counts the band and the card themselves.
        final surfaces = [
          const Key('coach.readinessBand'),
          const Key('form_check.cue_card'),
        ].where((k) => find.byKey(k).evaluate().isNotEmpty).toList();
        expect(surfaces.length, lessThanOrEqualTo(1),
            reason: '${entry.key}, avatar=$avatar rendered $surfaces — the '
                'instruction band and the verdict card are both on screen');
      });
    }
  }

  testWidgets('a sensor fault outranks the avatar, and is never dressed up as '
      'a framing problem', (t) async {
    // Codex, reviewing the first pass at this gate. `buildPoseAvatar` drops any
    // landmark more than half a unit outside the coordinate contract, so a
    // frame whose coordinates are in the wrong space entirely ALSO yields no
    // torso. With the avatar rung on top, the screen answered a sensor bug with
    // "step back so your shoulders and hips are both in view" — the user steps
    // back forever, having done nothing wrong, which is the precise failure
    // `PoseGateVerdict.unitMismatch` was separated out to prevent.
    _phoneSized(t);
    final c = _container([
      for (var i = 0; i < 20; i++)
        PoseFrame(timestampMs: i * 100, aspectRatio: 0.5625, landmarks: {
          // Pixels, unconverted: the shape of the bug this verdict names.
          LandmarkType.leftShoulder: const PoseLandmark(
              type: LandmarkType.leftShoulder,
              x: 480,
              y: 620,
              likelihood: 0.95),
          LandmarkType.leftHip: const PoseLandmark(
              type: LandmarkType.leftHip, x: 470, y: 980, likelihood: 0.95),
          LandmarkType.leftKnee: const PoseLandmark(
              type: LandmarkType.leftKnee, x: 468, y: 1320, likelihood: 0.95),
          LandmarkType.leftAnkle: const PoseLandmark(
              type: LandmarkType.leftAnkle, x: 466, y: 1660, likelihood: 0.95),
        }),
    ], skeleton: true);
    c.read(avatarModeProvider.notifier).state = true;
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(poseGateVerdictProvider), PoseGateVerdict.unitMismatch,
        reason: 'positive control: this really is the sensor-fault verdict');
    expect(c.read(avatarCannotPlaceBodyProvider), isTrue,
        reason: 'positive control: the avatar really cannot place a body '
            'either, so the two rungs really are competing');

    expect(_statuses(t), ['form_check.gate_hint']);
    expect(find.textContaining('cannot read'), findsOneWidget);
    expect(find.textContaining('step back'), findsNothing);
    expect(find.textContaining('shoulders and hips'), findsNothing);
  });

  testWidgets('a blocked view also silences the rep phase line', (t) async {
    // The fourth surface, missed by the first pass at this gate and found by
    // Codex: once a rep has completed the counter is armed, and the badge drew
    // "reps — ready" under the number while the band said the body was out of
    // frame.
    _phoneSized(t);
    final c = _container([
      ...oneSquat(0),
      for (var i = 0; i < 20; i++) faceSelfie(10000 + i * 100),
    ]);
    await t.pumpWidget(_page(c));
    await _settle(t);

    expect(c.read(repSessionControllerProvider).isArmed, isTrue,
        reason: 'positive control: armed, so the phase line would otherwise '
            'render');
    expect(c.read(poseGateVerdictProvider).isScorable, isFalse,
        reason: 'positive control: the view really is blocked');

    expect(find.byKey(const Key('form_check.phase')), findsNothing);
    expect(find.byKey(const Key('form_check.rep_count')), findsOneWidget,
        reason: 'the NUMBER stays — it is the count that was earned, not an '
            'instruction competing with the band');
  });

  testWidgets('a paused set is never told to stand tall', (t) async {
    // `countingIsLiveIn(paused)` stops frames reaching the counter, so standing
    // tall cannot arm it however exactly the user follows the instruction.
    _phoneSized(t);
    final c = _container(_neverStandsUp(), skeleton: true);
    await t.pumpWidget(_page(c));
    await _settle(t);
    expect(_statuses(t), ['form_check.waiting_for_top'],
        reason: 'positive control: unpaused, the instruction IS shown');

    c.read(coachPhaseControllerProvider.notifier).start();
    c.read(coachPhaseControllerProvider.notifier).pause();
    await _settle(t);

    expect(find.byKey(const Key('form_check.waiting_for_top')), findsNothing);
  });

  testWidgets('avatar mode now judges a rep against the target, at parity '
      'with camera mode', (t) async {
    // Was: "avatar mode does not fail a rep against a target it never
    // showed" — Codex's original concern, and it was right at the time: the
    // target outline used to be hidden in avatar mode because it was fitted
    // to the panel while the avatar was placed where the body is, two
    // unrelated scales in one box. Grading continued regardless, so a rep
    // could come back faulted for missing a shape the user could not see.
    //
    // That premise no longer holds. `FORMCOACH_COORDINATE_UNIFICATION_
    // 2026-08-31` (see `core/DECISION_LOG.md`) made the silhouette and the
    // avatar share one projection (`projectLandmark`), so the target IS shown,
    // at the avatar's own scale, in avatar mode now — the exact condition
    // Codex's fix required. `_onFrame` (`form_check_providers.dart`) stopped
    // withholding the target for avatar mode the same day, so scoring now
    // runs identically in both modes.
    _phoneSized(t);
    // Same fixture the sibling non-avatar test scores against the bottom
    // target with: a frontal, symmetric synthetic squat whose shape does not
    // match the authored SIDE-VIEW bottom target closely enough to pass —
    // known and asserted directly in `one_cue_per_rep_test.dart`'s "shipped
    // default configuration" test, which is the acceptance test for this
    // exact fixture/target pair.
    final frames = oneSquat(0);
    final c = _container(frames, skeleton: true);
    c.read(avatarModeProvider.notifier).state = true;
    await t.pumpWidget(_page(c));
    await _settle(t);

    final session = c.read(repSessionControllerProvider);
    expect(session.repCount, greaterThan(0),
        reason: 'positive control: reps are still counted in avatar mode');
    expect(session.lastRepMissedTarget, isNotNull,
        reason: 'the target is now shown at the avatar\'s own scale, so a '
            'completed rep IS judged against it — parity with camera mode');
    expect(c.read(poseMatchProvider), isNotNull,
        reason: 'a match score is now computed in avatar mode too, driving '
            'both the rep verdict and the avatar\'s green glow '
            '(avatarVerdictSeverity)');
    // Was `findsNothing`, with the reason "its design-mandated home is the
    // circular «Техника» gauge, not yet built". G3 built it, so the readout
    // has somewhere to live and no longer has to be withheld: the percentage
    // that already drives the rep verdict and the avatar's glow is now also
    // the number on the gauge, in both modes.
    expect(find.byKey(const Key('form_check.match')), findsOneWidget,
        reason: 'the technique gauge exists as of G3 and reports the same '
            'score avatar mode is already grading against');
  });

  testWidgets('a match percentage does not outlive the frames it was measured '
      'on', (t) async {
    // Codex round 2. `poseMatchProvider` was written on every scored frame and
    // cleared exactly once, when the page mounts — so the last good percentage
    // survived everything that came after it. Walk into a view the gate will
    // not score and the screen showed a frozen "N%" beside the band's
    // explanation of why nothing can be scored: two voices again, and the
    // stale one is indistinguishable from a live one.
    _phoneSized(t);
    final squat = oneSquat(0);
    final c = _container([
      ...squat,
      // A face filling the frame: no hips, no knees, nothing to score.
      for (var i = 0; i < 30; i++) faceSelfie(100000 + i * 100),
    ]);
    // Camera mode: the readout this test is about only exists against a target,
    // and avatar mode has none by Gate A's own decision. Stated here rather
    // than left to the default, which flipped to avatar on 2026-08-15.
    c.read(avatarModeProvider.notifier).state = false;
    await t.pumpWidget(_page(c));
    // Mid-set, which is both where the readout is mounted and the realistic
    // way to reach this: the view degrades under someone who is already
    // squatting, rather than before they start.
    c.read(coachPhaseControllerProvider.notifier).start();

    // Advance only as far as the first scored frame, so the "before" state is
    // observed rather than assumed.
    for (var i = 0; i < squat.length && c.read(poseMatchProvider) == null; i++) {
      await t.pump(const Duration(milliseconds: 33));
    }
    expect(c.read(poseMatchProvider), isNotNull,
        reason: 'positive control: a percentage really was measured, so its '
            'disappearance below is the clear and not an empty provider');
    // The loop exits on the state change, one frame before the tree carrying
    // it is built.
    await t.pump();
    expect(find.byKey(const Key('form_check.match')), findsOneWidget,
        reason: 'positive control: and it really was on screen');

    await _settle(t);

    expect(c.read(poseGateVerdictProvider).isScorable, isFalse,
        reason: 'positive control: the view really did become unscorable');
    expect(c.read(poseMatchProvider), isNull,
        reason: 'nothing is being scored, so there is no percentage to report');
    expect(find.byKey(const Key('form_check.match')), findsNothing);
    expect(_statuses(t).length, lessThanOrEqualTo(1),
        reason: 'and the band is left as the only voice');
  });

  testWidgets('a view that flickers never puts a percentage beside an '
      'instruction', (t) async {
    // The question round 3 of the Codex loop was meant to answer and could not
    // — the account hit its quota — so it is answered here instead, by
    // measurement rather than by review.
    //
    // `evaluateGated` has no hysteresis: the verdict is computed per frame, so
    // a borderline view oscillates scorable/unscorable on adjacent frames. The
    // clear added for round 2's finding therefore fires repeatedly. The thing
    // that must hold through all of it is not "the number is stable" — it is
    // that the number and the instruction are never on screen together, which
    // is the defect, whereas a percentage that comes and goes with the view it
    // describes is the honest behaviour.
    _phoneSized(t);
    final c = _container([
      for (var i = 0; i < 20; i++)
        if (i.isEven) squatFrame(i * 100, 0.71) else faceSelfie(i * 100),
    ]);
    // Camera mode, for the same reason as the test above: this asserts that a
    // percentage and an instruction never share the screen, which needs a view
    // that can produce a percentage at all.
    c.read(avatarModeProvider.notifier).state = false;
    await t.pumpWidget(_page(c));
    c.read(coachPhaseControllerProvider.notifier).start();

    var sawHint = false;
    var sawMatch = false;
    for (var i = 0; i < 25; i++) {
      await t.pump(const Duration(milliseconds: 33));
      final hint = find.byKey(const Key('form_check.gate_hint')).evaluate();
      final match = find.byKey(const Key('form_check.match')).evaluate();
      sawHint |= hint.isNotEmpty;
      sawMatch |= match.isNotEmpty;
      expect(hint.isNotEmpty && match.isNotEmpty, isFalse,
          reason: 'frame $i put a match percentage beside a gate instruction');
      expect(_statuses(t).length, lessThanOrEqualTo(1),
          reason: 'frame $i had ${_statuses(t)}');
    }

    // Both positive controls, because the assertion above is vacuously true on
    // a screen that never shows either one.
    expect(sawHint, isTrue,
        reason: 'positive control: the view really did go unscorable and get '
            'explained at least once');
    expect(sawMatch, isTrue,
        reason: 'positive control: and really did score at least once, so the '
            'two had the chance to collide');
  });

  testWidgets(
      'the avatar scene carries the still target and the tracked body, with '
      'no demo loop and no second skeleton', (t) async {
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    // Both diagnostics deliberately switched ON, which is the configuration
    // the operator's fourth screenshot was taken in.
    c.read(showSkeletonProvider.notifier).state = true;
    c.read(avatarModeProvider.notifier).state = true;
    await _settle(t);

    expect(_avatar, findsOneWidget, reason: 'positive control: a body IS drawn');
    expect(_skeleton, findsNothing,
        reason: 'the avatar already draws lit bones; a second, thinner set of '
            'the same joints on top reads as a tracking failure');
    // G17 (2026-09-04): ONE figure on the panel. The still white target
    // outline that used to sit next to the avatar here was removed on the
    // operator's instruction after three rounds of repair still left it
    // reading as a shape rather than a person; the demonstration that
    // replaces it is shown only while there is nobody to draw, and fades out
    // behind the avatar the moment there is (`live_demo_test.dart`). With a
    // body on screen the demonstration's host is still mounted — at opacity
    // zero, decoder paused — so the structural assertions are: no outline,
    // and the avatar is the figure.
    expect(_silhouette, findsNothing,
        reason: 'the white target outline exists on no screen in no state');
    expect(
        t.widget<AnimatedOpacity>(find.byKey(const Key('form_check.live_demo')))
            .opacity,
        0,
        reason: 'the demonstration has given way to the user\'s own figure');
  });

  testWidgets('turning the avatar off brings the camera overlays back',
      (t) async {
    // The other direction, so the suppression above cannot be implemented as
    // "never draw these again" and still pass.
    _phoneSized(t);
    final c = _container(oneSquat(0));
    await t.pumpWidget(_page(c));
    await t.pump();
    c.read(showSkeletonProvider.notifier).state = true;
    c.read(avatarModeProvider.notifier).state = true;
    await _settle(t);
    expect(_skeleton, findsNothing, reason: 'positive control');

    c.read(avatarModeProvider.notifier).state = false;
    await _settle(t);

    expect(_skeleton, findsOneWidget);
    expect(_avatar, findsNothing);
  });
}
