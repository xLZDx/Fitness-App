import 'dart:async';

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
/// Resilience (design 8.1): [send] NEVER throws. A failed batch is retried at
/// most [maxRetries] times with doubling backoff; if it still fails its events
/// are counted as dropped and the (capped) count is reported in the next batch.
/// Nothing is buffered beyond the session's own bounded ring buffer.
class CallableDebugTelemetrySink implements DebugTelemetrySink {
  CallableDebugTelemetrySink({
    TelemetryCallableInvoker? invoke,
    Future<void> Function(Duration)? delay,
    this.maxRetries = 3,
    this.baseBackoff = const Duration(seconds: 1),
  })  : _invoke = invoke ?? _invokeSendDebugTelemetry,
        _delay = delay ?? Future<void>.delayed;

  final TelemetryCallableInvoker _invoke;
  final Future<void> Function(Duration) _delay;
  final int maxRetries;
  final Duration baseBackoff;

  int _pendingDropped = 0;

  /// Events lost to failed sends and not yet reported (uncapped locally).
  int get pendingDropped => _pendingDropped;

  /// Converts the session JSON into closed-schema batches.
  @visibleForTesting
  List<Map<String, Object?>> buildBatches(Map<String, Object?> payload) {
    final raw = payload['events'];
    final events = <Map<String, Object?>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final level = telemetryLevelFor('${e['level']}');
        events.add({
          'type': level == 'error' ? 'error' : 'log',
          'level': level,
          'component': telemetryComponentFor('${e['area']}'),
        });
      }
    }
    final carried = payload['droppedCount'];
    final dropped = _pendingDropped + (carried is int ? carried : 0);
    final batches = <Map<String, Object?>>[];
    for (var i = 0; i < events.length || batches.isEmpty; i += kTelemetryMaxEvents) {
      final end = i + kTelemetryMaxEvents < events.length
          ? i + kTelemetryMaxEvents
          : events.length;
      final chunk = events.sublist(i, end);
      final batch = <String, Object?>{
        'events': [
          for (var n = 0; n < chunk.length; n++) {...chunk[n], 'seq': n},
        ],
      };
      if (batches.isEmpty && dropped > 0) {
        batch['droppedCount'] = telemetryCounter(dropped);
      }
      batches.add(batch);
      if (end >= events.length) break;
    }
    if (dropped == 0 && batches.length == 1 && events.isEmpty) return const [];
    return batches;
  }

  @override
  Future<void> send(Map<String, Object?> payload) async {
    try {
      final batches = buildBatches(payload);
      final reported = _pendingDropped;
      _pendingDropped = 0;
      var first = true;
      for (final batch in batches) {
        final ok = await _sendWithRetry(batch);
        if (!ok) {
          final n = (batch['events'] as List).length;
          _pendingDropped += n + (first ? reported : 0);
        }
        first = false;
      }
    } catch (_) {
      // Never throws into app flow (design 8.1); nothing to report to.
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
