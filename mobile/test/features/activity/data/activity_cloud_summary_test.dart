// S02-01 U05 (summary is scalar only), U07 (hasRoute is a flag), U13 (A-5
// provenance strings), U38 (rev serialisation and the saturating counter).
import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/activity_migration.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/lap.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/firestore_rules_parser.dart';
import '../../../support/s02_fixtures.dart';
import '../../../support/synthetic_activity_corpus.dart';

const _forbidden = <String>{
  'avgHrBpm', 'maxHrBpm', 'lats', 'lons', 'polyline', 'points', 'bbox',
  'startLat', 'startLon', 'laps', 'provenance', 'extras', 'userEdits',
  'explicitValues', 'sourceCandidate', 'recalcCandidate', 'mergeNotes',
  'visibility',
};

Map<String, Object> _first(ActivitySession s) => ActivityCloudSummary.fromSession(s);

bool _isForbiddenKey(String k) =>
    _forbidden.contains(k) || k.startsWith('place') || k.startsWith('friend');

void main() {
  final corpus = SyntheticCorpus.build();
  final rules = parseActivityRules();

  group('U05 the summary holds scalars only', () {
    test('for all 100 sessions: scalar values, no forbidden key, rules accept it',
        () {
      for (final s in corpus.valid) {
        final sum = _first(s);
        for (final e in sum.entries) {
          final v = e.value;
          expect(v is num || v is String || v is bool || v is DateTime, isTrue,
              reason: '${s.id} ${e.key} is ${v.runtimeType}');
          expect(_isForbiddenKey(e.key), isFalse, reason: '${s.id} ${e.key}');
        }
        expect(rulesViolations(rules, sum), isEmpty, reason: s.id);
      }
    });

    test('sentinel latitude tail 7351 and heart rate 173.25 never reach the summary',
        () {
      final s = ActivitySession(
        id: kMiniId,
        sport: SportType.running,
        startUtc: kMiniStart,
        endUtc: kMiniStart.add(const Duration(minutes: 10)),
        summary: const ActivitySummary(
            distanceM: 1234.5, avgHrBpm: 173.25, maxHrBpm: 173.25),
        streams: {
          StreamKind.gps: SampleStream.checked(
            kind: StreamKind.gps,
            sourceId: 'phone',
            offsetsMs: const [0, 1000],
            lats: const [2.3456787351, 2.3456887351],
            lons: const [-27.1, -27.2],
          ),
          StreamKind.heartRate: SampleStream.checked(
            kind: StreamKind.heartRate,
            sourceId: 'strap',
            offsetsMs: const [0, 1000],
            values: const [173.25, 170.25],
          ),
        },
        laps: const [
          Lap(index: 0, kind: LapKind.auto, startOffsetS: 0, durationS: 60, avgHrBpm: 173.25),
        ],
      );
      final text = jsonSummary(_first(s));
      expect(text.contains('173.25'), isFalse);
      expect(text.contains('7351'), isFalse);
      expect(text.contains('2.3456'), isFalse);
      // Contrast: the record itself does carry both strings.
      final record = s.toJson().toString();
      expect(record.contains('173.25') && record.contains('7351'), isTrue);
    });

    test('every corpus session: no coordinate or heart-rate value text in the summary',
        () {
      final hrToken = RegExp(r'(?<![0-9.])\d{2,3}\.25(?![0-9])');
      for (final s in corpus.valid) {
        final text = jsonSummary(_first(s));
        final gps = s.streams[StreamKind.gps];
        if (gps != null) {
          for (var i = 0; i < gps.length && i < 20; i++) {
            final lat = '${gps.lats[i]}';
            if (lat.endsWith('7351')) {
              expect(text.contains(lat), isFalse, reason: s.id);
            }
          }
        }
        final hr = s.streams[StreamKind.heartRate];
        if (hr != null) {
          final max = hr.values.reduce((a, b) => a > b ? a : b);
          expect(text.contains('$max'), isFalse, reason: '${s.id} max HR leaked');
          expect(hrToken.hasMatch(text), isFalse, reason: '${s.id}: ${hrToken.firstMatch(text)?.group(0)}');
        }
      }
    });

    test('unknown keys kept in extras never leak into the summary', () {
      final m = deepCopy(miniSession().toJson())
        ..['lats'] = [1.0, 2.0]
        ..['friendIds'] = ['u1']
        ..['visibility'] = 'public'
        ..['placeName'] = 'Home'
        ..['polyline'] = 'abc'
        ..['summary'] = {'distanceM': 100.0, 'bbox': [1, 2, 3, 4]};
      final s = ActivityMigration.read(m)!;
      expect(s.extras.keys, containsAll(['lats', 'friendIds', 'visibility']));
      final sum = _first(s);
      for (final k in sum.keys) {
        expect(_isForbiddenKey(k), isFalse, reason: k);
      }
      expect(sum['distanceM'], 100.0);
      expect(jsonSummary(sum).contains('Home'), isFalse);
    });
  });

  group('U07 hasRoute is a flag only', () {
    test('GPS session true, indoor false, an empty GPS stream false', () {
      final gps = miniSession(streams: {
        StreamKind.gps: SampleStream.checked(
          kind: StreamKind.gps,
          sourceId: 'phone',
          offsetsMs: const [0, 1000],
          lats: const [1.0000007351, 1.0000107351],
          lons: const [-27.0, -27.1],
        ),
      });
      expect(_first(gps)['hasRoute'], true);
      expect(_first(miniSession())['hasRoute'], false);
      final empty = miniSession(streams: {
        StreamKind.gps: SampleStream.checked(
            kind: StreamKind.gps, sourceId: 'phone', offsetsMs: const []),
      });
      expect(_first(empty)['hasRoute'], false);
      // No coordinate accompanies the flag.
      for (final k in _first(gps).keys) {
        expect(k.toLowerCase().contains('lat') || k.toLowerCase().contains('lon'),
            isFalse, reason: k);
      }
    });

    test('over the corpus hasRoute equals "has a non-empty GPS stream"', () {
      for (final s in corpus.valid) {
        final has = (s.streams[StreamKind.gps]?.length ?? 0) > 0;
        expect(_first(s)['hasRoute'], has, reason: s.id);
      }
      expect(corpus.valid.where((s) => _first(s)['hasRoute'] == true), hasLength(38));
    });
  });

  group('U13 A-5 provenance strings', () {
    test('defaults are emitted and valid on all 100 sessions', () {
      final re = RegExp(r'^[A-Za-z0-9._:-]{1,32}$');
      for (final s in corpus.valid) {
        final sum = _first(s);
        for (final k in const ['formulaVersion', 'metricDefinitionVersion', 'thresholdPolicyVersion']) {
          expect(re.hasMatch(sum[k] as String), isTrue, reason: '${s.id} $k');
        }
        final t = sum['sourceTermsSnapshot'];
        if (t != null) {
          expect((t as String).length, inInclusiveRange(1, 64));
          expect(t.contains(RegExp(r'\s')), isFalse);
        }
      }
    });

    test('empty, over-long or whitespace strings are never emitted', () {
      ActivitySession withV(String f, {String? terms}) => miniSession().copyWith(
            versions: CalcVersions(
                formulaVersion: f,
                metricDefinitionVersion: 'm1',
                thresholdPolicyVersion: 't1'),
            sourceTermsSnapshot: terms,
          );
      expect(_first(withV(''))['formulaVersion'], isNull);
      expect(_first(withV('x' * 33))['formulaVersion'], isNull);
      expect(_first(withV('x' * 32))['formulaVersion'], 'x' * 32);
      expect(_first(withV('has space'))['formulaVersion'], isNull);
      expect(_first(withV('f1', terms: 'y' * 65))['sourceTermsSnapshot'], isNull);
      expect(_first(withV('f1', terms: 'y' * 64))['sourceTermsSnapshot'], 'y' * 64);
      expect(_first(withV('f1', terms: 'we agree to the terms'))['sourceTermsSnapshot'], isNull);
      expect(_first(withV('f1', terms: 'tos-2026:abc='))['sourceTermsSnapshot'], 'tos-2026:abc=');
    });

    test('terms text smuggled through a stored record is rejected by the reader',
        () {
      final m = deepCopy(miniSession().toJson())
        ..['sourceTermsSnapshot'] = 'Terms: you agree to everything'
        ..['formulaVersion'] = 'a b';
      final s = ActivityMigration.read(m)!;
      expect(s.sourceTermsSnapshot, isNull);
      expect(s.formulaVersion, 'formula-1');
      expect(_first(s).containsKey('sourceTermsSnapshot'), isFalse);
    });
  });

  group('U38 rev serialisation and the saturating userEditCount', () {
    bool changed(Map<String, Object> a, Map<String, Object> b) {
      final keys = {...a.keys, ...b.keys}..removeAll(['rev', 'updatedAt']);
      for (final k in keys) {
        final x = a[k], y = b[k];
        final same = x is num && y is num ? x.toDouble() == y.toDouble() : x == y;
        if (!same) return true;
      }
      return false;
    }

    Map<String, Object> next(ActivitySession s, Map<String, Object> prev) =>
        ActivityCloudSummary.fromSession(s,
            previousSummary: prev, previousRev: prev['rev'] as int);

    test('first summary has rev 1; unchanged re-serialisation keeps it', () {
      final s = miniSession();
      final a = _first(s);
      expect(a['rev'], 1);
      expect(a['rev'], isA<int>());
      expect(next(s, a)['rev'], 1);
      expect(next(s, next(s, a))['rev'], 1);
    });

    test('a changed summary value raises rev by exactly one each time', () {
      var s = miniSession();
      var prev = _first(s);
      for (var k = 1; k <= 5; k++) {
        s = s.copyWith(summary: ActivitySummary(distanceM: 4800.0 + k));
        final n = next(s, prev);
        expect(n['rev'], 1 + k);
        prev = n;
      }
    });

    test('rev does not depend on the clock', () {
      final s = miniSession();
      final a = _first(s);
      final t0 = DateTime.utc(2026, 5, 1);
      final back = ActivityCloudSummary.fromSession(s,
          previousSummary: a, previousRev: 1, updatedAt: t0.subtract(const Duration(days: 1)));
      final fwd = ActivityCloudSummary.fromSession(s,
          previousSummary: a, previousRev: 1, updatedAt: t0.add(const Duration(days: 3650)));
      expect(back['rev'], 1);
      expect(fwd['rev'], 1);
      expect({...back}..remove('updatedAt'), {...fwd}..remove('updatedAt'));
      // A change still bumps whatever the clock says.
      final changedSession = s.copyWith(summary: const ActivitySummary(distanceM: 1));
      expect(
          ActivityCloudSummary.fromSession(changedSession,
              previousSummary: a, previousRev: 1, updatedAt: t0.subtract(const Duration(days: 1)))['rev'],
          2);
    });

    test('a device-only change (merge note text) does not bump rev; a count change does',
        () {
      final s = miniSession(mergeNotes: const ['summaryDisagreement:distanceM']);
      final a = _first(s);
      final rewritten = s.copyWith(mergeNotes: const ['summaryDisagreement:ascentM']);
      final b = next(rewritten, a);
      expect(b['rev'], 1);
      expect(changed(a, b), isFalse);
      final more = s.copyWith(mergeNotes: const ['a', 'b']);
      expect(next(more, a)['rev'], 2);
      expect(next(s.copyWith(userEditCount: 1), a)['rev'], 2);
    });

    test('rev is clamped into 1..1000000', () {
      final s = miniSession();
      final a = _first(s);
      final top = ActivityCloudSummary.fromSession(
          s.copyWith(summary: const ActivitySummary(distanceM: 9)),
          previousSummary: a,
          previousRev: 1000000);
      expect(top['rev'], 1000000);
      final low = ActivityCloudSummary.fromSession(s, previousSummary: a, previousRev: -5);
      expect(low['rev'], inInclusiveRange(1, 1000000));
    });

    // Literal table: n sequential explicit edit operations -> userEditCount.
    const table = {0: 0, 1: 1, 2: 2, 63: 63, 64: 64, 65: 64, 100: 64};

    void runTable(String label, Map<String, double> Function(int k) edit) {
      test('$label: counts 0,1,2,63,64,64,64 and rev advances iff a value changed',
          () {
        var s = miniSession();
        var prev = _first(s);
        final byN = <int, int>{0: prev['userEditCount'] as int};
        var lastCount = 0;
        for (var k = 1; k <= 100; k++) {
          s = SummaryProjection.applyExplicitEdit(s, edit(k));
          final n = next(s, prev);
          final count = n['userEditCount'] as int;
          expect(count, inInclusiveRange(0, 64));
          expect(count, greaterThanOrEqualTo(lastCount), reason: 'never decreases');
          expect(rulesViolations(rules, n), isEmpty, reason: 'edit $k');
          final bumped = (n['rev'] as int) - (prev['rev'] as int);
          expect(bumped, changed(prev, n) ? 1 : 0, reason: 'edit $k');
          if (k > 64) {
            expect(count, 64, reason: 'edits 65..100 stay at the cap');
            expect(bumped, 1, reason: 'a changed value still raises rev at the cap');
          }
          byN[k] = count;
          lastCount = count;
          prev = n;
        }
        for (final e in table.entries) {
          expect(byN[e.key], e.value, reason: 'n=${e.key}');
        }
        // The count is independent of both lists.
        expect(s.editHistory.length, 64);
        expect(_first(s)['userEditCount'], 64);
        expect(_first(s.copyWith(editHistory: const []))['userEditCount'], 64);
        final tenOfRing = s.copyWith(userEditCount: 10);
        expect(tenOfRing.editHistory.length, 64);
        expect(_first(tenOfRing)['userEditCount'], 10);
      });
    }

    runTable('one field edited repeatedly', (k) => {'distanceM': k.isOdd ? 5000.0 : 5100.0});
    runTable('edit/revert pairs', (k) => {'distanceM': k.isOdd ? 5000.0 : 4800.0});
    runTable('cycling over several fields', (k) {
      const f = ['distanceM', 'ascentM', 'descentM', 'movingTimeS'];
      return {f[k % 4]: 1000.0 + k};
    });

    test('at the cap an edit that changes no value leaves rev and the summary identical',
        () {
      var s = miniSession();
      for (var k = 1; k <= 64; k++) {
        s = SummaryProjection.applyExplicitEdit(s, {'distanceM': 5000.0 + k});
      }
      final prev = _first(s);
      expect(prev['userEditCount'], 64);
      final same = SummaryProjection.applyExplicitEdit(s, {'distanceM': 5064.0});
      final n = ActivityCloudSummary.fromSession(same,
          previousSummary: prev, previousRev: 1);
      expect(n['rev'], 1);
      expect(n, prev);
      expect(rulesViolations(rules, n), isEmpty);
    });

    test('below the cap an edit to the value already shown still raises rev by one',
        () {
      var s = SummaryProjection.applyExplicitEdit(miniSession(), {'distanceM': 4800.0});
      final prev = _first(s);
      expect(prev['userEditCount'], 1);
      s = SummaryProjection.applyExplicitEdit(s, {'distanceM': 4800.0});
      final n = next(s, prev);
      expect(n['userEditCount'], 2);
      expect(n['rev'], 2);
      expect(n['distanceM'], 4800.0);
    });

    test('one operation naming two fields counts once', () {
      final s = SummaryProjection.applyExplicitEdit(
          miniSession(), {'distanceM': 5000.0, 'ascentM': 40.0});
      expect(_first(s)['userEditCount'], 1);
      expect(s.editHistory, hasLength(2));
    });
  });
}
