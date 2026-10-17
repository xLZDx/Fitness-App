/// What the shell dock shows while a workout timer is running (S03-07,
/// contract S-4, design 2.6 and 7 F-11/F-14).
///
/// ## Read-only, derived, never a second timer
///
/// [activeSessionStatusProvider] is computed from [setTimerProvider] and
/// [restTimerProvider] (and the injectable [restClockProvider]) and from
/// nothing else. It never writes to either timer, adds no `autoDispose` to
/// them, and does not depend on mode state (F-8): a mode change cannot reset a
/// timer or the strip.
///
/// ## The table of contract S-4
///
///  * Set timer phase gettingReady, work or rest: `running` when the set
///    timer is running, `paused` otherwise.
///  * Rest timer not idle and (counting down, paused, or finished less than
///    [kRestFinishedVisibleFor] ago): `resting`, `paused`, `restFinished`.
///  * The set timer wins when both apply.
///  * Set phase `done` or `idle`, a rest finished longer ago than the window, a
///    skipped rest: no status (strip hidden).
///
/// A skipped rest clears its deadline (`RestTimerState.skip`), so "finished
/// less than 10 minutes ago" cannot be derived for it; it is treated as ended
/// by the user's own decision and hides the strip.
///
/// ## Driven transitions (RV-8)
///
/// Nothing polls. For a rest with a deadline the core provider arms one-shot
/// timers, created through [activeSessionTimerFactoryProvider], at `endsAt`
/// ("resting" becomes "rest finished") and at `endsAt + 10 min` (the strip
/// hides). They are cancelled with `ref.onDispose` and re-armed on every
/// recompute, so a timer state change re-arms them.
///
/// ## Account safety (F-11, RV-4)
///
/// The workout page writes an [ActiveSessionOwner] (uid + destination) at the
/// moment a set or rest timer starts, in one place, and nothing recomputes it
/// from the current auth. The public status is null whenever the owner's uid
/// differs from the signed-in uid. The owner is cleared by an explicit
/// `ref.listen` when the session ends; no provider writes to another provider
/// during `build`.
///
/// ## Prioritised sources (S04-24)
///
/// The public status is the highest-priority source that is visible to the
/// signed-in account (gym timers 10, GPS recording 20); see
/// [activeSessionSourcesProvider]. Each source has its own owner.
///
/// Process death clears both timers (they are in memory); there is no recovery
/// claim (R-S5, F-12).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../recording/state/recorder_display.dart';
import '../../recording/state/recorder_phase.dart';
import '../../recording/state/recorder_providers.dart'
    show recorderControllerProvider, recorderDisplayProvider, recorderPhaseProvider;
import '../data/set_session.dart' show SetPhase;
import 'rest_timer_providers.dart';
import 'set_timer_providers.dart';

/// How long a finished rest keeps the strip visible (contract S-4).
const Duration kRestFinishedVisibleFor = Duration(minutes: 10);

/// Where the strip opens when the owner holds no destination (AC-ST-5).
const String kActiveSessionDefaultDestination = '/workouts';

/// Route of the GPS recording page (S04-D `/record/gps`). Registered by the
/// router lane; the strip only navigates to it (SH-3).
const String kGpsRecordingDestination = '/record/gps';

/// What is being recorded. A new source adds a value here, a producer and an
/// [ActiveSessionSource] entry (S04 design 7.2).
enum ActiveSessionKind { gymWorkout, gpsRecording }

/// The one-line banner label shown as the strip's third line for a GPS
/// recording (S04-D 14.1); never a mode label.
enum ActiveSessionNote { storageWriteFailing, batteryCritical }

/// The strip state words of contract S-4 and S04-D 14.1.
enum ActiveSessionState {
  /// A set timer is running: "Workout in progress".
  running,

  /// A set timer or a rest is paused: "Paused".
  paused,

  /// A rest is counting down: "Resting".
  resting,

  /// A rest ran out less than [kRestFinishedVisibleFor] ago: "Rest finished".
  restFinished,

  // GPS recording words (S04-D 14.1). A manual pause reuses [paused].

  /// "Looking for GPS".
  acquiring,

  /// "Recording".
  recording,

  /// "Weak GPS signal".
  weakSignal,

  /// "Auto-paused".
  autoPaused,

  /// "Unfinished recording" (recovery offer pending).
  unfinished,

  /// "Recording not restored" (unreadable recording).
  notRestored,
}

/// One running session as the shell shows it.
@immutable
class ActiveSessionStatus {
  const ActiveSessionStatus({
    required this.kind,
    required this.state,
    this.title = '',
    this.mode = 'train',
    this.remaining,
    this.restEndsAt,
    this.destination = kActiveSessionDefaultDestination,
    this.ownerUid = '',
    this.note,
    this.countsUp = false,
  });

  final ActiveSessionKind kind;
  final ActiveSessionState state;

  /// Optional session title. Empty for the two timer sources (neither holds an
  /// exercise name); the strip then shows only the state word.
  final String title;

  /// The session's own mode id: `train`, `ride`, `explore` or `body`. Always
  /// `train` for the two timer sources. A plain string so the status does not
  /// depend on the mode state (F-8); it is the ICU select value of
  /// `stripModeLabel`.
  final String mode;

  /// Time left for a set (seconds of the current phase) or a paused rest.
  /// Null while a rest is counting down (use [restEndsAt] and a clock) and for
  /// a finished rest.
  final Duration? remaining;

  /// The wall-clock deadline of the rest, while it counts down or after it
  /// finished. Null for set-timer states and a paused rest.
  final DateTime? restEndsAt;

  /// Route opened by a tap. Never empty.
  final String destination;

  /// Uid that started the session; empty when no owner was recorded.
  final String ownerUid;

  /// Banner label of a GPS recording (third strip line); null for none.
  final ActiveSessionNote? note;

  /// True when [remaining] is elapsed (moving) time, not time left: the spoken
  /// label then must not say "left".
  final bool countsUp;

  /// Time left at [now]: [remaining] when set, else the rest deadline minus
  /// [now] (never negative), else null.
  Duration? remainingAt(DateTime now) {
    final fixed = remaining;
    if (fixed != null) return fixed;
    final end = restEndsAt;
    if (end == null || state != ActiveSessionState.resting) return null;
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  ActiveSessionStatus withOwner(ActiveSessionOwner? owner) {
    final dest = owner?.destination.trim() ?? '';
    return ActiveSessionStatus(
      kind: kind,
      state: state,
      title: title,
      mode: mode,
      remaining: remaining,
      restEndsAt: restEndsAt,
      destination: dest.isEmpty ? kActiveSessionDefaultDestination : dest,
      ownerUid: owner?.uid ?? '',
      note: note,
      countsUp: countsUp,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActiveSessionStatus &&
      other.kind == kind &&
      other.state == state &&
      other.title == title &&
      other.mode == mode &&
      other.remaining == remaining &&
      other.restEndsAt == restEndsAt &&
      other.destination == destination &&
      other.ownerUid == ownerUid &&
      other.note == note &&
      other.countsUp == countsUp;

  @override
  int get hashCode => Object.hash(
        kind,
        state,
        title,
        mode,
        remaining,
        restEndsAt,
        destination,
        ownerUid,
        note,
        countsUp,
      );

  // No content in diagnostics: no title, destination or uid.
  @override
  String toString() => 'ActiveSessionStatus($kind, $state)';
}

/// Who started the running session and where the strip should lead (RV-4).
@immutable
class ActiveSessionOwner {
  const ActiveSessionOwner({required this.uid, required this.destination});

  final String uid;

  /// Route string written by the workout page. Empty means `/workouts`.
  final String destination;

  @override
  bool operator ==(Object other) =>
      other is ActiveSessionOwner &&
      other.uid == uid &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(uid, destination);

  @override
  String toString() => 'ActiveSessionOwner';
}

/// Holds the [ActiveSessionOwner]. Written only where a set or rest timer
/// starts (`workout_player_page.dart`) and cleared by the status provider's
/// explicit listener when the session ends.
class ActiveSessionOwnerController extends Notifier<ActiveSessionOwner?> {
  @override
  ActiveSessionOwner? build() => null;

  /// Records the owner. [uid] is the signed-in uid AT THIS MOMENT and is never
  /// recomputed afterwards.
  void capture({required String uid, required String destination}) {
    final trimmed = destination.trim();
    final next = ActiveSessionOwner(
      uid: uid,
      destination: trimmed.isEmpty ? kActiveSessionDefaultDestination : trimmed,
    );
    if (state != next) state = next;
  }

  void clear() {
    if (state != null) state = null;
  }
}

final activeSessionOwnerProvider =
    NotifierProvider<ActiveSessionOwnerController, ActiveSessionOwner?>(
        ActiveSessionOwnerController.new);

/// Creates the one-shot transition timers. Tests override it with a factory
/// that records the callbacks and the delays (RV-8 seam).
typedef ActiveSessionTimerFactory = Timer Function(
    Duration delay, void Function() callback);

final activeSessionTimerFactoryProvider =
    Provider<ActiveSessionTimerFactory>((_) => Timer.new);

/// The pure table of contract S-4. Returns null when no strip should show.
///
/// Owner, destination and uid gating are NOT applied here; see
/// [activeSessionStatusProvider].
ActiveSessionStatus? deriveActiveSessionStatus({
  required SetTimerState setTimer,
  required RestTimerState rest,
  required DateTime now,
}) {
  switch (setTimer.phase) {
    case SetPhase.gettingReady:
    case SetPhase.work:
    case SetPhase.rest:
      return ActiveSessionStatus(
        kind: ActiveSessionKind.gymWorkout,
        state: setTimer.running
            ? ActiveSessionState.running
            : ActiveSessionState.paused,
        remaining: Duration(
            seconds: setTimer.secondsLeft < 0 ? 0 : setTimer.secondsLeft),
      );
    case SetPhase.idle:
    case SetPhase.done:
      break;
  }

  if (rest.isIdle || rest.skipped) return null;

  final paused = rest.pausedRemaining;
  if (paused != null) {
    return ActiveSessionStatus(
      kind: ActiveSessionKind.gymWorkout,
      state: ActiveSessionState.paused,
      remaining: paused,
    );
  }

  final end = rest.endsAt;
  if (end == null) return null;
  if (now.isBefore(end)) {
    return ActiveSessionStatus(
      kind: ActiveSessionKind.gymWorkout,
      state: ActiveSessionState.resting,
      restEndsAt: end,
    );
  }
  if (now.isBefore(end.add(kRestFinishedVisibleFor))) {
    return ActiveSessionStatus(
      kind: ActiveSessionKind.gymWorkout,
      state: ActiveSessionState.restFinished,
      restEndsAt: end,
    );
  }
  return null;
}

/// Delays from [now] to the next driven transitions of [rest]: its deadline
/// and the end of the "finished" window. Empty when the rest has no deadline.
List<Duration> activeSessionTransitionDelays(
  RestTimerState rest,
  DateTime now,
) {
  final end = rest.endsAt;
  if (end == null || rest.skipped) return const <Duration>[];
  final hideAt = end.add(kRestFinishedVisibleFor);
  return <Duration>[
    if (now.isBefore(end)) end.difference(now),
    if (now.isBefore(hideAt)) hideAt.difference(now),
  ];
}

/// Timer-derived status without owner gating. Private: the public provider
/// adds the account check. Hosts the driven timers (RV-8).
final _activeSessionCoreProvider = Provider<ActiveSessionStatus?>((ref) {
  try {
    final setTimer = ref.watch(setTimerProvider);
    final rest = ref.watch(restTimerProvider);
    final now = ref.watch(restClockProvider)();
    final makeTimer = ref.read(activeSessionTimerFactoryProvider);
    for (final delay in activeSessionTransitionDelays(rest, now)) {
      final timer = makeTimer(delay, () => ref.invalidateSelf());
      ref.onDispose(timer.cancel);
    }
    return deriveActiveSessionStatus(setTimer: setTimer, rest: rest, now: now);
  } catch (e) {
    // F-14: the strip hides, the shell is unaffected, the timers stay
    // reachable. Fixed message, content-free code, exception type only.
    debugPrint('active_session_status: derive_failed ${e.runtimeType}');
    return null;
  }
});

bool _sameUid(String ownerUid, String? currentUid) =>
    ownerUid == (currentUid ?? '');

/// The gym timer source: timer-derived status plus its own owner (F-11). The
/// status carries the owner's uid and destination; the account gate is applied
/// once, for every source, by [activeSessionStatusProvider].
final _gymSessionStatusProvider = Provider<ActiveSessionStatus?>((ref) {
  try {
    final core = ref.watch(_activeSessionCoreProvider);
    final owner = ref.watch(activeSessionOwnerProvider);

    // Explicit listener, not a write inside build: when the gym session ends
    // its own owner goes with it, so a later session never inherits a stale
    // route or uid. Only the gym owner is touched (S04-R-037 c).
    ref.listen<ActiveSessionStatus?>(_activeSessionCoreProvider,
        (previous, next) {
      if (next == null && ref.read(activeSessionOwnerProvider) != null) {
        ref.read(activeSessionOwnerProvider.notifier).clear();
      }
    });

    if (core == null) return null;
    return core.withOwner(owner);
  } catch (e) {
    debugPrint('active_session_status: gate_failed ${e.runtimeType}');
    return null;
  }
});

final _gymSessionOwnerUidProvider = Provider<String?>(
    (ref) => ref.watch(activeSessionOwnerProvider)?.uid);

// ---- GPS recording source (S04-24) -------------------------------------------

/// Uid that owned the current recording, captured when the recorder leaves
/// `idle` and cleared when it returns to `idle`. Never recomputed from the
/// current auth (same rule as [ActiveSessionOwner], RV-4): an account switch
/// hides the recording, it does not hand it to the new account. A transient
/// auth state changes nothing here (X1).
class GpsRecordingOwnerController extends Notifier<String?> {
  @override
  String? build() {
    ref.listen<RecorderPhase>(recorderPhaseProvider, (previous, next) {
      if (next == RecorderPhase.idle) {
        if (state != null) state = null;
      } else if (state == null) {
        state = _currentUid();
      }
    });
    // A recording restored at process start is already past idle at first read.
    return ref.read(recorderPhaseProvider) == RecorderPhase.idle
        ? null
        : _currentUid();
  }

  String _currentUid() => ref.read(authUserProvider).valueOrNull?.uid ?? '';
}

final gpsRecordingOwnerUidProvider =
    NotifierProvider<GpsRecordingOwnerController, String?>(
        GpsRecordingOwnerController.new);

/// Pure projection of the recorder display onto a strip status (S04-D 14.1).
/// Null for `idle`, `finished` and `permissionRevoked` (design 7.2: no strip).
/// [movingSeconds] is the moving time (frozen while paused).
ActiveSessionStatus? deriveGpsRecordingStatus({
  required RecorderDisplay display,
  required int movingSeconds,
  required String ownerUid,
}) {
  ActiveSessionStatus make(ActiveSessionState state,
          {bool withTime = false, ActiveSessionNote? note}) =>
      ActiveSessionStatus(
        kind: ActiveSessionKind.gpsRecording,
        state: state,
        remaining: withTime
            ? Duration(seconds: movingSeconds < 0 ? 0 : movingSeconds)
            : null,
        countsUp: withTime,
        mode: '',
        destination: kGpsRecordingDestination,
        ownerUid: ownerUid,
        note: note,
      );

  switch (display.headline) {
    case RecorderDisplayState.acquiring:
      return make(ActiveSessionState.acquiring);
    case RecorderDisplayState.poorAccuracy:
      return make(ActiveSessionState.weakSignal, withTime: true);
    case RecorderDisplayState.pausedManual:
      return make(ActiveSessionState.paused, withTime: true);
    case RecorderDisplayState.pausedAuto:
      return make(ActiveSessionState.autoPaused, withTime: true);
    case RecorderDisplayState.restoring:
      return make(ActiveSessionState.unfinished);
    case RecorderDisplayState.recoveryFailed:
      return make(ActiveSessionState.notRestored);
    case RecorderDisplayState.recording:
    case RecorderDisplayState.offline:
    case RecorderDisplayState.background:
    case RecorderDisplayState.batteryCritical:
      return make(
        ActiveSessionState.recording,
        withTime: true,
        note: switch (display.banner) {
          RecorderBanner.storageWriteFailing =>
            ActiveSessionNote.storageWriteFailing,
          RecorderBanner.batteryCritical => ActiveSessionNote.batteryCritical,
          null => null,
        },
      );
    case RecorderDisplayState.idle:
    case RecorderDisplayState.finished:
    case RecorderDisplayState.permissionRevoked:
      return null;
  }
}

/// The GPS recording source: recorder state only, no gym timer, no mode.
final _gpsRecordingStatusProvider = Provider<ActiveSessionStatus?>((ref) {
  try {
    final display = ref.watch(recorderDisplayProvider);
    // Whole seconds only, so the status changes once per second at most.
    final seconds = ref.watch(recorderControllerProvider
        .select((s) => s.totalMovingTimeMs ~/ 1000));
    final owner = ref.watch(gpsRecordingOwnerUidProvider) ?? '';
    return deriveGpsRecordingStatus(
        display: display, movingSeconds: seconds, ownerUid: owner);
  } catch (e) {
    debugPrint('active_session_status: gps_derive_failed ${e.runtimeType}');
    return null;
  }
});

// ---- Prioritised sources (S04 design 7.2) ------------------------------------

/// Seam: true when the GPS recorder entry points are on (compile-time flag
/// `GPS_RECORDER` and Android, S04-D 14.2). Default false, so the S03 behaviour
/// of the Record sheet and shortcut is unchanged. Overridden at the app root
/// (lane R9) from the flag file of lane R8.
final gpsRecorderEnabledProvider = Provider<bool>((ref) => false);

/// Priority of the gym timer source.
const int kGymTimersSourcePriority = 10;

/// Priority of the GPS recording source: it wins when both run (S04-R-038,
/// option A of D-12; change this one number for option B).
const int kGpsRecordingSourcePriority = 20;

/// One independent producer of a running session. It has its OWN owner rule:
/// [ownerUid] null means unowned (always visible); a uid that differs from the
/// signed-in uid hides the source without clearing it.
@immutable
class ActiveSessionSource {
  const ActiveSessionSource({
    required this.id,
    required this.priority,
    required this.status,
    required this.ownerUid,
  });

  final String id;

  /// Higher wins.
  final int priority;
  final ProviderListenable<ActiveSessionStatus?> status;
  final ProviderListenable<String?> ownerUid;
}

/// The registered sources. Tests override it with fakes.
final activeSessionSourcesProvider = Provider<List<ActiveSessionSource>>(
  (ref) => <ActiveSessionSource>[
    ActiveSessionSource(
      id: 'gymTimers',
      priority: kGymTimersSourcePriority,
      status: _gymSessionStatusProvider,
      ownerUid: _gymSessionOwnerUidProvider,
    ),
    ActiveSessionSource(
      id: 'gpsRecording',
      priority: kGpsRecordingSourcePriority,
      status: _gpsRecordingStatusProvider,
      ownerUid: gpsRecordingOwnerUidProvider,
    ),
  ],
);

List<ActiveSessionSource> _byPriority(List<ActiveSessionSource> sources) =>
    List<ActiveSessionSource>.of(sources)
      ..sort((a, b) => b.priority.compareTo(a.priority));

/// The strip and pill source: the status of the highest-priority source whose
/// owner matches the signed-in uid and whose status is non-null. Null means
/// "no session": the shell shows the Record pill (or the idle rail slot). A
/// source of another account is skipped, never cleared (F-11, S04-R-037).
final activeSessionStatusProvider = Provider<ActiveSessionStatus?>((ref) {
  try {
    final uid =
        ref.watch(authUserProvider.select((u) => u.valueOrNull?.uid));
    ActiveSessionStatus? winner;
    // Every source is watched (also those below the winner), so a change in
    // any of them recomputes the result.
    for (final source in _byPriority(ref.watch(activeSessionSourcesProvider))) {
      final status = ref.watch(source.status);
      final owner = ref.watch(source.ownerUid);
      if (winner != null || status == null) continue;
      if (owner != null && !_sameUid(owner, uid)) continue;
      winner = status;
    }
    return winner;
  } catch (e) {
    debugPrint('active_session_status: gate_failed ${e.runtimeType}');
    return null;
  }
});

/// True while a session of another account is running AND no session of the
/// signed-in account is visible: the shell then shows neither the strip nor
/// the Record pill (F-11, DT-07-8). A foreign timer beside the own recording
/// does not hide anything. The owner is kept so the other account's session is
/// never exposed.
final activeSessionForeignOwnerProvider = Provider<bool>((ref) {
  final uid = ref.watch(authUserProvider.select((u) => u.valueOrNull?.uid));
  var foreign = false;
  var visible = false;
  for (final source in ref.watch(activeSessionSourcesProvider)) {
    final status = ref.watch(source.status);
    final owner = ref.watch(source.ownerUid);
    if (owner != null && !_sameUid(owner, uid)) {
      foreign = true;
    } else if (status != null) {
      visible = true;
    }
  }
  return foreign && !visible;
});

/// The route string a tap on the strip opens (AC-ST-5): the destination of the
/// winning source (the gym owner's, else `/workouts`; `/record/gps` for a
/// recording).
final activeSessionDestinationProvider = Provider<String>((ref) {
  final dest = ref.watch(activeSessionStatusProvider)?.destination.trim() ?? '';
  return dest.isEmpty ? kActiveSessionDefaultDestination : dest;
});
