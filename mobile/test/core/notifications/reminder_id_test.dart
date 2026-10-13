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

    test('literal ids for real inputs, stable across calls (computed independently of the Dart code)', () {
      // FNV-1a 32 over the UTF-16 code units, masked to 31 bits; the numbers
      // come from a separate Python implementation, not from this function.
      expect(reminderIdFor('body_scan_next'), 1706528949);
      expect(reminderIdFor('body_scan_next'), 1706528949);
      expect(reminderIdFor('u1'), 71477235);
      expect(reminderIdFor('u2'), 88254854);
    });

    test('two different inputs give two different ids', () {
      expect(reminderIdFor('u1'), isNot(reminderIdFor('u2')));
      expect(reminderIdFor('body_scan_next'), isNot(reminderIdFor('session_1')));
    });
  });
}
