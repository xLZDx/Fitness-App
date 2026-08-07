import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'debug_telemetry.dart';

/// Where a session log goes. An interface so a test can assert what would have
/// been uploaded without a network, and so the upload can be swapped for a
/// file or a function endpoint later without touching a caller.
abstract interface class DebugTelemetrySink {
  Future<void> send(Map<String, Object?> payload);
}

/// Writes the session to `debug_sessions/{id}`.
///
/// Firestore rather than a new endpoint: the project already holds a Firestore
/// client, rules and an authenticated user, and standing up a second transport
/// for the same bytes would be a second thing to secure and keep alive.
///
/// **Rules must restrict `debug_sessions` to the operator's own uid.** This
/// collection is written by a build that logs what the app is doing; it is not
/// user content and no client should be able to read another's. That rule is
/// not shipped by this file — it lives in `firestore.rules` and is listed as
/// outstanding in the gate report rather than assumed.
class FirestoreDebugTelemetrySink implements DebugTelemetrySink {
  FirestoreDebugTelemetrySink({FirebaseFirestore? db, String? uid})
      : _injected = db,
        _uid = uid;

  final FirebaseFirestore? _injected;
  final String? _uid;

  FirebaseFirestore get _db => _injected ?? FirebaseFirestore.instance;

  @override
  Future<void> send(Map<String, Object?> payload) async {
    await _db.collection('debug_sessions').add({
      ...payload,
      'uid': _uid,
      'receivedAt': FieldValue.serverTimestamp(),
    });
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
