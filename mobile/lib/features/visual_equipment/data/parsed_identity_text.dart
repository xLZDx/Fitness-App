/// Parsed identity evidence extracted from structured OCR text.
///
/// Binding design: `ParsedIdentityText` in
/// `core/design/sptr_equipment_recognition_v4_1/
/// SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md`
/// lines 338-344. Produced by [parseIdentityText]
/// (`identity_text_parser.dart`) from a [MachineTextEvidence]
/// (`machine_text_evidence.dart`) -- never altering the generic
/// denoising/matching pipeline in `machine_text_anchor.dart`.
///
/// Two candidates conflicting is represented explicitly in [conflicts]
/// rather than silently resolved to one -- see the parser's own ownership
/// policy for when a model code is suppressed vs. kept as a conflict.
class ParsedIdentityText {
  const ParsedIdentityText({
    this.brandCandidates = const [],
    this.productLineCandidates = const [],
    this.modelCodeCandidates = const [],
    this.typeHints = const [],
    this.conflicts = const [],
  });

  final List<String> brandCandidates;
  final List<String> productLineCandidates;
  final List<String> modelCodeCandidates;
  final List<String> typeHints;
  final List<String> conflicts;

  /// True when every candidate/conflict list is empty -- the "no exact
  /// identity evidence" shape shared by both "no placard in frame" and
  /// "brand-only text with no model code" (OP-01's no-model subshape is a
  /// narrower check than this; this is the full-object case).
  bool get isEmpty =>
      brandCandidates.isEmpty &&
      productLineCandidates.isEmpty &&
      modelCodeCandidates.isEmpty &&
      typeHints.isEmpty &&
      conflicts.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ParsedIdentityText &&
          _listEquals(other.brandCandidates, brandCandidates) &&
          _listEquals(other.productLineCandidates, productLineCandidates) &&
          _listEquals(other.modelCodeCandidates, modelCodeCandidates) &&
          _listEquals(other.typeHints, typeHints) &&
          _listEquals(other.conflicts, conflicts));

  @override
  int get hashCode => Object.hash(
        Object.hashAll(brandCandidates),
        Object.hashAll(productLineCandidates),
        Object.hashAll(modelCodeCandidates),
        Object.hashAll(typeHints),
        Object.hashAll(conflicts),
      );

  @override
  String toString() =>
      'ParsedIdentityText(brand: $brandCandidates, line: $productLineCandidates, '
      'model: $modelCodeCandidates, type: $typeHints, conflicts: $conflicts)';
}

/// Caller-injected lexicon boundary for [parseIdentityText].
///
/// The parser owns NO canonical alias data itself -- a real caller derives
/// [typeHintPhrases] from the same phrase vocabulary already used elsewhere
/// (`machine_text_anchor.dart`'s phrase table, or the alias strings behind
/// `EquipmentAliasIndex`, `mobile/lib/features/equipment/data/
/// equipment_alias_index.dart`) rather than this module duplicating that
/// source. [brandAliases] and [productLineAliases] are similarly supplied
/// by the caller, since no canonical brand/product-line list exists
/// anywhere in this repository yet (confirmed by repo search before this
/// gate).
class IdentityLexicon {
  const IdentityLexicon({
    this.brandAliases = const {},
    this.productLineAliases = const {},
    this.typeHintPhrases = const {},
  });

  /// Canonical brand phrases, e.g. {"Star Trac", "Life Fitness"}.
  final Set<String> brandAliases;

  /// Canonical product-line phrases, e.g. {"Inspiration", "9NPL"}.
  final Set<String> productLineAliases;

  /// Canonical machine-type/exercise phrases, e.g. {"leg press", "treadmill"}.
  final Set<String> typeHintPhrases;
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
