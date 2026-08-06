/// The one authoritative rest-timer state.
///
/// ## What was wrong, twice
///
/// **First**, the controller was constructed inside `_RestTimerState`, so it
/// was born and died with the widget. Scrolling the card out of a lazy list,
/// opening the form coach, or backing out to the workout list all destroyed the
/// rest in progress, and returning started a fresh one from full.
///
/// **Second** — and this one was introduced by the fix for the first, then
/// found by two independent reviewers on the same day — moving the state into a
/// provider was not enough while *finishing* still required an observer. The
/// only thing that could mark a rest elapsed was a ticker inside the mounted
/// card. Leaving the page mid-rest, which is what a person waiting out 90 to
/// 180 seconds actually does, cancelled that ticker and left the rest running
/// against a deadline in the past forever.
///
/// ## The rule that fixes both
///
/// **Nothing about a rest is stored that can be derived from the clock.**
/// [RestTimerState.endsAt] is a wall-clock instant; [RestTimerState.remaining]
/// and [RestTimerState.outcomeAt] are pure functions of it and `now`. An
/// unobserved rest still ends, because ending is not an event anything has to
/// witness — it is a comparison.
///
/// The one exception is a skip, and it is not an exception to the rule: a skip
/// cannot be derived from the clock because it is a decision, and it can only
/// be made while the card is on screen, because the button is on the card.
///
/// ## Where the clock went
///
/// Nowhere. This file contains no `Timer`. The 1 Hz repaint belongs to the
/// widget, because that is all it is — a deadline does not need to be woken up
/// to still be true. Two mounted cards would repaint twice and read one
/// deadline; that is why duplicate clocks stopped being a hazard rather than
/// becoming a test.
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
    this.skipped = false,
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

  /// Whether the user cut it short. The only part of the outcome that is
  /// stored rather than derived — see the library doc.
  final bool skipped;

  bool get isIdle => endsAt == null && pausedRemaining == null && !skipped;
  bool get isPaused => pausedRemaining != null;

  /// How this rest ended at [now], or null if it has not.
  ///
  /// Derived, so no observer has to be alive for it to become true.
  RestOutcome? outcomeAt(DateTime now) {
    if (skipped) return RestOutcome.skipped;
    final end = endsAt;
    if (end == null) return null;
    return now.isBefore(end) ? null : RestOutcome.elapsed;
  }

  bool isFinishedAt(DateTime now) => outcomeAt(now) != null;

  /// Counting down right now — not merely "started".
  bool isRunningAt(DateTime now) => endsAt != null && !isFinishedAt(now);

  /// Time left at [now]. Never negative: a deadline that passed while the app
  /// was in a pocket is over, not overdue by two minutes.
  Duration remaining(DateTime now) {
    if (skipped) return Duration.zero;
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
    bool? skipped,
    bool clearEndsAt = false,
    bool clearPaused = false,
  }) =>
      RestTimerState(
        total: total ?? this.total,
        // Explicit clear flags rather than `?? this.x`: both of these fields
        // legitimately become null, and `??` cannot express that. The pause
        // path has to clear the deadline while setting the remainder, and a
        // copyWith that could not would silently keep a stale deadline that
        // later reported the rest as elapsed.
        endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
        pausedRemaining:
            clearPaused ? null : (pausedRemaining ?? this.pausedRemaining),
        skipped: skipped ?? this.skipped,
      );
}

/// Drives the rest period. App-scoped on purpose — see the library doc.
class RestTimerController extends Notifier<RestTimerState> {
  @override
  RestTimerState build() => RestTimerState.idle;

  DateTime get _now => ref.read(restClockProvider)();

  /// Begins a rest of [duration], replacing anything in progress.
  ///
  /// Idempotence per set is the caller's job, not this method's: "Complete Set"
  /// is what happens once, and a second press of it genuinely should restart
  /// the rest rather than be swallowed.
  void start(Duration duration) {
    state = RestTimerState(total: duration, endsAt: _now.add(duration));
  }

  void pause() {
    final now = _now;
    if (!state.isRunningAt(now)) return;
    state = state.copyWith(
      pausedRemaining: state.remaining(now),
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
    final now = _now;
    if (state.isIdle || state.isFinishedAt(now)) return;
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
    final now = _now;
    if (state.isIdle || state.isFinishedAt(now)) return;
    state = state.copyWith(skipped: true, clearEndsAt: true, clearPaused: true);
  }

  /// Back to nothing.
  ///
  /// Called when the user acknowledges a finished rest, so the card can leave
  /// the screen without waiting for the next set to be logged.
  void clear() => state = RestTimerState.idle;
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState>(
        RestTimerController.new);

/// Whether the rest card belongs on screen.
///
/// Derived from the rest itself rather than from a page-local flag. The flag
/// version (`_restTimerVisibleProvider`, a `StateProvider.autoDispose` in
/// `workout_player_page.dart`) was the second half of the same defect the
/// library doc describes: it reset to `false` when the page was popped, so a
/// rest that survived navigation — as designed — had no way back onto the
/// screen. The user saw the timer vanish with no indication it was ever there.
final restTimerVisibleProvider = Provider<bool>((ref) {
  return !ref.watch(restTimerProvider).isIdle;
});
