import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/form_classifier.dart';
import '../data/pose_detector_service.dart';
import '../data/pose_gate.dart';
import '../data/pose_landmark.dart';
import '../data/pose_silhouette.dart';
import '../data/pose_target.dart';
import '../data/pose_unit_probe.dart';
import '../data/rep_counter.dart';
import '../data/voice_coach.dart';

/// What the user says they are doing. Rules are chosen from this.
enum FormExercise { squat, pushup, deadlift }

/// Catalog pattern id -> the movement this coach knows, or null.
///
/// The catalog tags 570 exercises across eight patterns
/// (`scripts/catalog/tag_pose_targets.py`). This map is the far smaller set
/// the coach has actually been taught, and the gap between the two numbers is
/// the honest state of the feature, not an oversight.
const Map<String, FormExercise> kPosePatternToExercise = {
  'squat': FormExercise.squat,
};

/// Whether the Form Coach can judge [poseTargetId] well enough to offer it.
///
/// Stricter than "has an entry above", and the difference is the point.
/// `pushup` has both targets authored and still fails this, because the rep
/// counter's only signal is hip-versus-knee height — which, as
/// `pushupBottomTarget`'s own comment records, does not track a push-up at
/// all. Offering a coach that draws a silhouette and then counts nothing
/// teaches the user the feature is broken, and that lesson is expensive to
/// undo.
///
/// `deadlift` fails for a plainer reason: `poseTargetProvider` returns null
/// for it, so there is no shape to stand in.
///
/// Adding a pattern here is the last step of authoring it, after the targets
/// and the rep signal exist — never the first.
bool formCoachSupports(String? poseTargetId) {
  if (poseTargetId == null) return false;
  final e = kPosePatternToExercise[poseTargetId];
  if (e == null) return false;
  return poseTargetsFor(e) != null && countsRepsFor(e);
}

/// The two ends of [e]'s movement, or null when nothing is authored.
///
/// A plain function rather than only a provider, so the support gate above can
/// be decided -- and tested -- without a ProviderContainer. `poseDemoProvider`
/// reads it, which keeps one answer instead of two.
(PoseTarget, PoseTarget)? poseTargetsFor(FormExercise e) => switch (e) {
      FormExercise.squat => (squatTopTarget, squatBottomTarget),
      FormExercise.pushup => (pushupTopTarget, pushupBottomTarget),
      FormExercise.deadlift => null,
    };

/// Whether a rep of [e] can actually be counted.
///
/// Only the squat, and it is not an omission. `RepCounter`'s default extractor
/// is `squatDepthSignal` -- mean hip y minus mean knee y -- and there is no
/// second one. For a push-up that quantity barely moves, which
/// `pushupBottomTarget`'s own comment states outright; for a deadlift it moves
/// but means something else.
///
/// Kept separate from [poseTargetsFor] because the push-up is exactly the case
/// where the two disagree: shapes authored, reps uncountable.
bool countsRepsFor(FormExercise e) => e == FormExercise.squat;

/// How broad to draw the outline, from whatever the intake collected.
///
/// Operator: *"бери рост вес из анкеты чтобы понять рост человека, так как
/// силует для девочки 150 см будет другой нежели мужика 2метра ростом"*. The
/// request is answered, with one correction stated where it is made rather
/// than quietly: height does not scale the outline. The figure is fitted to
/// the camera panel, and how large a body appears in that panel is set by how
/// far it stands from the phone. What does differ between those two people on
/// screen is breadth — shoulder-to-hip ratio and overall width — so that is
/// what this reads, with height feeding the BMI rather than the size.
///
/// Missing answers are not guessed at. `nonBinary` and `preferNotToSay` take
/// the neutral build, which is the reason those answers exist.
final silhouetteBuildProvider = Provider<BodyBuild>((ref) {
  final personal = ref.watch(currentProfileProvider).valueOrNull?.personal;
  if (personal == null) return BodyBuild.unknown;
  return BodyBuild.forBody(
    sex: switch (personal.gender) {
      Gender.male => SilhouetteSex.male,
      Gender.female => SilhouetteSex.female,
      _ => SilhouetteSex.unspecified,
    },
    heightCm: personal.heightCm,
    weightKg: personal.weightCurrentKg,
  );
});

/// Which intake answers the silhouette would use and does not have.
///
/// Drives the prompt on the coach page. Empty means there is nothing to ask
/// for — including when the user has answered "prefer not to say", which IS an
/// answer and must not be asked again.
final missingBodyAnswersProvider = Provider<Set<BodyAnswer>>((ref) {
  final personal = ref.watch(currentProfileProvider).valueOrNull?.personal;
  return {
    if (personal?.gender == null) BodyAnswer.gender,
    if (personal?.heightCm == null) BodyAnswer.height,
    if (personal?.weightCurrentKg == null) BodyAnswer.weight,
  };
});

enum BodyAnswer { gender, height, weight }

/// The movement being coached. Squat by default: it is what the shipped rep
/// counter's signal (hip-versus-knee height) actually tracks.
final selectedExerciseProvider =
    StateProvider<FormExercise>((_) => FormExercise.squat);

/// The shape the user is aiming at, for the selected movement.
///
/// Null when the movement has no authored target yet — in which case the
/// silhouette is not drawn and no rep is failed for missing it, because failing
/// someone against a target that does not exist is worse than not judging.
final poseTargetProvider = Provider<PoseTarget?>((ref) {
  return switch (ref.watch(selectedExerciseProvider)) {
    FormExercise.squat => squatBottomTarget,
    FormExercise.pushup => pushupTopTarget,
    FormExercise.deadlift => null,
  };
});

/// The two ends of the movement to demonstrate, or null when there is nothing
/// authored to demonstrate.
///
/// Operator, after the first silhouette build: *"лучше добавить анимацию как
/// правильно надо делать"*. A single outline says where to arrive; it does not
/// say how — and for a squat the how is the whole difference between the shape
/// that scores and the shape that does not.
final poseDemoProvider = Provider<(PoseTarget, PoseTarget)?>(
    (ref) => poseTargetsFor(ref.watch(selectedExerciseProvider)));

/// The most recent frame the detector produced, or null before the first one.
///
/// Exists so the screen can draw what the app actually sees. Everything else on
/// this page is a CONCLUSION about the body — a count, a verdict, a match
/// percentage — and when a conclusion is wrong there is no way to tell whether
/// the rule misjudged a good rep or the detector never found the body at all.
/// Those two want opposite responses from the user.
final latestPoseFrameProvider = StateProvider<PoseFrame?>((_) => null);

/// Whether to draw the detected skeleton over the preview.
///
/// Off by default and behind a toggle, deliberately. The projection from camera
/// space to preview space depends on how the platform crops and whether it has
/// already mirrored the front camera, and neither is settled until it is seen on
/// a real device — the same way the coordinate unit was settled. A skeleton
/// drawn a few percent off reads as "the app cannot see me", which is exactly
/// the wrong conclusion and worse than drawing nothing.
final showSkeletonProvider = StateProvider<bool>((_) => false);

/// How well the CURRENT frame matches the target, or null when it cannot be
/// judged. Drives the live outline colour, so the user can see themselves
/// approaching the shape instead of finding out afterwards.
final poseMatchProvider = StateProvider<double?>((_) => null);

/// Classifiers for the selected movement, and only those.
///
/// Every rule used to run on every frame, because there was no picker. So a
/// squatting user was also judged by the push-up rule — which measures the
/// shoulder-hip-ankle angle and calls it "body line". On someone standing up
/// out of a squat that angle sweeps through the whole range, so the rule fired
/// constantly. The operator's set summary read "Ошибки: Глубина приседа, Линия
/// корпуса" for eight consecutive squats; half of that was a push-up rule
/// grading a squat, and it was never going to be fixed by tuning it.
final activeClassifiersProvider = Provider<List<FormClassifier>>((ref) {
  return switch (ref.watch(selectedExerciseProvider)) {
    FormExercise.squat => [SquatDepthClassifier()],
    FormExercise.pushup => [PushupAlignmentClassifier()],
    FormExercise.deadlift => [DeadliftHipHingeClassifier()],
  };
});

final poseDetectorServiceProvider = Provider<PoseDetectorService>((_) {
  // Default mock yields nothing — production binds the MlKit-backed
  // service from main.dart.
  return MockPoseDetectorService(const []);
});

/// Last fatal detector failure, or null while healthy.
///
/// The pose stream reports native failures as stream errors. Without a sink
/// for them they land on the Zone's uncaught-error handler and the user just
/// sees a live camera that never counts a rep — which is precisely how the
/// NV21 format bug stayed invisible until a device test.
final poseErrorProvider = StateProvider<String?>((_) => null);

/// Records a fatal detector error so the page can say what went wrong.
void _recordPoseError(Ref ref, Object e) {
  ref.read(poseErrorProvider.notifier).state =
      e is StateError ? e.message : e.toString();
}

/// Retires a stale error once frames are actually flowing again.
///
/// Nothing cleared this provider. It is app-scoped, not page-scoped, so a
/// single transient native failure pinned "camera unavailable" onto the screen
/// permanently — surviving leaving the page, coming back, backgrounding the app
/// and resuming. The page reads `_startError ?? poseErrorProvider`, so even a
/// fully successful restart could not get past it: the only exit was reinstall.
///
/// Cleared on a delivered FRAME rather than on `start()` returning, deliberately.
/// Success from `start()` is precisely the weak signal that produced an earlier
/// bug in this same feature: the camera started, the preview painted, and no
/// frame ever arrived. A frame is the only evidence that the whole pipeline
/// works end to end, which is the claim clearing this error makes.
void _retirePoseError(Ref ref) {
  // Read-and-compare rather than write-always: an unconditional write would
  // notify every listener 30 times a second for the entire session.
  if (ref.read(poseErrorProvider) != null) {
    ref.read(poseErrorProvider.notifier).state = null;
  }
}

/// Thresholds for "is this frame worth scoring". A provider so a future
/// per-exercise profile can loosen or tighten them in one place.
final poseGateConfigProvider =
    Provider<PoseGateConfig>((_) => const PoseGateConfig());

/// Why the last frame could not be scored, or [PoseGateVerdict.ok].
///
/// The page reads this to show a specific instruction ("step back", "too
/// dark") instead of an empty cue card. Before the gate existed there was
/// nothing to show, because a frame with invented joints always produced
/// feedback — the user could not distinguish "your form is fine" from "the
/// coach cannot see you".
///
/// A `StateProvider` only notifies on a changed value, so writing this on every
/// frame does not rebuild anything while the verdict holds steady.
final poseGateVerdictProvider =
    StateProvider<PoseGateVerdict>((_) => PoseGateVerdict.ok);

/// What the coordinates actually measured this session.
///
/// Read-only: nothing in the scoring path consults it. It exists because every
/// threshold in the gate, the rep counter and the classifiers was picked against
/// an assumed range, and this is the first thing in the app that reports the
/// real one. See `pose_unit_probe.dart`.
final poseUnitReportProvider =
    StateProvider<PoseUnitReport>((_) => PoseUnitReport.empty);

/// Drives the live overlay: every frame, run the active classifier set
/// and emit the worst feedback. Null when no frame yet / no rule fires.
class FormFeedbackController extends Notifier<FormFeedback?> {
  StreamSubscription<PoseFrame>? _sub;
  final PoseUnitProbe _probe = PoseUnitProbe();

  @override
  FormFeedback? build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    _sub?.cancel();
    _sub = svc.frames().listen(
          _onFrame,
          onError: (Object e) => _recordPoseError(ref, e),
        );
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onFrame(PoseFrame frame) {
    _retirePoseError(ref);
    // Published before the gate, like the probe below and for the same reason:
    // the frames worth LOOKING at are the ones the gate is about to reject.
    // Only while the overlay is on — otherwise this would notify a listener
    // thirty times a second for a picture nobody is drawing.
    if (ref.read(showSkeletonProvider)) {
      ref.read(latestPoseFrameProvider.notifier).state = frame;
    }
    // Before the gate, on purpose: a frame the gate rejects is exactly the
    // frame whose coordinates are most worth knowing about.
    _probe.observe(frame);
    ref.read(poseUnitReportProvider.notifier).state = _probe.report;

    final classifiers = ref.read(activeClassifiersProvider);
    final result = evaluateGated(
      classifiers,
      frame,
      config: ref.read(poseGateConfigProvider),
    );
    ref.read(poseGateVerdictProvider.notifier).state = result.verdict;
    state = result.worst;
  }
}

final formFeedbackControllerProvider =
    NotifierProvider<FormFeedbackController, FormFeedback?>(
        FormFeedbackController.new);

/// Thresholds the rep counter runs on. A provider rather than a constant so
/// a future per-exercise profile (press, curl) can override it in one place.
final repCounterConfigProvider =
    Provider<RepCounterConfig>((_) => const RepCounterConfig());

/// Speech engine. Defaults to the mock so widget tests never open a
/// MethodChannel; `main.dart` binds [TtsVoiceCoach] on device.
final voiceCoachProvider = Provider<VoiceCoach>((ref) {
  final coach = MockVoiceCoach();
  ref.onDispose(() => unawaited(coach.dispose()));
  return coach;
});

/// User-facing mute switch for spoken cues. The coach is the enforcement
/// point; this provider is the single source of truth the UI writes to.
final voiceMutedProvider = StateProvider<bool>((_) => false);

/// Last speech-engine failure, mirrored out of the coach so the UI can see it.
///
/// The page used to read `ref.watch(voiceCoachProvider).lastErrorMessage`.
/// `voiceCoachProvider` is a plain `Provider` yielding one long-lived object and
/// `lastErrorMessage` is a getter over a mutable field, so a failure mutated the
/// field and **notified nothing** — the banner appeared only if some unrelated
/// watched provider happened to change afterwards.
///
/// Which is worst exactly when it matters most: a steady user holding a steady
/// pose produces a steady gate verdict, and both `poseGateVerdictProvider` and
/// `poseUnitReportProvider` are deliberately built to stop notifying once their
/// values settle. So on a phone with no Russian voice installed — which latches
/// on the very first utterance — the coach could go permanently mute with the
/// card explaining why never painted. That is the precise confusion the card
/// was added to remove.
final voiceErrorProvider = StateProvider<String?>((_) => null);

/// Snapshot of the current set: how many reps, where in the movement, and
/// the quality record for each rep completed so far.
class RepSessionState {
  const RepSessionState({
    this.repCount = 0,
    this.phase = RepPhase.top,
    this.reps = const <RepQuality>[],
    this.lastRepCue,
    this.lastRepPeakMatch,
    this.lastRepMissedTarget,
    this.isArmed = false,
    this.lastReject,
  });

  /// Whether the counter has seen the lifter standing at the top and is
  /// therefore willing to start a repetition.
  ///
  /// Until this is true the count cannot move, no matter what the user does.
  /// That is correct behaviour — opening the camera mid-squat and standing up
  /// is not a repetition — but it is indistinguishable from a broken counter
  /// unless the screen says so. It did not, and a frozen `0` is the loudest
  /// thing on the page.
  final bool isArmed;

  /// Why the most recent attempt was thrown away, or null if the last thing
  /// that happened was a counted repetition.
  ///
  /// [RepCounter] has always reported this and nothing read it: a lap that
  /// came back up short vanished with no count and no explanation, which reads
  /// exactly like the detector losing track of the body.
  final RepRejectReason? lastReject;

  /// Closest the body got to the target shape during the last rep, 0..1.
  final double? lastRepPeakMatch;

  /// Whether the last rep failed to reach the silhouette. Null when there was
  /// no target to reach, or nothing to measure against it.
  final bool? lastRepMissedTarget;

  final int repCount;
  final RepPhase phase;
  final List<RepQuality> reps;

  /// The single fault of the rep just finished, or null when it had none.
  ///
  /// One per rep, chosen at the rep boundary. The screen used to render the
  /// current *frame's* feedback, which changes many times a second, so the card
  /// flickered between messages throughout every repetition. Operator, watching
  /// it: *"то что она постоянно повторяет одно и то же это бесит"*.
  ///
  /// A coach watches the rep and then says one thing. This is that.
  final FormFeedback? lastRepCue;

  /// Whether the rep just finished was a good one. Null before the first rep.
  ///
  /// Missing the silhouette counts as a fault in its own right: the per-frame
  /// rules can all be quiet — most of them are, deliberately — while the body
  /// never went near the target shape.
  bool? get lastRepClean {
    if (reps.isEmpty) return null;
    if (lastRepMissedTarget == true) return false;
    return reps.last.isClean;
  }

  int get cleanReps => reps.where((r) => r.isClean).length;

  int get sloppyReps => reps.length - cleanReps;
}

/// Drives rep counting off the same frame stream as [FormFeedbackController]:
/// per frame, run the active rules, fold them into the rep counter, and offer
/// the worst one to the voice coach (which decides whether to actually speak).
///
/// State is only republished when the counter reports an event, so a 30 FPS
/// camera does not trigger 30 widget rebuilds a second.
class RepSessionController extends Notifier<RepSessionState> {
  StreamSubscription<PoseFrame>? _sub;
  RepCounter? _counter;

  /// `cue()` is awaited off the frame path, so its completion can land after the
  /// controller is gone. Touching `ref` then throws.
  bool _disposed = false;

  /// Worst fault seen since the current repetition began, or null.
  FormFeedback? _worstThisRep;

  /// Closest the body got to the target shape during the current repetition.
  double? _peakMatchThisRep;

  @override
  RepSessionState build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    final coach = ref.watch(voiceCoachProvider);
    _counter = RepCounter(config: ref.watch(repCounterConfigProvider));

    coach.setMuted(ref.read(voiceMutedProvider));
    ref.listen<bool>(voiceMutedProvider, (_, isMuted) {
      coach.setMuted(isMuted);
      if (isMuted) unawaited(coach.stop());
    });

    _sub?.cancel();
    _sub = svc.frames().listen(
          _onFrame,
          onError: (Object e) => _recordPoseError(ref, e),
        );
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _sub = null;
    });
    return const RepSessionState();
  }

  void _onFrame(PoseFrame frame) {
    _retirePoseError(ref);
    final counter = _counter;
    if (counter == null) return;

    final result = evaluateGated(
      ref.read(activeClassifiersProvider),
      frame,
      config: ref.read(poseGateConfigProvider),
    );
    // An unscorable frame is dropped entirely — it must not reach the rep
    // counter and it must not reach the voice coach. This single early return
    // is what stops a selfie of a face from producing six reps and an endless
    // repeated safety warning.
    if (!result.scorable) return;

    // How close to the target shape this frame got. The readout on screen is
    // live and updates every frame; what the REP is judged on is the peak,
    // because a squat passes through the bottom for a fraction of a second and
    // the question is "did they reach it", not "are they in it right now".
    final target = ref.read(poseTargetProvider);
    double? match;
    if (target != null) {
      match = poseMatchScore(frame, target);
      ref.read(poseMatchProvider.notifier).state = match;
    }

    final wasInRep = counter.phase != RepPhase.top;
    final event = counter.update(frame, feedback: result.feedback);

    // Accumulate only while a repetition is actually in flight — which is what
    // RepCounter does with its own severity log, and what this did not. Frames
    // spent standing between reps were folded into the next one, so a fault
    // seen while resting was reported as a fault in the rep that followed, and
    // a movement whose target IS the top position could peak its silhouette
    // score without anybody moving. Both directions of the same mistake.
    //
    // `wasInRep ||` catches the two boundary frames: the one that starts the
    // descent (top before, descending after) and the one that completes the
    // lap (ascending before, top after). Neither belongs to the rest state.
    if (wasInRep || counter.phase != RepPhase.top) {
      if (match != null && match > (_peakMatchThisRep ?? -1)) {
        _peakMatchThisRep = match;
      }
      // Remember the worst thing seen so far, rather than reacting to it. The
      // decision to speak belongs at the rep boundary.
      final worst = result.worst;
      if (worst != null &&
          worst.severity >= 1 &&
          worst.severity > (_worstThisRep?.severity ?? 0)) {
        _worstThisRep = worst;
      }
    }

    if (event == null) {
      // Arming reports nothing: the counter quietly starts accepting laps on
      // the first frame that shows the lifter standing. Until then the count
      // physically cannot move, and a `0` that never budges is the single most
      // alarming thing this screen can display. Publish the transition so the
      // badge can say what it is waiting for.
      if (counter.isArmed != state.isArmed) state = _carryOver(counter);
      return;
    }

    switch (event.kind) {
      case RepEventKind.phaseChanged:
        state = _carryOver(counter);
        return;
      case RepEventKind.repRejected:
        _onRepRejected(counter, event, target);
        return;
      case RepEventKind.repCompleted:
        break;
    }

    // The silhouette is the verdict. A rep that never reached the target shape
    // is not a correct rep, however cleanly the per-frame rules ran — and this
    // is what gives the coach something true to say again. With both absolute
    // rules withdrawn it had nothing, and marked every rep clean; operator, on
    // that build: "все повторения правильные даже если я неправильно делаю".
    final peak = _peakMatchThisRep;
    final judged = target != null && peak != null;
    final missed = judged && peak < kPoseMatchPassing;
    var cue = _worstThisRep;
    if (missed) {
      cue = FormFeedback(
        rule: 'silhouette.match',
        severity: 2,
        cueKey: FormCueKey.silhouetteMissed,
        metric: peak,
      );
    }
    _worstThisRep = null;
    _peakMatchThisRep = null;

    state = RepSessionState(
      repCount: counter.repCount,
      phase: counter.phase,
      reps: counter.reps,
      isArmed: counter.isArmed,
      lastRepCue: cue,
      lastRepPeakMatch: peak,
      lastRepMissedTarget: judged ? missed : null,
    );

    // At most one utterance per completed repetition. The coach's own gate
    // still applies underneath — mute, severity floor, and not repeating the
    // identical sentence within its repeat window — but the PACING is the rep,
    // not a stopwatch. Before this, a severity-2 cue was re-spoken every 1.2s
    // for as long as the position held, which is what made it unbearable.
    if (cue != null) {
      final coach = ref.read(voiceCoachProvider);
      unawaited(coach.cue(cue).whenComplete(() => _publishVoiceError(coach)));
    }
  }

  /// Republish the counter's live numbers while keeping the last verdict.
  ///
  /// Phase changes and arming say nothing about how the previous repetition
  /// went, so the banner must survive them; without this the verdict would be
  /// wiped the instant the next descent began, which is well under a second
  /// after it appeared.
  RepSessionState _carryOver(RepCounter counter) => RepSessionState(
        repCount: counter.repCount,
        phase: counter.phase,
        reps: counter.reps,
        isArmed: counter.isArmed,
        lastReject: state.lastReject,
        lastRepCue: state.lastRepCue,
        lastRepPeakMatch: state.lastRepPeakMatch,
        lastRepMissedTarget: state.lastRepMissedTarget,
      );

  /// An attempt that started and was thrown away.
  ///
  /// It produces no count, and until now it produced no words either: the lap
  /// simply evaporated. From the user's side that is identical to the detector
  /// losing the body, and the natural response is to stop trusting the number.
  void _onRepRejected(RepCounter counter, RepEvent event, PoseTarget? target) {
    final peak = _peakMatchThisRep;
    // A discarded lap must not leak into the next one. The counter clears its
    // own severity log on discard; these two accumulators live out here and
    // did not, so a fault seen during a half rep was spoken at the end of the
    // NEXT repetition and attributed to it.
    _worstThisRep = null;
    _peakMatchThisRep = null;

    // Only the silhouette is allowed to blame the user for a rejection. The
    // counter's own signal is hip-height-minus-knee-height — the same
    // camera-dependent quantity that got the depth RULE withdrawn, after it
    // told the operator to sink lower at the bottom of a full squat: "ниже уже
    // некуда было". A rejection measured with that signal is reported on
    // screen and never spoken aloud as a fault.
    final cue = (target != null && peak != null && peak < kPoseMatchPassing)
        ? FormFeedback(
            rule: 'silhouette.match',
            severity: 2,
            cueKey: FormCueKey.silhouetteMissed,
            metric: peak,
          )
        : null;

    state = RepSessionState(
      repCount: counter.repCount,
      phase: counter.phase,
      reps: counter.reps,
      isArmed: counter.isArmed,
      lastReject: event.rejectReason,
      lastRepCue: state.lastRepCue,
      lastRepPeakMatch: state.lastRepPeakMatch,
      lastRepMissedTarget: state.lastRepMissedTarget,
    );

    if (cue != null) {
      final coach = ref.read(voiceCoachProvider);
      unawaited(coach.cue(cue).whenComplete(() => _publishVoiceError(coach)));
    }
  }

  /// Copies the coach's error state into a provider the UI can actually watch.
  ///
  /// After the attempt, not before: the failure this reports is raised inside
  /// `cue()`.
  void _publishVoiceError(VoiceCoach coach) {
    if (_disposed) return;
    final message = coach.lastErrorMessage;
    if (ref.read(voiceErrorProvider) != message) {
      ref.read(voiceErrorProvider.notifier).state = message;
    }
  }

  /// Start a new set: clear the count and the quality log.
  void resetSet() {
    _counter?.reset();
    _worstThisRep = null;
    // Also the silhouette peak. Left behind, the best shape of the previous
    // set would be credited to the first rep of the next one.
    _peakMatchThisRep = null;
    unawaited(ref.read(voiceCoachProvider).stop());
    state = const RepSessionState();
  }
}

final repSessionControllerProvider =
    NotifierProvider<RepSessionController, RepSessionState>(
        RepSessionController.new);
