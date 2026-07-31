import 'dart:ui' show Locale;

import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fitness_app/features/home/home_page.dart';

/// The schedule label on the home card.
///
/// It used to carry two hard-coded English arrays — `['Mon', 'Tue', ...]` and
/// `['Jan', 'Feb', ...]` — so a Russian user reading a Russian interface was
/// told their next session was on "Wed". Moving those nineteen names into the
/// ARB file would have fixed Russian and been wrong for the language after it:
/// Russian dates decline, and "20 мая" is not "мая 20". `DateFormat` knows the
/// ordering and the wording for every locale Flutter ships, so the names come
/// from there and only the sentence around them is translated.
void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    await initializeDateFormatting();
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  group('formatScheduleLabel', () {
    final now = DateTime(2026, 5, 8, 12); // 2026-05-08 is Friday

    test('today', () {
      expect(formatScheduleLabel(en, DateTime(2026, 5, 8, 7, 30), now: now),
          'Today 07:30');
    });

    test('tomorrow', () {
      expect(formatScheduleLabel(en, DateTime(2026, 5, 9, 18, 0), now: now),
          'Tomorrow 18:00');
    });

    test('within the next week shows weekday name', () {
      expect(formatScheduleLabel(en, DateTime(2026, 5, 13, 9, 0), now: now),
          'Wed 09:00');
    });

    test('beyond the next week shows month/day', () {
      expect(formatScheduleLabel(en, DateTime(2026, 5, 28, 14, 5), now: now),
          'May 28 · 14:05');
    });

    test('zero-pads single-digit hours and minutes', () {
      expect(formatScheduleLabel(en, DateTime(2026, 5, 8, 9, 5), now: now),
          'Today 09:05');
    });
  });

  group('in Russian', () {
    final now = DateTime(2026, 5, 8, 12);

    test('today and tomorrow are words, not translated abbreviations', () {
      expect(formatScheduleLabel(ru, DateTime(2026, 5, 8, 7, 30), now: now),
          'Сегодня, 07:30');
      expect(formatScheduleLabel(ru, DateTime(2026, 5, 9, 18, 0), now: now),
          'Завтра, 18:00');
    });

    test('the weekday comes from the locale, not from an English array', () {
      final label =
          formatScheduleLabel(ru, DateTime(2026, 5, 13, 9, 0), now: now);
      expect(label, contains('09:00'));
      expect(label, isNot(contains('Wed')),
          reason: 'this is the whole bug: a Russian interface saying "Wed"');
      expect(RegExp(r'[А-Яа-я]').hasMatch(label), isTrue, reason: label);
    });

    test('the date beyond a week is ordered the Russian way', () {
      // "28 мая", not "мая 28". Putting nineteen names in the ARB would have
      // produced the second one and looked fine to anyone not reading it.
      final label =
          formatScheduleLabel(ru, DateTime(2026, 5, 28, 14, 5), now: now);
      expect(label, contains('14:05'));
      expect(label, matches(RegExp(r'\d{1,2}\s+[а-я]')), reason: label);
    });
  });
}
