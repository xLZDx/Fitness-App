/// Hands-free shutter: readiness held for a while, then a 3-2-1 countdown, then
/// the shot.
///
/// A pure state machine. It owns NO timers and reads NO clock: the caller feeds
/// `update(nowMs, ready)` from whatever drives it (every analysed frame in the
/// app, a fake clock in tests) and reacts to the returned events with voice,
/// haptics and the actual capture. Because the schedule is anchored to the
/// moment readiness began, not to the moment an update happened to arrive, the
/// shutter time does not drift with frame jitter.
///
/// States: idle -> holding -> countdown -> (shutter) cooldown -> idle.
///
/// * idle: waiting for `ready`.
/// * holding: ready continuously; after [AutoShutterConfig.holdMs] the countdown
///   starts.
/// * countdown: ticks 3, 2, 1, one per [AutoShutterConfig.tickMs]; the shutter
///   fires one tick after the "1".
/// * cooldown: [AutoShutterConfig.cooldownMs] after the shot nothing can start;
///   this is the minimum gap between two shots.
///
/// ANY not-ready update during holding or countdown cancels back to idle with a
/// `cancelled` event (no grace window, per the product rule), including an
/// update that arrives exactly at the shutter time. Readiness is checked before
/// time is advanced, so a body that left the frame never gets photographed. A
/// gap longer than [AutoShutterConfig.maxFrameGapMs] between updates, or a clock
/// that goes backwards, is treated as lost readiness: we cannot vouch for a
/// stretch we did not observe.
library;

enum ShutterState { idle, holding, countdown, cooldown }

enum ShutterEventType {
  /// Readiness began; the hold period started.
  holdStart,

  /// Countdown number in [ShutterEvent.value] (3, 2 or 1).
  tick,

  /// Take the photo now.
  shutter,

  /// Readiness was lost (or observation lapsed) before the shutter.
  cancelled,

  /// The pose is finished; emitted in the same update right after [shutter] so
  /// the UI can advance to the next pose. The cooldown keeps the machine from
  /// firing again until it ends.
  poseDone,
}

class ShutterEvent {
  const ShutterEvent(this.type, this.atMs, [this.value]);

  final ShutterEventType type;

  /// Time of the update that produced the event.
  final int atMs;

  /// Countdown number for [ShutterEventType.tick].
  final int? value;

  @override
  String toString() => 'ShutterEvent($type${value == null ? '' : ' $value'} @$atMs)';

  @override
  bool operator ==(Object other) =>
      other is ShutterEvent &&
      other.type == type &&
      other.atMs == atMs &&
      other.value == value;

  @override
  int get hashCode => Object.hash(type, atMs, value);
}

class AutoShutterConfig {
  const AutoShutterConfig({
    this.holdMs = 1000,
    this.tickMs = 1000,
    this.countdownFrom = 3,
    this.cooldownMs = 3000,
    this.maxFrameGapMs = 500,
  })  : assert(holdMs >= 0),
        assert(tickMs > 0),
        assert(countdownFrom >= 1),
        assert(cooldownMs >= 0),
        assert(maxFrameGapMs > 0);

  /// Readiness must hold this long before the countdown starts.
  final int holdMs;
  final int tickMs;
  final int countdownFrom;

  /// Minimum time after a shot before readiness is looked at again.
  final int cooldownMs;

  /// Longest tolerated silence between two updates while holding/counting.
  final int maxFrameGapMs;
}

class AutoShutterMachine {
  AutoShutterMachine({this.config = const AutoShutterConfig()});

  final AutoShutterConfig config;

  ShutterState _state = ShutterState.idle;
  int _holdStartMs = 0;
  int _cooldownEndMs = 0;
  int _lastUpdateMs = 0;
  int _ticksEmitted = 0;

  ShutterState get state => _state;

  /// The countdown number currently on screen, or null outside the countdown.
  int? get currentTick =>
      _state == ShutterState.countdown && _ticksEmitted > 0
          ? config.countdownFrom - _ticksEmitted + 1
          : null;

  /// Drop everything and return to idle without events (e.g. the capture failed
  /// or the user left the screen).
  void reset() {
    _state = ShutterState.idle;
    _ticksEmitted = 0;
  }

  int get _countdownStartMs => _holdStartMs + config.holdMs;
  int get _shutterAtMs =>
      _countdownStartMs + config.countdownFrom * config.tickMs;

  /// Feed one observation. Returns the events it caused, in order.
  List<ShutterEvent> update(int nowMs, {required bool ready}) {
    final events = <ShutterEvent>[];
    final active =
        _state == ShutterState.holding || _state == ShutterState.countdown;

    if (active) {
      final gap = nowMs - _lastUpdateMs;
      if (!ready || gap < 0 || gap > config.maxFrameGapMs) {
        _lastUpdateMs = nowMs;
        _cancel(nowMs, events);
        return events;
      }
    }
    _lastUpdateMs = nowMs;

    switch (_state) {
      case ShutterState.cooldown:
        if (nowMs >= _cooldownEndMs) {
          _state = ShutterState.idle;
          if (ready) _beginHold(nowMs, events);
        }
      case ShutterState.idle:
        if (ready) _beginHold(nowMs, events);
      case ShutterState.holding:
      case ShutterState.countdown:
        _advance(nowMs, events);
    }
    return events;
  }

  void _beginHold(int nowMs, List<ShutterEvent> events) {
    _state = ShutterState.holding;
    _holdStartMs = nowMs;
    _ticksEmitted = 0;
    events.add(ShutterEvent(ShutterEventType.holdStart, nowMs));
    // A zero hold with a coarse update could already be due; handle uniformly.
    _advance(nowMs, events);
  }

  void _advance(int nowMs, List<ShutterEvent> events) {
    // Emit every tick whose anchored time has passed (normally just one).
    while (_ticksEmitted < config.countdownFrom &&
        nowMs >= _countdownStartMs + _ticksEmitted * config.tickMs) {
      _state = ShutterState.countdown;
      events.add(ShutterEvent(
        ShutterEventType.tick,
        nowMs,
        config.countdownFrom - _ticksEmitted,
      ));
      _ticksEmitted++;
    }
    if (_ticksEmitted == config.countdownFrom && nowMs >= _shutterAtMs) {
      events.add(ShutterEvent(ShutterEventType.shutter, nowMs));
      events.add(ShutterEvent(ShutterEventType.poseDone, nowMs));
      _state = ShutterState.cooldown;
      _cooldownEndMs = nowMs + config.cooldownMs;
      _ticksEmitted = 0;
    }
  }

  void _cancel(int nowMs, List<ShutterEvent> events) {
    _state = ShutterState.idle;
    _ticksEmitted = 0;
    events.add(ShutterEvent(ShutterEventType.cancelled, nowMs));
  }
}
