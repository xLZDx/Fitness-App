import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_report.dart';
import 'package:fitness_app/features/equipment/data/mock_equipment_report_service.dart';

void main() {
  group('EquipmentReport', () {
    final report = EquipmentReport(
      id: 'r_1',
      equipmentId: 'rack_rogue_rml390f',
      gymId: 'anytime_fitness_westwood',
      fault: EquipmentFault.unsafe,
      note: 'cable frayed',
      reportedAt: DateTime.utc(2026, 5, 10, 9, 30),
      reporterUid: 'alice',
    );

    test('toJson/fromJson round-trips losslessly', () {
      final restored = EquipmentReport.fromJson(report.toJson());
      expect(restored.id, report.id);
      expect(restored.equipmentId, report.equipmentId);
      expect(restored.gymId, report.gymId);
      expect(restored.fault, EquipmentFault.unsafe);
      expect(restored.note, 'cable frayed');
      expect(restored.reportedAt, report.reportedAt);
      expect(restored.reporterUid, 'alice');
    });

    test('fromJson defaults unknown fault to other', () {
      final r = EquipmentReport.fromJson({
        'id': 'x',
        'equipmentId': 'y',
        'gymId': 'z',
        'fault': 'mystery',
        'note': '',
        'reportedAt': '2026-05-10T00:00:00.000Z',
        'reporterUid': 'alice',
      });
      expect(r.fault, EquipmentFault.other);
    });

    test('fromJson tolerates DateTime values for reportedAt', () {
      final r = EquipmentReport.fromJson({
        'id': 'x',
        'equipmentId': 'y',
        'gymId': 'z',
        'fault': 'unsafe',
        'reportedAt': DateTime.utc(2026, 5, 10),
        'reporterUid': 'alice',
      });
      expect(r.reportedAt, DateTime.utc(2026, 5, 10));
    });
  });

  group('MockEquipmentReportService', () {
    late MockEquipmentReportService svc;

    setUp(() => svc = MockEquipmentReportService());

    test('submit records the report', () async {
      final r = EquipmentReport(
        id: 'r_1',
        equipmentId: 'rack',
        gymId: 'g',
        fault: EquipmentFault.degraded,
        note: 'wobbly',
        reportedAt: DateTime.utc(2026, 5, 10),
        reporterUid: 'alice',
      );
      await svc.submit(r);
      expect(svc.submitted, hasLength(1));
      expect(svc.submitted.first.equipmentId, 'rack');
    });

    test('failWith surfaces from submit', () {
      svc.failWith = Exception('backend down');
      expect(
        () => svc.submit(EquipmentReport(
          id: 'r',
          equipmentId: 'x',
          gymId: 'g',
          fault: EquipmentFault.other,
          note: '',
          reportedAt: DateTime.now(),
          reporterUid: 'alice',
        )),
        throwsException,
      );
    });

    test('reset clears observed reports + failure', () async {
      svc.failWith = Exception('boom');
      svc.submitted.add(EquipmentReport(
        id: 'r',
        equipmentId: 'x',
        gymId: 'g',
        fault: EquipmentFault.other,
        note: '',
        reportedAt: DateTime.now(),
        reporterUid: 'alice',
      ));
      svc.reset();
      expect(svc.failWith, isNull);
      expect(svc.submitted, isEmpty);
    });
  });
}
