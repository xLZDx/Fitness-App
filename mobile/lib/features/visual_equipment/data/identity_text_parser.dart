import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'machine_text_evidence.dart';
import 'parsed_identity_text.dart';

/// Parses brand/product-line/model-code/type-hint evidence out of
/// structured OCR, without altering `machine_text_anchor.dart`'s generic
/// denoising/matching pipeline (P2.G2, binding design: see
/// `parsed_identity_text.dart`'s own doc comment).
///
/// Pure: no side effects, no platform channel, never throws, always returns
/// a [ParsedIdentityText] -- there is no "failure" variant in this
/// function's own type. An actual OCR/plugin failure is a distinct
/// upstream outcome that never reaches this parser (see the OP-01 note
/// below for the current, honestly-scoped state of that distinction).
///
/// When [evidence.lines] carries geometry, lines are clustered by spatial
/// proximity and the cluster with the largest total bounding-box area is
/// treated as the primary placard -- the ownership policy below then
/// decides what a SECONDARY (neighbour) cluster's model code means. When no
/// geometry is available (empty `lines`, e.g. a caller that only has plain
/// text), the whole text is parsed as a single cluster.
///
/// OP-01: an empty/whitespace-only [evidence.fullText] and a brand-only text
/// with no model code both flow through the exact same code path below and
/// produce the same no-model subshape (modelCodeCandidates/typeHints/
/// conflicts all empty) -- only brandCandidates legitimately differs. This
/// gate does NOT prove distinctness from an actual OCR/plugin failure: no
/// failureCode/UNAVAILABLE_* runtime exists anywhere in this client today
/// (confirmed by reading `scan_outcome.dart` and both OCR call sites before
/// this gate) -- that half of binding T4 is a real, named, deferred gap,
/// not silently claimed as satisfied.
ParsedIdentityText parseIdentityText(
  MachineTextEvidence evidence, {
  required IdentityLexicon lexicon,
}) {
  if (evidence.lines.isEmpty) {
    return _parseTokens(_tokenize(evidence.fullText), lexicon);
  }

  final clusters = _clusterLines(evidence.lines);
  final ownership = _determineOwnership(clusters);

  final primaryParsed =
      _parseTokens(_tokenize(_joinText(ownership.primary)), lexicon);

  if (ownership.secondary == null) {
    return primaryParsed;
  }

  final secondaryParsed =
      _parseTokens(_tokenize(_joinText(ownership.secondary!)), lexicon);

  if (ownership.ambiguous) {
    // Ambiguous ownership (near-tied clusters, GPT-PM ruling): both
    // plausible codes are preserved, never arbitrarily picking the larger
    // cluster -- surfaced as a conflict when they actually differ. An
    // OCR digit/letter confusion pair (e.g. 9NP1/9NPI) is the SAME code
    // misread, not a genuine conflict, exactly as within a single cluster.
    final combinedModelCodes = <String>{
      ...primaryParsed.modelCodeCandidates,
      ...secondaryParsed.modelCodeCandidates,
    }.toList()
      ..sort();
    final conflicts = <String>[
      ...primaryParsed.conflicts,
      ...secondaryParsed.conflicts,
    ];
    for (final p in primaryParsed.modelCodeCandidates) {
      for (final s in secondaryParsed.modelCodeCandidates) {
        if (p != s && !isOcrConfusionVariant(p, s)) {
          conflicts.add('$p vs $s (ambiguous placard ownership)');
        }
      }
    }
    conflicts.sort();
    return ParsedIdentityText(
      brandCandidates: {
        ...primaryParsed.brandCandidates,
        ...secondaryParsed.brandCandidates,
      }.toList()
        ..sort(),
      productLineCandidates: {
        ...primaryParsed.productLineCandidates,
        ...secondaryParsed.productLineCandidates,
      }.toList()
        ..sort(),
      modelCodeCandidates: combinedModelCodes,
      typeHints: {
        ...primaryParsed.typeHints,
        ...secondaryParsed.typeHints,
      }.toList()
        ..sort(),
      conflicts: conflicts,
    );
  }

  // Confident ownership (GPT-PM ruling): the secondary/neighbour cluster is
  // suppressed entirely, not just its model code. With the current flat
  // ParsedIdentityText schema there is no provenance/confidence field to
  // mark "this brand/type came from a neighbour, not the placard actually
  // being scanned" -- merging any of the secondary's evidence into the
  // primary result would silently defeat the very ownership distinction
  // this policy exists to establish (GPT-PM round-1 finding, confirmed:
  // an earlier version of this function merged brand/productLine/typeHints
  // from both clusters while only suppressing modelCodeCandidates, so a
  // confidently-secondary neighbour's brand/type still leaked through).
  return primaryParsed;
}

String _joinText(List<MachineTextLine> lines) =>
    lines.map((l) => l.text).join(' ');

// ---------------------------------------------------------------------------
// Tokenization + phrase/model-code classification (P2.G2 step 2/3)
// ---------------------------------------------------------------------------

/// Splits on whitespace only, so a hyphen/slash inside a token (a model
/// code's own delimiter) is preserved rather than treated as a break.
@visibleForTesting
List<String> tokenize(String text) =>
    text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

final List<String> Function(String) _tokenize = tokenize;

/// Strips leading/trailing punctuation OCR commonly appends (commas,
/// periods, colons, quotes) while preserving internal hyphens/slashes,
/// which a model code needs.
@visibleForTesting
String stripPunctuation(String token) =>
    token.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '');

const _kUnitWords = {
  'kg', 'kgs', 'lb', 'lbs', 'cm', 'mm', 'v', 'kw', 'hp', 'w', 'a',
  'reps', 'sets', 'rep', 'set',
};
const _kMeasurementContextWords = {'max', 'min'};
const _kModelContextWords = {'model', 'no', 'no.', 'sku', 'ref', 'ref.'};

/// A token that is a plain number (optionally decimal, optionally a
/// dash-separated range) immediately followed by a unit suffix with no
/// separator (e.g. "220V", "150KG", "3SETS", "2.5HP", "220-240V") is a
/// compact measurement, not a model code, even though it satisfies the
/// generic "has a letter and a digit, length 2-10" shape below -- the
/// unit-adjacency check above only catches a unit written as its OWN
/// token, not fused onto the number, and a naive digits-only version of
/// this pattern still let decimal/range forms like "2.5HP" or "220-240V"
/// through (round-2 pre-commit review finding).
final RegExp _kCompactMeasurementSuffix = RegExp(
  r'^[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?'
  r'(KGS|KG|LBS|LB|CM|MM|KW|HP|REPS|REP|SETS|SET|V|W|A)$',
  caseSensitive: false,
);

/// Whether the (punctuation-stripped) token at [index] in [rawTokens] looks
/// like a model/SKU code candidate. Context-aware rather than shape-only:
/// a token adjacent to a unit word or preceded by MAX/MIN is a measurement
/// regardless of its own shape (excludes "200" out of "MAX 200 KG"); a
/// digit-then-unit-suffix token fused with no separator is a measurement
/// too (excludes "220V", "150KG", "3SETS"); a short mixed alpha+digit token
/// needs no delimiter otherwise (admits "8TRx"); a pure-numeric token needs
/// explicit MODEL/NO/SKU/REF context or a delimiter to qualify, since a
/// bare number alone is usually a rep count, a weight, or noise.
@visibleForTesting
bool looksLikeModelCode(List<String> rawTokens, int index) {
  final cleaned = stripPunctuation(rawTokens[index]);
  if (cleaned.isEmpty) return false;

  final prev =
      index > 0 ? stripPunctuation(rawTokens[index - 1]).toLowerCase() : null;
  final next = index < rawTokens.length - 1
      ? stripPunctuation(rawTokens[index + 1]).toLowerCase()
      : null;

  if (next != null && _kUnitWords.contains(next)) return false;
  if (prev != null && _kMeasurementContextWords.contains(prev)) return false;
  if (_kCompactMeasurementSuffix.hasMatch(cleaned)) return false;

  final hasLetter = cleaned.contains(RegExp(r'[A-Za-z]'));
  final hasDigit = cleaned.contains(RegExp(r'[0-9]'));
  final hasDelimiter = cleaned.contains('-') || cleaned.contains('/');
  final isPureNumeric = RegExp(r'^[0-9]+$').hasMatch(cleaned);

  if (!hasDigit) return false;

  if (hasLetter && cleaned.length >= 2 && cleaned.length <= 10) return true;
  if (hasDelimiter) return true;
  if (isPureNumeric) {
    final strongContext = (prev != null && _kModelContextWords.contains(prev)) ||
        (next != null && _kModelContextWords.contains(next));
    return strongContext;
  }
  return false;
}

/// Two model-code strings that differ only by a common OCR digit/letter
/// confusion (O<->0, I<->1) are the SAME code misread, not a genuine
/// conflict.
@visibleForTesting
bool isOcrConfusionVariant(String a, String b) =>
    _ocrCanonical(a) == _ocrCanonical(b);

String _ocrCanonical(String s) =>
    s.toUpperCase().replaceAll('O', '0').replaceAll('I', '1');

/// Whole-phrase containment on already-[normalizePhraseText]-normalized,
/// single-space-separated word lists -- NOT a `\b`-anchored regex. `\b` in
/// Dart's (ECMAScript-style) `RegExp` is ASCII-only: `\w` excludes Cyrillic
/// letters entirely, so neither side of a Cyrillic word is ever "inside a
/// word" to `\b`, and the boundary check silently fails to anchor at all
/// (round-2 pre-commit review finding, confirmed live: a real RU alias
/// like "беговая дорожка" never matched with the old `\b` version even
/// after the punctuation-normalization fix alone). Comparing normalized
/// word lists sidesteps `\w`/`\b` semantics entirely and works identically
/// for Latin and Cyrillic text.
bool _containsPhrase(String haystackNormalized, String phraseNormalized) {
  if (phraseNormalized.isEmpty) return false;
  final haystackWords = haystackNormalized.split(' ');
  final phraseWords = phraseNormalized.split(' ');
  if (phraseWords.length > haystackWords.length) return false;
  for (var start = 0; start <= haystackWords.length - phraseWords.length; start++) {
    var matches = true;
    for (var i = 0; i < phraseWords.length; i++) {
      if (haystackWords[start + i] != phraseWords[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

/// Canonical form used ONLY for phrase matching (brand/product-line/type
/// hint), never for model-code detection: lowercases, then collapses every
/// run of characters outside Latin+Cyrillic letters/digits (hyphens,
/// slashes, commas, periods, ...) to a single space. This lets a lexicon
/// phrase like "Star Trac" match OCR-common punctuated forms such as
/// "STAR-TRAC" or "STAR/TRAC", which the raw whitespace-only tokenizer
/// alone would miss -- and it stays Cyrillic-safe because the real
/// `typeHintPhrases` lexicon this parser documents as a caller source
/// (`EquipmentAliasIndex`'s alias strings, `equipment_aliases.json`) is
/// EN+RU, not ASCII-only: an ASCII-only version of this function degrades
/// every Cyrillic alias (e.g. "беговая дорожка") to an empty string, which
/// then makes `\b...\b` match degenerately. Mirrors the SAME normalization
/// convention `EquipmentAliasIndex.normalise` already uses (`equipment_
/// alias_index.dart`): lowercase, ё->е, keep `[a-zа-я0-9]`, collapse the
/// rest to single spaces. Model-code detection stays on the raw,
/// un-normalized token stream in [looksLikeModelCode] since a hyphen/slash
/// there is a meaningful delimiter, not noise to discard.
@visibleForTesting
String normalizePhraseText(String text) {
  final spaced = text
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ');
  return spaced.trim();
}

ParsedIdentityText _parseTokens(
  List<String> rawTokens,
  IdentityLexicon lexicon,
) {
  final normalizedText = normalizePhraseText(rawTokens.join(' '));

  final brands = [
    for (final brand in lexicon.brandAliases)
      if (_containsPhrase(normalizedText, normalizePhraseText(brand))) brand,
  ]..sort();
  final productLines = [
    for (final line in lexicon.productLineAliases)
      if (_containsPhrase(normalizedText, normalizePhraseText(line))) line,
  ]..sort();
  final typeHints = [
    for (final hint in lexicon.typeHintPhrases)
      if (_containsPhrase(normalizedText, normalizePhraseText(hint))) hint,
  ]..sort();

  final modelCodes = <String>[];
  for (var i = 0; i < rawTokens.length; i++) {
    if (looksLikeModelCode(rawTokens, i)) {
      modelCodes.add(stripPunctuation(rawTokens[i]).toUpperCase());
    }
  }
  final distinctCodes = modelCodes.toSet().toList()..sort();

  final conflicts = <String>[];
  for (var i = 0; i < distinctCodes.length; i++) {
    for (var j = i + 1; j < distinctCodes.length; j++) {
      if (!isOcrConfusionVariant(distinctCodes[i], distinctCodes[j])) {
        conflicts.add('${distinctCodes[i]} vs ${distinctCodes[j]}');
      }
    }
  }
  conflicts.sort();

  return ParsedIdentityText(
    brandCandidates: brands,
    productLineCandidates: productLines,
    modelCodeCandidates: distinctCodes,
    typeHints: typeHints,
    conflicts: conflicts,
  );
}

// ---------------------------------------------------------------------------
// Bounding-box clustering / ownership (P2.G2 step 4)
// ---------------------------------------------------------------------------

double _lineArea(MachineTextLine l) => l.bounds.width * l.bounds.height;

double _clusterArea(List<MachineTextLine> cluster) =>
    cluster.fold(0.0, (sum, l) => sum + _lineArea(l));

({double dx, double dy}) _centerOf(Rect r) =>
    (dx: r.left + r.width / 2, dy: r.top + r.height / 2);

/// Groups [lines] by bounding-box proximity: two lines join the same
/// cluster when the distance between their centers is within
/// [proximityFactor] times the average line height in the whole set -- an
/// OCR line-spacing heuristic. Lines on one placard sit close together;
/// lines from a different, more distant machine's placard do not.
@visibleForTesting
List<List<MachineTextLine>> clusterLines(
  List<MachineTextLine> lines, {
  double proximityFactor = 3.0,
}) {
  if (lines.isEmpty) return [];
  final n = lines.length;
  if (n == 1) return [lines];

  final parent = List<int>.generate(n, (i) => i);
  int find(int x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  final avgHeight =
      lines.map((l) => l.bounds.height).reduce((a, b) => a + b) / n;
  final threshold = avgHeight * proximityFactor;
  final thresholdSq = threshold * threshold;

  for (var i = 0; i < n; i++) {
    final ci = _centerOf(lines[i].bounds);
    for (var j = i + 1; j < n; j++) {
      final cj = _centerOf(lines[j].bounds);
      final dx = ci.dx - cj.dx;
      final dy = ci.dy - cj.dy;
      if (dx * dx + dy * dy <= thresholdSq) union(i, j);
    }
  }

  final groups = <int, List<MachineTextLine>>{};
  for (var i = 0; i < n; i++) {
    groups.putIfAbsent(find(i), () => []).add(lines[i]);
  }
  return groups.values.toList();
}

/// The result of deciding which cluster (if any) owns the placard being
/// photographed. [ambiguous] is true when [primary] and [secondary] are
/// near-tied in total bounding-box area -- genuinely unclear ownership,
/// per GPT-PM's ruling, rather than an arbitrary pick.
class ClusterOwnership {
  ClusterOwnership({
    required this.primary,
    required this.secondary,
    required this.ambiguous,
  });

  final List<MachineTextLine> primary;
  final List<MachineTextLine>? secondary;
  final bool ambiguous;
}

/// Near-tied threshold: the second-largest cluster is "ambiguous" against
/// the largest once it reaches 70% of the largest's total area -- a
/// genuinely close call, not merely "smaller."
const _kAmbiguousAreaRatio = 0.7;

@visibleForTesting
ClusterOwnership determineOwnership(List<List<MachineTextLine>> clusters) {
  if (clusters.isEmpty) {
    return ClusterOwnership(primary: const [], secondary: null, ambiguous: false);
  }
  final sorted = [...clusters]
    ..sort((a, b) => _clusterArea(b).compareTo(_clusterArea(a)));
  final primary = sorted.first;
  if (sorted.length == 1) {
    return ClusterOwnership(primary: primary, secondary: null, ambiguous: false);
  }
  final secondary = sorted[1];
  final primaryArea = _clusterArea(primary);
  final ratio = primaryArea == 0 ? 1.0 : _clusterArea(secondary) / primaryArea;
  return ClusterOwnership(
    primary: primary,
    secondary: secondary,
    ambiguous: ratio >= _kAmbiguousAreaRatio,
  );
}

List<List<MachineTextLine>> _clusterLines(List<MachineTextLine> lines) =>
    clusterLines(lines);

ClusterOwnership _determineOwnership(List<List<MachineTextLine>> clusters) =>
    determineOwnership(clusters);
