import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/notifications/local_notification_service.dart';

void main() {
  group('reminderIdFor (FNV-1a)', () {
    test('matches the published FNV-1a 32-bit vectors (masked to 31 bits)', () {
      // Reference: FNV-1a 32 of "" = 0x811C9DC5, "a" = 0xE40C292C,
      // "foobar" = 0xBF9CF968.
      expect(reminderIdFor(''), 0x811C9DC5 & 0x7FFFFFFF);
      expect(reminderIdFor('a'), 0xE40C292C & 0x7FFFFFFF);
      expect(reminderIdFor('foobar'), 0xBF9CF968 & 0x7FFFFFFF);
    });

    test('is non-negative, 31-bit, and distinguishes nearby ids', () {
      final ids = {for (var i = 0; i < 500; i++) reminderIdFor('session_$i')};
      expect(ids.length, 500);
      expect(ids.every((v) => v >= 0 && v <= 0x7FFFFFFF), isTrue);
    });
  });
}
