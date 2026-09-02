import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/data/profile_models.dart';
import '../../profile/state/profile_providers.dart';
import '../data/coach_counters.dart';
import '../data/coach_phases.dart';
import '../data/form_classifier.dart';
import '../data/measured_rep_configs.dart';
import '../data/pose_avatar.dart';
import '../data/pose_detector_service.dart';
import '../data/pose_gate.dart';
import '../data/pose_landmark.dart';
import '../data/pose_silhouette.dart';
import '../data/pose_target.dart';
import '../data/pose_unit_probe.dart';
import '../data/rep_counter.dart';
import '../data/rep_signals.dart';
import '../data/voice_coach.dart';
// Imports back into this library, which Dart allows and which is deliberate:
// the alternative was a second copy of "is the set running" living here, and a
// pause that two places had to agree about is a pause that will eventually
// disagree. The dependency is one-way at RUNTIME — the phase controller never
// reads the rep session — so there is no provider cycle, only an import one.
import 'coach_phase_providers.dart';

/// What the user says they are doing. Rules are chosen from this.
enum FormExercise {
  squat,
  pushup,
  deadlift,
  curl,
  hinge,
  lunge,
  situp,
  overheadPress,
}

/// Catalog pattern id -> the movement this coach knows, or null.
///
/// The catalog tags 570 exercises across eight patterns
/// (`scripts/catalog/tag_pose_targets.py`). This map is the far smaller set
/// the coach has actually been taught, and the gap between the two numbers is
/// the honest state of the feature, not an oversight.
const Map<String, FormExercise> kPosePatternToExercise = {
  'squat': FormExercise.squat,
  'curl': FormExercise.curl,
  'hinge': FormExercise.hinge,
  'lunge': FormExercise.lunge,
  'situp': FormExercise.situp,
  'overhead_press': FormExercise.overheadPress,
};

/// Catalogue tag for [e], i.e. the inverse of [kPosePatternToExercise].
///
/// Written as a switch rather than a reversed map so a new enum value fails to
/// compile until it is answered here — the registries this feeds are what
/// decide whether a movement is offered to a user at all.
String? poseTagFor(FormExercise e) => switch (e) {
      FormExercise.squat => 'squat',
      FormExercise.pushup => 'pushup',
      FormExercise.curl => 'curl',
      FormExercise.hinge => 'hinge',
      FormExercise.lunge => 'lunge',
      FormExercise.situp => 'situp',
      FormExercise.overheadPress => 'overhead_press',
      // No catalogue tag: `deadlift` predates the tagging and the catalogue
      // files its exercises under `hinge`, which is the same movement with a
      // shape authored for it.
      FormExercise.deadlift => null,
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
  return formCoachTeaches(e);
}

/// The same question asked about a [FormExercise] rather than a catalogue tag.
///
/// Extracted because the Form Coach's own exercise picker offered all eight
/// values while every other surface — the Train tab's chip, the exercise page,
/// the player — asked [formCoachSupports] first. Selecting `pushup` there gave
/// a silhouette and a counter that never moved, and `deadlift` gave no shape at
/// all: the screen the feature is named after was the one place its own support
/// gate did not run.
bool formCoachTeaches(FormExercise e) =>
    poseTargetsFor(e) != null && countsRepsFor(e);

/// The two ends of [e]'s movement, or null when nothing is authored.
///
/// A plain function rather than only a provider, so the support gate above can
/// be decided -- and tested -- without a ProviderContainer. `poseDemoProvider`
/// reads it, which keeps one answer instead of two.
(PoseTarget, PoseTarget)? poseTargetsFor(FormExercise e) {
  final tag = poseTagFor(e);
  return tag == null ? null : poseTargetsByTag[tag];
}

/// Whether a rep of [e] can actually be counted.
///
/// Kept separate from [poseTargetsFor] because the push-up is exactly the case
/// where the two disagree: shapes authored, reps uncountable. Its only signal
/// would be hip-versus-knee height, which barely moves during a push-up —
/// `pushupBottomTarget`'s own comment says so.
///
/// The squat keeps `squatDepthSignal`; every movement added since reads a
/// body-relative signal from `rep_signals.dart`, so its thresholds do not
/// depend on how far the lifter stands from the phone.
bool countsRepsFor(FormExercise e) {
  if (e == FormExercise.squat) return true;
  final tag = poseTagFor(e);
  return tag != null && repSignalsByTag.containsKey(tag);
}

/// The signal and thresholds to count [e] with, or null when it cannot be
/// counted.
///
/// One lookup for both halves: a config paired with the wrong extractor would
/// produce a counter that never leaves the top phase, which on screen is
/// indistinguishable from a camera that cannot see the user.
(RepSignalExtractor, RepCounterConfig)? repSignalFor(FormExercise e) {
  if (e == FormExercise.squat) {
    return (squatDepthSignal, const RepCounterConfig());
  }
  final tag = poseTagFor(e);
  return tag == null ? null : repSignalsByTag[tag];
}

/// Signal + thresholds that actually drive [RepSessionController], per
/// movement -- the wiring [repSignalFor] was defined for but never reached:
/// the live counter had zero call sites for it and always ran the squat
/// signal regardless of [selectedExerciseProvider].
///
/// Prefers a measured config from `measured_rep_configs.dart` (MM-Fit,
/// [MeasuredRepConfig.countsReps] cleared) over the older, authored-shape
/// [repSignalFor]. Squat is the one exception: [squatDepthSignal] stays --
/// a measured squat config exists too, but replacing a tuned, shipped signal
/// for no accuracy gain is not what the measurement was for.
(RepSignalExtractor, RepCounterConfig)? liveRepSignalFor(FormExercise e) {
  if (e == FormExercise.squat) return repSignalFor(e);
  final tag = poseTagFor(e);
  final measured = tag == null ? null : measuredRepConfigs[tag];
  if (measured != null && measured.countsReps) {
    return (measured.signal, measured.toConfig());
  }
  return repSignalFor(e);
}

/// The per-side extractor for [e], or null when this movement has none.
///
/// G4. Only the squat, and deliberately so: [squatSideDepths] compares hip to
/// knee down each leg, which measures nothing at all on a push-up or a
/// sit-up. The panel renders the absence as «—», which is the correct answer
/// rather than a gap — a 50/50 split printed for a movement whose legs are not
/// moving would be a fabricated reassurance.
RepSideSignalExtractor? coachSideSignalFor(FormExercise e) =>
    e == FormExercise.squat ? squatSideDepths : null;

/// The signal value that counts as FULL amplitude for [e], or null when this
/// movement has no defensible answer.
///
/// Squat only, for the same reason: 0 in [squatDepthSignal]'s convention is
/// the hips level with the knees, the depth [SquatDepthClassifier] is tuned
/// around and the one the coach actually asks for. The measured configs the
/// other movements run on carry thresholds but no statement of what their own
/// full range is, so there is nothing here to be a percentage of.
double? coachFullAmplitudeSignalFor(FormExercise e) =>
    e == FormExercise.squat ? 0.0 : null;

/// The four trainer counters, read off the last completed repetition.
///
/// Off the last COMPLETED rep, like the technique gauge's cause tag and for
/// the same reason: these are numbers about a repetition, and a value
/// recomputed thirty times a second is not one anybody can read.
final coachCountersProvider = Provider<CoachCounters>((ref) {
  final session = ref.watch(repSessionControllerProvider);
  final exercise = ref.watch(selectedExerciseProvider);
  final signal = liveRepSignalFor(exercise);
  return coachCountersFor(
    session.reps.isEmpty ? null : session.reps.last,
    config: signal?.$2 ?? const RepCounterConfig(),
    fullAmplitudeSignal: coachFullAmplitudeSignalFor(exercise),
  );
});

/// Whether the on-screen rep count for [e] is accurate enough to show.
///
/// Deliberately separate from whether [e] is coached at all: the frame
/// pipeline (silhouette match, phase tracking) runs the same for every
/// movement via [liveRepSignalFor]'s fallback, so a push-up or a sit-up is
/// still demonstrated and judged on shape. Only the NUMBER is withheld for
/// the two movements MM-Fit measured below the 80% bar -- a count that is
/// wrong more often than right is worse than no count, the same contract
/// [MeasuredRepConfig.countsReps] states for [counterFor].
bool showRepCountFor(FormExercise e) {
  if (e == FormExercise.squat) return true;
  final tag = poseTagFor(e);
  final measured = tag == null ? null : measuredRepConfigs[tag];
  if (measured != null) return measured.countsReps;
  return countsRepsFor(e);
}

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
/// Which END of the movement is scored, and why it differs between movements.
///
/// A squat is judged at the bottom — the depth is the question. A push-up is
/// judged at the TOP, because the rep counter cannot find its bottom (see
/// [countsRepsFor]) and a target nothing arrives at fails everyone.
///
/// The movements added in 2026-08-08 are judged at the end the user is trying
/// to REACH: the curled position, the locked-out press, the folded crunch, the
/// bottom of the hinge and of the lunge. That is where the fault lives — a
/// half-curl and a half-press are the errors worth naming.
final poseTargetProvider = Provider<PoseTarget?>((ref) {
  final e = ref.watch(selectedExerciseProvider);
  final pair = poseTargetsFor(e);
  if (pair == null) return null;
  return switch (e) {
    FormExercise.pushup => pair.$1,
    _ => pair.$2,
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

/// Draw the user as a figure on a backdrop instead of showing the camera.
///
/// The camera keeps running — detection reads the image stream, not the
/// preview. What changes is only what is put on screen: the room is replaced by
/// a drawn scene and the body by an avatar built from the live pose.
///
/// Two things had to exist before this could: `pose_avatar.dart`, so a body can
/// be drawn from one believable side rather than from the far side's guesses,
/// and the empty frame the detector now emits, so losing the person clears the
/// figure. Without the second, this switch would replace an honest picture with
/// a figure that freezes and keeps posing.
///
/// ## ON by default since 2026-08-15, by operator decision
///
/// It was off, for the same reason the skeleton is off: this decides what the
/// user sees INSTEAD of the ground truth, and the honest default for something
/// unwatched is the picture that cannot be wrong about where the body is.
///
/// That argument was about an unverified feature, not about a preference, and it
/// stops applying the moment the preference is stated. The operator asked for
/// this screen to look like the reference animation — a dusk scene, the body
/// dark, the skeleton lit on it — and answered the direct question with "avatar
/// mode = the main view", camera and target outline kept as the option behind
/// the toggle. This is that decision.
///
/// What the old default was protecting against has not gone away and is now the
/// toggle's job: if the avatar is ever wrong about where the body is, the camera
/// is one tap away and `_MatchReadout`, `_Silhouette` and `_SkeletonOverlay` all
/// come back with it. What is NOT kept is the pretence that both views can be on
/// at once — Gate A settled that, and this only changes which of them opens.
final avatarModeProvider = StateProvider<bool>((_) => true);

/// The scenes the avatar can stand in.
///
/// Photographs rather than the painted gradient they replaced, because the
/// gradient was a placeholder for exactly this and said so. Ten of them so that
/// opening the coach twice in an evening does not look like the same screen
/// twice; the operator supplied them and asked for one at random each time.
///
/// Ordered and const so the list is greppable against `assets/coach_bg/` and a
/// file renamed without updating this shows up as a missing asset at build time
/// rather than as a blank screen at run time.
const kCoachBackdrops = <String>[
  'assets/coach_bg/01_cliffs_moher.webp',
  'assets/coach_bg/02_volcano.webp',
  'assets/coach_bg/03_waterfall_dock.webp',
  'assets/coach_bg/04_fuji_sakura.webp',
  'assets/coach_bg/05_sunset_hills.webp',
  'assets/coach_bg/06_greek_terrace.webp',
  'assets/coach_bg/07_snow_peak_tarn.webp',
  'assets/coach_bg/08_coast_turquoise.webp',
  'assets/coach_bg/09_forest_lake.webp',
  'assets/coach_bg/10_beach_sunset.webp',
];

/// Injectable so a test gets the same scene every run.
///
/// A widget test that pumped a random one of ten would be a test that fails one
/// time in ten for a reason nobody could reproduce.
final coachBackdropRandomProvider = Provider<math.Random>((_) => math.Random());

/// Which scene is on screen, re-rolled each time the coach page is opened.
///
/// "Each time" is the page mount, not the app launch: the operator asked for a
/// different scene each time, and once per process would mean the same picture
/// for a whole day of training.
class CoachBackdropController extends Notifier<String> {
  @override
  String build() => kCoachBackdrops[
      ref.read(coachBackdropRandomProvider).nextInt(kCoachBackdrops.length)];

  /// Pick a new scene, never the one already showing.
  ///
  /// Uniform choice over ten would repeat one open in ten, and a repeat does
  /// not read as chance — it reads as the shuffle being broken. Drawing from
  /// the other nine costs nothing and removes the only outcome a user could
  /// mistake for a bug.
  void shuffle() {
    if (kCoachBackdrops.length < 2) return;
    final others = [
      for (final b in kCoachBackdrops)
        if (b != state) b,
    ];
    state = others[ref.read(coachBackdropRandomProvider).nextInt(others.length)];
  }
}

final coachBackdropProvider =
    NotifierProvider<CoachBackdropController, String>(
        CoachBackdropController.new);

/// The live body as a drawable figure, or null when there is nothing to draw.
///
/// Built here rather than inside the painting widget so that ONE answer to
/// "can the avatar be drawn" exists. It used to be computed inside
/// `_PoseAvatar`, which meant the widget was the only thing in the app that
/// knew the figure had failed — so it had to announce that failure itself, in
/// its own centred box, while the status band two layers above went on saying
/// "Ready. Start when you are." off the gate's separate opinion. Two surfaces,
/// two verdicts, both on screen at once; see [avatarCannotPlaceBodyProvider].
///
/// Null when the mode is off or no pose has arrived. A pose that arrives and
/// yields no torso returns the empty figure rather than null, because those two
/// states want different things said about them.
final avatarFigureProvider = Provider<SilhouetteFigure?>((ref) {
  if (!ref.watch(avatarModeProvider)) return null;
  final frame = ref.watch(latestPoseFrameProvider);
  if (frame == null) return null;
  return buildPoseAvatar(
    frame,
    build: ref.watch(silhouetteBuildProvider),
    latch: ref.watch(avatarFarSideLatchProvider),
  );
});

/// Frame-to-frame state for the avatar, and the only piece of it there is.
///
/// Its own provider so it survives `avatarFigureProvider` recomputing on every
/// frame — a latch rebuilt each frame would hold nothing and the snap it exists
/// to remove would still be there, silently. It depends on nothing, so nothing
/// invalidates it; leaving the mode expires it on the clock (see
/// [AvatarFarSideLatch.gate]) rather than needing a reset hook that could be
/// forgotten.
final avatarFarSideLatchProvider =
    Provider<AvatarFarSideLatch>((_) => AvatarFarSideLatch());

/// A pose arrived, the mode is on, and it still yields no body to draw.
///
/// This is not the detector failing and it is not the user being absent — both
/// of those clear [latestPoseFrameProvider] and are already explained by the
/// gate. It is the narrower case the avatar alone can hit: `buildSilhouette`
/// needs a shoulder AND a hip to have a spine to mirror about, while
/// `SquatDepthClassifier.requiredLandmarks` needs neither. On a squat framed
/// low the gate says `ok`, the counter counts, and there is nothing to paint.
///
/// With the camera image replaced by a drawn scene, an unexplained empty scene
/// is indistinguishable from a crash — so this drives the status band rather
/// than being swallowed.
final avatarCannotPlaceBodyProvider = Provider<bool>((ref) {
  final figure = ref.watch(avatarFigureProvider);
  return figure != null && figure.torso.isEmpty;
});

/// Whether the coach is about to tell the user to do something, so everything
/// else on the page should get out of the way.
///
/// One expression, in one place. It was written out twice — in the page's build
/// and again in the rep badge's — and the comment above the first copy said the
/// fix was that "the page decides who speaks, instead of each widget deciding
/// for itself from its own private signal". Two copies of the deciding
/// expression are two private signals; they simply agreed. The next person to
/// add a blocking condition would have had to find both, and the failure when
/// they found one is the two-voices defect coming back.
final coachIsInstructingProvider = Provider<bool>((ref) =>
    ref.watch(avatarCannotPlaceBodyProvider) ||
    ref.watch(coachSessionProvider).blocker != CoachBlocker.none);

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
    // Empty ON PURPOSE, not pending work. The movements added 2026-08-08 are
    // coached by standing in a shape and having the match scored; they have no
    // rule-based classifier and must not borrow one. Every classifier here
    // measures a specific quantity of a specific movement — the push-up rule
    // grading a squat is the exact defect recorded above, and handing a curl
    // to `SquatDepthClassifier` would repeat it with a different name.
    //
    // A cue for these movements therefore comes from the pose match, which is
    // the mechanism that replaced thresholds because thresholds were wrong.
    FormExercise.curl ||
    FormExercise.hinge ||
    FormExercise.lunge ||
    FormExercise.situp ||
    FormExercise.overheadPress =>
      const [],
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

/// Whether developer diagnostics may paint over the camera and be measured.
///
/// Defaults to [kDebugMode], so a release build is false. A provider rather
/// than a bare `if (kDebugMode)` at each site for one reason: a test runs in
/// debug, so a bare constant would make "the release screen shows no debug
/// copy" untestable — the assertion would be checking the debug build.
/// Overriding this to false is how a test reproduces the release screen.
final poseDebugOverlayProvider = Provider<bool>((_) => kDebugMode);

/// What the coordinates actually measured this session.
///
/// Read-only: nothing in the scoring path consults it. It exists because every
/// threshold in the gate, the rep counter and the classifiers was picked against
/// an assumed range, and this is the first thing in the app that reports the
/// real one. See `pose_unit_probe.dart`.
///
/// Stays empty in a release build — see [poseDebugOverlayProvider].
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
    // The avatar is drawn from this frame too, so it has to be published for
    // either reader. Still gated rather than always on: with both off nothing
    // draws a pose, and notifying a provider nobody reads thirty times a second
    // is what this condition was added to stop.
    if (ref.read(showSkeletonProvider) || ref.read(avatarModeProvider)) {
      // A frame carrying no landmarks is the detector saying it looked and
      // found nobody. Published as null rather than as itself, so the overlay
      // CLEARS instead of holding the last live pose on screen as though it
      // were current — the same reason the toggle drops the held frame when it
      // is switched off.
      ref.read(latestPoseFrameProvider.notifier).state =
          frame.landmarks.isEmpty ? null : frame;
    }
    // Before the gate, on purpose: a frame the gate rejects is exactly the
    // frame whose coordinates are most worth knowing about. Gated with the
    // rendering rather than left running, so a release build pays nothing for a
    // measurement it will never display.
    if (ref.read(poseDebugOverlayProvider)) {
      _probe.observe(frame);
      final report = _probe.report;
      final previous = ref.read(poseUnitReportProvider);
      ref.read(poseUnitReportProvider.notifier).state = report;
      // Also written to the log, not only to the screen.
      //
      // The measurement this probe exists for needs a real body in front of a
      // real camera, which means the person taking it is holding the phone and
      // cannot simultaneously read six decimals off it and type them somewhere.
      // Every previous round of this ended with a number transcribed by hand
      // into a plan. On the log it can be captured by whoever is running
      // `flutter run` or `adb logcat`, and pasted rather than retyped.
      //
      // Emitted on CHANGE only, using the same equality the provider uses — a
      // steady camera settles within a second or two, so this is a handful of
      // lines per session and not thirty a second.
      if (report != previous) {
        debugPrint('[pose-probe] ${report.summary.replaceAll('\n', ' | ')}');
      }
    }

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

/// The colour-verdict severity the live avatar should paint with, or null for
/// "no verdict — plain white", exactly the figure painted before colour
/// existed.
///
/// Gated on [FormClassifier.canFault], not on [feedback]'s severity value
/// alone. Squat depth and hip-hinge report a metric at severity 0 on every
/// frame by construction (`form_classifier.dart` —
/// `SquatDepthClassifier.canFault`, `DeadliftHipHingeClassifier.canFault`,
/// both false, and documented as camera-angle-confounded, not merely
/// untuned). Reading `feedback.severity` without this gate would happen to
/// work today, only because that value never moves for either rule — and
/// would silently start colouring an unentitled rule "correct" or "wrong"
/// the moment either one grows a severity>0 arm.
///
/// Also gated on [feedback] carrying THIS classifier's own [FormFeedback.rule]
/// — not merely on some feedback existing. `FormFeedbackController` keeps its
/// last worst feedback until the next scorable frame; switching exercises
/// changes [activeClassifiers] immediately but does not itself clear that
/// stale value. Without this check, switching from an exercise that last
/// read severity 0 into a fault-capable one paints the new exercise green
/// off the OLD exercise's verdict until a fresh frame arrives — exactly the
/// false-safety-signal class of defect this whole gate exists to avoid.
/// GPT-PM review (round 1, `9d43c92`) caught this.
///
/// [matchScore] is the fallback for exactly the movements the paragraph above
/// excludes — `canFault == false` — and it is what `_onFrame`'s own comment
/// named as the missing "silhouette-match rule" before this could be lit up
/// at all. It existed only in non-avatar mode until the coordinate-unification
/// fix (`FORMCOACH_COORDINATE_UNIFICATION_2026-08-31`) made the target and the
/// live body share one projection, at which point scoring against a target
/// the user can actually see — the same condition Gate A required — became
/// true in avatar mode too. It can only ever return 0 (correct), never an
/// error severity: falling short of the target mid-rep is not a fault, only a
/// COMPLETED rep judged against it is (`lastRepMissedTarget`, decided once at
/// the rep boundary in `_onFrame`) — painting red on every frame the user has
/// not yet reached the bottom would be exactly the false-fault class of
/// defect the classifier branch above already guards against, just moved to a
/// different signal.
///
/// Scoped to a classifier that exists and simply cannot fault — an EMPTY
/// [activeClassifiers] still returns null unconditionally, matchScore or not.
/// "No classifier at all" means no known movement is even being attempted,
/// and a shape match is meaningless without one.
int? avatarVerdictSeverity(
  List<FormClassifier> activeClassifiers,
  FormFeedback? feedback, {
  double? matchScore,
  bool? lastRepMissedTarget,
}) {
  if (activeClassifiers.isEmpty) return null;
  final classifier = activeClassifiers.first;
  if (classifier.canFault) {
    if (feedback == null || feedback.rule != classifier.rule) return null;
    return feedback.severity;
  }
  // `classifier` names a real, known movement that has simply chosen not to
  // fault it (camera-angle-confounded, e.g. squat depth / hip hinge) — unlike
  // an empty list, which means no classifier at all is watching. The match
  // fallback stays scoped to the former: a shape-match result answers "does
  // this known movement match its target", which is meaningless without a
  // classifier already naming what movement is being attempted.
  //
  // Live first, so reaching the shape turns the body green immediately rather
  // than waiting for the rep to end.
  if (matchScore != null && matchScore >= kPoseMatchPassing) return 0;
  // Then the last COMPLETED rep's own verdict, which is what the paragraph
  // above always said the error colour would come from — and which nothing
  // passed in until 2026-09-02.
  //
  // Found by standing in front of the camera. Thirteen squats on an S23: the
  // skeleton was white on every single frame. Green needs a live match at or
  // above 0.80, and a body descending into a squat is nowhere near the
  // bottom-target's shape for most of the movement; red had no source at all.
  // So the one shipped movement with a target and a rep counter could show
  // "correct" and "no opinion", never "wrong" — while the cue card two
  // centimetres below it said «Вы не дошли до силуэта» in so many words. The
  // reference calls for exactly two overlay states, green and red
  // (`full_handoff_v1/README.md` §8), and this one had one and a half.
  if (lastRepMissedTarget == true) return 2;
  return null;
}

/// The joints the fault currently on screen is ABOUT, or empty when there is
/// no fault or nothing named one.
///
/// G6. The live skeleton glowed one colour for the whole body off
/// [avatarVerdictSeverity]'s single number, so "your back is rounding" lit the
/// shins exactly as brightly as the spine and the user had to read a sentence
/// to find out where to look. A [FormClassifier] already declares the joints it
/// reads and is forbidden from reading any others (`requiredLandmarks`), so
/// that set IS the answer — no new knowledge, only wiring that was missing.
///
/// Empty for severity 0 and for no verdict at all. A clean body is not a body
/// with an empty fault region: the painter distinguishes them by the severity
/// it is given, and this set only says WHERE, never WHETHER.
Set<LandmarkType> avatarFaultJoints(
  List<FormClassifier> activeClassifiers,
  FormFeedback? feedback,
) {
  if (feedback == null || feedback.severity <= 0) return const {};
  for (final c in activeClassifiers) {
    if (c.rule == feedback.rule) return _faultRegion(c.requiredLandmarks);
  }
  // A verdict from a rule no longer in the active set — the movement changed
  // mid-frame. Nothing to point at, and pointing at the previous movement's
  // joints would be worse than pointing at nothing.
  return const {};
}

/// The joint the current fault turns on, and its mirror, or empty.
///
/// G8 — the reference's pulsing ring. Separate from [avatarFaultJoints], which
/// answers "which part of the body", because they are different questions: the
/// region is a limb and the vertex is a point, and lighting a limb while
/// ringing every joint in it would say the same thing twice at two sizes.
///
/// Mirrored for the same reason the region is: a classifier reads left-keyed
/// joints only, and a sagging hip is not a fault of somebody's left hip.
Set<LandmarkType> avatarFaultVertices(
  List<FormClassifier> activeClassifiers,
  FormFeedback? feedback,
) {
  if (feedback == null || feedback.severity <= 0) return const {};
  for (final c in activeClassifiers) {
    if (c.rule != feedback.rule) continue;
    final vertex = c.faultVertex;
    if (vertex == null) return const {};
    final mirror = _mirrorOf(vertex);
    return {vertex, if (mirror != null) mirror};
  }
  return const {};
}

/// The limb chains the skeleton's bones actually run along.
///
/// Bones exist only WITHIN a chain: `buildSilhouette` draws shoulder-elbow,
/// elbow-wrist, hip-knee and knee-ankle, and nothing between a shoulder and a
/// hip — that span is the filled trunk, not a bone.
const _faultChains = <List<LandmarkType>>[
  [LandmarkType.leftShoulder, LandmarkType.leftElbow, LandmarkType.leftWrist],
  [LandmarkType.leftHip, LandmarkType.leftKnee, LandmarkType.leftAnkle],
];

/// A rule's declared joints, widened to the region of the body it is about.
///
/// **This function exists because G6's narrowing did not work in production,
/// and neither its tests nor three rounds of review caught it.** The painter
/// lights a bone when BOTH of its ends are in the fault set; the only shipped
/// rule that can fault a repetition declares `{leftShoulder, leftHip,
/// leftAnkle}`; and no bone in the skeleton has both of its ends in that set —
/// shoulder-to-hip is the trunk quad, and hip-to-ankle is two bones with a
/// knee in the middle that the rule never names. So zero bones ever lit and
/// the glow fell back to the whole skeleton every time, which is the exact
/// pre-G6 behaviour G6's own comments described as fixed. Measured, not
/// inferred: a probe over a full frontal body returned an empty lit set.
///
/// Two widenings, both of them about the difference between "the joints a rule
/// READS" and "the part of the body a rule is ABOUT":
///
/// 1. **Along a chain.** A rule that names two joints of the same limb is
///    talking about the limb between them, including the joints it did not
///    have to measure. The push-up rule reads hip and ankle; the knee lies
///    between them and its two bones are the lower body the rule is judging.
/// 2. **Across the body.** Every classifier reads LEFT-keyed joints only,
///    because the avatar is built from one side and mirrored
///    (`pose_avatar.dart`'s header). A sagging hip is not a fault of somebody's
///    left leg, so the region mirrors — otherwise the picture would light half
///    a body for a fault the whole body has.
///
/// **Known and deliberate limit:** the shoulder-to-hip span is the trunk, drawn
/// as a filled quad rather than as a bone, so the part of the push-up line that
/// runs through the torso still cannot light. Narrowing to the legs is a real
/// improvement over lighting everything; lighting the trunk too needs the
/// painter to tint a fill, which is a different change.
Set<LandmarkType> _faultRegion(Set<LandmarkType> declared) {
  final out = <LandmarkType>{...declared};
  for (final chain in _faultChains) {
    var first = -1;
    var last = -1;
    for (var i = 0; i < chain.length; i++) {
      if (!declared.contains(chain[i])) continue;
      if (first < 0) first = i;
      last = i;
    }
    if (first < 0 || last <= first) continue;
    for (var i = first; i <= last; i++) {
      out.add(chain[i]);
    }
  }
  return {
    for (final j in out) ...[j, _mirrorOf(j) ?? j],
  };
}

/// The same joint on the other side of the body, or null for a centre one.
LandmarkType? _mirrorOf(LandmarkType t) {
  final name = t.name;
  final other = name.startsWith('left')
      ? 'right${name.substring(4)}'
      : name.startsWith('right')
          ? 'left${name.substring(5)}'
          : null;
  if (other == null) return null;
  for (final candidate in LandmarkType.values) {
    if (candidate.name == other) return candidate;
  }
  return null;
}

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

/// Whether the cue card has a verdict on a finished repetition to show.
///
/// A free function rather than a getter on [RepSessionState] because it is a
/// statement about what the SCREEN will render, not about the set: the card
/// shows a rejection or a rep's quality and nothing else, so "has a verdict" is
/// exactly "one of those two is non-null". The status band asks this to know
/// whether its own informational rungs should stay quiet.
/// Asks [RepVerdict], not [RepSessionState.lastRepClean]. `lastRepClean` is
/// null for two different situations and the card renders only one of them as
/// nothing: "no rep yet" draws nothing, "not evaluated" draws a band. Reading
/// the boolean here would leave the band above believing the card was silent
/// while it was speaking, which is how a screen grows a second voice — the
/// defect this predicate was written to prevent.
bool coachStatusHasRepVerdict(RepSessionState s) =>
    s.lastReject != null || s.lastRepVerdict != RepVerdict.none;

/// What the coach may say about the repetition that just finished.
///
/// [notEvaluated] is the state this enum exists for. Before it, the screen had
/// no way to distinguish "watched it and found nothing wrong" from "was in no
/// position to find anything wrong", and rendered both as a green *rep clean* —
/// so a set performed badly, in the shipped default configuration, came back
/// eight-for-eight faultless.
enum RepVerdict {
  /// No repetition has finished yet. The card draws nothing.
  none,

  /// Judged, and it held up.
  clean,

  /// Judged, and it did not.
  faulted,

  /// A repetition finished and nothing was entitled to judge it: no silhouette
  /// was being scored and no active rule can fault a rep, or the lifter was
  /// not visible for enough of the repetition to have been watched at all.
  /// Said out loud rather than dressed as a pass.
  notEvaluated,
}

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
    this.lastRepEvaluated = false,
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

  /// Whether ANYTHING was in a position to fail the repetition just finished.
  ///
  /// False means the coach watched a rep it had no way to judge: no silhouette
  /// was being scored, and no active rule is entitled to fault one. It is not a
  /// verdict and must never be rendered as one.
  ///
  /// This exists because the two silences are identical from the outside.
  /// "Every rule stayed quiet" and "no rule was allowed to speak" both produce
  /// an empty fault list, and [lastRepClean] used to answer `true` to both. In
  /// the shipped default — avatar mode on, squat selected — the silhouette is
  /// withdrawn (`_onFrame`, the `avatarModeProvider` read) and the only active
  /// rule is `SquatDepthClassifier`, which is severity 0 in every arm. So every
  /// repetition came back faultless, which is the defect recorded at
  /// `repCompleted` below and reported by the operator once already.
  final bool lastRepEvaluated;

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

  /// What the coach is entitled to say about the repetition just finished.
  ///
  /// Four states, because there are four situations and the previous `bool?`
  /// could express only three. The one it could not express is the one that was
  /// shipping: a repetition finished, and nothing was in a position to judge it.
  /// That was rendered as [RepVerdict.clean].
  RepVerdict get lastRepVerdict {
    if (reps.isEmpty) return RepVerdict.none;
    if (!lastRepEvaluated) return RepVerdict.notEvaluated;
    // Rules being active is not the same as the rules having seen anything.
    // A repetition performed half out of frame produces no signal, so no rule
    // runs on those frames and the severity map comes back empty — which is
    // the value a faultless repetition also produces.
    if (!reps.last.isObservedAt(_minObservedRatio)) {
      return RepVerdict.notEvaluated;
    }
    if (lastRepMissedTarget == true) return RepVerdict.faulted;
    return reps.last.isClean ? RepVerdict.clean : RepVerdict.faulted;
  }

  /// Whether the rep just finished was a good one.
  ///
  /// Null when there is no answer — either no repetition has finished, or one
  /// has and nothing could judge it. Callers that need to tell those two apart
  /// must read [lastRepVerdict]; this getter deliberately refuses to guess.
  ///
  /// Missing the silhouette counts as a fault in its own right: the per-frame
  /// rules can all be quiet — most of them are, deliberately — while the body
  /// never went near the target shape.
  bool? get lastRepClean => switch (lastRepVerdict) {
        RepVerdict.none || RepVerdict.notEvaluated => null,
        RepVerdict.clean => true,
        RepVerdict.faulted => false,
      };

  int get cleanReps => reps
      .where((r) => r.isObservedAt(_minObservedRatio) && r.isClean)
      .length;

  int get sloppyReps => reps
      .where((r) => r.isObservedAt(_minObservedRatio) && !r.isClean)
      .length;

  /// Repetitions that finished with too little of them visible to judge.
  ///
  /// Counted separately rather than folded into [sloppyReps]: the app has no
  /// grounds to call these bad either.
  int get unobservedReps =>
      reps.where((r) => !r.isObservedAt(_minObservedRatio)).length;
}

/// Mirrors [RepCounterConfig.minObservedRatio]. The session summary reads
/// [RepQuality] records it did not build and has no counter to ask.
const double _minObservedRatio = 0.5;

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

  /// The frame that produced [_peakMatchThisRep], kept only so the debug
  /// breakdown at the rep boundary can say WHICH joints lost the score. Never
  /// read in a release build.
  PoseFrame? _peakFrameThisRep;

  /// The deepest frame of the rep, by hip-minus-knee height, and that depth.
  ///
  /// Separate from [_peakFrameThisRep] on purpose, and the distinction is the
  /// whole reason this exists: the peak-MATCH frame is chosen by the target
  /// being scored against, so judging a candidate target on frames the current
  /// target selected is circular. The deepest frame is selected by the movement
  /// itself and is the same frame whatever shape is authored.
  PoseFrame? _deepestFrameThisRep;
  double? _deepestThisRep;

  /// How many frames of the rep could and could not be scored.
  ///
  /// Required by GPT-PM before the squat gate closes, and it is instrumentation
  /// rather than a change of behaviour: excluding the elbow leaves the squat
  /// with exactly four scored joints, which is `poseMatchScore`'s own minimum,
  /// so any one of them dropping below the likelihood threshold now yields no
  /// score for that frame where previously the arm joints provided slack. A few
  /// unscoreable frames around the bottom are expected and harmless — the peak
  /// is taken over the frames that DID score. Whole correct repetitions coming
  /// back unscoreable would be a different matter, and this is how that would
  /// be noticed rather than assumed away.
  int _scoredFramesThisRep = 0;
  int _unscoredFramesThisRep = 0;

  /// Debug-only instrumentation for `FORM_COACH_REP_SIGNAL_DEVICE_RECALIBRATION`.
  ///
  /// The three movements that gate needs to measure — hinge, lunge, situp — have
  /// thresholds that their own authored shape cannot reach
  /// (`FORMCOACH_TARGET_ISOTROPIC_2026-09-01`), which means their counter never
  /// leaves the top phase and the per-rep log below never fires. Rep-boundary
  /// logging is therefore useless for exactly the movements that need measuring,
  /// and a window over the raw signal is the only way to see the distribution.
  ///
  /// Deliberately NOT a rolling average: what the recalibration needs is the
  /// extremes a real body reaches and the noise around them, and an average is
  /// the one summary that hides both.
  final List<double> _signalWindow = [];
  int _signalWindowStartMs = 0;
  int _signalFramesInWindow = 0;
  RepSignalExtractor? _debugSignal;
  RepCounterConfig? _debugConfig;
  String? _debugTag;

  @override
  RepSessionState build() {
    final svc = ref.watch(poseDetectorServiceProvider);
    final coach = ref.watch(voiceCoachProvider);
    final exercise = ref.watch(selectedExerciseProvider);
    final signal = liveRepSignalFor(exercise);
    _counter = RepCounter(
      config: signal?.$2 ?? const RepCounterConfig(),
      signal: signal?.$1,
      // Only where a per-side reading has a defined meaning. See
      // [coachSideSignalFor].
      sideSignal: coachSideSignalFor(exercise),
    );
    assert(() {
      _debugSignal = signal?.$1;
      _debugConfig = signal?.$2 ?? const RepCounterConfig();
      _debugTag = poseTagFor(exercise) ?? exercise.name;
      _signalWindow.clear();
      _signalFramesInWindow = 0;
      _signalWindowStartMs = 0;
      return true;
    }());

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

  /// Publish this frame's match percentage, INCLUDING when there isn't one.
  ///
  /// The readout is a live number, and until now it was only ever written —
  /// never cleared, except once when the page mounts. So the last scorable
  /// frame's percentage stayed on screen through everything that followed: an
  /// unusable view, a withdrawn target, a switch into avatar mode. A frozen
  /// "87%" beside "Step into frame so your whole body is visible" is the same
  /// two-voices defect this gate exists to close, made worse by a stale number
  /// being indistinguishable from a live one.
  ///
  /// Codex raised it against the avatar toggle. The toggle is not needed: any
  /// route to a frame with nothing to score reaches it, which is why the clear
  /// sits at the two points where "nothing to score" is DECIDED rather than
  /// behind one more condition in the widget that draws it.
  void _publishMatch(double? match) {
    ref.read(poseMatchProvider.notifier).state = match;
  }

  /// Prints the extremes the rep signal actually reaches, once every two
  /// seconds, in debug builds only.
  ///
  /// Reports the window's min and max rather than its mean, and reports how
  /// many frames produced no signal at all -- a movement filmed from the wrong
  /// angle yields nulls, and a distribution built without knowing how many
  /// frames were dropped is not a distribution. The configured gates are
  /// printed on the same line so the numbers can be read against them without
  /// looking anything up.
  void _logSignalWindow(PoseFrame frame, RepCounter counter) {
    final signal = _debugSignal;
    final config = _debugConfig;
    if (signal == null || config == null) return;

    if (_signalWindowStartMs == 0) _signalWindowStartMs = frame.timestampMs;
    final value = signal(frame, config.minLikelihood);
    if (value != null) _signalWindow.add(value);
    _signalFramesInWindow++;

    if (frame.timestampMs - _signalWindowStartMs < 2000) return;

    if (_signalWindow.isEmpty) {
      debugPrint('[sig] $_debugTag frames=$_signalFramesInWindow '
          'no signal at all -- wrong camera angle, or joints missing');
    } else {
      final lo = _signalWindow.reduce(math.min);
      final hi = _signalWindow.reduce(math.max);
      debugPrint('[sig] $_debugTag n=${_signalWindow.length}'
          '/$_signalFramesInWindow min=${lo.toStringAsFixed(3)} '
          'max=${hi.toStringAsFixed(3)} '
          'phase=${counter.phase.name} reps=${counter.repCount} '
          'gates top<=${config.topEnter} bottom>=${config.bottomEnter}');
    }
    _signalWindow.clear();
    _signalFramesInWindow = 0;
    _signalWindowStartMs = frame.timestampMs;
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
    if (!result.scorable) {
      _publishMatch(null);
      return;
    }

    // How close to the target shape this frame got. The readout on screen is
    // live and updates every frame; what the REP is judged on is the peak,
    // because a squat passes through the bottom for a fraction of a second and
    // the question is "did they reach it", not "are they in it right now".
    //
    // Used to be withheld entirely in avatar mode: that outline was fitted to
    // the PANEL while the avatar was placed where the body actually is, so
    // scoring against it graded the user on a shape they could not see drawn
    // at their own scale — `_SilhouettePainter`'s own doc says the drawn
    // target is what makes the score legitimate, and the same sentence read
    // backwards says an undrawn (or wrongly-scaled) target makes it
    // illegitimate. Codex raised exactly that against Gate A and it was
    // right, at the time.
    //
    // That premise no longer holds. Both painters now project through the
    // same `projectLandmark` transform (see
    // `FORMCOACH_COORDINATE_UNIFICATION_2026-08-31` in `core/DECISION_LOG.md`
    // and `form_check_page.dart`'s `_Silhouette`/`_SilhouettePainter`), so the
    // target the user is shown and the target the score is computed against
    // are the same shape at the same scale in both modes. Scoring now runs
    // identically regardless of `avatarModeProvider` — the two modes differ
    // only in how the tracked body is drawn, never in what "correct" means.
    final target = ref.read(poseTargetProvider);
    final match = target == null ? null : poseMatchScore(frame, target);
    _publishMatch(match);

    // Paused, or finished. One guard, and it sits HERE rather than at the top
    // of the method on purpose: everything above is a readout of the live
    // camera — the skeleton, the match percentage — and the camera keeps
    // running through a pause by the operator's decision. Freezing the overlay
    // over a moving preview would read as a crash, not as a pause.
    //
    // What stops below this line is the COUNT, and with it the fault
    // accumulation and the voice. Keyed on the phase rather than on a flag of
    // this controller's own, so the app has exactly one answer to "is the set
    // running" — the same reason R11h put the pre-set stages behind the gate
    // verdict instead of behind a second copy of it.
    if (!countingIsLiveIn(ref.read(coachPhaseControllerProvider).phase)) {
      return;
    }

    assert(() {
      _logSignalWindow(frame, counter);
      return true;
    }());

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
      assert(() {
        if (target != null) {
          if (match == null) {
            _unscoredFramesThisRep++;
          } else {
            _scoredFramesThisRep++;
          }
        }
        return true;
      }());
      if (match != null && match > (_peakMatchThisRep ?? -1)) {
        _peakMatchThisRep = match;
        assert(() {
          _peakFrameThisRep = frame;
          return true;
        }());
      }
      assert(() {
        final depth = _debugHipMinusKnee(frame);
        if (depth != null && depth > (_deepestThisRep ?? -1e9)) {
          _deepestThisRep = depth;
          _deepestFrameThisRep = frame;
        }
        return true;
      }());
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
    // ...and when the silhouette is not being scored either, SOMETHING has to
    // have been entitled to disagree, or there is no verdict to give. Squat in
    // the shipped default is exactly that case: avatar mode withdraws the
    // target, and `SquatDepthClassifier` is severity 0 in every arm. Asking the
    // rules whether they may fault at all is the difference between "nothing
    // was wrong" and "nothing could have been found wrong"; the screen renders
    // the second as `RepVerdict.notEvaluated` rather than as a pass.
    final evaluated =
        judged || ref.read(activeClassifiersProvider).any((c) => c.canFault);
    // Debug-only, and it exists because the alternative was guessing. The
    // silhouette verdict is the one number on this screen with no on-screen
    // readout in avatar mode (`_MatchReadout` is camera-mode only), so a
    // report of "it says I missed on every rep" could not be told apart from
    // "the scorer is broken" without a person in front of the camera
    // describing what they did. Mirrors `pose_unit_probe.dart`'s precedent:
    // one line, stripped from release by `assert`.
    assert(() {
      debugPrint('[rep] #${counter.repCount} target=${target?.id} '
          'peak=${peak?.toStringAsFixed(3) ?? "-"} '
          'pass=$kPoseMatchPassing missed=$missed gate=${ref.read(
        poseGateVerdictProvider,
      )} frames=$_scoredFramesThisRep scored/'
          '$_unscoredFramesThisRep unscoreable');
      final f = _peakFrameThisRep;
      if (f != null && target != null) {
        debugPrint('[rep]   ${debugMatchBreakdown(f, target)}');
      }
      final deep = _deepestFrameThisRep;
      if (deep != null && target != null) {
        debugPrint('[rep]   deepest hipMinusKnee='
            '${_deepestThisRep?.toStringAsFixed(3)} '
            'match=${poseMatchScore(deep, target)?.toStringAsFixed(3)} '
            '${debugJointDump(deep, target)}');
      }
      return true;
    }());

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
    _peakFrameThisRep = null;
    _deepestFrameThisRep = null;
    _deepestThisRep = null;
    _scoredFramesThisRep = 0;
    _unscoredFramesThisRep = 0;

    state = RepSessionState(
      repCount: counter.repCount,
      phase: counter.phase,
      reps: counter.reps,
      isArmed: counter.isArmed,
      lastRepCue: cue,
      lastRepPeakMatch: peak,
      lastRepMissedTarget: judged ? missed : null,
      lastRepEvaluated: evaluated,
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
        // Carried for the same reason as the rest: dropping it would silently
        // rewrite a verdict that HAD been earned into "nothing could judge it"
        // on the next phase change, which is under a second later.
        lastRepEvaluated: state.lastRepEvaluated,
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
    _peakFrameThisRep = null;
    _deepestFrameThisRep = null;
    _deepestThisRep = null;
    _scoredFramesThisRep = 0;
    _unscoredFramesThisRep = 0;

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
      lastRepEvaluated: state.lastRepEvaluated,
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
    _peakFrameThisRep = null;
    _deepestFrameThisRep = null;
    _deepestThisRep = null;
    _scoredFramesThisRep = 0;
    _unscoredFramesThisRep = 0;
    unawaited(ref.read(voiceCoachProvider).stop());
    state = const RepSessionState();
  }
}

final repSessionControllerProvider =
    NotifierProvider<RepSessionController, RepSessionState>(
        RepSessionController.new);

/// Mean hip height minus mean knee height, the squat's own depth signal, in
/// frame-height units. Debug diagnostics only — negative means the hip is above
/// the knee, and `RepCounterConfig.bottomEnter` (-0.04) is the depth at which a
/// repetition is allowed to count.
double? _debugHipMinusKnee(PoseFrame f) {
  double? mid(LandmarkType l, LandmarkType r) {
    final a = f.landmarks[l], b = f.landmarks[r];
    if (a == null || b == null) return null;
    if (a.likelihood < 0.5 || b.likelihood < 0.5) return null;
    return (a.y + b.y) / 2;
  }

  final hip = mid(LandmarkType.leftHip, LandmarkType.rightHip);
  final knee = mid(LandmarkType.leftKnee, LandmarkType.rightKnee);
  return (hip == null || knee == null) ? null : hip - knee;
}
