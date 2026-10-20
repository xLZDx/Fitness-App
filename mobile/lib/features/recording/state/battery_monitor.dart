/// Battery seam and policy (S04 design 8.1, S04-22). The package or channel
/// behind [BatteryMonitor] is undecided (D-14); only this interface is fixed.
library;

import 'dart:async';

import 'recorder_state_constants.dart';

/// One battery reading.
class BatteryReading {
  const BatteryReading({required this.percent, required this.charging});

  /// 0 to 100.
  final int percent;
  final bool charging;

  @override
  bool operator ==(Object other) =>
      other is BatteryReading &&
      other.percent == percent &&
      other.charging == charging;

  @override
  int get hashCode => Object.hash(percent, charging);

  @override
  String toString() => 'BatteryReading($percent, charging=$charging)';
}

/// The battery seam.
abstract class BatteryMonitor {
  /// The current reading, or null when the platform gives none.
  Future<BatteryReading?> current();

  /// Subsequent readings. Implementations make no network call.
  Stream<BatteryReading> get readings;
}

/// Pure thresholds (S04-22, design 8.1). Charging never enters the state.
class BatteryPolicy {
  const BatteryPolicy._();

  /// At or below 10 percent and not charging: flag `batteryCritical`.
  static bool entersCritical(BatteryReading r) =>
      !r.charging && r.percent <= kBatteryCriticalPercent;

  /// Leaves the state at charging or at 12 percent (hysteresis).
  static bool leavesCritical(BatteryReading r) =>
      r.charging || r.percent >= kBatteryCriticalExitPercent;

  /// At or below 3 percent and not charging: finish, save, reason `battery`.
  static bool finishes(BatteryReading r) =>
      !r.charging && r.percent <= kBatteryFinishPercent;
}

/// Scripted battery for tests and for builds without a battery source.
class FakeBatteryMonitor implements BatteryMonitor {
  FakeBatteryMonitor([this._current]);

  BatteryReading? _current;
  final StreamController<BatteryReading> _controller =
      StreamController<BatteryReading>.broadcast();

  @override
  Future<BatteryReading?> current() async => _current;

  @override
  Stream<BatteryReading> get readings => _controller.stream;

  /// Sets the current value and emits it.
  void emit(int percent, {bool charging = false}) {
    _current = BatteryReading(percent: percent, charging: charging);
    _controller.add(_current!);
  }

  Future<void> dispose() => _controller.close();
}
