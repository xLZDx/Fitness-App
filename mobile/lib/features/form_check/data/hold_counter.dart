// Time-in-band counter for hold exercises (plank, glute bridge).
//
// The timer only starts crediting once the body has been in band for an
// unbroken [minHoldMs] (so a flicker through the band is not a hold); the
// qualifying streak is then credited in full. Leaving the band pauses it:
// banked time is kept, the streak restarts, and the next [minHoldMs] of
// continuous band time must elapse before it runs again. A gap between updates
// longer than [maxGapMs] (frames were dropped, the lifter left the picture)
// counts as leaving the band. Time comes from the injected [clock] unless a
// caller passes `atMs` (the frame timestamp), so tests are deterministic.

class HoldCounter {
  HoldCounter({
    required this.minHoldMs,
    int Function()? clock,
    this.maxGapMs = 1500,
  })  : assert(minHoldMs > 0),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int minHoldMs;
  final int maxGapMs;
  final int Function() _clock;

  int _bankedMs = 0;
  int? _streakStartMs;
  int? _lastUpdateMs;

  /// Held time so far, ms, at the last update.
  int get heldMs {
    final start = _streakStartMs;
    final last = _lastUpdateMs;
    if (start == null || last == null) return _bankedMs;
    final streak = last - start;
    return streak >= minHoldMs ? _bankedMs + streak : _bankedMs;
  }

  /// Whether the timer is currently crediting time.
  bool get running {
    final start = _streakStartMs, last = _lastUpdateMs;
    return start != null && last != null && last - start >= minHoldMs;
  }

  void update(bool inBand, {int? atMs}) {
    final now = atMs ?? _clock();
    final last = _lastUpdateMs;
    if (last != null && now - last > maxGapMs) _breakStreak();
    if (!inBand) {
      _breakStreak();
      _lastUpdateMs = now;
      return;
    }
    _streakStartMs ??= now;
    _lastUpdateMs = now;
  }

  void _breakStreak() {
    final start = _streakStartMs, last = _lastUpdateMs;
    if (start != null && last != null && last - start >= minHoldMs) {
      _bankedMs += last - start;
    }
    _streakStartMs = null;
  }

  void reset() {
    _bankedMs = 0;
    _streakStartMs = null;
    _lastUpdateMs = null;
  }
}
