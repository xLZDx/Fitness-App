// RECOG-C1 — the metric script's own rules, tested before there are numbers.
//
// The step-8 tool decides what counts, what is excluded, and what is named as
// non-comparable. Every one of those decisions is a place where a wrong answer
// looks exactly like a right one: a silently dropped pair, a silently deduped
// duplicate, an operational failure quietly diluting a semantic denominator.
// None of that is visible in the output, which is why it is tested here rather
// than checked by eye once the run exists.
//
// Synthetic rows throughout, deliberately. Testing this against the real run
// would make the test a description of whatever happened rather than a check
// of the rules.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/visual_equipment/measurement/recog_c1_contract.dart';

import '../../tools/recog_c1_compute_metrics.dart';

/// A ground-truth row shaped like the committed CSV's.
Map<String, String> gt(
  String imageId,
  String arm, {
  // snake_case, because that is what the frozen ground-truth CSV actually
  // writes. This fixture used to say 'canonicalSingle' -- Dart's enum spelling,
  // which appears nowhere in the data -- so every test here passed against an
  // input shape the script would never receive, and the script crashed on its
  // first contact with the real file.
  String kind = 'canonical_single',
  String equipmentId = 'treadmill',
  String status = 'resolved',
  String equivalent = 'true',
}) =>
    <String, String>{
      'image_id': imageId,
      'arm': arm,
      'gt_kind': kind,
      'canonical_equipment_id': equipmentId,
      'gt_status': status,
      'gt_equivalent': equivalent,
    };

/// A raw observation shaped like the harness's own output.
String obs(
  String imageId,
  String arm, {
  String pair = 'p00',
  String session = 's1',
  String reply = '{"machine": "treadmill", "confidence": 0.91}',
  String responseClass = 'canonicalResponse',
  String? productionOutcome = 'confident',
  String? transportError,
  bool callReturned = true,
  List<Map<String, Object?>>? candidates,
  String? observationId,
}) =>
    jsonEncode(<String, Object?>{
      'record_type': 'observation',
      'run_id': 'w1',
      'session_id': session,
      'observation_id': observationId ?? 'w1-$pair-$arm-1',
      'pair_id': pair,
      'image_id': imageId,
      'arm': arm,
      'raw_reply': reply,
      'call_returned': callReturned,
      'transport_error': transportError,
      'response_class': responseClass,
      'production_outcome': productionOutcome,
      'candidates': candidates ??
          <Map<String, Object?>>[
            {'equipment_id': 'treadmill', 'confidence': 0.91},
          ],
    });

void main() {
  late EquipmentAliasIndex index;

  setUpAll(() {
    index = EquipmentAliasIndex.fromJson(const {
      'treadmill': ['treadmill'],
      'leg_press': ['leg press'],
    });
  });

  RecogC1Metrics run(
    List<String> raw,
    List<Map<String, String>> gtRows, {
    int planned = 2,
  }) =>
      computeMetrics(
        rawLines: raw,
        gtRows: gtRows,
        planRows: List.generate(planned, (_) => <String, String>{}),
        index: index,
      );

  group('the reconstruction check', () {
    test('a class the raw reply does not support is a stop', () {
      // Verification clause (f). If the device and the analysis disagree about
      // what the model said, no number computed afterwards means anything —
      // so this must halt rather than prefer one of the two.
      expect(
        () => run(
          [obs('i1', 'A', reply: 'not json at all')],
          [gt('i1', 'A')],
        ),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('reconstruction failed'))),
      );
    });

    test('a row whose recorded class matches its reply passes', () {
      final m = run([obs('i1', 'A')], [gt('i1', 'A')]);
      expect(m.observations, 1);
    });

    test('an empty reply that RETURNED reconstructs as a model failure', () {
      // The harness's own distinction, re-derived here rather than trusted:
      // `call_returned` true with no text is the model answering uselessly,
      // which is a malformed parse, not a transport failure.
      final m = run(
        [
          obs('i1', 'A',
              reply: '',
              responseClass: 'malformedParseFailure',
              productionOutcome: null)
        ],
        [gt('i1', 'A')],
      );
      expect(m.scores['w1-p00-A-1'], RecogC1SemanticScore.modelResponseFailure);
    });
  });

  group('what must never be silently absorbed', () {
    test('a duplicate observation id is a stop, not a dedupe', () {
      // Two rows for one target means it was measured twice and both counted.
      // Deduplicating would hide a double-spend of quota AND a double-count in
      // the metric; keeping both would inflate the denominator.
      expect(
        () => run(
          [obs('i1', 'A'), obs('i1', 'A')],
          [gt('i1', 'A')],
        ),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('duplicate observation'))),
      );
    });

    test('an observation with no ground truth is a stop', () {
      expect(
        () => run([obs('i9', 'A')], [gt('i1', 'A')]),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('no ground truth'))),
      );
    });

    test('an unparseable line is a stop, not a skipped row', () {
      expect(
        () => run([obs('i1', 'A'), '{"record_type": "observ'], [gt('i1', 'A')]),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('unparseable line'))),
      );
    });

    test('a short run is reported as short, against the plan', () {
      final m = run([obs('i1', 'A')], [gt('i1', 'A')], planned: 52);
      expect(m.markdown, contains('short of its plan'));
      expect(m.markdown, contains('51 planned observations'));
    });
  });

  group('the operational axis is kept out of the semantic denominator', () {
    test('an operational failure is counted but never scored', () {
      // The frozen contract's rule, not this file's: an attempt that never
      // reached the model measures the transport, and letting it into a
      // semantic denominator would make the model look worse than it is.
      final m = run(
        [
          obs('i1', 'A'),
          obs('i2', 'A',
              pair: 'p01',
              reply: '',
              callReturned: false,
              transportError: 'unavailable',
              responseClass: 'operationalFailure',
              productionOutcome: null),
        ],
        [gt('i1', 'A'), gt('i2', 'A')],
      );
      expect(m.observations, 2);
      expect(m.operational, 1);
      expect(m.scores.keys, ['w1-p00-A-1'],
          reason: 'only the attempt that reached the model is scored');
    });
  });

  group('a pair counts only when it is genuinely a pair', () {
    List<Map<String, String>> bothArms({
      String equivalent = 'true',
      String status = 'resolved',
    }) =>
        [
          gt('i1', 'A', equivalent: equivalent, status: status),
          gt('i1', 'B', equivalent: equivalent, status: status),
        ];

    test('both arms, same session, equivalent ground truth: comparable', () {
      final m = run(
        [obs('i1', 'A'), obs('i1', 'B')],
        bothArms(),
      );
      expect(m.comparablePairs, {'p00'});
      expect(m.notComparable, isEmpty);
    });

    test('arms from different sessions are named, not compared', () {
      // The rule declared before the first inference. A resume between the two
      // arms leaves rows that still share a pair_id and still sit adjacent in
      // the file, so nothing else in the data reveals the split.
      final m = run(
        [obs('i1', 'A', session: 's1'), obs('i1', 'B', session: 's2')],
        bothArms(),
      );
      expect(m.comparablePairs, isEmpty);
      expect(m.notComparable['p00'], contains('different sessions'));
    });

    test('a crop that changed the task is named, not compared', () {
      final m = run(
        [obs('i1', 'A'), obs('i1', 'B')],
        bothArms(equivalent: 'false'),
      );
      expect(m.comparablePairs, isEmpty);
      expect(m.notComparable['p00'], contains('changed the task'));
    });

    test('a pair with only one scorable arm is named, not compared', () {
      final m = run([obs('i1', 'A')], [gt('i1', 'A'), gt('i1', 'B')]);
      expect(m.comparablePairs, isEmpty);
      expect(m.notComparable['p00'], contains('only arm A'));
    });

    test('every non-comparable pair reaches the report with its reason', () {
      // A pair dropped without a stated reason is a pair nobody can check.
      final m = run(
        [obs('i1', 'A', session: 's1'), obs('i1', 'B', session: 's2')],
        bothArms(),
      );
      expect(m.markdown, contains('p00'));
      expect(m.markdown, contains('different sessions'));
    });
  });

  group('correctness is computed over resolved rows only', () {
    test('an unresolved row is scored but excluded from the crop comparison',
        () {
      // The three photographs nobody could name must contribute to no accuracy
      // number in either direction — not as a correct answer, and not as a
      // wrong one.
      final m = run(
        [obs('i1', 'A'), obs('i1', 'B')],
        [
          gt('i1', 'A', status: 'unresolved'),
          gt('i1', 'B', status: 'unresolved'),
        ],
      );
      expect(m.scores, hasLength(2), reason: 'still classified');
      expect(m.comparablePairs, isEmpty,
          reason: 'but it enters no correctness comparison');
    });
  });

  group('the ground truth is read in the format it is actually written in', () {
    // Three tests for one defect, because the defect was not "a wrong string" —
    // it was that nothing anywhere connected the frozen CSV's vocabulary to the
    // frozen enum's, and the tests invented a third vocabulary of their own.
    test('every gt_kind the frozen CSV uses is accepted', () {
      for (final kind in ['canonical_single', 'multiple']) {
        final m = run([obs('i1', 'A')], [gt('i1', 'A', kind: kind)]);
        expect(m.observations, 1, reason: '$kind should parse');
      }
    });

    test('the enum spelling is REJECTED, not quietly accepted', () {
      // The exact value this test file used to pass in. If a future edit makes
      // the lookup permissive — a de-snake, a case-insensitive compare — this
      // goes green again and the guard is gone.
      expect(
        () => run([obs('i1', 'A')], [gt('i1', 'A', kind: 'canonicalSingle')]),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('unknown gt_kind'))),
      );
    });

    test('an unrecognised gt_kind names the observation it came from', () {
      expect(
        () => run([obs('i1', 'A')], [gt('i1', 'A', kind: 'canonical_singles')]),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('w1-p00-A-1'))),
      );
    });
  });

  group('every observed pair is accounted for', () {
    test('a pair unresolved on BOTH arms is named, not silently dropped', () {
      // The defect the real window-1 file exposed: `byPair` was built from the
      // resolved rows only, so a pair unresolved on both arms appeared in
      // neither list. The report then said "25 comparable, 0 not comparable"
      // about a 26-pair corpus, under a sentence promising that never happens.
      final m = run(
        [obs('i1', 'A'), obs('i1', 'B')],
        [
          gt('i1', 'A', status: 'unresolved'),
          gt('i1', 'B', status: 'unresolved'),
        ],
      );
      expect(m.comparablePairs, isEmpty);
      expect(m.notComparable.keys, contains('p00'),
          reason: 'the pair must appear somewhere, with a reason');
      expect(m.markdown, contains('p00'));
    });

    test('comparable + not-comparable equals the observed pair count', () {
      // The invariant itself, over a mixed corpus: one comparable pair, one
      // unresolved pair, one pair with a single observed arm.
      final m = run(
        [
          obs('i1', 'A'), obs('i1', 'B'),
          obs('i2', 'A', pair: 'p01'), obs('i2', 'B', pair: 'p01'),
          obs('i3', 'A', pair: 'p02'),
        ],
        [
          gt('i1', 'A'), gt('i1', 'B'),
          gt('i2', 'A', status: 'unresolved'),
          gt('i2', 'B', status: 'unresolved'),
          gt('i3', 'A'), gt('i3', 'B'),
        ],
        planned: 6,
      );
      expect(m.comparablePairs, {'p00'});
      expect(m.notComparable.keys, containsAll(<String>['p01', 'p02']));
      expect(m.comparablePairs.length + m.notComparable.length, 3,
          reason: 'three pairs were observed, three must be reported');
    });
  });

  group('control records survive into the report', () {
    test('routine write-ahead markers are summarised, not listed one by one',
        () {
      // 52 markers per window, one per observation. Listing them individually
      // buried the records this section exists for under a wall of routine
      // rows, which is how a real stop record becomes invisible.
      final m = run(
        [
          obs('i1', 'A'),
          jsonEncode({
            'record_type': 'attempt_started',
            'observation_id': 'w1-p00-A-1',
            'pair_id': 'p00',
            'arm': 'A',
            'attempt_no': 1,
          }),
        ],
        [gt('i1', 'A')],
      );
      expect(m.markdown, contains('1 write-ahead'));
      expect(m.markdown, isNot(contains('| `attempt_started` |')),
          reason: 'a routine marker must not get its own table row');
    });

    test('a marker with no matching observation is named individually', () {
      // The one case where a marker matters more than any observation: the
      // attempt was sent, it may have spent quota, and nothing says what came
      // back. It must never be absorbed into a count.
      final m = run(
        [
          obs('i1', 'A'),
          jsonEncode({
            'record_type': 'attempt_started',
            'observation_id': 'w1-p09-B-1',
            'pair_id': 'p09',
            'arm': 'B',
            'attempt_no': 1,
          }),
        ],
        [gt('i1', 'A')],
      );
      expect(m.markdown, contains('w1-p09-B-1'));
      expect(m.markdown, contains('never finished'));
    });

    test('a stop record is counted and printed, not dropped', () {
      // The whole reason those records exist: a short file must never read as
      // a complete one.
      final m = run(
        [
          obs('i1', 'A'),
          jsonEncode({
            'record_type': 'run_stopped_consecutive_failures',
            'run_id': 'w1',
            'consecutive_failures': 3,
            'observations_left_unrun': 49,
          }),
        ],
        [gt('i1', 'A')],
      );
      expect(m.control, 1);
      expect(m.observations, 1);
      expect(m.markdown, contains('run_stopped_consecutive_failures'));
      expect(m.markdown, contains('49'));
    });
  });
}
