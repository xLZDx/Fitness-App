// RECOG-C1 — the frozen measurement contract.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, GPT-PM APPROVE on hash
// b78bffa57739e2835795f85ded6dbad3bd667dbe0188891405c8031d0d01fddc.
//
// This file is the plan's P1 (response-class precedence) and P2 (scoring
// matrix) as executable code. It is written and unit-tested BEFORE any real
// inference, on purpose: every rule here could otherwise be decided after the
// outputs were visible, and the whole point of the contract is that it cannot.
//
// Measurement-only. Nothing in the shipped app imports it; it holds no state,
// touches no I/O and changes no behaviour. It lives under `lib/` rather than
// `test/` for one reason: the on-device harness that runs inside the APK and
// the offline metric script must use ONE implementation of these rules, and
// only `lib/` is importable from both.
//
// Two axes, deliberately independent:
//
//   * RESPONSE CLASS — what the model's RAW PRIMARY `machine` field was.
//     A compliance measure of the model against its own prompt contract.
//   * SEMANTIC SCORE — what the USER would have been shown, decided by the
//     production `ScanResult.fromMatches` outcome over the parsed candidates.
//
// A reply can be non-compliant and still serve the user well (an off-list name
// the alias index resolves), or compliant and still mislead (a canonical name
// for the wrong machine). Collapsing the two axes is what earlier revisions of
// this plan did wrong.

import 'dart:convert';

import '../../equipment/data/equipment_alias_index.dart';
import '../data/scan_outcome.dart';

/// The seven mutually exclusive classes of one recognition attempt.
///
/// Assigned by [classifyResponse] in a FROZEN precedence order over the raw
/// primary `machine` field alone. Alternatives are parsed into candidates by
/// production and therefore drive the semantic score, but they never move a
/// response between these classes — that rule is what makes the classes
/// mutually exclusive for a reply that carries both a primary and
/// alternatives.
enum RecogC1ResponseClass {
  /// The reply was not JSON, or decoded to something that is not a map.
  /// Production's `parseResponse` throws here, so no candidate list and no
  /// `ScanResult.fromMatches` outcome exists for such a row — see
  /// [RecogC1SemanticScore.modelResponseFailure].
  malformedParseFailure,

  /// The reply parsed as a map and its raw primary `machine` field is absent
  /// or not a String — WHATEVER the alternatives contain.
  primaryAbsentOrNonString,

  /// The raw primary is the literal `unknown` (trimmed, case-insensitive).
  /// The one class that can earn abstention credit.
  explicitUnknown,

  /// The raw primary is byte-equal to an entry of [kCanonicalMachines].
  canonicalResponse,

  /// The raw primary is not canonical, but the production alias index
  /// resolves it to a real equipment id. Non-compliant as raw model output,
  /// yet perfectly usable once shipped — which is exactly why it is its own
  /// class rather than being folded into either neighbour.
  offListResolved,

  /// The raw primary is a string that resolves to nothing.
  offListUnresolvable,

  /// Transport, quota or configuration failure: no model answer at all.
  /// Not model behaviour, so it is excluded from every semantic denominator.
  operationalFailure,
}

/// What the observation is worth once scored against ground truth.
enum RecogC1SemanticScore {
  // canonical_single
  correctConfident,
  wrongConfident,
  correctInAlternatives,
  wrongAlternatives,
  missed,

  // out_of_catalog_single
  overclaimWrong,
  honestAbstention,

  // multiple / none
  overclaimed,
  abstained,

  /// Shared by out_of_catalog_single, multiple and none: the app declined to
  /// assert a single machine. Neither an overclaim nor an abstention.
  safeNonOverclaim,

  /// A `noEquipment` that came from an unusable answer rather than restraint.
  unusableAnswer,

  /// A `noEquipment` that came from a structurally defective reply.
  nonHonestEmpty,

  /// The model's reply could not be parsed at all. Always non-honest, never
  /// correct, never abstention credit — and never an operational failure.
  modelResponseFailure,
}

/// What the photograph actually shows, frozen before any inference.
enum RecogC1GtKind {
  /// Exactly one machine, and it IS in [kCanonicalMachines].
  canonicalSingle,

  /// Exactly one machine, and it is NOT in the catalogue.
  outOfCatalogSingle,

  /// Several machines with no single subject.
  multiple,

  /// No gym equipment at all.
  none,
}

/// The server's machine list, byte-for-byte.
///
/// Copied from `functions/src/ai_equipment_recognition.ts` because the
/// on-device harness cannot read the TypeScript source. That copy is a drift
/// risk, so it is not trusted: `recog_c1_contract_test.dart` parses the real
/// `.ts` file and asserts this list equals it exactly, in the same order.
const List<String> kCanonicalMachines = <String>[
  'treadmill', 'rowing machine', 'squat rack', 'bench press station',
  'cable machine', 'leg press', 'lat pulldown', 'barbell', 'dumbbells',
  'kettlebell', 'elliptical trainer', 'exercise bike', 'recumbent bike',
  'stair climber', 'air bike', 'ski erg', 'smith machine',
  'hack squat machine', 'leg extension machine', 'leg curl machine',
  'hip abductor machine', 'glute kickback machine', 'calf raise machine',
  'chest press machine', 'pec deck', 'shoulder press machine',
  'seated row machine', 't-bar row', 'assisted pull-up machine',
  'pull-up bar', 'dip station', 'preacher curl bench',
  'biceps curl machine', 'triceps extension machine', 'ab crunch machine',
  'rotary torso machine', 'back extension bench', 'captain\'s chair',
  'flat bench', 'ez curl bar', 'weight plates', 'resistance bands',
  'suspension trainer', 'medicine ball', 'battle ropes', 'plyo box',
  'punching bag', 'foam roller', 'stability ball', 'skipping rope',
  'ab wheel', 'parallettes', 'seated dip machine', 'multi hip machine',
  'lateral raise machine', 'sissy squat machine', 'agility ladder',
  'mini trampoline', 'balance board', 'yoga blocks', 'weighted sled',
  'ab mat', 'bosu ball', 'sliding discs', 'sandbag', 'gymnastic rings',
  'tyre', 'vertical pole', 'outdoor air walker', 'push-up blocks',
  'aerobic step',
];

/// The frozen P1 precedence rule.
///
/// [rawReply] is the model's answer exactly as the callable returned it, or
/// null when the call itself failed. [operationalError] true means transport,
/// quota or configuration — it wins over everything, because there is no
/// model answer to classify.
///
/// The fence-stripping and `jsonDecode` here mirror production's
/// `GeminiVisualEquipmentService.parseResponse` so that "not JSON or not a
/// map" means exactly what production means by it, rather than something
/// stricter that would invent malformed rows the app never saw.
RecogC1ResponseClass classifyResponse({
  required String? rawReply,
  required EquipmentAliasIndex index,
  bool operationalError = false,
}) {
  if (operationalError || rawReply == null) {
    return RecogC1ResponseClass.operationalFailure;
  }

  final cleaned = rawReply
      .replaceAll(RegExp(r'^\s*```(?:json)?', multiLine: true), '')
      .replaceAll('```', '')
      .trim();

  final Object? decoded;
  try {
    decoded = jsonDecode(cleaned);
  } catch (_) {
    return RecogC1ResponseClass.malformedParseFailure;
  }
  if (decoded is! Map) return RecogC1ResponseClass.malformedParseFailure;

  final Object? primary = decoded['machine'];
  if (primary is! String) return RecogC1ResponseClass.primaryAbsentOrNonString;

  if (primary.trim().toLowerCase() == 'unknown') {
    return RecogC1ResponseClass.explicitUnknown;
  }
  if (kCanonicalMachines.contains(primary)) {
    return RecogC1ResponseClass.canonicalResponse;
  }
  return index.resolve(primary) == null
      ? RecogC1ResponseClass.offListUnresolvable
      : RecogC1ResponseClass.offListResolved;
}

/// The frozen P2 scoring matrix.
///
/// Returns null for [RecogC1ResponseClass.operationalFailure]: an attempt that
/// never reached the model is measured on the operational axis only and must
/// not dilute a semantic denominator.
///
/// [productionOutcome] is the REAL `ScanResult.fromMatches` outcome recorded
/// on device, and is required for every class except `malformedParseFailure`
/// (where no such outcome can exist) and `operationalFailure`.
RecogC1SemanticScore? scoreObservation({
  required RecogC1GtKind gtKind,
  required RecogC1ResponseClass responseClass,
  required ScanOutcome? productionOutcome,
  required bool topMatchesGt,
  required bool gtAmongCandidates,
}) {
  if (responseClass == RecogC1ResponseClass.operationalFailure) return null;

  // A malformed reply never reaches `fromMatches`; production surfaces it
  // through `classifyFilePath`'s generic catch as `ScanResult.failed()`. It is
  // scored the same way in every GT kind, so no ScanResult has to be invented
  // for it and none may be.
  if (responseClass == RecogC1ResponseClass.malformedParseFailure) {
    return RecogC1SemanticScore.modelResponseFailure;
  }

  // Unconditional, NOT `assert`. Dart strips assertions outside debug mode
  // (`dart run` needs --enable-asserts), and the offline metric script imports
  // this same file — so a fail-closed check written as an assert would be
  // silently absent exactly where the frozen methodology most needs it, and a
  // malformed row would be normalised into a real score instead of stopping
  // the analysis.
  if (productionOutcome == null) {
    throw StateError(
      'a parsed reply must carry the production outcome recorded on device',
    );
  }
  final outcome = productionOutcome;

  // `fromMatches` only ever returns these three. `unknown`, `timeout` and
  // `failed` come from layers this measurement deliberately sits above, so a
  // row carrying one of them is a defect in the harness, not an observation.
  if (outcome != ScanOutcome.confident &&
      outcome != ScanOutcome.alternatives &&
      outcome != ScanOutcome.noEquipment) {
    throw StateError(
      'unexpected production outcome at the service boundary: $outcome',
    );
  }

  switch (gtKind) {
    case RecogC1GtKind.canonicalSingle:
      switch (outcome) {
        case ScanOutcome.confident:
          return topMatchesGt
              ? RecogC1SemanticScore.correctConfident
              : RecogC1SemanticScore.wrongConfident;
        case ScanOutcome.alternatives:
          return gtAmongCandidates
              ? RecogC1SemanticScore.correctInAlternatives
              : RecogC1SemanticScore.wrongAlternatives;
        default:
          // Frozen with no credit clause: a photograph of a catalogue machine
          // that produced nothing is a miss however the reply was phrased.
          return RecogC1SemanticScore.missed;
      }

    case RecogC1GtKind.outOfCatalogSingle:
      switch (outcome) {
        case ScanOutcome.confident:
          return RecogC1SemanticScore.overclaimWrong;
        case ScanOutcome.alternatives:
          return RecogC1SemanticScore.safeNonOverclaim;
        default:
          return _abstentionCell(
            responseClass,
            credited: RecogC1SemanticScore.honestAbstention,
          );
      }

    case RecogC1GtKind.multiple:
    case RecogC1GtKind.none:
      switch (outcome) {
        case ScanOutcome.confident:
          return RecogC1SemanticScore.overclaimed;
        case ScanOutcome.alternatives:
          return RecogC1SemanticScore.safeNonOverclaim;
        default:
          return _abstentionCell(
            responseClass,
            credited: RecogC1SemanticScore.abstained,
          );
      }
  }
}

/// The frozen abstention-credit rule.
///
/// A `noEquipment` earns credit ONLY behind an explicit `unknown`. Restraint
/// the model did not exercise is not scored as restraint.
///
/// `canonicalResponse` and `offListResolved` DO reach here, and an earlier
/// revision of this file was wrong to call the combination impossible. A
/// resolved primary becomes a candidate, but `parseResponse` then applies
/// `rankTopK(..., minConfidence: 0.01)` (gemini_equipment_service.dart:321,
/// visual_equipment_match.dart:50-58), which drops any candidate scoring below
/// 0.01. So `{"machine": "lat pulldown", "confidence": 0.0}` classifies as
/// `canonicalResponse` and still yields an empty ranked list and `noEquipment`.
/// It is scored `unusableAnswer`: the model named a machine, the user was shown
/// nothing, and the frozen credit rule gives credit only behind an explicit
/// `unknown`. Caught by GPT-PM's review of this contract, before any inference.
RecogC1SemanticScore _abstentionCell(
  RecogC1ResponseClass responseClass, {
  required RecogC1SemanticScore credited,
}) {
  switch (responseClass) {
    case RecogC1ResponseClass.explicitUnknown:
      return credited;
    case RecogC1ResponseClass.offListUnresolvable:
      return RecogC1SemanticScore.unusableAnswer;
    case RecogC1ResponseClass.primaryAbsentOrNonString:
      return RecogC1SemanticScore.nonHonestEmpty;
    case RecogC1ResponseClass.canonicalResponse:
    case RecogC1ResponseClass.offListResolved:
      // Reachable through the 0.01 confidence floor — see this function's doc.
      return RecogC1SemanticScore.unusableAnswer;
    case RecogC1ResponseClass.malformedParseFailure:
    case RecogC1ResponseClass.operationalFailure:
      throw StateError('handled before the matrix: $responseClass');
  }
}
