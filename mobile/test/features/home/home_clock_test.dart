import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/home/data/home_dashboard.dart';
import 'package:fitness_app/features/home/state/home_dashboard_providers.dart';

/// The Home screen reads the wall clock, and for a while nothing could pin it.
///
/// Two things on that screen depend on the time: the greeting, which is one of
/// three depending on the hour, and the week strip, which marks today. Both are
/// drawn into `test/golden/composed_screen_golden_test.dart`'s reference image,
/// so that golden could only ever match at the hour and on the weekday it was
/// recorded. It failed from the moment it was taken and was carried for days as
/// a "known pre-existing failure" — which is what every clock-dependent test
/// eventually becomes, because the failure looks environmental and never gets a
/// second look.
///
/// [homeNowProvider] is the fix. These tests exist so that a future change
/// which reads `DateTime.now()` directly again fails HERE, in a fast test that
/// names the problem, rather than in a golden whose 200 000-pixel diff explains
/// nothing.

void main() {
  test('the week strip marks the day the clock provider names', () {
    ProviderContainer at(DateTime now) {
      final c = ProviderContainer(
          overrides: [homeNowProvider.overrideWithValue(now)]);
      addTearDown(c.dispose);
      return c;
    }

    DateTime todayIn(ProviderContainer c) =>
        c.read(weekStripProvider).firstWhere((cell) => cell.isToday).day;

    // A Wednesday and the Saturday of the same week: the strip must follow the
    // provider, not the machine this test happens to run on.
    //
    // Expected as UTC midnight because that is `_dayOf`'s deliberate
    // normalisation — it takes the LOCAL calendar day and stores it as a UTC
    // instant, so a day is a day rather than a moment. Asserting local
    // midnight here would be asserting against the runner's timezone, which is
    // the class of bug this whole file exists to remove.
    expect(todayIn(at(DateTime(2026, 1, 14, 9, 30))), DateTime.utc(2026, 1, 14));
    expect(todayIn(at(DateTime(2026, 1, 17, 21, 5))), DateTime.utc(2026, 1, 17));
  });

  test('and the strip still spans exactly the week that day falls in', () {
    // The positive control for the assertion above: a strip that marked the
    // right day inside the wrong week would pass it.
    final c = ProviderContainer(overrides: [
      homeNowProvider.overrideWithValue(DateTime(2026, 1, 17, 21, 5)),
    ]);
    addTearDown(c.dispose);
    final week = c.read(weekStripProvider);
    expect(week.length, 7);
    expect(week.first.day, DateTime.utc(2026, 1, 12), reason: 'the Monday');
    expect(week.last.day, DateTime.utc(2026, 1, 18), reason: 'the Sunday');
  });

  test('the greeting the header picks changes with that same clock', () {
    // `_HudGreeting` is private, so this asserts the function it feeds rather
    // than the widget. What matters is that the three branches are genuinely
    // distinct at the three times of day the golden could have been recorded
    // at — if they were not, pinning the clock would have fixed nothing.
    expect(greetingFor(DateTime(2026, 1, 14, 9, 30)), DayGreeting.morning);
    expect(greetingFor(DateTime(2026, 1, 14, 14, 0)), DayGreeting.afternoon);
    expect(greetingFor(DateTime(2026, 1, 14, 21, 0)), DayGreeting.evening);
  });

  test('the default is the real clock, so pinning it is a test-only act', () {
    // The provider must not quietly ship a fixed date to production.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final before = DateTime.now();
    final read = c.read(homeNowProvider);
    final after = DateTime.now();
    expect(read.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    expect(read.isAfter(after.add(const Duration(seconds: 1))), isFalse);
  });
}
