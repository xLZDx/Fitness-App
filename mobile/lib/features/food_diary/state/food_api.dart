/// Client of the four food callables behind ONE interface (design s17.4-s17.6;
/// server contracts in `functions/src/{analyze_meal_photo,parse_nutrition_label,
/// nutrition_lookup}.ts`).
///
/// Every failure becomes a [FoodApiException] carrying a CLOSED
/// [FoodApiFailure]; the raw SDK message never reaches the UI (D-67). A server
/// that answers `failed-precondition: feature-disabled` maps to
/// [FoodApiFailure.featureDisabled], which the screens render as a calm
/// "not available yet" state (D-78), never as an error.
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import '../data/check_these.dart';
import '../data/food_entry.dart';
import '../data/food_source.dart';

/// Why a food call produced nothing.
enum FoodApiFailure {
  /// The server flag for this call is off: "not available yet".
  featureDisabled,

  /// Daily or burst limit reached; trying again later can succeed.
  rateLimited,

  /// Upstream database or model unavailable; a retry can succeed.
  upstreamUnavailable,

  /// The server refused the input (too short, bad barcode, bad image).
  invalidInput,

  /// A source is not configured on the server (treated like feature-off).
  sourceNotConfigured,

  /// Signed out or App Check refused.
  notAllowed,

  /// Anything else.
  unknown,
}

class FoodApiException implements Exception {
  const FoodApiException(this.failure, {this.slug});

  final FoodApiFailure failure;

  /// The closed server slug when there was one (never free text).
  final String? slug;

  bool get isNotAvailableYet =>
      failure == FoodApiFailure.featureDisabled ||
      failure == FoodApiFailure.sourceNotConfigured;

  bool get retriable =>
      failure == FoodApiFailure.rateLimited ||
      failure == FoodApiFailure.upstreamUnavailable ||
      failure == FoodApiFailure.unknown;

  @override
  String toString() => 'FoodApiException($failure, $slug)';
}

/// Maps a callable error to the closed failure set.
FoodApiException mapFoodCallableError(FirebaseFunctionsException e) {
  final raw = e.message ?? '';
  final slug = RegExp(r'^[a-z0-9][a-z0-9:_,-]{0,59}$').hasMatch(raw) ? raw : null;
  switch (slug) {
    case 'feature-disabled':
      return FoodApiException(FoodApiFailure.featureDisabled, slug: slug);
    case 'source-not-configured':
      return FoodApiException(FoodApiFailure.sourceNotConfigured, slug: slug);
    case 'rate-limited':
      return FoodApiException(FoodApiFailure.rateLimited, slug: slug);
    case 'upstream-unavailable':
      return FoodApiException(FoodApiFailure.upstreamUnavailable, slug: slug);
    case 'invalid-barcode':
    case 'invalid-query':
      return FoodApiException(FoodApiFailure.invalidInput, slug: slug);
  }
  switch (e.code) {
    case 'resource-exhausted':
      return FoodApiException(FoodApiFailure.rateLimited, slug: slug);
    case 'invalid-argument':
      return FoodApiException(FoodApiFailure.invalidInput, slug: slug);
    case 'unauthenticated':
    case 'permission-denied':
      return FoodApiException(FoodApiFailure.notAllowed, slug: slug);
    case 'unavailable':
    case 'deadline-exceeded':
    case 'internal':
    case 'aborted':
      return FoodApiException(FoodApiFailure.upstreamUnavailable, slug: slug);
  }
  return FoodApiException(FoodApiFailure.unknown, slug: slug);
}

/// One food proposed by the meal analysis (a database match or the model's own
/// estimate), already carrying its source tag.
class AnalysedItem {
  const AnalysedItem({
    required this.name,
    required this.grams,
    required this.per100g,
    required this.source,
    required this.matchQuality,
    required this.confidence,
    this.sourceRef,
    this.checkCodes = const [],
  });

  final String name;
  final MacroRange grams;

  /// Null only when neither a database match nor a model estimate exists; such
  /// an item must be completed by hand and is never written as zeros.
  final Per100g? per100g;
  final FoodSource source;
  final String? sourceRef;
  final MatchQuality matchQuality;

  /// 0..1 item confidence (model confidence x match factor).
  final double confidence;
  final List<CheckCode> checkCodes;

  /// The stored `foodRef`: `off:<barcode>`, `usda:<fdcId>`, else `llm:<slug>`.
  String get foodRef {
    final ref = sourceRef;
    if (ref != null && ref.isNotEmpty) {
      if (source == FoodSource.off) return 'off:$ref';
      if (source == FoodSource.usda) return 'usda:$ref';
    }
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'llm:${slug.isEmpty ? 'item' : slug}';
  }

  FoodItem? toFoodItem() {
    final p = per100g;
    if (p == null) return null;
    return FoodItem(
      foodRef: foodRef,
      name: name.length > FoodItem.maxNameLength
          ? name.substring(0, FoodItem.maxNameLength)
          : name,
      grams: grams,
      per100g: p,
      matchQuality: matchQuality,
      source: source,
    );
  }
}

class MealAnalysis {
  const MealAnalysis({
    required this.mealName,
    required this.items,
    required this.confidence,
    this.assumptions = const [],
    this.model,
  });

  final String mealName;
  final List<AnalysedItem> items;
  final EntryConfidence confidence;
  final List<CheckCode> assumptions;
  final ModelRef? model;
}

/// A database food (barcode hit or search result).
class FoodCandidate {
  const FoodCandidate({
    required this.foodRef,
    required this.name,
    required this.per100g,
    required this.source,
    this.brand,
    this.servingG,
    this.complete = true,
  });

  /// `off:<barcode>` or `usda:<fdcId>`.
  final String foodRef;
  final String name;
  final String? brand;
  final Per100g per100g;
  final double? servingG;
  final FoodSource source;

  /// False when the source marked the record partial; the UI says so.
  final bool complete;
}

class BarcodeLookup {
  const BarcodeLookup.notFound() : candidate = null;
  const BarcodeLookup.found(FoodCandidate this.candidate);

  final FoodCandidate? candidate;
  bool get found => candidate != null;
}

class SearchResults {
  const SearchResults(this.results);
  final List<FoodCandidate> results;
}

/// What the label reader produced; per-100 g is null when nothing usable.
class LabelReading {
  const LabelReading({
    this.per100g,
    this.perServing,
    this.servingG,
    this.checkCodes = const [],
    this.model,
  });

  final Per100g? per100g;
  final Per100g? perServing;
  final double? servingG;
  final List<CheckCode> checkCodes;
  final ModelRef? model;
}

enum FoodSearchScope { generic, packaged, both }

abstract class FoodApi {
  /// Photo ([imageBase64] + [mimeType], optional [note]) or describe ([text]).
  Future<MealAnalysis> analyzeMeal({
    String? text,
    String? imageBase64,
    String? mimeType,
    String? note,
    required String languageCode,
  });

  Future<BarcodeLookup> lookupBarcode(String barcode);

  Future<SearchResults> searchFoods(
    String query, {
    required String languageCode,
    FoodSearchScope scope = FoodSearchScope.both,
    int limit = 20,
  });

  Future<LabelReading> parseLabel({
    required String imageBase64,
    required String mimeType,
    required String languageCode,
  });
}

double? _d(Object? v) => v is num && v.isFinite && v >= 0 ? v.toDouble() : null;

Per100g? _per100(Object? raw) {
  if (raw is! Map) return null;
  final k = _d(raw['kcal']);
  final p = _d(raw['proteinG']);
  final c = _d(raw['carbsG']);
  final f = _d(raw['fatG']);
  if (k == null || p == null || c == null || f == null) return null;
  return Per100g(kcal: k, proteinG: p, carbsG: c, fatG: f);
}

List<CheckCode> _codes(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final c in CheckThese.fromCodes([
      for (final r in raw)
        if (CheckCode.tryParse(r) case final code?) code,
    ]))
      c.code,
  ];
}

EntryConfidence _conf(Object? raw) => switch (raw) {
      'high' => EntryConfidence.high,
      'medium' => EntryConfidence.medium,
      _ => EntryConfidence.low,
    };

MatchQuality _match(Object? raw) {
  for (final m in MatchQuality.values) {
    if (m.name == raw) return m;
  }
  return MatchQuality.none;
}

/// Pure parsers (exposed for tests) -----------------------------------------

MealAnalysis parseMealAnalysis(Map<String, dynamic> body) {
  final items = <AnalysedItem>[];
  final raw = body['items'];
  if (raw is List) {
    for (final r in raw) {
      if (r is! Map) continue;
      final g = r['grams'];
      final name = r['name'];
      if (name is! String || name.trim().isEmpty || g is! Map) continue;
      final src = FoodSource.tryParse(r['source']) ?? FoodSource.llmEstimate;
      items.add(AnalysedItem(
        name: name.trim(),
        grams: MacroRange.fromJson(g),
        per100g: _per100(r['per100g']),
        source: src,
        sourceRef: r['sourceRef'] is String ? r['sourceRef'] as String : null,
        matchQuality: _match(r['matchQuality']),
        confidence: _d(r['confidence']) ?? 0,
        checkCodes: _codes(r['checkCodes']),
      ));
      if (items.length >= FoodEntry.maxItems) break;
    }
  }
  final mealName = body['mealName'];
  return MealAnalysis(
    mealName: mealName is String ? mealName.trim() : '',
    items: items,
    confidence: _conf(body['entryConfidence']),
    assumptions: _codes(body['assumptions']),
    model: ModelRef.tryFromJson(body['model']),
  );
}

FoodCandidate? parseCandidate(Object? raw) {
  if (raw is! Map) return null;
  final name = raw['name'];
  final ref = raw['foodRef'];
  final per = _per100(raw['per100g']);
  final src = FoodSource.tryParse(raw['source']);
  if (name is! String || ref is! String || per == null || src == null) {
    return null;
  }
  if (src != FoodSource.off && src != FoodSource.usda) return null;
  final brand = raw['brand'];
  final completeness = raw['completeness'];
  return FoodCandidate(
    foodRef: ref,
    name: name,
    brand: brand is String && brand.isNotEmpty ? brand : null,
    per100g: per,
    servingG: _d(raw['servingG']),
    source: src,
    complete: completeness == null || completeness == 'complete',
  );
}

BarcodeLookup parseBarcodeLookup(Map<String, dynamic> body, String barcode) {
  if (body['found'] != true) return const BarcodeLookup.notFound();
  final product = body['product'];
  final src = FoodSource.tryParse(body['source']);
  if (product is! Map || src == null) return const BarcodeLookup.notFound();
  final per = _per100(product['per100g']);
  final name = product['name'];
  if (per == null || name is! String) return const BarcodeLookup.notFound();
  final brand = product['brand'];
  return BarcodeLookup.found(FoodCandidate(
    foodRef: src == FoodSource.off ? 'off:$barcode' : 'usda:$barcode',
    name: name,
    brand: brand is String && brand.isNotEmpty ? brand : null,
    per100g: per,
    servingG: _d(product['servingG']),
    source: src,
    complete: body['dataQuality'] == null || body['dataQuality'] == 'complete',
  ));
}

LabelReading parseLabelReading(Map<String, dynamic> body) => LabelReading(
      per100g: _per100(body['per100g']),
      perServing: _per100(body['perServing']),
      servingG: _d(body['servingG']),
      checkCodes: _codes(body['checkCodes']),
      model: ModelRef.tryFromJson(body['model']),
    );

/// The real client, region `europe-west1` like every other callable.
class CallableFoodApi implements FoodApi {
  CallableFoodApi([this._injected]);

  final FirebaseFunctions? _injected;

  /// Resolved lazily so merely constructing the client never touches Firebase.
  FirebaseFunctions get _functions => _injected ?? functionsForRegion;

  Future<Map<String, dynamic>> _call(
      String name, Map<String, Object?> data) async {
    try {
      final res = await _functions.httpsCallable(name).call<Object?>(data);
      final body = res.data;
      if (body is Map) return Map<String, dynamic>.from(body);
      throw const FoodApiException(FoodApiFailure.unknown, slug: 'bad-response');
    } on FirebaseFunctionsException catch (e) {
      throw mapFoodCallableError(e);
    }
  }

  @override
  Future<MealAnalysis> analyzeMeal({
    String? text,
    String? imageBase64,
    String? mimeType,
    String? note,
    required String languageCode,
  }) async {
    final describe = text != null;
    final body = await _call('analyzeMealPhoto', {
      'mode': describe ? 'describe' : 'photo',
      'languageCode': languageCode,
      if (describe) 'text': text,
      if (!describe) 'imageBase64': imageBase64,
      if (!describe) 'mimeType': mimeType,
      if (!describe && note != null && note.isNotEmpty) 'note': note,
    });
    return parseMealAnalysis(body);
  }

  @override
  Future<BarcodeLookup> lookupBarcode(String barcode) async =>
      parseBarcodeLookup(await _call('lookupBarcode', {'barcode': barcode}), barcode);

  @override
  Future<SearchResults> searchFoods(
    String query, {
    required String languageCode,
    FoodSearchScope scope = FoodSearchScope.both,
    int limit = 20,
  }) async {
    final body = await _call('searchFoods', {
      'query': query,
      'languageCode': languageCode,
      'scope': scope.name,
      'limit': limit,
    });
    final raw = body['results'];
    return SearchResults([
      if (raw is List)
        for (final r in raw)
          if (parseCandidate(r) case final c?) c,
    ]);
  }

  @override
  Future<LabelReading> parseLabel({
    required String imageBase64,
    required String mimeType,
    required String languageCode,
  }) async =>
      parseLabelReading(await _call('parseNutritionLabel', {
        'imageBase64': imageBase64,
        'mimeType': mimeType,
        'languageCode': languageCode,
      }));
}

/// Scriptable fake: set a field to the value to return, or [failure] to make
/// every call throw. Counts calls so tests can prove "no call when off".
class FakeFoodApi implements FoodApi {
  FakeFoodApi({
    this.analysis,
    this.barcode,
    this.search = const [],
    this.label,
    this.failure,
  });

  MealAnalysis? analysis;
  FoodCandidate? barcode;
  List<FoodCandidate> search;
  LabelReading? label;
  FoodApiFailure? failure;

  int analyzeCalls = 0;
  int barcodeCalls = 0;
  int searchCalls = 0;
  int labelCalls = 0;
  String? lastQuery;

  void _maybeFail() {
    final f = failure;
    if (f != null) throw FoodApiException(f);
  }

  @override
  Future<MealAnalysis> analyzeMeal({
    String? text,
    String? imageBase64,
    String? mimeType,
    String? note,
    required String languageCode,
  }) async {
    analyzeCalls++;
    _maybeFail();
    return analysis ??
        const MealAnalysis(
          mealName: '',
          items: [],
          confidence: EntryConfidence.low,
        );
  }

  @override
  Future<BarcodeLookup> lookupBarcode(String barcodeValue) async {
    barcodeCalls++;
    _maybeFail();
    final c = barcode;
    return c == null ? const BarcodeLookup.notFound() : BarcodeLookup.found(c);
  }

  @override
  Future<SearchResults> searchFoods(
    String query, {
    required String languageCode,
    FoodSearchScope scope = FoodSearchScope.both,
    int limit = 20,
  }) async {
    searchCalls++;
    lastQuery = query;
    _maybeFail();
    return SearchResults(search);
  }

  @override
  Future<LabelReading> parseLabel({
    required String imageBase64,
    required String mimeType,
    required String languageCode,
  }) async {
    labelCalls++;
    _maybeFail();
    return label ?? const LabelReading();
  }
}
