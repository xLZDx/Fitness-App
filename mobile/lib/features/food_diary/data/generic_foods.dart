/// Bundled generic food table: pure parse and token search (C21, design 17.5).
///
/// Pure Dart, no Flutter imports. The asset read (`rootBundle`) lives in the
/// state layer and hands the two JSON strings to [GenericFoodTable.parse];
/// `assets/nutrition/generic_foods_v1.json` is built by
/// `scripts/nutrition/build_generic_foods.py` (USDA FDC, CC0 1.0) and
/// `generic_foods_ru.json` carries own-authored Russian display names.
///
/// Uncertain tags default to the RESTRICTIVE side: an unknown allergen name,
/// a missing or malformed tag block, or `allergenCertain != true` all make the
/// row uncertain. Uncertain rows stay searchable (with a warning in the UI) but
/// the suggestion filter hides them.
library;

import 'dart:convert';

import '../../safety/data/health_flags.dart';

/// Diet and allergen tags of one generic food.
class GenericFoodTags {
  const GenericFoodTags({
    this.allergens = const {},
    this.allergenCertain = false,
    this.animalProduct,
    this.pescatarianOk,
    this.pork = false,
    this.alcohol = false,
  });

  /// Allergens the food contains (EU-14). Meaningful as a complete list only
  /// when [allergenCertain] is true.
  final Set<FoodAllergen> allergens;

  /// The allergen list is complete. False for mixed or processed foods whose
  /// ingredients are unknown: then ANY allergen may be present.
  final bool allergenCertain;

  /// Null means unknown (treated as an animal product by restrictive diets).
  final bool? animalProduct;

  /// Null means unknown (treated as not pescatarian-safe).
  final bool? pescatarianOk;

  final bool pork;
  final bool alcohol;

  /// Any tag is unknown, so the row must not be suggested to a restricted user.
  bool get isUncertain =>
      !allergenCertain || animalProduct == null || pescatarianOk == null;

  /// Restrictive parse: anything unreadable becomes the restrictive value.
  factory GenericFoodTags.fromJson(Object? raw) {
    if (raw is! Map) return const GenericFoodTags();
    var certain = raw['allergenCertain'] == true;
    final allergens = <FoodAllergen>{};
    final rawAllergens = raw['allergens'];
    if (rawAllergens is List) {
      for (final a in rawAllergens) {
        FoodAllergen? match;
        for (final v in FoodAllergen.values) {
          if (v.name == a) match = v;
        }
        if (match == null) {
          certain = false; // unknown allergen name: cannot vouch for the list
        } else {
          allergens.add(match);
        }
      }
    } else {
      certain = false;
    }
    final animal = raw['animalProduct'];
    final pesc = raw['pescatarianOk'];
    return GenericFoodTags(
      allergens: Set.unmodifiable(allergens),
      allergenCertain: certain,
      animalProduct: animal is bool ? animal : null,
      pescatarianOk: pesc is bool ? pesc : null,
      pork: raw['pork'] == true,
      alcohol: raw['alcohol'] == true,
    );
  }
}

/// Energy and macros per 100 g.
class GenericPer100g {
  const GenericPer100g({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

class GenericFood {
  const GenericFood({
    required this.id,
    required this.name,
    required this.category,
    required this.per100g,
    required this.fdcId,
    required this.tags,
    this.nameRu,
    this.derivedEnergy = false,
  });

  /// `gen:<fdcId>`.
  final String id;

  /// English USDA description.
  final String name;
  final String category;
  final GenericPer100g per100g;
  final int fdcId;
  final GenericFoodTags tags;

  /// Own-authored Russian display name, when one exists.
  final String? nameRu;

  /// Energy was derived 4/4/9 from the macros rather than read from FDC.
  final bool derivedEnergy;

  /// Display name for [languageCode]; Russian falls back to English.
  String displayName(String languageCode) =>
      languageCode.toLowerCase().startsWith('ru') && nameRu != null
          ? nameRu!
          : name;
}

/// One ranked search hit.
class GenericFoodHit {
  const GenericFoodHit(this.food, this.score);
  final GenericFood food;
  final int score;

  /// The UI shows a warning on uncertain rows (design 17.5).
  bool get showTagWarning => food.tags.isUncertain;
}

class GenericFoodTable {
  GenericFoodTable._(this.foods) : _index = [for (final f in foods) _Indexed(f)];

  /// Empty table: the safe result when the asset cannot be read.
  GenericFoodTable.empty()
      : foods = const [],
        _index = const [];

  final List<GenericFood> foods;
  final List<_Indexed> _index;

  /// Parses the two asset documents. A malformed row is skipped, never thrown;
  /// a malformed document yields an empty table so the diary keeps working.
  static GenericFoodTable parse(String foodsJson, {String? ruJson}) {
    final doc = _decode(foodsJson);
    final rows = doc is Map ? doc['foods'] : null;
    if (rows is! List) return GenericFoodTable.empty();
    final ru = <String, String>{};
    if (ruJson != null) {
      final rd = _decode(ruJson);
      final names = rd is Map ? rd['names'] : null;
      if (names is Map) {
        names.forEach((k, v) {
          if (k is String && v is String && v.trim().isNotEmpty) {
            ru[k] = v.trim();
          }
        });
      }
    }
    final out = <GenericFood>[];
    for (final r in rows) {
      final food = _parseRow(r, ru);
      if (food != null) out.add(food);
    }
    return GenericFoodTable._(List.unmodifiable(out));
  }

  static Object? _decode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }

  static GenericFood? _parseRow(Object? r, Map<String, String> ru) {
    if (r is! Map) return null;
    final id = r['id'];
    final name = r['name'];
    final per = r['per100g'];
    final fdc = r['fdcId'];
    if (id is! String || name is! String || per is! Map || fdc is! num) {
      return null;
    }
    double? n(Object? v) => v is num && v.isFinite && v >= 0 ? v.toDouble() : null;
    final kcal = n(per['kcal']);
    final p = n(per['proteinG']);
    final c = n(per['carbsG']);
    final f = n(per['fatG']);
    if (kcal == null || p == null || c == null || f == null) return null;
    return GenericFood(
      id: id,
      name: name,
      category: r['category'] is String ? r['category'] as String : '',
      per100g: GenericPer100g(kcal: kcal, proteinG: p, carbsG: c, fatG: f),
      fdcId: fdc.toInt(),
      tags: GenericFoodTags.fromJson(r['tags']),
      nameRu: ru[name],
      derivedEnergy: r['derivedEnergy'] == true,
    );
  }

  GenericFood? byId(String id) {
    for (final f in foods) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Token search: exact token (3) > prefix (2) > substring (1) per query token,
  /// every query token must match (directly or through [synonyms]). Searches
  /// the English and the Russian name regardless of the UI language. Ties go to
  /// the shorter name, then the id, so the order is deterministic.
  List<GenericFoodHit> search(String query, {int limit = 20}) {
    final qTokens = tokenize(query);
    if (qTokens.isEmpty || limit <= 0) return const [];
    final hits = <GenericFoodHit>[];
    for (final item in _index) {
      var total = 0;
      var ok = true;
      for (final q in qTokens) {
        var best = 0;
        for (final alt in [q, ...?synonyms[q]]) {
          final s = item.score(alt);
          if (s > best) best = s;
        }
        if (best == 0) {
          ok = false;
          break;
        }
        total += best;
      }
      if (ok) hits.add(GenericFoodHit(item.food, total));
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byLen = a.food.name.length.compareTo(b.food.name.length);
      return byLen != 0 ? byLen : a.food.id.compareTo(b.food.id);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }

  /// Small synonym table (query token -> alternatives), EN and RU.
  static const Map<String, List<String>> synonyms = {
    'chicken': ['poultry'],
    'курица': ['chicken', 'курин'],
    'курицу': ['chicken'],
    'курин': ['chicken'],
    'potato': ['potatoes'],
    'картошка': ['картофель', 'potatoes'],
    'картофель': ['potatoes'],
    'yoghurt': ['yogurt'],
    'йогурт': ['yogurt'],
    'curd': ['cottage', 'творог'],
    'творог': ['cottage'],
    'cottage': ['творог'],
    'oatmeal': ['oats', 'овсян'],
    'овсянка': ['oats', 'овсяные'],
    'porridge': ['oats'],
    'каша': ['oats', 'buckwheat', 'millet'],
    'eggs': ['egg'],
    'яйцо': ['egg'],
    'яйца': ['egg', 'яйцо'],
    'beef': ['говяж'],
    'говядина': ['beef'],
    'pork': ['свин'],
    'свинина': ['pork'],
    'fish': ['рыб'],
    'рыба': ['fish', 'salmon', 'cod', 'tuna'],
    'bread': ['хлеб'],
    'хлеб': ['bread'],
    'milk': ['молоко'],
    'молоко': ['milk'],
    'rice': ['рис'],
    'рис': ['rice'],
    'pasta': ['макароны'],
    'макароны': ['pasta'],
    'cheese': ['сыр'],
    'сыр': ['cheese'],
    'butter': ['масло'],
    'apple': ['apples', 'яблок'],
    'яблоко': ['apples'],
    'banana': ['bananas'],
    'банан': ['bananas'],
    'tomato': ['tomatoes'],
    'помидор': ['tomatoes', 'томат'],
    'cucumber': ['огурец'],
    'огурцы': ['cucumber', 'огурец'],
    'peanut': ['peanuts', 'арахис'],
    'nuts': ['nut', 'орех'],
    'орехи': ['nuts'],
  };
}

/// Lowercase letter/digit tokens (Unicode aware; punctuation separates).
List<String> tokenize(String s) {
  final lower = s.toLowerCase().replaceAll('ё', 'е');
  return [
    for (final t in lower.split(_separator))
      if (t.isNotEmpty) t
  ];
}

final RegExp _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

class _Indexed {
  _Indexed(this.food)
      : tokens = [
          ...tokenize(food.name),
          if (food.nameRu != null) ...tokenize(food.nameRu!),
        ];

  final GenericFood food;
  final List<String> tokens;

  int score(String query) {
    final q = query.toLowerCase().replaceAll('ё', 'е');
    var best = 0;
    for (final t in tokens) {
      if (t == q) return 3;
      if (t.startsWith(q)) {
        if (best < 2) best = 2;
      } else if (best < 1 && q.length >= 3 && t.contains(q)) {
        best = 1;
      }
    }
    return best;
  }
}
