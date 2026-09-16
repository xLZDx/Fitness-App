import 'package:cloud_functions/cloud_functions.dart';

/// Mirrors `functions-equipment-identity/src/p2/telemetry_contract.ts`'s
/// `LocalFailureReasonSchema` -- design doc §4.2. All four happen strictly
/// BEFORE any network call, which is what separates this enum from
/// [RequestFailureReason] below.
enum LocalFailureReason {
  missingImagePath,
  missingStructuredRecognizer,
  ocrException,
  parserException,
}

/// Mirrors `telemetry_contract.ts`'s `RequestFailureReasonSchema` -- design
/// doc §4.2a.
enum RequestFailureReason {
  networkUnreachable,
  timeout,
  appCheckOrAuth,
  rateLimited,
  backendError,
  unknownClientError,
  malformedReply,
}

/// Classifies whatever `CloudEquipmentIdentityService.resolveFromText`
/// actually throws (that class's own doc comment: a
/// `FirebaseFunctionsException` from the callable itself, or a
/// `FormatException` from `EquipmentIdentity.fromJson` after a reply already
/// arrived) into one [RequestFailureReason]. Pure -- no I/O, no platform
/// calls -- so every branch is unit-testable without a device, the same
/// shape as `video_failure.dart`'s `classifyVideoFailure`.
///
/// `FirebaseFunctionsException.code` values mirror the underlying gRPC
/// status codes `cloud_functions` surfaces from an `onCall` failure.
/// `unauthenticated`/`permission-denied` both map to [appCheckOrAuth]: a
/// Callable v2 App Check rejection and an auth rejection are
/// indistinguishable from the client's own error code alone, and both mean
/// the same thing to this telemetry signal -- the request never reached the
/// server's own business logic. Anything not explicitly named falls to
/// [RequestFailureReason.unknownClientError], so this classifier never needs
/// to enumerate every possible code to stay exhaustive (mirrors
/// `RequestFailureReasonSchema`'s own doc comment server-side).
RequestFailureReason classifyRequestFailureReason(Object error) {
  if (error is FormatException) return RequestFailureReason.malformedReply;
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'deadline-exceeded':
        return RequestFailureReason.timeout;
      case 'unavailable':
        return RequestFailureReason.networkUnreachable;
      case 'unauthenticated':
      case 'permission-denied':
        return RequestFailureReason.appCheckOrAuth;
      case 'resource-exhausted':
        return RequestFailureReason.rateLimited;
      case 'internal':
      case 'aborted':
      case 'data-loss':
        return RequestFailureReason.backendError;
      default:
        return RequestFailureReason.unknownClientError;
    }
  }
  return RequestFailureReason.unknownClientError;
}

/// Parses the mint instant already embedded in a `scanId` minted as
/// `'scan-${DateTime.now().microsecondsSinceEpoch}'` (`scanner_page.dart`'s
/// `_classify`) into the UTC RFC3339 string the telemetry contract requires
/// -- design doc §5.4: no new mobile state needed, and a retry reuses the
/// SAME scanId, so this correctly reads as the ORIGINAL attempt's start even
/// across a retry. Returns null on a scanId that does not match the
/// expected shape (defensive -- every real scanId this app mints does)
/// rather than fabricating a timestamp.
String? parseScanStartedAt(String scanId) {
  const prefix = 'scan-';
  if (!scanId.startsWith(prefix)) return null;
  final micros = int.tryParse(scanId.substring(prefix.length));
  if (micros == null) return null;
  return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toIso8601String();
}

/// `DateTime.now().toUtc().toIso8601String()` -- never bare `DateTime.now()`
/// (design doc §5.4: Dart's `toIso8601String()` omits the `Z` suffix for a
/// non-UTC value, which the server's strict RFC3339 validator rejects).
/// Wrapped so every call site uses the identical construction.
String nowUtcIso() => DateTime.now().toUtc().toIso8601String();

/// Request bodies for `equipmentIdentityRecordTelemetry`
/// (`telemetry_contract.ts`'s `EquipmentIdentityTelemetryReportRequestSchema`
/// -- exactly 3 shapes; see that file's own header for the authority split
/// that makes these the ONLY 3 shapes a mobile client may ever send).
Map<String, dynamic> buildLocalFailureReportBody({
  required String scanId,
  required LocalFailureReason reason,
  required String scanStartedAt,
  required String scanEndedAt,
}) =>
    {
      'scanId': scanId,
      'state': 'LOCAL_FAILURE',
      'reason': reason.name,
      'scanStartedAt': scanStartedAt,
      'scanEndedAt': scanEndedAt,
    };

Map<String, dynamic> buildRequestFailureReportBody({
  required String scanId,
  required RequestFailureReason reason,
  required String scanStartedAt,
  required String scanEndedAt,
}) =>
    {
      'scanId': scanId,
      'state': 'REQUEST_FAILURE',
      'reason': reason.name,
      'scanStartedAt': scanStartedAt,
      'scanEndedAt': scanEndedAt,
    };

/// The success-path fragment (design doc §6 rule 5b): timing only, no
/// `state` at all.
Map<String, dynamic> buildScanTimingReportBody({
  required String scanId,
  required String scanStartedAt,
  required String scanEndedAt,
}) =>
    {
      'scanId': scanId,
      'scanStartedAt': scanStartedAt,
      'scanEndedAt': scanEndedAt,
    };
