// S02 test epic 3, U15: the A-2 source cursor record.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/source_cursor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('U15 cursor record', () {
    test('(sourceId, cursor, windowInclusive) round trips, both flag values',
        () {
      for (final inclusive in [true, false]) {
        final c = SourceCursor(
            sourceId: 'garmin-connect',
            cursor: '2026-10-01T06:00:00Z',
            windowInclusive: inclusive);
        final back = SourceCursor.tryParse(c.toJsonString());
        expect(back, isNotNull);
        expect(back!.sourceId, 'garmin-connect');
        expect(back.cursor, '2026-10-01T06:00:00Z');
        expect(back.windowInclusive, inclusive);
        expect(back, c);
      }
    });

    test('the stored shape is exactly the three keys', () {
      final j = const SourceCursor(sourceId: 's', cursor: 'c').toJson();
      expect(j.keys.toSet(), {'sourceId', 'cursor', 'windowInclusive'});
      expect(j['windowInclusive'], true, reason: 'default is inclusive');
    });

    test('an opaque cursor with odd characters survives', () {
      const odd = 'tok/é日本"\\\n{}[]';
      final c = SourceCursor(sourceId: 'x', cursor: odd);
      expect(SourceCursor.tryParse(c.toJsonString())!.cursor, odd);
    });

    test('a missing windowInclusive reads as inclusive', () {
      final c = SourceCursor.tryParse('{"sourceId":"s","cursor":"c"}');
      expect(c, isNotNull);
      expect(c!.windowInclusive, isTrue);
    });

    test('corrupt bodies reset to "no cursor" (null) and never throw', () {
      final bad = <String?>[
        null,
        '',
        'garbage',
        '{',
        '[]',
        '"s"',
        '42',
        'null',
        '{}',
        '{"sourceId":"","cursor":"c"}',
        '{"sourceId":1,"cursor":"c"}',
        '{"sourceId":"s","cursor":5}',
        '{"sourceId":"s"}',
        '{"sourceId":"s","cursor":"c","windowInclusive":"yes"}',
        '{"sourceId":"s","cursor":"c","windowInclusive":1}',
        '\u0000\u0001\u0002',
      ];
      for (final b in bad) {
        expect(() => SourceCursor.tryParse(b), returnsNormally, reason: '$b');
        expect(SourceCursor.tryParse(b), isNull, reason: '$b');
      }
    });

    test('a file truncated at every byte offset is null or the whole record',
        () {
      final full = const SourceCursor(
              sourceId: 'garmin', cursor: 'abc', windowInclusive: false)
          .toJsonString();
      for (var n = 0; n <= full.length; n++) {
        final r = SourceCursor.tryParse(full.substring(0, n));
        if (n < full.length) {
          expect(r, isNull, reason: 'prefix $n');
        } else {
          expect(r?.cursor, 'abc');
        }
      }
    });

    test('a cursor file of another source is "no cursor"', () {
      final body = const SourceCursor(sourceId: 'a', cursor: 'c').toJsonString();
      expect(SourceCursor.tryParseFor('a', body), isNotNull);
      expect(SourceCursor.tryParseFor('b', body), isNull);
      expect(SourceCursor.tryParseFor('a', 'junk'), isNull);
    });

    test('equality distinguishes each of the three fields', () {
      const base = SourceCursor(sourceId: 's', cursor: 'c');
      expect(base, const SourceCursor(sourceId: 's', cursor: 'c'));
      expect(base, isNot(const SourceCursor(sourceId: 't', cursor: 'c')));
      expect(base, isNot(const SourceCursor(sourceId: 's', cursor: 'd')));
      expect(
          base,
          isNot(const SourceCursor(
              sourceId: 's', cursor: 'c', windowInclusive: false)));
      expect(jsonDecode(base.toJsonString()), base.toJson());
    });
  });
}
