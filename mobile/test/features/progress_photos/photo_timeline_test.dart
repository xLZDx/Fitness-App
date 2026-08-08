import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/progress_photos/data/photo_timeline.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';

ProgressPhoto _p(
  String id,
  DateTime t, {
  ProgressPhotoAngle angle = ProgressPhotoAngle.front,
}) =>
    ProgressPhoto(
      id: id,
      takenAt: t,
      storagePath: '/tmp/$id.bin',
      keyFingerprint: 'fp',
      angle: angle,
    );

void main() {
  group('groupByMonth', () {
    test('returns empty for no photos', () {
      expect(groupByMonth(const []), isEmpty);
    });

    test('groups by calendar month, newest month first', () {
      final months = groupByMonth([
        _p('a', DateTime(2026, 3, 4)),
        _p('b', DateTime(2026, 5, 1)),
        _p('c', DateTime(2026, 3, 28)),
      ]);
      expect(months.length, 2);
      expect(months.first.month, DateTime(2026, 5));
      expect(months.last.month, DateTime(2026, 3));
      expect(months.last.count, 2);
    });

    test('sorts newest first inside a month regardless of input order', () {
      // The repository happens to return oldest-first today. This asserts the
      // grouping does its own sorting rather than inheriting that accident.
      final months = groupByMonth([
        _p('old', DateTime(2026, 3, 1)),
        _p('new', DateTime(2026, 3, 30)),
        _p('mid', DateTime(2026, 3, 15)),
      ]);
      expect(months.single.photos.map((p) => p.id), ['new', 'mid', 'old']);
    });

    test('same month in different years does not merge', () {
      final months = groupByMonth([
        _p('a', DateTime(2025, 3, 4)),
        _p('b', DateTime(2026, 3, 4)),
      ]);
      expect(months.length, 2);
    });
  });

  group('defaultComparePair', () {
    test('null below two photos', () {
      expect(defaultComparePair(const []), isNull);
      expect(defaultComparePair([_p('a', DateTime(2026, 1, 1))]), isNull);
    });

    test('null when no angle has two photos — never pairs across angles', () {
      final pair = defaultComparePair([
        _p('f', DateTime(2026, 1, 1), angle: ProgressPhotoAngle.front),
        _p('s', DateTime(2026, 6, 1), angle: ProgressPhotoAngle.side),
      ]);
      expect(pair, isNull);
    });

    test('oldest and newest of the same angle, in that order', () {
      final pair = defaultComparePair([
        _p('mid', DateTime(2026, 3, 1)),
        _p('new', DateTime(2026, 6, 1)),
        _p('old', DateTime(2026, 1, 1)),
      ]);
      expect(pair!.before.id, 'old');
      expect(pair.after.id, 'new');
    });

    test('picks the widest span when two angles both qualify', () {
      final pair = defaultComparePair([
        // front: 30 days apart
        _p('f1', DateTime(2026, 1, 1), angle: ProgressPhotoAngle.front),
        _p('f2', DateTime(2026, 1, 31), angle: ProgressPhotoAngle.front),
        // side: 150 days apart — should win
        _p('s1', DateTime(2026, 1, 1), angle: ProgressPhotoAngle.side),
        _p('s2', DateTime(2026, 5, 31), angle: ProgressPhotoAngle.side),
      ]);
      expect(pair!.before.id, 's1');
      expect(pair.after.id, 's2');
      expect(pair.daySpan, 150);
    });

    test('daySpan counts calendar days across a DST boundary', () {
      // Europe/Chisinau moves the clock forward in late March, so the elapsed
      // interval from 1 Jan to 31 May is 149 days and 23 hours. `inDays` on
      // that truncates to 149 and the card would read one day short of five
      // months. This is the regression: the count is on the dates.
      final pair = defaultComparePair([
        _p('a', DateTime(2026, 1, 1)),
        _p('b', DateTime(2026, 5, 31)),
      ]);
      expect(pair!.daySpan, 150);
    });

    test('same-day pair spans zero, not a negative or a rounding artefact', () {
      final pair = defaultComparePair([
        _p('morning', DateTime(2026, 5, 1, 8)),
        _p('evening', DateTime(2026, 5, 1, 21)),
      ]);
      expect(pair!.daySpan, 0);
    });

    test('daySpan is never negative', () {
      final pair = defaultComparePair([
        _p('new', DateTime(2026, 6, 1)),
        _p('old', DateTime(2026, 1, 1)),
      ]);
      expect(pair!.daySpan, greaterThan(0));
    });
  });

  group('photosForAngle', () {
    test('filters and sorts oldest first', () {
      final out = photosForAngle([
        _p('b', DateTime(2026, 5, 1), angle: ProgressPhotoAngle.side),
        _p('a', DateTime(2026, 1, 1), angle: ProgressPhotoAngle.side),
        _p('x', DateTime(2026, 3, 1), angle: ProgressPhotoAngle.front),
      ], ProgressPhotoAngle.side);
      expect(out.map((p) => p.id), ['a', 'b']);
    });
  });
}
