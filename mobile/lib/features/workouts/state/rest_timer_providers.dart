/// The one authoritative rest-timer state.
///
/// ## What was wrong
///
/// The controller was constructed inside `_RestTimerState`
/// (`rest_timer.dart:90`), so it was born and died with the widget. Scrolling
/// the card out of a lazy list, opening the form coach, or backing out to the
/// workout list all destroyed the rest that was in progress — and returning
/// started a fresh one from full. Master prompt §17 asks for "exactly one
/// authoritative timer state"; there was one per mount.
///
/// It also counted ticks. `Timer.periodic(1s)` decremented an integer, which
/// is only the same as measuring time while the process is scheduled at 1 Hz.
/// Android does not promise that: a backgrounded app has its timers coalesced
/// and throttled, so a 90-second rest could report 70 seconds remaining after
/// 90 real ones. The user's phone is in their pocket for the entire duration
/// of the thing being measured, which is the worst possible case for that
/// design.
///
/// ## What replaces it
///
/// A deadline. [RestTimerState.endsAt] is a wall-clock instant, and
/// [RestTimerState.remaining] is a pure function of it and `now`. Backgrounding
/// cannot make a deadline wrong, so foreground restoration needs no code at
/// all — the value is simply recomputed. Everything here is derivable, so the
/// whole state machine is testable with an injected clock and no timers.
///
/// ## Where the clock went
///
/// Nowhere. This file contains no `Timer`. The 1 Hz repaint belongs to the
/// widget, because that is what it is for — a deadline does not need to be
/// woken up to still be true. That is also why "no duplicate clocks" stopped
/// being a hazard rather than becoming a test: two mounted widgets would repaint
/// twice and still read one deadline.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a rest ended. Null while it is still going, or before it starts.
enum RestOutcome {
  /// The deadline passed. This is the one that earns a haptic.
  elapsed,

  /// The user pressed Skip. Deliberately distinct: buzzing someone's phone to
  /// confirm that they pressed the button they just pressed is noise, and the
  /// summary should be able to tell a completed rest from a cut-short one.
  skipped,
}

/// Injectable clock. Overridden in tests; nothing else should touch it.
final restClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// A rest period, described entirely by its deadline.
class RestTimerState {
  const RestTimerState({
    this.total = Duration.zero,
    this.endsAt,
    this.pausedRemaining,
    this.outcome,
  });

  /// The empty state: no rest in progress.
  static const idle = RestTimerState();

  /// What the rest was set to. Grows with every `+30 s`, so the ring's
  /// progress stays honest instead of overflowing past full.
  final Duration total;

  /// When it ends. Null while paused or idle.
  final DateTime? endsAt;

  /// What was left at the moment of pausing. Null unless paused.
  final Duration? pausedRemaining;

  /// Set once, when the rest finishes. Kept afterwards so the card can say
  /// what happened rather than silently reverting to idle.
  final RestOutcome? outcome;

  bool get isIdle => endsAt == null && pausedRemaining == null;
  bool get isPaused => pausedRemaining != null;
  bool get isFinished => outcome != null;

  /// Running means counting down right now — not merely "started".
  bool get isRunning => endsAt != null && outcome == null;

  /// Time left at [now]. Never negative: a deadline that passed while the app
  /// was backgrounded is over, not overdue by two minutes.
  Duration remaining(DateTime now) {
    if (outcome != null) return Duration.zero;
    final paused = pausedRemaining;
    if (paused != null) return paused;
    final end = endsAt;
    if (end == null) return total;
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 0 at the start, 1 at the deadline. Clamped, and safe at `total == 0`.
  double progress(DateTime now) {
    if (total == Duration.zero) return 0;
    final done = total - remaining(now);
    return (done.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  RestTimerState copyWith({
    Duration? total,
    DateTime? endsAt,
    Duration? pausedRemaining,
    RestOutcome? outcome,
    bool clearEndsAt = false,
    bool clearPaused = false,
    bool clearOutcome = false,
  }) =>
      RestTimerState(
        total: total ?? this.total,
        // Explicit clear flags rather than `?? this.x`: every one of these
        // fields legitimately becomes null, and `??` cannot express that. The
        // pause path in particular has to clear the deadline while setting the
        // remainder, and a copyWith that could not would have silently kept a
        // stale deadline that later fired.
        endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
        pausedRemaining:
            clearPaused ? null : (pausedRemaining ?? this.pausedRemaining),
        outcome: clearOutcome ? null : (outcome ?? this.outcome),
      );
}

/// Drives the rest period. App-scoped on purpose — see the library doc.
class RestTimerController extends Notifier<RestTimerState> {
  @override
  RestTimerState build() => RestTimerState.idle;

  DateTime get _now => ref.read(restClockProvider)();

  /// Begins a rest of [duration], replacing anything in progress.
  ///
  /// Idempotent per set is the caller's job, not this method's: "Complete Set"
  /// is what happens once, and a second press of it genuinely should restart
  /// the rest rather than be swallowed.
  void start(Duration duration) {
    state = RestTimerState(total: duration, endsAt: _now.add(duration));
  }

  void pause() {
    if (!isRunningAt(_now)) return;
    state = state.copyWith(
      pausedRemaining: state.remaining(_now),
      clearEndsAt: true,
    );
  }

  void resume() {
    final left = state.pausedRemaining;
    if (left == null) return;
    // Re-derived from `now`, not from the old deadline: the pause may have
    // lasted a minute, and the rest owes the user what was left, not what the
    // clock said before.
    state = state.copyWith(endsAt: _now.add(left), clearPaused: true);
  }

  /// Adds [extra] (30 seconds from the UI) to a running or paused rest.
  ///
  /// Also grows [RestTimerState.total], so the ring reads 60% rather than
  /// pinning at 100% with a minute still to go.
  void addTime(Duration extra) {
    if (state.isIdle || state.isFinished) return;
    final paused = state.pausedRemaining;
    if (paused != null) {
      state = state.copyWith(
        total: state.total + extra,
        pausedRemaining: paused + extra,
      );
      return;
    }
    state = state.copyWith(
      total: state.total + extra,
      endsAt: state.endsAt!.add(extra),
    );
  }

  /// Ends the rest now, by the user's choice.
  void skip() {
    if (state.isIdle || state.isFinished) return;
    state = state.copyWith(
      outcome: RestOutcome.skipped,
      clearEndsAt: true,
      clearPaused: true,
    );
  }

  /// Records that the deadline passed. Called by the UI's ticker, which is the
  /// only thing that observes the moment it happens.
  ///
  /// Guarded rather than trusting: a repaint can arrive early, and marking a
  /// rest complete a second before it is would fire the haptic and hand the
  /// user back to the bar.
  void completeIfElapsed() {
    if (!state.isRunning) return;
    if (state.remaining(_now) > Duration.zero) return;
    state = state.copyWith(outcome: RestOutcome.elapsed, clearEndsAt: true);
  }

  /// Back to nothing — used when the set is left behind, not when it ends.
  void clear() => state = RestTimerState.idle;

  bool isRunningAt(DateTime now) =>
      state.isRunning && state.remaining(now) > Duration.zero;
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(
        RestTimerController.new);
