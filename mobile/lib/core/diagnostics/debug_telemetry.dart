import 'dart:collection';

/// B6 — what the app was actually doing, on the operator's own phone.
///
/// ## Why this exists
///
/// The emulator cannot reproduce the things that break: native permission
/// dialogs, a real camera, a real network, and — the one that cost a whole
/// session on 2026-08-07 — WHICH BUILD is installed. The operator reported
/// photographs of people in the catalogue and sent screenshots dated 06.08.
/// The photographs had been removed on 03.08 (`88d0759`). Three days and a
/// long investigation went into establishing that the screenshots came from a
/// stale APK, and every minute of it would have been saved by one line saying
/// which build produced them.
///
/// So [SessionIdentity] is not a nicety attached to the log. It is the first
/// thing written, and the reason the log exists at all.
///
/// ## Why it is not Crashlytics
///
/// Crashlytics reports crashes; this reports a session that did NOT crash and
/// still did the wrong thing. They are also inverted by design — Crashlytics
/// is switched off in debug builds (`main.dart:109`) precisely so hot-reload
/// noise stays out of production signal, which is exactly the build this needs
/// to describe.
///
/// ## Debug builds only
///
/// This app holds health data, body-composition estimates and progress
/// photographs. A "log everything and upload it" switch belongs nowhere near a
/// release build, whatever it is defaulted to. The guard is a dart-define
/// rather than `kReleaseMode` for the reason the tier override already
/// documents: `flutter test` runs in debug, so a `kReleaseMode` guard is inert
/// in every test and would let this suite pass while proving nothing about the
/// shipped build.
const bool kDebugTelemetryEnabled =
    bool.fromEnvironment('DEBUG_TELEMETRY', defaultValue: true);

/// Identifies the build that produced a log. Written first, every time.
class SessionIdentity {
  const SessionIdentity({
    required this.appVersion,
    required this.buildNumber,
    required this.gitSha,
    required this.platform,
    required this.builtAt,
  });

  /// From pubspec `version:` — `1.0.0+14` splits into these two.
  final String appVersion;
  final String buildNumber;

  /// `--dart-define=GIT_SHA=$(git rev-parse --short HEAD)` at build time.
  ///
  /// 'unknown' when nobody passed it, and that is itself worth reading: a
  /// build assembled outside the project's own build command cannot be traced
  /// back to a commit, so a log claiming a fix is present cannot be believed.
  final String gitSha;
  final String platform;

  /// `--dart-define=BUILT_AT=<iso8601>`. The answer to "is this APK older than
  /// the fix?" without needing to ask anybody.
  final String builtAt;

  Map<String, Object?> toJson() => {
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'gitSha': gitSha,
        'platform': platform,
        'builtAt': builtAt,
      };
}

enum LogLevel { debug, info, warn, error }

class LogEvent {
  const LogEvent({
    required this.at,
    required this.level,
    required this.area,
    required this.message,
  });

  final DateTime at;
  final LogLevel level;

  /// Coarse subsystem tag — 'scanner', 'camera', 'catalog'. Free-form on
  /// purpose: an enum here would need editing every time a subsystem wants to
  /// report, and the friction is what stops it reporting.
  final String area;
  final String message;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'level': level.name,
        'area': area,
        'message': message,
      };
}

/// Strips the things that must never leave the device.
///
/// Deliberately conservative and deliberately dumb: it over-redacts rather
/// than reasoning about context. A log line that reads `[email]` where a
/// harmless word stood is a minor annoyance; a log line carrying a real
/// address is a privacy incident, and no amount of cleverness is worth that
/// asymmetry.
///
/// It is NOT the only defence — the rule is that callers do not log personal
/// data in the first place. This catches the accident, not the intent.
String redact(String input) {
  var out = input;
  // Email addresses.
  out = out.replaceAll(
      RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+', caseSensitive: false), '[email]');
  // Bearer / API tokens and long opaque blobs. 24+ chars of base64-ish text is
  // not prose; nothing legitimate in a log line looks like that.
  out = out.replaceAll(RegExp(r'\b[A-Za-z0-9_\-]{24,}\b'), '[token]');
  // Absolute paths under a user's home / app sandbox, which carry the account
  // name on desktop and the app+user ids on device.
  out = out.replaceAll(
      RegExp(r'(/(?:Users|home|data/user/\d+)/[^\s"]+)'), '[path]');
  out = out.replaceAll(
      RegExp(r'([A-Za-z]:\\Users\\[^\s"]+)', caseSensitive: false), '[path]');
  // Runs of 7+ digits: phone numbers, ids, anything measured in a person.
  out = out.replaceAll(RegExp(r'\b\d{7,}\b'), '[number]');
  return out;
}

/// A bounded, in-memory session log.
///
/// Bounded is load-bearing. A live-recognition session emits per frame, and an
/// unbounded buffer on a phone pointed at a machine for ten minutes is an
/// out-of-memory crash caused by the diagnostics — the tool breaking the thing
/// it was installed to observe. The oldest events are dropped, and
/// [droppedCount] says how many, so a truncated log cannot be mistaken for a
/// complete one.
class DebugTelemetry {
  DebugTelemetry({
    required this.identity,
    this.capacity = 500,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        assert(capacity > 0);

  final SessionIdentity identity;
  final int capacity;
  final DateTime Function() _now;

  final Queue<LogEvent> _events = Queue<LogEvent>();
  int _dropped = 0;

  /// Events still held, oldest first.
  List<LogEvent> get events => List.unmodifiable(_events);

  /// How many events fell out of the buffer. Non-zero means the log is a
  /// window, not a transcript.
  int get droppedCount => _dropped;

  void log(String area, String message, {LogLevel level = LogLevel.info}) {
    if (!kDebugTelemetryEnabled) return;
    _events.add(LogEvent(
      at: _now(),
      level: level,
      area: area,
      message: redact(message),
    ));
    while (_events.length > capacity) {
      _events.removeFirst();
      _dropped++;
    }
  }

  /// The payload an uploader sends. Identity first — see the class doc.
  Map<String, Object?> toJson() => {
        'identity': identity.toJson(),
        'droppedCount': _dropped,
        'events': [for (final e in _events) e.toJson()],
      };
}
