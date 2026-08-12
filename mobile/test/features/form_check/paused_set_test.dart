import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/coach_phases.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'unscorable_frame_test.dart' show oneSquat;

/// P2: pausing stops the COUNT, and nothing else.
///
/// The camera keeps running through a pause by the operator's decision, so the
/// interesting assertion is not "the button changed colour" — it is that good,
/// scorable frames went on arriving and the counter did not move. A test that
/// only stopped the frames would pass against a pause implemented by tearing
/// the camera down, which is the implementation this one is here to rule out.
///
/// The positive control is not optional, for the reason `unscorable_frame_test`
/// gives: a "0 reps" that happens because nothing ran proves nothing.

Future<(RepSessionState, bool scorable, MockVoiceCoach)> runSquat({
  void Function(CoachPhaseController)? phase,
}) async {
  final coach = MockVoiceCoach();
  final svc = MockPoseDetectorService(oneSquat(0));
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWith((_) => svc),
    voiceCoachProvider.overrideWith((_) => coach),
  ]);
  addTearDown(container.dispose);

  // Before the frames flow, so the phase is already settled when the first one
  // lands. Pausing halfway through a synchronous replay would leave the result
  // depending on how fast the mock drains.
  phase?.call(container.read(coachPhaseControllerProvider.notifier));

  container.read(repSessionControllerProvider);
  container.read(formFeedbackControllerProvider);
  await svc.start();
  await Future<void>.delayed(const Duration(milliseconds: 20));

  return (
    container.read(repSessionControllerProvider),
    container.read(poseGateVerdictProvider).isScorable,
    coach,
  );
}

void main() {
  test('POSITIVE CONTROL: a running set counts the squat', () async {
    final (session, scorable, _) = await runSquat();
    expect(scorable, isTrue);
    expect(session.repCount, greaterThan(0),
        reason: 'without this every assertion below passes vacuously');
  });

  test('a paused set counts nothing, however good the frames are', () async {
    final (session, scorable, coach) = await runSquat(
      phase: (c) => c
        ..start()
        ..pause(),
    );

    expect(scorable, isTrue,
        reason: 'the frames DID arrive and were usable -- the camera keeps '
            'running through a pause, so this is what makes the zero below '
            'mean something');
    expect(session.repCount, 0);
    expect(session.reps, isEmpty);
    expect(coach.spoken, isEmpty,
        reason: 'a paused coach that still talks is worse than a silent one');
  });

  test('resuming counts again', () async {
    // The other half. A guard that never lets go would pass the test above and
    // leave the feature dead after the first pause.
    final resumed = await runSquat(
      phase: (c) => c
        ..start()
        ..pause()
        ..resume(),
    );
    expect(resumed.$1.repCount, greaterThan(0));
  });

  test('finishing also stops the count', () async {
    // `summary` is not `paused`, so this would have slipped past a guard
    // written as `phase == active` inverted. The set is over; frames arriving
    // after the user called it done must not append to it.
    final finished = await runSquat(
      phase: (c) => c
        ..start()
        ..pause()
        ..finish(),
    );
    expect(finished.$1.repCount, 0);
  });

  group('the phase machine refuses impossible moves', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('pause does nothing when no set is running', () {
      final c = container.read(coachPhaseControllerProvider.notifier);
      c.pause();
      expect(container.read(coachPhaseControllerProvider).phase,
          CoachPhase.launch,
          reason: 'nothing to pause from the intro card');
    });

    test('resume does nothing when not paused', () {
      final c = container.read(coachPhaseControllerProvider.notifier)..start();
      c.resume();
      expect(container.read(coachPhaseControllerProvider).phase,
          CoachPhase.active);
    });
  });
}
