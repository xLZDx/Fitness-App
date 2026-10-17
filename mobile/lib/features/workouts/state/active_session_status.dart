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
/// Process death clears both timers (they are in memory); there is no recovery
/// claim (R-S5, F-12).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../data/set_session.dart' show SetPhase;
import 'rest_timer_providers.dart';
import 'set_timer_providers.dart';

/// How long a finished rest keeps the strip visible (contract S-4).
const Duration kRestFinishedVisibleFor = Duration(minutes: 10);

/// Where the strip opens when the owner holds no destination (AC-ST-5).
const String kActiveSessionDefaultDestination = '/workouts';

/// What is being recorded. Future sources (GPS recording, S04) add a value and
/// a producer; the strip itself does not change.
enum ActiveSessionKind { gymWorkout }

/// The strip state words of contract S-4.
enum ActiveSessionState {
  /// A set timer is running: "Workout in progress".
  running,

  /// A set timer or a rest is paused: "Paused".
  paused,

  /// A rest is counting down: "Resting".
  resting,

  /// A rest ran out less than [kRestFinishedVisibleFor] ago: "Rest finished".
  restFinished,
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
      other.ownerUid == ownerUid;

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

/// The strip and pill source. Null means "no session": the shell shows the
/// Record pill (or the idle rail slot). Also null when the session belongs to
/// another account (F-11).
final activeSessionStatusProvider = Provider<ActiveSessionStatus?>((ref) {
  try {
    final core = ref.watch(_activeSessionCoreProvider);
    final owner = ref.watch(activeSessionOwnerProvider);
    final uid =
        ref.watch(authUserProvider.select((u) => u.valueOrNull?.uid));

    // Explicit listener, not a write inside build: when the session ends the
    // owner goes with it, so a later session never inherits a stale route or
    // uid.
    ref.listen<ActiveSessionStatus?>(_activeSessionCoreProvider,
        (previous, next) {
      if (next == null && ref.read(activeSessionOwnerProvider) != null) {
        ref.read(activeSessionOwnerProvider.notifier).clear();
      }
    });

    if (core == null) return null;
    if (owner != null && !_sameUid(owner.uid, uid)) return null;
    return core.withOwner(owner);
  } catch (e) {
    debugPrint('active_session_status: gate_failed ${e.runtimeType}');
    return null;
  }
});

/// True while a session started by another account is still running: the
/// shell then shows neither the strip nor the Record pill (F-11, DT-07-8).
/// The owner is kept so the other account's session is never exposed.
final activeSessionForeignOwnerProvider = Provider<bool>((ref) {
  final owner = ref.watch(activeSessionOwnerProvider);
  if (owner == null) return false;
  final uid = ref.watch(authUserProvider.select((u) => u.valueOrNull?.uid));
  return !_sameUid(owner.uid, uid);
});

/// The route string a tap on the strip opens (AC-ST-5): the owner's
/// destination, else `/workouts`.
final activeSessionDestinationProvider = Provider<String>((ref) {
  final dest = ref.watch(activeSessionOwnerProvider)?.destination.trim() ?? '';
  return dest.isEmpty ? kActiveSessionDefaultDestination : dest;
});
