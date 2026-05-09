import 'equipment_report.dart';
import 'equipment_report_service.dart';

class MockEquipmentReportService implements EquipmentReportService {
  /// Override to simulate a backend rejection.
  Exception? failWith;

  /// Reports observed since construction; cleared by [reset].
  final List<EquipmentReport> submitted = [];

  void reset() {
    submitted.clear();
    failWith = null;
  }

  @override
  Future<void> submit(EquipmentReport report) async {
    if (failWith != null) throw failWith!;
    submitted.add(report);
  }
}
