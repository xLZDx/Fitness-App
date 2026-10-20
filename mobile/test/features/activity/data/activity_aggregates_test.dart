// S03-13 aggregates, sport groups and source labels (test plan 5.2, unit rows).
// Pure Dart plus the generated localisations; injected "now" and zone only.
import 'package:flutter_gen/gen_l10n/app_localizations_en.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/activity/data/activity_aggregates.dart';
import 'package:fitness_app/features/activity/data/source_kind.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/progress/widgets/progress_activity_widgets.dart'
    show progressSourceLabelText;

import '../../../support/s03_step4_support.dart';

SessionDigest dg(
  String id,
  DateTime start, {
  SportGroup g = SportGroup.run,
  double? time,
  double? dist,
}) =>
    SessionDigest(
      id: id,
      startUtc: start,
      sportGroup: g,
      syncState: JournalSyncState.pending,
      streamLost: false,
      movingTimeS: time,
      distanceM: dist,
    );

String labelEn(SessionDigest d) =>
    progressSourceLabelText(AppLocalizationsEn(), sourceLabelOf(d).key);

SessionDigest withSource(String id, SourceKind kind, {int count = 1}) =>
    SessionDigest(
      id: 'x',
      startUtc: kNow,
      sportGroup: SportGroup.run,
      syncState: JournalSyncState.pending,
      streamLost: false,
      primarySourceId: id,
      primarySourceKind: kind,
      sourceCount: count,
    );

void main() {
  group('AC-PR-5 strength never leaks', () {
    test('AC-PR-5 strength session yields no digest, run is counted', () {
      final strength =
          sess('s', sport: SportType.strength, start: kNow, dist: 0, time: 60);
      final run = sess('r', start: kNow, dist: 1000, time: 600);
      expect(buildDigest(strength), isNull);
      final digests = [buildDigest(run)!];
      final week = aggregateWeek(digests, kNow, zone: utcZone);
      expect(week.tiles, hasLength(1));
      expect(week.tiles.single.group, SportGroup.run);
      expect(week.tiles.single.sessions, 1);
      expect(recentSessions(digests), hasLength(1));
      expect(todaySessions(digests, kNow, zone: utcZone), hasLength(1));
    });
  });

  group('AC-PR-7 Monday week in the device zone', () {
    // Local Sunday 2026-10-11 23:30 and local Monday 2026-10-12 00:10, for a
    // zone with offset 0 and one with offset -8h. now = Wed 2026-10-14 local.
    for (final zoneCase in [
      ('UTC+0', utcZone, Duration.zero),
      ('UTC-8', minus8Zone, const Duration(hours: 8)),
    ]) {
      final (name, zone, shift) = zoneCase;
      final now = DateTime.utc(2026, 10, 14, 12).add(shift);
      test('AC-PR-7/$name/sundayLate belongs to the PREVIOUS week', () {
        final sun = DateTime.utc(2026, 10, 11, 23, 30).add(shift);
        final w = aggregateWeek([dg('a', sun)], now, zone: zone);
        expect(w.tiles, isEmpty);
        expect(w.hasOutsideWeek, isTrue);
      });
      test('AC-PR-7/$name/mondayEarly belongs to the NEW week', () {
        final mon = DateTime.utc(2026, 10, 12, 0, 10).add(shift);
        final w = aggregateWeek([dg('a', mon)], now, zone: zone);
        expect(w.tiles.single.sessions, 1);
        expect(w.hasOutsideWeek, isFalse);
      });
    }
  });

  test('AC-PR-11 groups are counted once each', () {
    final ds = [
      for (var i = 0; i < 3; i++) dg('r$i', kNow, g: SportGroup.run),
      for (var i = 0; i < 2; i++) dg('c$i', kNow, g: SportGroup.ride),
    ];
    final w = aggregateWeek(ds, kNow, zone: utcZone);
    final byGroup = {for (final t in w.tiles) t.group: t.sessions};
    expect(byGroup[SportGroup.run], 3);
    expect(byGroup[SportGroup.ride], 2);
    expect(byGroup.values.fold<int>(0, (a, b) => a + b), 5);
    expect(byGroup.length, 2);
  });

  group('AC-SRC-6 label of a source', () {
    final cases = <String, (String, SourceKind, String)>{
      'platformHealth': ('xyz', SourceKind.platformHealth, 'Health platform'),
      'bleSensor': ('xyz', SourceKind.bleSensor, 'Sensor'),
      'vendorCloud': ('xyz', SourceKind.vendorCloud, 'Service'),
      'companionApp': ('xyz', SourceKind.companionApp, 'App'),
      'fileImport': ('xyz', SourceKind.fileImport, 'File import'),
    };
    cases.forEach((name, c) {
      test('AC-SRC-6/$name', () {
        expect(labelEn(withSource(c.$1, c.$2)), c.$3);
      });
    });
    test('AC-SRC-6/unknownKindName parses to File import, never empty', () {
      final kind = SourceKind.parse('someFutureKind');
      expect(kind, SourceKind.fileImport);
      final text = labelEn(withSource('xyz', kind));
      expect(text, 'File import');
      expect(text, isNotEmpty);
    });
  });

  test('DT-13-1 DST days land in the right week by local calendar day', () {
    // Fall back: offset -4h until 2026-11-01 06:00Z, then -5h (25-hour Sunday).
    DateTime fall(DateTime u) => u.subtract(
        Duration(hours: u.isBefore(DateTime.utc(2026, 11, 1, 6)) ? 4 : 5));
    final nowFall = DateTime.utc(2026, 11, 4, 12);
    // Local Sun Nov 1 23:30 EST = Nov 2 04:30Z: still Sunday (old week).
    final sun = dg('sun', DateTime.utc(2026, 11, 2, 4, 30));
    // Local Mon Nov 2 00:10 EST = 05:10Z: new week.
    final mon = dg('mon', DateTime.utc(2026, 11, 2, 5, 10));
    final wf = aggregateWeek([sun, mon], nowFall, zone: fall);
    expect(wf.tiles.single.sessions, 1);
    expect(wf.hasOutsideWeek, isTrue);
    expect(todaySessions([sun, mon], DateTime.utc(2026, 11, 2, 12), zone: fall)
        .map((d) => d.id)
        .toList(), ['mon']);
    // Spring forward: -5h until 2026-03-08 07:00Z, then -4h (23-hour Sunday).
    DateTime spring(DateTime u) => u.subtract(
        Duration(hours: u.isBefore(DateTime.utc(2026, 3, 8, 7)) ? 5 : 4));
    final nowSpring = DateTime.utc(2026, 3, 11, 12);
    final sun2 = dg('sun2', DateTime.utc(2026, 3, 9, 3, 30)); // Sun 23:30 EDT
    final mon2 = dg('mon2', DateTime.utc(2026, 3, 9, 4, 10)); // Mon 00:10 EDT
    final ws = aggregateWeek([sun2, mon2], nowSpring, zone: spring);
    expect(ws.tiles.single.sessions, 1);
    expect(ws.hasOutsideWeek, isTrue);
  });

  test('DT-13-2 the zone is read at aggregation time (device zone rule)', () {
    final s = dg('a', DateTime.utc(2026, 10, 12, 3)); // Mon 03:00Z
    final now = DateTime.utc(2026, 10, 14, 12);
    expect(aggregateWeek([s], now, zone: utcZone).tiles, hasLength(1));
    // Same stored instant read in UTC-8: Sunday 19:00, the previous week.
    final w8 = aggregateWeek([s], now, zone: minus8Zone);
    expect(w8.tiles, isEmpty);
    expect(w8.hasOutsideWeek, isTrue);
  });

  test('DT-13-3 no provenance gives the Unknown source label', () {
    final d = dg('a', kNow);
    expect(sourceLabelOf(d).key, SourceLabelKey.unknown);
    expect(labelEn(d), 'Unknown source');
    expect(AppLocalizationsRu().sourceLabelUnknown, isNotEmpty);
  });

  test('DT-13-4 plus-k sources suffix and plural forms', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    String more(SessionDigest d, dynamic l10n) {
      final k = sourceLabelOf(d).moreSources;
      return k == 0 ? '' : l10n.activitySourcesMore(k) as String;
    }

    SessionDigest n(int c) =>
        withSource('xyz', SourceKind.vendorCloud, count: c);
    expect(sourceLabelOf(n(1)).moreSources, 0);
    expect(more(n(1), en), '');
    expect(more(n(2), en), '+1 source');
    expect(more(n(5), en), '+4 sources');
    expect(more(n(21), en), '+20 sources');
    expect(more(n(2), ru), '+1 источник');
    expect(more(n(5), ru), '+4 источника');
    expect(more(n(21), ru), '+20 источников');
  });

  test('DT-13-5 time sums only sessions with a time; k of n hint', () {
    final ds = [
      dg('1', kNow, time: 600),
      dg('2', kNow, time: 600),
      dg('3', kNow, time: 600),
      dg('4', kNow),
      dg('5', kNow),
    ];
    final t = aggregateWeek(ds, kNow, zone: utcZone).tiles.single;
    expect(t.timeSeconds, 1800);
    expect(t.timeContributing, 3);
    expect(t.sessions, 5);
    expect(t.timePartial, isTrue);
    expect(AppLocalizationsEn().activityTimeFrom(t.timeContributing, t.sessions),
        'Time from 3 of 5 sessions');
  });

  test('DT-13-6 week state: none / older only / this week', () {
    expect(aggregateWeek(const [], kNow, zone: utcZone).hasOutsideWeek, isFalse);
    expect(aggregateWeek(const [], kNow, zone: utcZone).hasWeekData, isFalse);
    final older = aggregateWeek([dg('o', DateTime.utc(2026, 9, 1))], kNow,
        zone: utcZone);
    expect(older.hasWeekData, isFalse);
    expect(older.hasOutsideWeek, isTrue);
    expect(aggregateWeek([dg('n', kNow)], kNow, zone: utcZone).hasWeekData,
        isTrue);
  });

  test('DT-13-7 known source ids have their own label', () {
    final cases = {
      'app': 'Recorded in this app',
      'health_connect': 'Health Connect',
      'healthkit': 'Health platform',
      'wear_os': 'Watch',
      'ble_hr': 'Sensor',
    };
    cases.forEach((id, text) {
      expect(labelEn(withSource(id, SourceKind.fileImport)), text,
          reason: 'source id $id');
    });
  });

  test('DT-13-17 an unreadable session is counted, not shown as no data', () {
    final good = [
      for (var i = 0; i < 4; i++) sess('g$i', start: kNow, dist: 1000, time: 60),
    ];
    var unreadable = 0;
    final digests = <SessionDigest>[];
    for (final s in [...good, BadSession('bad', kNow)]) {
      try {
        final d = buildDigest(s);
        if (d != null) digests.add(d);
      } catch (_) {
        unreadable++;
      }
    }
    expect(() => buildDigest(BadSession('bad', kNow)), throwsStateError);
    expect(unreadable, 1);
    expect(digests, hasLength(4));
  });

  test('DT-13-19 unmapped SourceKind: not constructible; parse path pinned',
      () {
    // The label function switches exhaustively over SourceKind and the enum
    // has no "unknown" member: a value without a mapping cannot exist. The only
    // unrecognised input is a stored NAME, and parse() maps it to fileImport
    // (contract 8.1). This test pins that decision (see the findings).
    expect(SourceKind.values.length, 5);
    expect(SourceKind.parse(null), SourceKind.fileImport);
    expect(SourceKind.parse('???'), SourceKind.fileImport);
    for (final k in SourceKind.values) {
      expect(sourceLabelKeyOf('xyz', k), isNot(SourceLabelKey.unknown));
    }
  });

  group('DT-13-21 sport groups', () {
    test('every non-strength sport maps to exactly one group', () {
      for (final s in SportType.values) {
        final g = groupOf(s);
        if (s == SportType.strength) {
          expect(g, isNull);
        } else {
          expect(g, isNotNull, reason: s.name);
          expect(kSportGroupOrder.where((x) => x == g), hasLength(1));
        }
      }
      expect(SportType.values.where((s) => groupOf(s) != null), hasLength(11));
    });
    test('an unknown stored name degrades to other', () {
      expect(groupOf(SportType.parse('quidditch')), SportGroup.other);
    });
    test('mapping table', () {
      expect(groupOf(SportType.hiking), SportGroup.walkHike);
      expect(groupOf(SportType.trailRunning), SportGroup.run);
      expect(groupOf(SportType.mountainBiking), SportGroup.ride);
      expect(groupOf(SportType.swimmingOpenWater), SportGroup.swim);
      expect(groupOf(SportType.rowing), SportGroup.row);
    });
  });

  test('DT-13-22 zero is a value, null is missing', () {
    final ds = [
      dg('zero', kNow, dist: 0, time: 600),
      dg('nullDist', kNow, time: 600),
      dg('nullTime', kNow, dist: 0),
    ];
    final t = aggregateWeek(ds, kNow, zone: utcZone).tiles.single;
    expect(t.distanceContributing, 2);
    expect(t.distanceM, 0);
    expect(t.hasDistance, isTrue, reason: 'a reported 0 is data');
    expect(t.timeContributing, 2);
    expect(t.distancePartial, isTrue);
    final onlyMissing =
        aggregateWeek([dg('m', kNow)], kNow, zone: utcZone).tiles.single;
    expect(onlyMissing.hasTime, isFalse);
    expect(onlyMissing.hasDistance, isFalse);
    expect(onlyMissing.timeContributing, 0);
  });

  test('DT-13-24 label follows the FIRST provenance record', () {
    final s = sess('p',
        start: kNow,
        prov: [src('health_connect', SourceKind.platformHealth),
          src('app', SourceKind.companionApp)]);
    final d = buildDigest(s)!;
    final l = sourceLabelOf(d);
    expect(l.key, SourceLabelKey.healthConnect);
    expect(l.moreSources, 1);
  });

  test('isEstimate is false for every field (no value is an estimate)', () {
    final s = sess('e', start: kNow, dist: 1, time: 1);
    expect(isEstimate('time', s), isFalse);
    expect(isEstimate('distance', s), isFalse);
  });
}
