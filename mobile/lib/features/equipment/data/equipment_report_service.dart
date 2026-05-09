import 'equipment_report.dart';

/// Submits broken-equipment reports to the backend. The mock impl is the
/// default Riverpod provider so unit tests stay plugin-free; production
/// uses `CloudFunctionsEquipmentReportService` calling a `reportEquipment`
/// callable that writes to Firestore + dispatches to the gym's webhook
/// (Slack / Teams / email — whatever the chain configured).
abstract class EquipmentReportService {
  Future<void> submit(EquipmentReport report);
}

class EquipmentReportException implements Exception {
  EquipmentReportException(this.message);
  final String message;
  @override
  String toString() => 'EquipmentReportException: $message';
}
