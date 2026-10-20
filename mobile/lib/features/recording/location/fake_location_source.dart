import 'dart:async';

import 'fix.dart';
import 'location_source.dart';

/// Scripted [LocationSource] for tests. Makes no platform call and no network
/// call.
///
/// Time is carried by the scripted [Fix] values themselves, so tests drive any
/// fake clock by choosing `timeUtcMs`.
class FakeLocationSource implements LocationSource {
  FakeLocationSource();

  StreamController<Fix>? _controller;
  bool _listening = false;
  final StreamController<void> _detached = StreamController<void>.broadcast();

  /// Every request passed to [start], in order.
  final List<LocationRequest> startRequests = <LocationRequest>[];

  /// Every value passed to [setInterval] while a subscription was active.
  final List<int> intervalCalls = <int>[];

  /// Total [start] calls, including ones that threw.
  int startCount = 0;

  /// Total [stop] calls.
  int stopCount = 0;

  /// When set, [start] throws this instead of subscribing (scripts a start
  /// failure such as a missing permission).
  Object? startError;

  @override
  int get activeSubscriptions => _listening ? 1 : 0;

  @override
  Stream<void> get engineDetached => _detached.stream;

  @override
  Stream<Fix> start(LocationRequest request) {
    startCount++;
    final error = startError;
    if (error != null) throw error;
    if (_controller != null) {
      throw StateError('LocationSource already started');
    }
    startRequests.add(request);
    final controller = StreamController<Fix>(
      onListen: () => _listening = true,
      onCancel: () {
        _listening = false;
        // A listener cancelling ends the subscription; allow a later start.
        _controller = null;
      },
    );
    _controller = controller;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    final controller = _controller;
    _controller = null;
    _listening = false;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  @override
  Future<void> setInterval(int seconds) async {
    if (_controller == null) return;
    intervalCalls.add(seconds);
  }

  /// Delivers a scripted fix to the active subscriber. No-op when none.
  void emit(Fix fix) {
    final controller = _controller;
    if (controller != null && !controller.isClosed) controller.add(fix);
  }

  /// Delivers a scripted error event to the active subscriber.
  void emitError(Object error) {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.addError(error);
    }
  }

  /// Signals that the engine detached.
  void emitEngineDetached() => _detached.add(null);

  /// Releases the fake's own resources at the end of a test.
  Future<void> dispose() async {
    await stop();
    await _detached.close();
  }
}
