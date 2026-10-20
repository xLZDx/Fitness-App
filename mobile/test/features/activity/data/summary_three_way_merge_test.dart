// S02-01 U39: the pure three-way merge of two cloud summaries (design 3.2).
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:fitness_app/features/activity/data/summary_three_way_merge.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime.utc(2026, 5, 1, 6);

Map<String, Object?> _doc(Map<String, Object?> fields, {int rev = 3}) => {
      'startUtc': _t0,
      'sport': 'running',
      'rev': rev,
      ...fields,
    };

/// (base, local, server) literals per key; three distinct values.
(Object, Object, Object) _triple(String k) {
  if (k == 'endUtc') {
    return (DateTime.utc(2026, 5, 1, 7), DateTime.utc(2026, 5, 1, 8), DateTime.utc(2026, 5, 1, 9));
  }
  if (kSummaryNumericBounds.containsKey(k) || kSummaryIntBounds.containsKey(k)) {
    return (10, 11, 12);
  }
  return ('a', 'b', 'c');
}

SummaryMerged _merged(SummaryMergeResult r) {
  expect(r, isA<SummaryMerged>());
  return r as SummaryMerged;
}

void main() {
  final fields = (kSummaryAllowedKeys.toList()
        ..removeWhere((k) =>
            kSummaryBookkeepingKeys.contains(k) || kSummaryImmutableKeys.contains(k)))
      ..sort();

  test('the table covers every mergeable summary field of the allowlist', () {
    expect(fields.length, kSummaryAllowedKeys.length - 4);
    expect(fields, containsAll(['distanceM', 'userEditCount', 'hasRoute', 'endUtc', 'formulaVersion']));
  });

  for (final k in fields) {
    group('field $k', () {
      final isBool = k == 'hasRoute';
      final (b, l, s) = isBool ? (false, true, true) : _triple(k);
      final (cb, cl, cs) = isBool ? (null, true, false) : _triple(k);

      test('only local changed -> local value, not adopted', () {
        final r = _merged(mergeSummaries(
            base: _doc({k: b}), local: _doc({k: isBool ? true : l}), server: _doc({k: b})));
        expect(r.summary[k], isBool ? true : l);
        expect(r.adoptedFromServer, isEmpty);
      });

      test('only server changed -> server value, reported as adopted', () {
        final r = _merged(mergeSummaries(
            base: _doc({k: b}), local: _doc({k: b}), server: _doc({k: isBool ? true : s})));
        expect(r.summary[k], isBool ? true : s);
        expect(r.adoptedFromServer, {k});
      });

      test('neither changed -> base', () {
        final r = _merged(mergeSummaries(
            base: _doc({k: b}), local: _doc({k: b}), server: _doc({k: b})));
        expect(r.summary[k], b);
        expect(r.adoptedFromServer, isEmpty);
      });

      test('both changed to the same value -> that value', () {
        final r = _merged(mergeSummaries(
            base: _doc({k: b}), local: _doc({k: isBool ? true : l}), server: _doc({k: isBool ? true : l})));
        expect(r.summary[k], isBool ? true : l);
        expect(r.adoptedFromServer, isEmpty);
      });

      test('both changed to different values -> conflict naming the field, no merged value',
          () {
        final res = mergeSummaries(
            base: _doc({k: cb}), local: _doc({k: cl}), server: _doc({k: cs}));
        expect(res, isA<SummaryMergeConflict>());
        expect((res as SummaryMergeConflict).fields, [k]);
      });
    });
  }

  group('whole-document behaviour', () {
    test('one conflicting field makes the whole document a conflict (no partial merge)',
        () {
      final res = mergeSummaries(
        base: _doc({'movingTimeS': 1, 'distanceM': 4800, 'ascentM': 5}),
        local: _doc({'movingTimeS': 2, 'distanceM': 5100, 'ascentM': 5}),
        server: _doc({'movingTimeS': 1, 'distanceM': 5200, 'ascentM': 9}),
      );
      expect(res, isA<SummaryMergeConflict>());
      expect((res as SummaryMergeConflict).fields, ['distanceM']);
    });

    test('several non-conflicting changes merge together', () {
      final r = _merged(mergeSummaries(
        base: _doc({'movingTimeS': 1, 'distanceM': 4800, 'ascentM': 5}),
        local: _doc({'movingTimeS': 2, 'distanceM': 4800, 'ascentM': 5}),
        server: _doc({'movingTimeS': 1, 'distanceM': 5000, 'ascentM': 9}),
      ));
      expect(r.summary['movingTimeS'], 2);
      expect(r.summary['distanceM'], 5000);
      expect(r.summary['ascentM'], 9);
      expect(r.adoptedFromServer, {'distanceM', 'ascentM'});
    });

    test('startUtc or sport differing is a typed error, not a merge', () {
      expect(
          () => mergeSummaries(
              base: _doc({}),
              local: _doc({}),
              server: {..._doc({}), 'sport': 'cycling'}),
          throwsA(isA<ImmutableSummaryFieldViolation>().having((e) => e.field, 'field', 'sport')));
      expect(
          () => mergeSummaries(
              base: _doc({}),
              local: _doc({}),
              server: {..._doc({}), 'startUtc': _t0.add(const Duration(seconds: 1))}),
          throwsA(isA<ImmutableSummaryFieldViolation>().having((e) => e.field, 'field', 'startUtc')));
    });

    test('rev is max(local, server) + 1, clamped, and never below either side', () {
      int rev(int a, int b) => _merged(mergeSummaries(
              base: _doc({'distanceM': 1}, rev: 1),
              local: _doc({'distanceM': 2}, rev: a),
              server: _doc({'distanceM': 1}, rev: b)))
          .summary['rev'] as int;
      expect(rev(5, 9), 10);
      expect(rev(9, 5), 10);
      expect(rev(7, 7), 8);
      expect(rev(1000000, 3), 1000000);
      final noRev = _merged(mergeSummaries(
          base: {'startUtc': _t0, 'sport': 'running'},
          local: {'startUtc': _t0, 'sport': 'running'},
          server: {'startUtc': _t0, 'sport': 'running'}));
      expect(noRev.summary['rev'], 1);
    });

    test('keys outside the allowlist never reach the merged summary', () {
      final r = _merged(mergeSummaries(
        base: _doc({'distanceM': 1}),
        local: _doc({'distanceM': 2, 'lats': [1.0], 'avgHrBpm': 150.25, 'friendIds': 'x'}),
        server: _doc({'distanceM': 1, 'polyline': 'abc', 'visibility': 'public'}),
      ));
      for (final bad in const ['lats', 'avgHrBpm', 'friendIds', 'polyline', 'visibility']) {
        expect(r.summary.containsKey(bad), isFalse, reason: bad);
      }
      expect(r.summary.keys.every(kSummaryAllowedKeys.contains), isTrue);
    });

    test('deterministic and symmetric in the roles of the two devices', () {
      final base = _doc({'movingTimeS': 1, 'distanceM': 4800, 'ascentM': 5, 'steps': 7});
      final a = _doc({'movingTimeS': 2, 'distanceM': 4800, 'ascentM': 5, 'steps': 8}, rev: 4);
      final b = _doc({'movingTimeS': 1, 'distanceM': 5000, 'ascentM': 5, 'steps': 8}, rev: 6);
      final ab = _merged(mergeSummaries(base: base, local: a, server: b));
      final again = _merged(mergeSummaries(base: base, local: a, server: b));
      final ba = _merged(mergeSummaries(base: base, local: b, server: a));
      expect(again.summary, ab.summary);
      expect(ba.summary, ab.summary);
      expect(ab.adoptedFromServer, {'distanceM'});
      expect(ba.adoptedFromServer, {'movingTimeS'});
      // Conflicts are symmetric too.
      final c1 = mergeSummaries(base: base, local: _doc({'distanceM': 1}), server: _doc({'distanceM': 2}));
      final c2 = mergeSummaries(base: base, local: _doc({'distanceM': 2}), server: _doc({'distanceM': 1}));
      expect((c1 as SummaryMergeConflict).fields, (c2 as SummaryMergeConflict).fields);
    });

    test('a missing baseSummary conflicts on every differing field, never "server wins"',
        () {
      final res = mergeSummaries(
        base: null,
        local: _doc({'distanceM': 5100, 'ascentM': 5, 'steps': 3}),
        server: _doc({'distanceM': 5000, 'ascentM': 5, 'steps': 4}),
      );
      expect(res, isA<SummaryMergeConflict>());
      expect((res as SummaryMergeConflict).fields, ['distanceM', 'steps']);
      // Equal everywhere is not a conflict.
      final ok = _merged(mergeSummaries(
        base: null,
        local: _doc({'distanceM': 5000}),
        server: _doc({'distanceM': 5000}),
      ));
      expect(ok.summary['distanceM'], 5000);
      expect(ok.adoptedFromServer, isEmpty);
    });

    test('int and double of the same numeric value are the same value', () {
      final r = _merged(mergeSummaries(
        base: _doc({'distanceM': 5000}),
        local: _doc({'distanceM': 5000.0}),
        server: _doc({'distanceM': 5200}),
      ));
      expect(r.summary['distanceM'], 5200);
      expect(r.adoptedFromServer, {'distanceM'});
    });

    test('the local updatedAt hint is carried and never merged as a value', () {
      final hint = DateTime.utc(2026, 6, 1);
      final r = _merged(mergeSummaries(
        base: _doc({'distanceM': 1, 'updatedAt': DateTime.utc(2026, 1, 1)}),
        local: _doc({'distanceM': 1, 'updatedAt': hint}),
        server: _doc({'distanceM': 1, 'updatedAt': DateTime.utc(2026, 9, 9)}),
      ));
      expect(r.summary['updatedAt'], hint);
    });
  });
}
