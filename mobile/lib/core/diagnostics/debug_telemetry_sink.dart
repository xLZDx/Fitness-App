import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../firebase/functions_region.dart';
import 'debug_telemetry.dart';
import 'debug_telemetry_schema.dart';

/// Where a session log goes. An interface so a test can assert what would have
/// been uploaded without a network, and so the upload can be swapped for a
/// file or a function endpoint later without touching a caller.
abstract interface class DebugTelemetrySink {
  Future<void> send(Map<String, Object?> payload);
}

/// Sends one batch to the `sendDebugTelemetry` callable. Injectable so a test
/// can fail it, delay it, or record what would have been sent.
typedef TelemetryCallableInvoker = Future<void> Function(
    Map<String, Object?> batch);

Future<void> _invokeSendDebugTelemetry(Map<String, Object?> batch) async {
  await functionsForRegion.httpsCallable('sendDebugTelemetry').call<Object?>(batch);
}

/// Sends the session through the server-side sanitising callable
/// `sendDebugTelemetry` (S02 design 8.1; GPS-PRIV-050 / 098). The client no
/// longer writes `debug_sessions`: the callable owns the closed schema, the
/// uid and the timestamp, and rules refuse every client create.
///
/// The session payload is converted to the closed schema: each event keeps
/// only its level and a `component` from an enumeration (the free-text message
/// and the free-form build identity are NOT sent; Phase 1 behaviour change,
/// recorded in the S02-09 change record). Batches hold at most
/// [kTelemetryMaxEvents] events.
///
/// Resilience (design 8.1):
/// - [send] NEVER throws and does NOT wait for the network: it queues the events
///   and starts a background drain; [flush] awaits that drain (tests, shutdown).
/// - A failed batch is retried at most [maxRetries] times with doubling backoff.
///   If it still fails, its events stay in a local buffer for the next [send].
/// - The buffer holds at most [maxBufferEvents] events and [maxBufferBytes]
///   bytes of serialised events; the OLDEST are dropped first and counted.
/// - The dropped count is reported (capped at [kTelemetryCounterMax]) in the
///   next batch that is delivered, then reset.
class CallableDebugTelemetrySink implements DebugTelemetrySink {
  CallableDebugTelemetrySink({
    TelemetryCallableInvoker? invoke,
    Future<void> Function(Duration)? delay,
    this.maxRetries = 3,
    this.baseBackoff = const Duration(seconds: 1),
    this.maxBufferEvents = 500,
    this.maxBufferBytes = 64 * 1024,
  })  : _invoke = invoke ?? _invokeSendDebugTelemetry,
        _delay = delay ?? Future<void>.delayed;

  final TelemetryCallableInvoker _invoke;
  final Future<void> Function(Duration) _delay;
  final int maxRetries;
  final Duration baseBackoff;
  final int maxBufferEvents;
  final int maxBufferBytes;

  /// Events waiting for delivery, oldest first (closed-schema maps without `seq`).
  final List<Map<String, Object?>> _buffer = [];
  int _bufferBytes = 0;
  int _inFlightCount = 0; // leading events of _buffer being sent now
  int _pendingDropped = 0;
  int _carriedDropped = 0;
  Future<void>? _drain;

  /// Events lost to buffer overflow and not yet reported (uncapped locally).
  int get pendingDropped => _pendingDropped;

  /// Events currently held for delivery (queued plus in flight).
  int get bufferedCount => _buffer.length;

  /// Serialised size of the events currently held.
  int get bufferedBytes => _bufferBytes;

  static int _sizeOf(Map<String, Object?> e) => utf8.encode(jsonEncode(e)).length;

  void _enqueue(Map<String, Object?> payload) {
    final raw = payload['events'];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final level = telemetryLevelFor('${e['level']}');
        final event = <String, Object?>{
          'type': level == 'error' ? 'error' : 'log',
          'level': level,
          'component': telemetryComponentFor('${e['area']}'),
        };
        _buffer.add(event);
        _bufferBytes += _sizeOf(event);
      }
    }
    final carried = payload['droppedCount'];
    if (carried is int && carried > 0) _carriedDropped = carried;
    _trim();
  }

  /// Drops the oldest queued events until both caps hold.
  void _trim() {
    while (_buffer.isNotEmpty &&
        (bufferedCount > maxBufferEvents || bufferedBytes > maxBufferBytes)) {
      _bufferBytes -= _sizeOf(_buffer.removeAt(0));
      if (_inFlightCount > 0) _inFlightCount--;
      _pendingDropped++;
    }
  }

  @override
  Future<void> send(Map<String, Object?> payload) async {
    try {
      _enqueue(payload);
      _drain ??= _drainLoop().whenComplete(() => _drain = null);
    } catch (_) {
      // Never throws into app flow (design 8.1).
    }
  }

  /// Completes when the running drain (if any) has finished. Never throws.
  Future<void> flush() async {
    while (_drain != null) {
      await _drain;
    }
  }

  Future<void> _drainLoop() async {
    try {
      while (true) {
        final reportedPending = _pendingDropped;
        final dropped = reportedPending + _carriedDropped;
        if (_buffer.isEmpty && dropped == 0) return;
        final n = _buffer.length < kTelemetryMaxEvents
            ? _buffer.length
            : kTelemetryMaxEvents;
        // The chunk stays in the buffer while it is sent, so the caps always
        // count it and an overflow evicts the OLDEST event, in flight or not.
        final chunk = _buffer.sublist(0, n);
        _inFlightCount = n;
        final batch = <String, Object?>{
          'events': [
            for (var i = 0; i < n; i++) {...chunk[i], 'seq': i},
          ],
        };
        if (dropped > 0) batch['droppedCount'] = telemetryCounter(dropped);
        final ok = await _sendWithRetry(batch);
        // Events evicted during the send no longer count as in flight.
        final sent = _inFlightCount;
        _inFlightCount = 0;
        if (!ok) return;
        for (var i = 0; i < sent; i++) {
          _bufferBytes -= _sizeOf(_buffer.removeAt(0));
        }
        _pendingDropped -= reportedPending;
        _carriedDropped = 0;
      }
    } catch (_) {
      // Never throws (design 8.1).
    }
  }

  Future<bool> _sendWithRetry(Map<String, Object?> batch) async {
    var wait = baseBackoff;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _invoke(batch);
        return true;
      } catch (_) {
        if (attempt == maxRetries) return false;
        await _delay(wait);
        wait *= 2;
      }
    }
    return false;
  }
}

/// Installs [telemetry] as the destination for every `debugPrint` in the app.
///
/// This is the "log everything" half. `debugPrint` is what this codebase
/// already uses for the interesting failures — a swallowed clip-signing error,
/// a camera that refused, a recognition that fell back on-device — and every
/// one of those lines currently exists only in a console nobody is attached
/// to when the app is on the operator's phone in a gym.
///
/// The original is kept and still called, so `flutter run` behaves exactly as
/// before: this adds a listener, it does not take the console away.
///
/// Returns a function that restores the previous `debugPrint`. Tests must call
/// it — `debugPrint` is process-global, and a capture left installed would
/// quietly accumulate every later test's output.
void Function() captureDebugPrint(DebugTelemetry telemetry) {
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) telemetry.log('print', message);
    previous(message, wrapWidth: wrapWidth);
  };
  return () => debugPrint = previous;
}
