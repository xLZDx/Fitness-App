// S02 test epic 3, U11 and U23: replaying an import yields one session, and the
// merge does not depend on the input order (5 seeded shuffles of the 155 raw
// records).
import 'package:fitness_app/features/activity/data/activity_merger.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/merge_policy.dart';
import 'package:fitness_app/features/activity/data/source_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/synthetic_activity_corpus.dart';

const _policy = MergePolicy();

String _sig(MergeResult r) =>
    canonicalJson([for (final s in r.sessions) s.toJson()]);

void main() {
  final corpus = SyntheticCorpus.build();
  final raw = corpus.rawCandidates;
  final base = merge(raw, _policy);
  final baseSig = _sig(base);

  test('guard: the 155 raw records merge into the 100 logical workouts', () {
    expect(raw, hasLength(155));
    expect(base.sessions, hasLength(100));
    // The surviving id is the best-ranked member's id, so it is one of the
    // raw ids (not necessarily the id of the logical workout).
    expect({for (final s in raw) s.id}.containsAll([for (final s in base.sessions) s.id]),
        isTrue);
    expect({for (final s in base.sessions) s.id}, hasLength(100));
  });

  group('U11 replay of the same import twice', () {
    test('merge(corpus ++ corpus) equals merge(corpus): count and content', () {
      final twice = merge([...raw, ...raw], _policy);
      expect(twice.sessions, hasLength(base.sessions.length));
      expect(_sig(twice), baseSig);
    });

    test('the order of the duplicate list does not change the result', () {
      final reversed = merge([...raw.reversed, ...raw], _policy);
      final interleaved = merge([
        for (final s in raw) ...[s, s],
      ], _policy);
      final r = SplitMix64(11);
      final shuffled = [...raw, ...raw];
      r.shuffle(shuffled);
      expect(_sig(reversed), baseSig);
      expect(_sig(interleaved), baseSig);
      expect(_sig(merge(shuffled, _policy)), baseSig);
    });

    test('the same recording imported again later (newer importedAt) is still '
        'one session, and the newest import is kept in either order', () {
      final first = raw.firstWhere((s) => s.provenance.length == 1);
      SourceRecord later(SourceRecord p) => SourceRecord(
            sourceId: p.sourceId,
            sourceKind: p.sourceKind,
            importedAt: p.importedAt.add(const Duration(days: 3)),
            deviceModel: p.deviceModel,
            appPackage: p.appPackage,
            externalId: p.externalId,
            fieldsContributed: p.fieldsContributed,
          );
      final again = first.copyWith(provenance: [later(first.provenance.first)]);
      expect(again.id, first.id);
      final ab = merge([first, again], _policy);
      final ba = merge([again, first], _policy);
      expect(ab.sessions, hasLength(1));
      expect(ba.sessions, hasLength(1));
      expect(_sig(ab), _sig(ba));
      expect(ab.sessions.single.provenance.single.importedAt,
          again.provenance.single.importedAt);
    });

    test('control: two DIFFERENT recordings are not collapsed', () {
      final a = raw.firstWhere((s) => s.provenance.length == 1);
      final b = raw.lastWhere((s) => s.id != a.id && s.startUtc != a.startUtc);
      expect(merge([a, b], _policy).sessions.length, greaterThanOrEqualTo(1));
      expect(merge([...raw], _policy).sessions.length, isNot(1));
    });
  });

  group('U23 order independence on the corpus', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      test('seeded shuffle $seed of the 155 raw records gives the same result',
          () {
        final l = [...raw];
        SplitMix64(1000 + seed).shuffle(l);
        expect(l.map((s) => s.id).toList(),
            isNot(raw.map((s) => s.id).toList()),
            reason: 'the shuffle must really reorder');
        expect(_sig(merge(l, _policy)), baseSig);
      });
    }
  });
}
