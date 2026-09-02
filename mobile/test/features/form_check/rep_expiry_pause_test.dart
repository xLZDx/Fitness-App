import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'unscorable_frame_test.dart' show squatFrame;

/// The 20-second ceiling must run on COUNTING time, not on wall-clock time.
///
/// `rep_abandoned_test.dart` pins the ceiling itself, entirely inside
/// `RepCounter` — a unit that has no idea a set can be paused. This file pins
/// the wiring one level up, in `RepSessionController._onFrame`, where the
/// ceiling check and the "counting is paused" gate both live and have to agree
/// with each other.
///
/// The first version of that wiring did not: the expiry check ran before the
/// pause gate, using every frame's timestamp regardless of phase. The camera
/// keeps delivering frames through a pause by design (`paused_set_test.dart`
/// pins that), so a lifter who opens a repetition and then pauses — to answer
/// the door, say — would have the pause itself silently spent as abandoned-
/// repetition time and the rep discarded out from under them the moment they
/// resumed. GPT-PM, round 2, reviewing the first version of this gate.

/// A service the test pushes frames into directly and on its own clock,
/// rather than one that replays a fixed list at a fixed real-time pace — the
/// whole point here is a real-time gap of milliseconds standing in for a
/// frame timestamp gap of tens of seconds, which `MockPoseDetectorService`'s
/// self-paced replay cannot express.
class _ManualService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _frames.close();

  Future<void> push(PoseFrame f) async {
    _frames.add(f);
    // Flushes the broadcast controller's async delivery before the test reads
    // state — the same reason every existing frame-driven test in this suite
    // awaits after a push rather than reading synchronously.
    await Future<void>.delayed(Duration.zero);
  }
}

/// Mid-descent: past `topExit` (opens a rep) and short of `bottomEnter`
/// (never reaches depth), held at one position. What a paused, stalled, or
/// simply slow lifter all look like to the counter.
PoseFrame _midDescent(int ts) => squatFrame(ts, 0.63);

void main() {
  test('a repetition left open across a pause is not abandoned by it',
      () async {
    final coach = MockVoiceCoach();
    final svc = _ManualService();
    final container = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWith((_) => svc),
      voiceCoachProvider.overrideWith((_) => coach),
    ]);
    addTearDown(container.dispose);

    final phase = container.read(coachPhaseControllerProvider.notifier);
    container.read(repSessionControllerProvider);
    container.read(formFeedbackControllerProvider);
    phase.start();

    await svc.push(squatFrame(0, 0.42)); // standing: arms the counter
    await svc.push(_midDescent(50)); // opens the repetition

    expect(container.read(repSessionControllerProvider).phase,
        isNot(RepPhase.top),
        reason: 'positive control: the rep really is open before the pause');

    phase.pause();

    // 25 seconds of camera-still-running, paused-set time — comfortably past
    // the 20-second ceiling, delivered as the SAME still body a paused camera
    // would actually show. If the ceiling ran on wall-clock time this frame
    // alone would abandon the rep.
    await svc.push(_midDescent(25050));

    final whilePaused = container.read(repSessionControllerProvider);
    expect(whilePaused.repCount, 0);
    expect(whilePaused.lastReject, isNull,
        reason: 'the pause must not silently become abandoned-repetition '
            'time');
    expect(whilePaused.phase, isNot(RepPhase.top),
        reason: 'the repetition is still open, waiting for the set to '
            'resume — not discarded and not completed');
    expect(coach.spoken, isEmpty,
        reason: 'a paused coach that announces an abandoned rep is worse '
            'than a silent one');

    phase.resume();

    // Finish the repetition normally. Timestamps continue from where the
    // pause left off, as they would on a real device — the counter's own
    // clock never stopped, only the set did.
    //
    // Three frames, not two: `RepCounter.update` advances at most one phase
    // per frame (`descending` -> `bottom` -> `ascending` -> `top` are four
    // separate switch cases, never chained within a single call), so
    // reaching depth and standing back up needs depth, then a still-ascending
    // frame, then a frame the counter reads FROM `ascending`. And the gap
    // from resume to completion has to clear `minRepDurationMs` (600ms
    // default) same as any other rep — `extendDeadline` moves the ceiling,
    // not the floor.
    await svc.push(squatFrame(25100, 0.71)); // depth reached
    await svc.push(squatFrame(25400, 0.42)); // ascending: back past bottomExit
    await svc.push(squatFrame(25800, 0.42)); // read from ascending: completes

    final after = container.read(repSessionControllerProvider);
    expect(after.repCount, 1,
        reason: 'the SAME repetition that was open before the pause '
            'completed after it resumed — the pause did not cost it');
    expect(after.lastReject, isNull,
        reason: 'and it completed clean, not as a late abandonment or a '
            'too-fast rejection manufactured by the pause math');
  });

  test(
      'and neither is one across a pause where NO frame arrives at all',
      () async {
    // The case GPT-PM, round 3, found the first fix still missed: the test
    // above proves a pause survives when a frame happens to arrive while
    // paused, but the pause boundary that first version recorded was itself
    // only set by observing such a frame. A paused camera that produces
    // nothing at all until resume — a real pattern, and this repo's own
    // positive control for "paused set counts nothing" below never claims
    // otherwise — left that version with no boundary to extend from, and the
    // very first frame after resume abandoned the rep exactly as before the
    // fix. The boundary is now set from the phase transition itself
    // (`_onCoachPhaseChanged`), so this proves the fix without leaning on the
    // one frame that used to carry it.
    final coach = MockVoiceCoach();
    final svc = _ManualService();
    final container = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWith((_) => svc),
      voiceCoachProvider.overrideWith((_) => coach),
    ]);
    addTearDown(container.dispose);

    final phase = container.read(coachPhaseControllerProvider.notifier);
    container.read(repSessionControllerProvider);
    container.read(formFeedbackControllerProvider);
    phase.start();

    await svc.push(squatFrame(0, 0.42)); // standing: arms the counter
    await svc.push(_midDescent(50)); // opens the repetition

    expect(container.read(repSessionControllerProvider).phase,
        isNot(RepPhase.top),
        reason: 'positive control: the rep really is open before the pause');

    phase.pause();
    // No frame pushed at all until resume — the whole point of this test.

    phase.resume();

    // First frame back is already 25 seconds past the ceiling on the frame
    // clock. If the pause boundary were not recorded, this alone would
    // abandon the rep the instant counting resumed.
    await svc.push(squatFrame(25100, 0.71)); // depth reached
    await svc.push(squatFrame(25400, 0.42)); // ascending: back past bottomExit
    await svc.push(squatFrame(25800, 0.42)); // read from ascending: completes

    final after = container.read(repSessionControllerProvider);
    expect(after.repCount, 1,
        reason: 'the SAME repetition that was open before the pause '
            'completed after it resumed — a silent pause cost it nothing');
    expect(after.lastReject, isNull);
  });

  test(
      'and a genuinely abandoned repetition is still caught once counting '
      'resumes', () async {
    // The negative control for the test above, and the reason the fix is a
    // gate rather than a blanket suppression: pausing must not launder an
    // abandonment that happened DURING counting into one that never gets
    // caught. Time spent paused does not count against the ceiling; time
    // spent counting still does.
    final coach = MockVoiceCoach();
    final svc = _ManualService();
    final container = ProviderContainer(overrides: [
      poseDetectorServiceProvider.overrideWith((_) => svc),
      voiceCoachProvider.overrideWith((_) => coach),
    ]);
    addTearDown(container.dispose);

    final phase = container.read(coachPhaseControllerProvider.notifier);
    container.read(repSessionControllerProvider);
    container.read(formFeedbackControllerProvider);
    phase.start();

    await svc.push(squatFrame(0, 0.42));
    await svc.push(_midDescent(50));
    // 25 seconds, still counting — never paused.
    await svc.push(_midDescent(25050));

    final result = container.read(repSessionControllerProvider);
    expect(result.repCount, 0);
    expect(result.lastReject, RepRejectReason.abandoned);
  });
}
