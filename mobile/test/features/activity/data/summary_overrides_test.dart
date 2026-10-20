// S02-01 U41: summaryOverrides / explicitValues projection (design 3.2 rules
// 1-2), pure level. Every expectation is a literal of plan 1.16 (rows G1-G46),
// held in test/support/golden_override_scenarios.dart or written inline.
import 'dart:convert';

import 'package:fitness_app/features/activity/data/activity_cloud_summary.dart';
import 'package:fitness_app/features/activity/data/activity_migration.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/activity_summary.dart';
import 'package:fitness_app/features/activity/data/activity_versions.dart';
import 'package:fitness_app/features/activity/data/summary_fields.dart';
import 'package:fitness_app/features/activity/data/summary_overrides.dart';
import 'package:fitness_app/features/activity/data/summary_projection.dart';
import 'package:fitness_app/features/activity/data/summary_three_way_merge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_override_scenarios.dart';
import '../../../support/s02_fixtures.dart';

CalcVersions _v(List<String> t) => CalcVersions(
    formulaVersion: t[0], metricDefinitionVersion: t[1], thresholdPolicyVersion: t[2]);

final _v1 = _v(kV1);
final _v2 = _v(kV2);
final _v3 = _v(kV3);

SummaryOverride _o5000({CalcVersions? at, double atComputed = 4800, double? cand}) =>
    SummaryOverride(
        value: 5000, atComputed: atComputed, atVersions: at ?? _v1, atRev: 8, recalcCandidate: cand);

ActivitySession _withRaw(ActivitySession s, double raw) => s.copyWith(
    summary: ActivitySummary.fromFieldMap({...s.summary.toFieldMap(), 'distanceM': raw}));

/// The common state: raw 4 800, override O, versions V1.
ActivitySession _s0() => miniSession(distanceM: 4800)
    .copyWith(versions: _v1, summaryOverrides: {'distanceM': _o5000()});

/// A restart: through the stored JSON text.
ActivitySession _restart(ActivitySession s) => ActivityMigration.read(
    jsonDecode(jsonEncode(s.toJson())))!;

double? _eff(ActivitySession s, [String f = 'distanceM']) => SummaryProjection.effective(s)[f];
double? _raw(ActivitySession s, [String f = 'distanceM']) => SummaryProjection.derive(s)[f];
ActivitySession _rec(ActivitySession s, [CalcVersions? v]) =>
    SummaryProjection.reconcile(s, inForce: v ?? _v1);

Map<String, Object?> _m(double? d, {int rev = 8}) => {
      'startUtc': kMiniStart,
      'sport': 'running',
      'rev': rev,
      if (d != null) 'distanceM': d,
    };

SummaryMergeResult _merge(double? written, double? server, {double base = 5000}) =>
    mergeSummaries(base: _m(base), local: _m(written), server: _m(server));

void main() {
  group('rows of the oracle file (generic driver)', () {
    ActivitySession event(OverrideRow r) {
      final s = _s0();
      switch (r.event) {
        case 'mergeNote added':
        case 'merge note added':
          return s.copyWith(mergeNotes: const ['summaryDisagreement:distanceM']);
        case 'provenance changed':
          return s.copyWith(provenance: [miniSource(), miniSource(sourceId: 'second', externalId: 'e2')]);
        case 'restart':
          return _restart(s);
        case 'input change':
          return _withRaw(s, r.rawAfter);
        case 'versions only':
          return s;
        default:
          // metadata-only mutations: synced, baseRev, queue state, replay, generation
          return _restart(s.copyWith(extras: {'synced': true, 'baseRev': 9, 'queue': 'idle'}));
      }
    }

    for (final r in kOverrideRows) {
      test('${r.id} (${r.kind}): ${r.event}', () {
        final after = event(r);
        expect(_raw(after), r.rawAfter);
        final rec = _rec(after, _v(r.inForce));
        final o = rec.summaryOverrides['distanceM'];
        expect(o != null, r.kept, reason: '${r.id} kept');
        if (r.kept) {
          expect(o!.value, 5000);
          expect(o.atComputed, r.atComputed);
          expect(o.atVersions, _v(r.atVersions!));
          expect(o.recalcCandidate, r.candidate);
        }
        expect(_eff(rec), r.written);
        // Idempotent: a second reconciliation changes nothing.
        expect(_rec(rec, _v(r.inForce)).toJson(), rec.toJson());
        // The written value in the three-way merge (base 5 000).
        final res = _merge(_eff(rec), r.server);
        if (r.outcome == MergeOutcome.conflict) {
          expect(res, isA<SummaryMergeConflict>());
          expect((res as SummaryMergeConflict).fields, ['distanceM']);
        } else {
          expect(res, isA<SummaryMerged>());
          final merged = res as SummaryMerged;
          expect(merged.summary['distanceM'], r.mergedValue);
          expect(merged.adoptedFromServer.contains('distanceM'), r.adopted);
        }
        if (r.adopted) {
          final adopted = SummaryProjection.adoptServerValue(rec, 'distanceM', r.server, 9,
              inForce: _v(r.inForce))!;
          final n = adopted.summaryOverrides['distanceM']!;
          expect([n.value, n.atComputed, n.atVersions, n.atRev, n.recalcCandidate],
              [5400, 4830, _v2, 9, 4830]);
          expect(_eff(adopted), 5400);
        }
      });
    }

    test('G10 versus G27: the version triple decides the kind of the same input change',
        () {
      final inputChange = _withRaw(_s0(), 5100);
      expect(_rec(inputChange, _v1).summaryOverrides, isEmpty);
      expect(_eff(_rec(inputChange, _v1)), 5100);
      final r = _rec(inputChange, _v2);
      expect(r.summaryOverrides['distanceM']!.recalcCandidate, 5100);
      expect(_eff(r), 5000);
    });
  });

  group('overlay and metadata-only mutations (items 1, 3)', () {
    test('the written summary is recompute overlaid with the override; the rest is the recompute',
        () {
      final s = _s0().copyWith(
          summary: const ActivitySummary(distanceM: 4800, ascentM: 77));
      final sum = ActivityCloudSummary.fromSession(s);
      expect(sum['distanceM'], 5000);
      expect(sum['ascentM'], 77);
      expect(sum['movingTimeS'], 1700);
      // A writer that ignores the overrides would emit 4 800.
      expect(SummaryProjection.recompute(s)['distanceM'], 4800);
    });

    test('a new generation with an arbitrarily larger number and repeated synced updates keep it',
        () {
      var s = _s0();
      for (var i = 0; i < 25; i++) {
        s = _restart(s.copyWith(extras: {'generation': 1000 + i, 'synced': i.isEven}));
        s = _rec(s);
        expect(_eff(s), 5000, reason: 'round $i');
      }
      expect(s.summaryOverrides['distanceM'], _o5000());
    });
  });

  group('G15, G16: later changes and per-field independence', () {
    test('G15 a later change that moves the value is not pinned back to the old override',
        () {
      final dropped = _rec(_withRaw(_s0(), 5100));
      expect(dropped.summaryOverrides, isEmpty);
      final back = _rec(_withRaw(dropped, 4800));
      expect(back.summaryOverrides, isEmpty);
      expect(_eff(back), 4800);
      final res = _merge(_eff(back), 5000) as SummaryMerged;
      expect(res.summary['distanceM'], 4800);
    });

    test('G16 dropping the distanceM override leaves the movingTimeS override', () {
      final s = _s0().copyWith(summaryOverrides: {
        'distanceM': _o5000(),
        'movingTimeS': SummaryOverride(
            value: 1800, atComputed: 1700, atVersions: _v1, atRev: 8),
      });
      final r = _rec(_withRaw(s, 5100));
      expect(r.summaryOverrides.keys, ['movingTimeS']);
      expect(_eff(r), 5100);
      expect(_eff(r, 'movingTimeS'), 1800);
    });
  });

  group('G18, G19: creation rules', () {
    test('G18 a field the device cannot recompute is not adopted; keep cloud creates '
        'the override from the held value', () {
      final noValue = miniSession(distanceM: null);
      expect(SummaryProjection.adoptServerValue(noValue, 'distanceM', 5000, 8), isNull);
      final held = miniSession(distanceM: 4800);
      final kept = SummaryProjection.keepCloudValue(held, 'distanceM', 5000, 8, inForce: _v1);
      final o = kept.summaryOverrides['distanceM']!;
      expect([o.value, o.atComputed, o.atRev], [5000, 4800, 8]);
      final again = _rec(_restart(kept));
      expect(again.summaryOverrides['distanceM'], o);
      expect(_eff(again), 5000);
      expect(_merge(_eff(again), 5000), isA<SummaryMerged>());
    });

    test('G19 no override is created for: local-only change, same value both sides, '
        'unchanged field, conflicting field, value == atComputed', () {
      // (i) local-only 4 800 -> 5 100, server 4 800
      final i = _merge(5100, 4800, base: 4800) as SummaryMerged;
      expect(i.summary['distanceM'], 5100);
      expect(i.adoptedFromServer, isEmpty);
      // (ii) both sides 5 000
      final ii = _merge(5000, 5000, base: 4800) as SummaryMerged;
      expect(ii.summary['distanceM'], 5000);
      expect(ii.adoptedFromServer, isEmpty);
      // (iii) unchanged
      final iii = _merge(4800, 4800, base: 4800) as SummaryMerged;
      expect(iii.summary['distanceM'], 4800);
      expect(iii.adoptedFromServer, isEmpty);
      // (iv) conflict: A 5 000, B 5 200
      final iv = _merge(5200, 5000, base: 4800);
      expect(iv, isA<SummaryMergeConflict>());
      // (v) value == atComputed: nothing is created, an older one is removed
      final v = SummaryProjection.adoptServerValue(miniSession(distanceM: 5000), 'distanceM', 5000, 8);
      expect(v!.summaryOverrides, isEmpty);
      final v2 = SummaryProjection.adoptServerValue(_withRaw(_s0(), 5000), 'distanceM', 5000, 9);
      expect(v2!.summaryOverrides, isEmpty);
      // A server-only change IS adopted.
      final adoptable = _merge(4800, 5000, base: 4800) as SummaryMerged;
      expect(adoptable.adoptedFromServer, {'distanceM'});
    });

    test('an out-of-bound or non-overridable server value is not adopted', () {
      expect(SummaryProjection.adoptServerValue(miniSession(), 'distanceM', 2e7, 8), isNull);
      expect(SummaryProjection.adoptServerValue(miniSession(), 'rev', 5, 8), isNull);
    });
  });

  group('explicit edits (kind X), G20-G23', () {
    test('G20 an edit to the value equal to atComputed drops the override at once', () {
      final e = SummaryProjection.applyExplicitEdit(_s0(), {'distanceM': 4800});
      expect(e.summaryOverrides, isEmpty);
      expect(_raw(e), 4800);
      expect(_eff(e), 4800);
      final x = e.explicitValues['distanceM']!;
      expect([x.value, x.atDerived, x.seq], [4800, 4800, 1]);
      for (final r in [_rec(e), _rec(_restart(e)), _rec(_restart(_rec(e)))]) {
        expect(_eff(r), 4800);
        expect(r.summaryOverrides, isEmpty, reason: 'no override reappears');
      }
      final w = _merge(_eff(e), 5000) as SummaryMerged;
      expect(w.summary['distanceM'], 4800);
      expect(_merge(_eff(e), 5200), isA<SummaryMergeConflict>());
    });

    test('G21 an edit to the override value reproduces 5 000 from explicitValues alone',
        () {
      final e = SummaryProjection.applyExplicitEdit(_s0(), {'distanceM': 5000});
      expect(_raw(e), 4800);
      expect(_eff(e), 5000);
      expect(e.summaryOverrides, isEmpty);
      expect((_merge(_eff(e), 5000) as SummaryMerged).summary['distanceM'], 5000);
      for (final r in [_rec(_restart(e)), _rec(SummaryProjection.applyExplicitEdit(e, {'ascentM': 40}))]) {
        expect(_raw(r), 4800);
        expect(_eff(r), 5000);
        expect(r.summaryOverrides, isEmpty);
      }
    });

    test('G22 edit then revert: one entry holds the second edit, count 2, ring has both', () {
      var e = SummaryProjection.applyExplicitEdit(_s0(), {'distanceM': 4800});
      expect(_eff(e), 4800);
      e = SummaryProjection.applyExplicitEdit(e, {'distanceM': 5000});
      expect(_raw(e), 4800);
      expect(_eff(e), 5000);
      expect(e.explicitValues, hasLength(1));
      expect(e.explicitValues['distanceM']!.value, 5000);
      expect(e.explicitValues['distanceM']!.seq, 2);
      expect(e.userEditCount, 2);
      expect([for (final h in e.editHistory) h.value], [4800, 5000]);
      expect(e.summaryOverrides, isEmpty);
      expect(_eff(_rec(_restart(e))), 5000);
    });

    test('G22b the other direction ends on 4 800 and the cloud 5 000 is not restored', () {
      var e = SummaryProjection.applyExplicitEdit(_s0(), {'distanceM': 5100});
      expect(_eff(e), 5100);
      e = SummaryProjection.applyExplicitEdit(e, {'distanceM': 4800});
      expect(_eff(e), 4800);
      expect(e.summaryOverrides, isEmpty);
      expect(_eff(_rec(_restart(e))), 4800);
      expect((_merge(_eff(e), 5000) as SummaryMerged).summary['distanceM'], 4800);
    });

    test('G23 an edit naming only movingTimeS leaves the distanceM override', () {
      final e = SummaryProjection.applyExplicitEdit(_s0(), {'movingTimeS': 1900});
      expect(e.summaryOverrides['distanceM'], _o5000());
      expect(_eff(e), 5000);
      expect(_eff(e, 'movingTimeS'), 1900);
    });

    test('an edit that names no field, an unknown field or an out-of-range value is rejected',
        () {
      expect(() => SummaryProjection.applyExplicitEdit(_s0(), {}), throwsArgumentError);
      expect(() => SummaryProjection.applyExplicitEdit(_s0(), {'rev': 3}), throwsArgumentError);
      expect(() => SummaryProjection.applyExplicitEdit(_s0(), {'distanceM': 2e7}), throwsArgumentError);
      expect(() => SummaryProjection.applyExplicitEdit(_s0(), {'distanceM': -1}), throwsArgumentError);
    });
  });

  group('recalculation (kind R), G24-G29, G32', () {
    ActivitySession g14() => _rec(_withRaw(_s0(), 4830), _v2);

    test('G24 the G14 state survives a restart and a second reconciliation unchanged', () {
      final a = g14();
      final b = _rec(_restart(a), _v2);
      final o = b.summaryOverrides['distanceM']!;
      expect([o.atComputed, o.atVersions, o.recalcCandidate], [4830, _v2, 4830]);
      expect(b.toJson(), a.toJson());
      expect(_eff(b), 5000);
      expect((_merge(_eff(b), 5000) as SummaryMerged).summary['distanceM'], 5000);
    });

    test('G25 a second upgrade only refreshes the single candidate', () {
      final r = _rec(_withRaw(g14(), 4860), _v3);
      final o = r.summaryOverrides['distanceM']!;
      expect([o.atComputed, o.atVersions, o.recalcCandidate, o.value], [4860, _v3, 4860, 5000]);
      expect(_eff(r), 5000);
    });

    test('G26 a downgrade only refreshes the candidate and never overwrites 5 000', () {
      final r = _rec(_withRaw(g14(), 4800), _v1);
      final o = r.summaryOverrides['distanceM']!;
      expect([o.atComputed, o.atVersions, o.recalcCandidate], [4800, _v1, 4800]);
      expect(_eff(r), 5000);
    });

    test('G28 use recalculated value: candidate cleared, override dropped, 4 830 merged three-way',
        () {
      final s = g14();
      expect(SummaryProjection.offeredChoices(s, 'distanceM'),
          {CandidateChoice.useComputed, CandidateChoice.useCloud});
      final res = SummaryProjection.resolveCandidate(s, 'distanceM', CandidateChoice.useComputed,
          baseSummary: _m(5000), serverSummary: _m(5000));
      expect(res.record.summaryOverrides, isEmpty);
      expect(res.localValue, 4830);
      expect(_eff(res.record), 4830);
      expect(res.merge, ResolutionMerge.write);
      final moved = SummaryProjection.resolveCandidate(s, 'distanceM', CandidateChoice.useComputed,
          baseSummary: _m(5000), serverSummary: _m(5200));
      expect(moved.merge, ResolutionMerge.conflict);
      expect(moved.localValue, 4830);
      expect(SummaryProjection.offeredChoices(res.record, 'distanceM'), isEmpty);
      expect(_eff(_rec(_restart(res.record), _v2)), 4830);
    });

    test('G29 keep cloud value: candidate cleared, override kept, zero writes, not suppressed forever',
        () {
      final s = g14();
      final res = SummaryProjection.resolveCandidate(s, 'distanceM', CandidateChoice.useCloud,
          baseSummary: _m(5000), serverSummary: _m(5000));
      expect(res.merge, ResolutionMerge.noWrite);
      final o = res.record.summaryOverrides['distanceM']!;
      expect([o.value, o.recalcCandidate], [5000, null]);
      final r = _rec(_restart(res.record), _v2);
      expect(r.summaryOverrides['distanceM']!.recalcCandidate, isNull,
          reason: 'no candidate again for the same recompute');
      expect(_eff(r), 5000);
      final later = _rec(_withRaw(r, 4860), _v3);
      expect(later.summaryOverrides['distanceM']!.recalcCandidate, 4860);
    });

    test('G30 version reconciliation first, then a passive change is kind P', () {
      final step1 = _rec(_s0(), _v2);
      final o1 = step1.summaryOverrides['distanceM']!;
      expect([o1.atVersions, o1.recalcCandidate, o1.atComputed], [_v2, null, 4800]);
      final step2 = _rec(_withRaw(_restart(step1), 5100), _v2);
      expect(step2.summaryOverrides, isEmpty);
      expect(_eff(step2), 5100);
      expect((_merge(_eff(step2), 5000) as SummaryMerged).summary['distanceM'], 5100);
      expect(_merge(_eff(step2), 5200), isA<SummaryMergeConflict>());
    });

    test('G31 a replayed reconciliation produces the identical record (no second candidate)', () {
      final once = _rec(_s0(), _v2);
      final replay = _rec(_restart(once), _v2);
      final twice = _rec(replay, _v2);
      expect(replay.toJson(), once.toJson());
      expect(twice.toJson(), once.toJson());
    });

    test('G32 only atVersions moves when a record is merely loaded under V2', () {
      final before = _s0();
      final after = _rec(before, _v2);
      final b = before.toJson(), a = after.toJson();
      final bo = Map<String, dynamic>.from(b['summaryOverrides']['distanceM'] as Map);
      final ao = Map<String, dynamic>.from(a['summaryOverrides']['distanceM'] as Map);
      expect(ao['atVersions'], _v2.toJson());
      for (final k in ['value', 'atComputed', 'atRev']) {
        expect(ao[k], bo[k], reason: k);
      }
      expect(ao.containsKey('recalcCandidate'), isFalse);
      // Everything else equals, except the three session version strings, which
      // follow the triple in force (recorded in the findings file).
      final strip = {'summaryOverrides', 'formulaVersion', 'metricDefinitionVersion', 'thresholdPolicyVersion'};
      for (final k in b.keys.where((k) => !strip.contains(k))) {
        expect(jsonEncode(a[k]), jsonEncode(b[k]), reason: k);
      }
      expect(_rec(after, _v2).toJson(), a);
    });
  });

  group('explicit value versus a later raw derivation, G33-G38 (items 13)', () {
    ActivitySession g33() {
      final edited = SummaryProjection.applyExplicitEdit(miniSession(distanceM: 4800), {'distanceM': 4800});
      return _rec(_withRaw(_restart(edited), 5100));
    }

    test('G33 the explicit value is kept, atDerived moves, ONE candidate, no write', () {
      final s = g33();
      final x = s.explicitValues['distanceM']!;
      expect([x.value, x.atDerived, x.sourceCandidate], [4800, 5100, 5100]);
      expect(_raw(s), 5100);
      expect(_eff(s), 4800);
      expect(s.summaryOverrides, isEmpty);
      expect(_rec(s).toJson(), s.toJson(), reason: 'idempotent');
      expect(_rec(_restart(s)).toJson(), s.toJson(), reason: 'survives restart');
      // a second raw change only refreshes
      final s2 = _rec(_withRaw(s, 5200));
      final y = s2.explicitValues['distanceM']!;
      expect([y.value, y.atDerived, y.sourceCandidate], [4800, 5200, 5200]);
      expect(s2.explicitValues, hasLength(1));
    });

    test('a raw value that returns to the edit-time value or to the explicit value clears the candidate',
        () {
      final edited = SummaryProjection.applyExplicitEdit(miniSession(distanceM: 4800), {'distanceM': 4900});
      final withCand = _rec(_withRaw(edited, 5100));
      expect(withCand.explicitValues['distanceM']!.sourceCandidate, 5100);
      final backToEdit = _rec(_withRaw(withCand, 4800)).explicitValues['distanceM']!;
      expect([backToEdit.sourceCandidate, backToEdit.atDerived, backToEdit.value], [null, 4800, 4900]);
      final toValue = _rec(_withRaw(withCand, 4900)).explicitValues['distanceM']!;
      expect(toValue.sourceCandidate, isNull);
      // raw unchanged -> nothing happens
      final same = _rec(edited).explicitValues['distanceM']!;
      expect([same.atDerived, same.sourceCandidate], [4800, null]);
    });

    test('G34 a concurrent cloud change is adopted above the explicit value; the candidate stays',
        () {
      final adopted = SummaryProjection.adoptServerValue(g33(), 'distanceM', 5400, 9, inForce: _v1)!;
      final o = adopted.summaryOverrides['distanceM']!;
      expect([o.value, o.atComputed, o.atVersions, o.atRev], [5400, 4800, _v1, 9]);
      expect(adopted.explicitValues['distanceM']!.sourceCandidate, 5100);
      expect(_eff(adopted), 5400);
    });

    test('G35 use the new computed value (no override): entry removed, 5 100 merged three-way',
        () {
      final s = g33();
      expect(SummaryProjection.offeredChoices(s, 'distanceM'),
          {CandidateChoice.useComputed, CandidateChoice.keepMine});
      final r = SummaryProjection.resolveCandidate(s, 'distanceM', CandidateChoice.useComputed,
          baseSummary: _m(4800), serverSummary: _m(4800));
      expect(r.record.explicitValues, isEmpty);
      expect(_eff(r.record), 5100);
      expect(r.merge, ResolutionMerge.write);
      expect(SummaryProjection.resolveCandidate(s, 'distanceM', CandidateChoice.useComputed,
              baseSummary: _m(4800), serverSummary: _m(5200)).merge,
          ResolutionMerge.conflict);
      expect(_eff(_rec(_restart(r.record))), 5100);
    });

    test('G36 keep my value: candidate cleared, entry kept, later change records a NEW candidate',
        () {
      final r = SummaryProjection.resolveCandidate(g33(), 'distanceM', CandidateChoice.keepMine,
          baseSummary: _m(4800), serverSummary: _m(4800));
      final x = r.record.explicitValues['distanceM']!;
      expect([x.value, x.atDerived, x.sourceCandidate], [4800, 5100, null]);
      expect(_eff(r.record), 4800);
      expect(_rec(_restart(r.record)).explicitValues['distanceM']!.sourceCandidate, isNull);
      final later = _rec(_withRaw(r.record, 5300)).explicitValues['distanceM']!;
      expect(later.sourceCandidate, 5300);
    });

    test('G37 a calculation upgrade under an explicit value takes the same path', () {
      final edited = SummaryProjection.applyExplicitEdit(miniSession(distanceM: 4800), {'distanceM': 4800});
      final up = _rec(_withRaw(edited, 4830), _v2);
      final x = up.explicitValues['distanceM']!;
      expect([x.atDerived, x.sourceCandidate, x.value], [4830, 4830, 4800]);
      final again = _rec(_withRaw(up, 4860), _v3).explicitValues['distanceM']!;
      expect(again.sourceCandidate, 4860);
      expect(_eff(up), 4800);
    });

    test('G38 an explicit edit while a candidate exists replaces the entry and clears it', () {
      final e = SummaryProjection.applyExplicitEdit(g33(), {'distanceM': 4900});
      final x = e.explicitValues['distanceM']!;
      expect([x.value, x.atDerived, x.sourceCandidate, x.seq], [4900, 5100, null, 2]);
      expect(_eff(e), 4900);
      expect(e.summaryOverrides, isEmpty);
      expect(SummaryProjection.offeredChoices(e, 'distanceM'), isEmpty);
    });
  });

  group('bounded ring and saturating counter, G39, G40 (item 14)', () {
    ActivitySession run(int n, Map<String, double> Function(int k) edit) {
      var s = miniSession();
      for (var k = 1; k <= n; k++) {
        s = SummaryProjection.applyExplicitEdit(s, edit(k));
      }
      return s;
    }

    test('G39 63, 64, 65, 100 operations: count, ring length and oldest surviving operation',
        () {
      const expected = {
        63: (63, 63, 1),
        64: (64, 64, 1),
        65: (64, 64, 2),
        100: (64, 64, 37),
      };
      for (final e in expected.entries) {
        final s = run(e.key, (k) => {'distanceM': 1000.0 + k});
        expect([s.userEditCount, s.editHistory.length, s.editHistory.first.seq],
            [e.value.$1, e.value.$2, e.value.$3], reason: 'n=${e.key}');
        expect(s.explicitValues, hasLength(1));
        expect(_eff(s), 1000.0 + e.key);
        // deleting the ring changes nothing in the effective summary
        expect(_eff(s.copyWith(editHistory: const [])), 1000.0 + e.key);
      }
    });

    test('G40 repeated edit/revert of one field ends on the last operation', () {
      for (final n in [64, 65, 100]) {
        final s = run(n, (k) => {'distanceM': k.isOdd ? 5000.0 : 4800.0});
        expect(_eff(s), n.isOdd ? 5000 : 4800, reason: 'n=$n');
        expect(s.explicitValues['distanceM']!.seq, n);
        expect(s.userEditCount, n > 64 ? 64 : n);
      }
    });

    test('several fields: one entry per field, the last operation wins per field', () {
      const f = ['distanceM', 'ascentM', 'descentM'];
      final s = run(100, (k) => {f[k % 3]: 2000.0 + k});
      expect(s.explicitValues.keys.toSet(), f.toSet());
      expect(_eff(s, f[100 % 3]), 2100);
      expect(_eff(s, f[99 % 3]), 2099);
      expect(_eff(s, f[98 % 3]), 2098);
    });

    test('one operation naming two fields counts once and adds two ring entries', () {
      final s = SummaryProjection.applyExplicitEdit(miniSession(), {'distanceM': 5, 'ascentM': 6});
      expect([s.userEditCount, s.editHistory.length], [1, 2]);
      expect(s.editHistory.map((h) => h.seq).toSet(), {1});
    });
  });

  group('atomic candidate resolution, G41-G46 (item 15)', () {
    // S34: explicit {4800, atDerived 5100, seq 1}, override {5400, atComputed 4800, V1, 8},
    // candidate 5100, raw 5100, base 5400, server 5400.
    ActivitySession s34() => miniSession(distanceM: 5100).copyWith(
          versions: _v1,
          userEditCount: 1,
          explicitValues: const {
            'distanceM': ExplicitValue(
                value: 4800, atDerived: 5100, editDerived: 4800, seq: 1, sourceCandidate: 5100),
          },
          summaryOverrides: {
            'distanceM': SummaryOverride(value: 5400, atComputed: 4800, atVersions: _v1, atRev: 8),
          },
        );
    ActivitySession s33() => miniSession(distanceM: 5100).copyWith(
          versions: _v1,
          userEditCount: 1,
          explicitValues: const {
            'distanceM': ExplicitValue(
                value: 4800, atDerived: 5100, editDerived: 4800, seq: 1, sourceCandidate: 5100),
          },
        );

    CandidateResolution res(ActivitySession s, CandidateChoice c, {double base = 5400, double server = 5400}) =>
        SummaryProjection.resolveCandidate(s, 'distanceM', c,
            baseSummary: _m(base), serverSummary: _m(server));

    test('S34 itself: raw 5 100, effective 5 400, three choices offered', () {
      final s = s34();
      expect([_raw(s), _eff(s)], [5100, 5400]);
      expect(SummaryProjection.offeredChoices(s, 'distanceM'),
          {CandidateChoice.useComputed, CandidateChoice.keepMine, CandidateChoice.useCloud});
    });

    test('G41 (1) use the new computed value: explicit, override and candidate gone; write 5 100',
        () {
      final r = res(s34(), CandidateChoice.useComputed);
      expect(r.record.explicitValues, isEmpty);
      expect(r.record.summaryOverrides, isEmpty);
      expect(SummaryProjection.offeredChoices(r.record, 'distanceM'), isEmpty);
      expect(_eff(r.record), 5100);
      expect([r.merge, r.localValue], [ResolutionMerge.write, 5100]);
      // The merge reads the CURRENT base 5 400; the stale pre-adoption base 4 800 would conflict.
      expect(res(s34(), CandidateChoice.useComputed, base: 4800).merge, ResolutionMerge.conflict);
    });

    test('G42 (2) keep my value: entry kept, override removed; write 4 800', () {
      final r = res(s34(), CandidateChoice.keepMine);
      final x = r.record.explicitValues['distanceM']!;
      expect([x.value, x.atDerived, x.seq, x.sourceCandidate], [4800, 5100, 1, null]);
      expect(r.record.summaryOverrides, isEmpty);
      expect(_eff(r.record), 4800);
      expect([r.merge, r.localValue], [ResolutionMerge.write, 4800]);
    });

    test('G43 (3) use the cloud value: explicit removed, override kept with atComputed moved to the raw value',
        () {
      final r = res(s34(), CandidateChoice.useCloud);
      expect(r.record.explicitValues, isEmpty);
      final o = r.record.summaryOverrides['distanceM']!;
      expect([o.value, o.atComputed, o.atVersions, o.atRev, o.recalcCandidate], [5400, 5100, _v1, 8, null]);
      expect(r.merge, ResolutionMerge.noWrite);
      expect(_eff(r.record), 5400);
      // The cloud value survives the next load; without the move it would be dropped.
      expect(_eff(_rec(_restart(r.record))), 5400);
      // A later passive raw change follows the G10 path.
      final later = _rec(_withRaw(r.record, 5300));
      expect(later.summaryOverrides, isEmpty);
      expect((_merge(_eff(later), 5400, base: 5400) as SummaryMerged).summary['distanceM'], 5300);
    });

    test('G44 the server changed again to 5 600: (1) and (2) end in conflict with the local value kept',
        () {
      final one = res(s34(), CandidateChoice.useComputed, server: 5600);
      expect([one.merge, one.localValue], [ResolutionMerge.conflict, 5100]);
      expect(one.record.summaryOverrides, isEmpty, reason: 'the old override is not restored');
      final two = res(s34(), CandidateChoice.keepMine, server: 5600);
      expect([two.merge, two.localValue], [ResolutionMerge.conflict, 4800]);
      expect(two.record.summaryOverrides, isEmpty);
      final three = res(s34(), CandidateChoice.useCloud, server: 5600);
      expect(three.merge, ResolutionMerge.noWrite);
      final adopted = SummaryProjection.adoptServerValue(three.record, 'distanceM', 5600, 9, inForce: _v1)!;
      final o = adopted.summaryOverrides['distanceM']!;
      expect([o.value, o.atComputed, o.atVersions, o.atRev], [5600, 5100, _v1, 9]);
    });

    test('G45 only (1) and (2) are offered without an override; order independence', () {
      final s = s33();
      expect(SummaryProjection.offeredChoices(s, 'distanceM'),
          {CandidateChoice.useComputed, CandidateChoice.keepMine});
      expect(() => res(s, CandidateChoice.useCloud, base: 4800, server: 4800), throwsArgumentError);
      // (b1) resolve (1) offline, then the cloud moves to 5 400: conflict, local preserved, no override.
      final b1 = res(s, CandidateChoice.useComputed, base: 4800, server: 4800);
      expect(b1.record.summaryOverrides, isEmpty);
      final conflict = mergeSummaries(base: _m(4800), local: _m(_eff(b1.record)), server: _m(5400));
      expect(conflict, isA<SummaryMergeConflict>());
      expect(_eff(b1.record), 5100);
      // (b2) resolve (2) offline, then 5 400 arrives: adopted through a NEW override above the entry.
      final b2 = res(s, CandidateChoice.keepMine, base: 4800, server: 4800);
      expect(b2.merge, ResolutionMerge.noWrite);
      final adopted = SummaryProjection.adoptServerValue(b2.record, 'distanceM', 5400, 9, inForce: _v1)!;
      final o = adopted.summaryOverrides['distanceM']!;
      expect([o.value, o.atComputed, o.atRev], [5400, 4800, 9]);
      expect(adopted.explicitValues, isNotEmpty);
      expect(_eff(adopted), 5400);
      // (b3) the cloud equals the local value: converges.
      expect(res(s, CandidateChoice.useComputed, base: 4800, server: 5100).merge, ResolutionMerge.noWrite);
    });

    test('G46 durability and idempotence: restart, replay, a later independent edit', () {
      for (final c in [CandidateChoice.useComputed, CandidateChoice.keepMine, CandidateChoice.useCloud]) {
        final r = res(s34(), c);
        final expectedEff = {
          CandidateChoice.useComputed: 5100,
          CandidateChoice.keepMine: 4800,
          CandidateChoice.useCloud: 5400,
        }[c];
        // (s1/s2) from the stored record alone
        final back = _rec(_restart(r.record));
        expect(back.toJson(), r.record.toJson(), reason: '$c restart');
        expect(_eff(back), expectedEff, reason: '$c');
        expect(SummaryProjection.offeredChoices(back, 'distanceM'), isEmpty);
        // (s4) the retried resolution is a no-op
        final again = res(r.record, c);
        expect(again.record.toJson(), r.record.toJson(), reason: '$c replay');
        expect(again.merge, ResolutionMerge.noWrite);
        // (s5) a later independent edit keeps the chosen value
        final edited = SummaryProjection.applyExplicitEdit(r.record, {'ascentM': 40});
        expect(_eff(edited), expectedEff, reason: '$c after edit');
        expect(_eff(edited, 'ascentM'), 40);
      }
      // (s1) every structure of S34 survives a restart.
      expect(_restart(s34()).toJson(), s34().toJson());
    });
  });

  group('tolerant JSON of the record state (items 9, 11)', () {
    ActivitySession full() => miniSession().copyWith(
          versions: _v1,
          userEditCount: 2,
          editHistory: const [EditHistoryEntry(field: 'distanceM', value: 5, seq: 1)],
          explicitValues: const {
            'distanceM': ExplicitValue(value: 5, atDerived: 4800, editDerived: 4800, seq: 1),
            'ascentM': ExplicitValue(value: 9, atDerived: null, editDerived: null, seq: 2),
          },
          summaryOverrides: {
            'movingTimeS': SummaryOverride(
                value: 1800, atComputed: 1700, atVersions: _v2, atRev: 8, recalcCandidate: 1750),
            'steps': SummaryOverride(value: 10, atComputed: 9, atVersions: _v1, atRev: 3),
          },
        );

    test('explicitValues, overrides (with and without candidate) and the ring round trip deep-equal',
        () {
      final s = full();
      final b = _restart(s);
      expect(b.explicitValues, s.explicitValues);
      expect(b.summaryOverrides, s.summaryOverrides);
      expect(b.summaryOverrides['movingTimeS']!.atVersions, _v2);
      expect(b.summaryOverrides['movingTimeS']!.recalcCandidate, 1750);
      expect(b.summaryOverrides['steps']!.recalcCandidate, isNull);
      expect(b.editHistory, s.editHistory);
      expect(b.userEditCount, 2);
    });

    test('bad entries are dropped one by one without throwing and without touching others',
        () {
      final m = deepCopy(full().toJson());
      (m['summaryOverrides'] as Map)['lats'] = {'value': 1, 'atComputed': 1, 'atVersions': _v1.toJson(), 'atRev': 1};
      (m['summaryOverrides'] as Map)['distanceM'] = {'value': 5000, 'atComputed': 4800, 'atRev': 8}; // no atVersions
      (m['summaryOverrides'] as Map)['ascentM'] = {'value': 'x', 'atComputed': 1, 'atVersions': _v1.toJson(), 'atRev': 1};
      (m['summaryOverrides'] as Map)['descentM'] = {'value': 1e9, 'atComputed': 1, 'atVersions': _v1.toJson(), 'atRev': 1};
      (m['explicitValues'] as Map)['rev'] = {'value': 1, 'atDerived': 1, 'seq': 1};
      (m['explicitValues'] as Map)['descentM'] = {'value': 1, 'seq': 1}; // missing atDerived
      (m['explicitValues'] as Map)['avgSwolf'] = {'value': 'a', 'atDerived': 1, 'seq': 1};
      (m['explicitValues'] as Map)['steps'] = {'value': 5e9, 'atDerived': 1, 'seq': 1};
      final s = ActivityMigration.read(m)!;
      expect(s.summaryOverrides.keys.toSet(), {'movingTimeS', 'steps'});
      expect(s.explicitValues.keys.toSet(), {'distanceM', 'ascentM'});
      final cloud = ActivityCloudSummary.fromSession(s);
      expect(cloud.keys.every(kSummaryAllowedKeys.contains), isTrue);
    });

    test('a ring longer than 64 is trimmed to the newest 64; garbage ring entries are ignored',
        () {
      final m = deepCopy(full().toJson());
      m['editHistory'] = [
        for (var k = 1; k <= 80; k++) {'field': 'distanceM', 'value': k, 'seq': k},
        'garbage', null, {'field': 3}, {'field': 'x', 'value': double.nan.toString(), 'seq': 1},
      ];
      final s = ActivityMigration.read(m)!;
      expect(s.editHistory, hasLength(64));
      expect([s.editHistory.first.seq, s.editHistory.last.seq], [17, 80]);
    });

    test('the effective summary is identical whatever the ring holds', () {
      final base = full();
      final variants = [
        base.copyWith(editHistory: const []),
        base.copyWith(editHistory: [
          for (var k = 0; k < 64; k++) EditHistoryEntry(field: 'distanceM', value: 1.0 + k, seq: k),
        ]),
        base.copyWith(editHistory: const [EditHistoryEntry(field: 'zzz', value: 1, seq: 9)]),
        base.copyWith(editHistory: const [EditHistoryEntry(field: 'distanceM', value: 99999, seq: 50)]),
      ];
      final expected = SummaryProjection.effective(base);
      for (final v in variants) {
        expect(SummaryProjection.effective(v), expected);
        expect(SummaryProjection.recompute(v), SummaryProjection.recompute(base));
        expect(SummaryProjection.derive(v), SummaryProjection.derive(base));
      }
    });

    test('precedence: raw, then explicit value, then override; raw never contains the edit', () {
      final s = miniSession(distanceM: 4800).copyWith(
        explicitValues: const {'distanceM': ExplicitValue(value: 5000, atDerived: 4800, editDerived: 4800, seq: 1)},
      );
      expect([_raw(s), SummaryProjection.recompute(s)['distanceM'], _eff(s)], [4800, 5000, 5000]);
      final withOverride = s.copyWith(summaryOverrides: {
        'distanceM': SummaryOverride(value: 5400, atComputed: 5000, atVersions: _v1, atRev: 3),
      });
      expect(_eff(withOverride), 5400);
      expect(SummaryProjection.recompute(withOverride)['distanceM'], 5000);
      // Neither explicit value nor override: effective equals raw.
      expect(_eff(miniSession(distanceM: 4800)), 4800);
      // The rule compares against the explicit value, not the raw one.
      final r = _rec(withOverride.copyWith(summaryOverrides: {
        'distanceM': SummaryOverride(value: 5400, atComputed: 4800, atVersions: _v1, atRev: 3),
      }));
      expect(r.summaryOverrides, isEmpty, reason: 'recompute 5 000 differs from atComputed 4 800');
    });

    test('the functions are pure and deterministic', () {
      final s = _withRaw(_s0(), 4830);
      expect(_rec(s, _v2).toJson(), _rec(s, _v2).toJson());
      final before = jsonEncode(s.toJson());
      SummaryProjection.reconcile(s, inForce: _v2);
      SummaryProjection.applyExplicitEdit(s, {'distanceM': 1});
      SummaryProjection.effective(s);
      expect(jsonEncode(s.toJson()), before, reason: 'inputs are never mutated');
    });
  });
}
