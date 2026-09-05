// RECOG-C1 — the frozen contract's own tests.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0 (GPT-PM APPROVE on hash
// b78bffa5...), step 2: these pass BEFORE a single real image is sent
// anywhere. Their whole purpose is that the rules cannot be adjusted once the
// outputs are visible, so `git log` order is part of the evidence.
//
// Three groups:
//   1. the canonical list is the server's, not a stale transcription of it;
//   2. P1 assigns exactly one class to every response, including the mixed
//      primary/alternative shapes that broke two earlier plan revisions;
//   3. P2 scores every cell of the matrix, and refuses the combinations that
//      the production parser makes impossible.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/visual_equipment/data/gemini_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/measurement/recog_c1_contract.dart';

/// The alias data, read straight off disk rather than through `rootBundle`:
/// the production JSON is the source of truth either way, and a plain file
/// read cannot pass while the asset declaration is broken.
EquipmentAliasIndex _loadIndex() {
  final f = File('assets/data/equipment_aliases.json');
  expect(f.existsSync(), isTrue, reason: 'missing ${f.absolute.path}');
  return EquipmentAliasIndex.fromJson(
    (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>(),
  );
}

/// The server's list, parsed out of the TypeScript that actually ships.
List<String> _canonicalFromServer() {
  final f = File('../functions/src/ai_equipment_recognition.ts');
  expect(f.existsSync(), isTrue, reason: 'missing ${f.absolute.path}');
  final src = f.readAsStringSync();
  final block = RegExp(
    r'export const CANONICAL_MACHINES: readonly string\[\] = \[(.*?)\] as const;',
    dotAll: true,
  ).firstMatch(src);
  expect(block, isNotNull, reason: 'CANONICAL_MACHINES not found in the server');
  return RegExp('"([^"]+)"')
      .allMatches(block!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  late EquipmentAliasIndex index;

  setUpAll(() {
    index = _loadIndex();
  });

  group('canonical list', () {
    test('is byte-identical to the server\'s, in the same order', () {
      expect(kCanonicalMachines, equals(_canonicalFromServer()));
    });

    // This is not decoration. The scoring matrix REFUSES a canonical or
    // resolved primary that produced `noEquipment`, on the grounds that such a
    // primary always becomes a candidate. That reasoning is only sound if
    // every canonical name really does resolve, so it is checked rather than
    // assumed — and if it ever stops being true, this fails here instead of
    // throwing in the middle of an analysis run.
    test('every canonical name resolves through the production alias index',
        () {
      final unresolved =
          kCanonicalMachines.where((m) => index.resolve(m) == null).toList();
      expect(unresolved, isEmpty,
          reason: 'these canonical names resolve to nothing: $unresolved');
    });
  });

  group('P1 — response class, over the raw primary field only', () {
    RecogC1ResponseClass classify(String? reply, {bool operational = false}) =>
        classifyResponse(
          rawReply: reply,
          index: index,
          operationalError: operational,
        );

    test('transport/quota failure wins over everything', () {
      expect(classify(null), RecogC1ResponseClass.operationalFailure);
      expect(classify('{"machine":"treadmill"}', operational: true),
          RecogC1ResponseClass.operationalFailure);
    });

    test('not JSON, or JSON that is not a map, is malformed', () {
      expect(classify('sorry, I cannot help with that'),
          RecogC1ResponseClass.malformedParseFailure);
      expect(classify('[{"machine":"treadmill"}]'),
          RecogC1ResponseClass.malformedParseFailure);
      expect(classify('"treadmill"'),
          RecogC1ResponseClass.malformedParseFailure);
      expect(classify(''), RecogC1ResponseClass.malformedParseFailure);
    });

    test('a map with no usable primary is primary_absent_or_non_string', () {
      expect(classify('{}'), RecogC1ResponseClass.primaryAbsentOrNonString);
      expect(classify('{"machine": null}'),
          RecogC1ResponseClass.primaryAbsentOrNonString);
      expect(classify('{"machine": 42}'),
          RecogC1ResponseClass.primaryAbsentOrNonString);
      expect(classify('{"confidence": 0.9}'),
          RecogC1ResponseClass.primaryAbsentOrNonString);
    });

    // The fixture rev6 was rejected over: a reply with NO primary but a
    // perfectly usable alternative. The class is decided by the absent
    // primary; the alternative still becomes a production candidate and still
    // drives the semantic score, which is the whole point of keeping the two
    // axes apart.
    test('a usable alternative does not rescue an absent primary', () {
      expect(
        classify('{"alternatives":[{"machine":"lat pulldown",'
            '"confidence":0.8}]}'),
        RecogC1ResponseClass.primaryAbsentOrNonString,
      );
    });

    test('an explicit unknown stays explicit_unknown whatever follows it', () {
      expect(classify('{"machine":"unknown"}'),
          RecogC1ResponseClass.explicitUnknown);
      expect(classify('{"machine":"  UNKNOWN  "}'),
          RecogC1ResponseClass.explicitUnknown);
      expect(
        classify('{"machine":"unknown","alternatives":'
            '[{"machine":"lat pulldown","confidence":0.8}]}'),
        RecogC1ResponseClass.explicitUnknown,
      );
    });

    test('an exact catalogue string is canonical, fences and all', () {
      expect(classify('{"machine":"lat pulldown","confidence":0.9}'),
          RecogC1ResponseClass.canonicalResponse);
      expect(
        classify('```json\n{"machine":"treadmill","confidence":0.9}\n```'),
        RecogC1ResponseClass.canonicalResponse,
      );
    });

    // "Exact" is byte equality, so a case variant is NOT canonical — but the
    // alias index normalises and still resolves it. That is precisely the
    // off_list_resolved state: non-compliant raw output, usable once shipped.
    test('a case variant of a catalogue name is off_list_resolved', () {
      const reply = '{"machine":"Lat Pulldown","confidence":0.9}';
      expect(kCanonicalMachines.contains('Lat Pulldown'), isFalse);
      expect(index.resolve('Lat Pulldown'), isNotNull);
      expect(classify(reply), RecogC1ResponseClass.offListResolved);
    });

    test('a name nothing resolves is off_list_unresolvable', () {
      expect(classify('{"machine":"quantum flux capacitor"}'),
          RecogC1ResponseClass.offListUnresolvable);
    });

    test('every fixture receives exactly one class', () {
      const fixtures = <String>[
        'not json at all',
        '[1,2,3]',
        '{}',
        '{"machine": null}',
        '{"alternatives":[{"machine":"lat pulldown","confidence":0.8}]}',
        '{"machine":"unknown"}',
        '{"machine":"unknown","alternatives":[{"machine":"leg press"}]}',
        '{"machine":"lat pulldown"}',
        '{"machine":"Lat Pulldown"}',
        '{"machine":"quantum flux capacitor"}',
      ];
      for (final f in fixtures) {
        final assigned = RecogC1ResponseClass.values
            .where((c) => classify(f) == c)
            .toList();
        expect(assigned, hasLength(1), reason: 'fixture: $f -> $assigned');
      }
    });
  });

  group('P2 — the scoring matrix, cell by cell', () {
    RecogC1SemanticScore? score({
      required RecogC1GtKind gt,
      required RecogC1ResponseClass cls,
      ScanOutcome? outcome,
      bool topMatches = false,
      bool gtAmong = false,
    }) =>
        scoreObservation(
          gtKind: gt,
          responseClass: cls,
          productionOutcome: outcome,
          topMatchesGt: topMatches,
          gtAmongCandidates: gtAmong,
        );

    test('canonical_single: all five cells', () {
      expect(
        score(
            gt: RecogC1GtKind.canonicalSingle,
            cls: RecogC1ResponseClass.canonicalResponse,
            outcome: ScanOutcome.confident,
            topMatches: true),
        RecogC1SemanticScore.correctConfident,
      );
      expect(
        score(
            gt: RecogC1GtKind.canonicalSingle,
            cls: RecogC1ResponseClass.canonicalResponse,
            outcome: ScanOutcome.confident),
        RecogC1SemanticScore.wrongConfident,
      );
      expect(
        score(
            gt: RecogC1GtKind.canonicalSingle,
            cls: RecogC1ResponseClass.canonicalResponse,
            outcome: ScanOutcome.alternatives,
            gtAmong: true),
        RecogC1SemanticScore.correctInAlternatives,
      );
      expect(
        score(
            gt: RecogC1GtKind.canonicalSingle,
            cls: RecogC1ResponseClass.canonicalResponse,
            outcome: ScanOutcome.alternatives),
        RecogC1SemanticScore.wrongAlternatives,
      );
      expect(
        score(
            gt: RecogC1GtKind.canonicalSingle,
            cls: RecogC1ResponseClass.explicitUnknown,
            outcome: ScanOutcome.noEquipment),
        RecogC1SemanticScore.missed,
      );
    });

    // Frozen with no credit clause: on a photo of a catalogue machine, a
    // `noEquipment` is a miss however honestly it was phrased. An explicit
    // unknown does NOT earn abstention credit here.
    test('canonical_single: an explicit unknown is still a miss, not credit',
        () {
      for (final cls in const [
        RecogC1ResponseClass.explicitUnknown,
        RecogC1ResponseClass.offListUnresolvable,
        RecogC1ResponseClass.primaryAbsentOrNonString,
      ]) {
        expect(
          score(
              gt: RecogC1GtKind.canonicalSingle,
              cls: cls,
              outcome: ScanOutcome.noEquipment),
          RecogC1SemanticScore.missed,
          reason: '$cls',
        );
      }
    });

    test('out_of_catalog_single: confident is an overclaim however phrased',
        () {
      for (final cls in const [
        RecogC1ResponseClass.canonicalResponse,
        RecogC1ResponseClass.offListResolved,
      ]) {
        expect(
          score(
              gt: RecogC1GtKind.outOfCatalogSingle,
              cls: cls,
              outcome: ScanOutcome.confident,
              topMatches: false),
          RecogC1SemanticScore.overclaimWrong,
          reason: '$cls',
        );
      }
    });

    test('out_of_catalog_single: alternatives is its own safe state', () {
      expect(
        score(
            gt: RecogC1GtKind.outOfCatalogSingle,
            cls: RecogC1ResponseClass.canonicalResponse,
            outcome: ScanOutcome.alternatives),
        RecogC1SemanticScore.safeNonOverclaim,
      );
    });

    test('multiple and none behave identically', () {
      for (final gt in const [RecogC1GtKind.multiple, RecogC1GtKind.none]) {
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.canonicalResponse,
              outcome: ScanOutcome.confident),
          RecogC1SemanticScore.overclaimed,
          reason: '$gt',
        );
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.offListResolved,
              outcome: ScanOutcome.alternatives),
          RecogC1SemanticScore.safeNonOverclaim,
          reason: '$gt',
        );
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.explicitUnknown,
              outcome: ScanOutcome.noEquipment),
          RecogC1SemanticScore.abstained,
          reason: '$gt',
        );
      }
    });

    // The abstention-credit rule, which is the reason the two axes exist.
    test('abstention credit only behind an explicit unknown', () {
      for (final gt in const [
        RecogC1GtKind.outOfCatalogSingle,
        RecogC1GtKind.multiple,
        RecogC1GtKind.none,
      ]) {
        final credited = gt == RecogC1GtKind.outOfCatalogSingle
            ? RecogC1SemanticScore.honestAbstention
            : RecogC1SemanticScore.abstained;
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.explicitUnknown,
              outcome: ScanOutcome.noEquipment),
          credited,
          reason: '$gt',
        );
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.offListUnresolvable,
              outcome: ScanOutcome.noEquipment),
          RecogC1SemanticScore.unusableAnswer,
          reason: '$gt',
        );
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.primaryAbsentOrNonString,
              outcome: ScanOutcome.noEquipment),
          RecogC1SemanticScore.nonHonestEmpty,
          reason: '$gt',
        );
      }
    });

    test('a malformed reply scores the same in every GT kind, with no '
        'ScanResult at all', () {
      for (final gt in RecogC1GtKind.values) {
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.malformedParseFailure,
              outcome: null),
          RecogC1SemanticScore.modelResponseFailure,
          reason: '$gt',
        );
      }
    });

    test('an operational failure is not scored semantically at all', () {
      for (final gt in RecogC1GtKind.values) {
        expect(
          score(
              gt: gt,
              cls: RecogC1ResponseClass.operationalFailure,
              outcome: null),
          isNull,
          reason: '$gt',
        );
      }
    });

    // A resolved primary does NOT guarantee a surviving candidate: production
    // applies a 0.01 confidence floor after resolution, so a named machine
    // scored 0.0 disappears and the user is shown nothing. An earlier revision
    // of this contract called that impossible and would have thrown on real
    // data; GPT-PM caught it before any inference existed.
    test('a resolved primary that produced noEquipment is an unusable answer',
        () {
      for (final cls in const [
        RecogC1ResponseClass.canonicalResponse,
        RecogC1ResponseClass.offListResolved,
      ]) {
        for (final gt in const [
          RecogC1GtKind.outOfCatalogSingle,
          RecogC1GtKind.multiple,
          RecogC1GtKind.none,
        ]) {
          expect(
            score(gt: gt, cls: cls, outcome: ScanOutcome.noEquipment),
            RecogC1SemanticScore.unusableAnswer,
            reason: '$gt/$cls',
          );
        }
      }
      // canonical_single is unchanged: a photo of a catalogue machine that
      // produced nothing is a miss however the reply was phrased.
      expect(
        score(
            gt: RecogC1GtKind.canonicalSingle,
            cls: RecogC1ResponseClass.canonicalResponse,
            outcome: ScanOutcome.noEquipment),
        RecogC1SemanticScore.missed,
      );
    });

    // The end-to-end proof, through the REAL production parser rather than a
    // hand-built candidate list: a canonical name at confidence 0.0 survives
    // `addCandidate` and is then dropped by `rankTopK(minConfidence: 0.01)`.
    test('production really does turn a canonical name at 0.0 into noEquipment',
        () {
      for (final raw in const [
        '{"machine": "lat pulldown", "confidence": 0.0}',
        '{"machine": "lat pulldown", "confidence": 0.005}',
      ]) {
        final matches = GeminiVisualEquipmentService.parseResponse(raw, index);
        expect(matches, isEmpty, reason: raw);
        final result = ScanResult.fromMatches(matches, answeredOffline: false);
        expect(result.outcome, ScanOutcome.noEquipment, reason: raw);
        expect(
          classifyResponse(rawReply: raw, index: index),
          RecogC1ResponseClass.canonicalResponse,
          reason: raw,
        );
        expect(
          score(
              gt: RecogC1GtKind.multiple,
              cls: RecogC1ResponseClass.canonicalResponse,
              outcome: result.outcome),
          RecogC1SemanticScore.unusableAnswer,
          reason: raw,
        );
      }
      // The control: the same name above the floor is a normal candidate.
      final ok = GeminiVisualEquipmentService.parseResponse(
          '{"machine": "lat pulldown", "confidence": 0.9}', index);
      expect(ok, hasLength(1));
      expect(ScanResult.fromMatches(ok).outcome, ScanOutcome.confident);
    });

    // Fail-closed, and NOT via `assert`: Dart strips assertions outside debug
    // mode, and the offline metric script imports this same contract. These
    // must throw in any assertion mode, which is why they are real `throw`s.
    test('a missing or impossible production outcome stops the analysis', () {
      expect(
        () => score(gt: RecogC1GtKind.multiple, cls: RecogC1ResponseClass.canonicalResponse),
        throwsStateError,
      );
      for (final bad in const [
        ScanOutcome.unknown,
        ScanOutcome.timeout,
        ScanOutcome.failed,
      ]) {
        expect(
          () => score(
              gt: RecogC1GtKind.multiple,
              cls: RecogC1ResponseClass.canonicalResponse,
              outcome: bad),
          throwsStateError,
          reason: '$bad',
        );
      }
    });

    // Exhaustiveness: no legal combination is left undefined, and none is
    // counted twice. `null` is legal only for an operational failure.
    test('every legal combination yields exactly one outcome', () {
      for (final gt in RecogC1GtKind.values) {
        for (final cls in RecogC1ResponseClass.values) {
          final outcomes = cls == RecogC1ResponseClass.malformedParseFailure ||
                  cls == RecogC1ResponseClass.operationalFailure
              ? <ScanOutcome?>[null]
              : const <ScanOutcome?>[
                  ScanOutcome.confident,
                  ScanOutcome.alternatives,
                  ScanOutcome.noEquipment,
                ];
          for (final o in outcomes) {
            final s = score(gt: gt, cls: cls, outcome: o);
            if (cls == RecogC1ResponseClass.operationalFailure) {
              expect(s, isNull, reason: '$gt/$cls/$o');
            } else {
              expect(s, isNotNull, reason: '$gt/$cls/$o');
            }
          }
        }
      }
    });
  });
}
