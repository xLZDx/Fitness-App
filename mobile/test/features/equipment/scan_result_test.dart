import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';

void main() {
  group('ScanResult.tryParse', () {
    test('returns null for null / empty', () {
      expect(ScanResult.tryParse(null), isNull);
      expect(ScanResult.tryParse(''), isNull);
    });

    test('returns null for non-fitness URIs', () {
      expect(ScanResult.tryParse('https://example.com'), isNull);
      expect(ScanResult.tryParse('just a string'), isNull);
      expect(ScanResult.tryParse('fitness://exercises/foo'), isNull);
    });

    test('parses fitness://equipment/<id>', () {
      final r = ScanResult.tryParse('fitness://equipment/treadmill_precor_trm211');
      expect(r, isNotNull);
      expect(r!.equipmentId, 'treadmill_precor_trm211');
      expect(r.raw, 'fitness://equipment/treadmill_precor_trm211');
    });

    test('returns null when the equipment id is empty', () {
      expect(ScanResult.tryParse('fitness://equipment/'), isNull);
    });
  });
}
