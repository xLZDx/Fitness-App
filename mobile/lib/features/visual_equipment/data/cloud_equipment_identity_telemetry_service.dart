import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';

/// The Cloud Function this surface calls
/// (`functions-equipment-identity/src/index.ts`'s `equipmentIdentityRecordTelemetry`
/// `onCall` export). Named once so this service and its test cannot drift
/// apart on a typo -- the same convention
/// `cloud_equipment_identity_service.dart`'s own
/// `kEquipmentIdentityFunctionName` already uses.
const String kEquipmentIdentityTelemetryFunctionName = 'equipmentIdentityRecordTelemetry';

/// Sends one mobile-authoritative telemetry report body (built by
/// `equipment_identity_telemetry_report.dart`'s `build*ReportBody`
/// functions) -- injectable for tests, mirroring `EquipmentIdentityAsk`
/// one file over.
typedef EquipmentIdentityTelemetrySend = Future<void> Function(Map<String, dynamic> body);

/// Calls [kEquipmentIdentityTelemetryFunctionName]. Deliberately thin, same
/// posture as `CloudEquipmentIdentityService`: this class does not catch or
/// reinterpret a failure -- `equipmentIdentityProvider` is the boundary that
/// decides a telemetry-send failure must never affect the scan's own result,
/// wrapping every call site in its own `catch`.
class CloudEquipmentIdentityTelemetryService {
  CloudEquipmentIdentityTelemetryService({FirebaseFunctions? functions}) : _injected = functions;

  final FirebaseFunctions? _injected;

  // Lazy, like `CloudEquipmentIdentityService._fns` one file over: touching
  // `functionsForRegion` requires Firebase to already be initialized, so a
  // Provider default that merely CONSTRUCTS this class must not eagerly
  // reach for it.
  late final FirebaseFunctions _fns = _injected ?? functionsForRegion;

  Future<void> send(Map<String, dynamic> body) async {
    await _fns.httpsCallable(kEquipmentIdentityTelemetryFunctionName).call<Map<String, dynamic>>(body);
  }
}
