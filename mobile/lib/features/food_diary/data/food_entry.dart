/// Diary entry model: `users/{uid}/food_entries/{entryId}` (design s5.6,
/// FOOD-23). Pure Dart, no Flutter or Firestore imports; the repository in
/// `state/` maps `loggedAt` to a Timestamp.
///
/// Serialisation rules: `toJson` omits null and empty optional keys and
/// REFUSES (throws [FormatException]) an entry that Firestore rules would
/// refuse; `fromJson` is tolerant: unknown enum values degrade to a safe
/// default and set [FoodEntry.degraded], which blocks a later write.
library;

import 'dart:math' as math;

import 'check_these.dart';
import 'food_source.dart';

double _num(Object? raw) {
  final v = raw is num ? raw.toDouble() : double.nan;
  return v.isFinite && v >= 0 ? v : 0.0;
}

/// `{low, mid, high}` with `0 <= low <= mid <= high` (design s17.7).
class MacroRange {
  const MacroRange._(this.low, this.mid, this.high);

  /// Sanitises (non-finite or negative -> 0) and reorders so
  /// `low <= mid <= high` always holds.
  factory MacroRange(double low, double mid, double high) {
    double s(double v) => v.isFinite && v > 0 ? v : 0.0;
    final sorted = [s(low), s(mid), s(high)]..sort();
    return MacroRange._(sorted[0], sorted[1], sorted[2]);
  }

  /// A degenerate range around one value.
  factory MacroRange.exact(double v) => MacroRange(v, v, v);

  static const MacroRange zero = MacroRange._(0, 0, 0);

  final double low;
  final double mid;
  final double high;

  /// Multiplies all three bounds by a non-negative [factor].
  MacroRange scaled(double factor) {
    final f = factor.isFinite && factor > 0 ? factor : 0.0;
    return MacroRange(low * f, mid * f, high * f);
  }

  /// Plain bound-wise sum (used for ranges that are NOT independent errors).
  MacroRange operator +(MacroRange o) =>
      MacroRange(low + o.low, mid + o.mid, high + o.high);

  /// Day/entry total: `mid = sum(mid)`; asymmetric spreads combined by root
  /// sum of squares (design s17.7, assumes independent errors, so two items
  /// each 100 below mid give 141.4 below, not 200).
  static MacroRange combine(Iterable<MacroRange> ranges) {
    var mid = 0.0;
    var lo2 = 0.0;
    var hi2 = 0.0;
    for (final r in ranges) {
      mid += r.mid;
      final dl = r.mid - r.low;
      final dh = r.high - r.mid;
      lo2 += dl * dl;
      hi2 += dh * dh;
    }
    return MacroRange(mid - math.sqrt(lo2), mid, mid + math.sqrt(hi2));
  }

  Map<String, dynamic> toJson() => {'low': low, 'mid': mid, 'high': high};

  /// Tolerant read: a missing/invalid map is [zero]; each bound is sanitised
  /// and the triple reordered.
  factory MacroRange.fromJson(Object? raw) {
    if (raw is! Map) return zero;
    return MacroRange(_num(raw['low']), _num(raw['mid']), _num(raw['high']));
  }

  @override
  bool operator ==(Object other) =>
      other is MacroRange &&
      other.low == low &&
      other.mid == mid &&
      other.high == high;

  @override
  int get hashCode => Object.hash(low, mid, high);

  @override
  String toString() => 'MacroRange($low, $mid, $high)';
}

/// Per-100 g nutrition values of a food.
class Per100g {
  const Per100g({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  Map<String, dynamic> toJson() => {
        'kcal': kcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
      };

  factory Per100g.fromJson(Object? raw) {
    if (raw is! Map) return const Per100g(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);
    return Per100g(
      kcal: _num(raw['kcal']),
      proteinG: _num(raw['proteinG']),
      carbsG: _num(raw['carbsG']),
      fatG: _num(raw['fatG']),
    );
  }

  /// Rules bound each per-100 g value to [0, 1000].
  bool get isWithinRulesBounds =>
      [kcal, proteinG, carbsG, fatG].every((v) => v.isFinite && v >= 0 && v <= 1000);

  @override
  bool operator ==(Object other) =>
      other is Per100g &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbsG, fatG);
}

/// `totals`: exactly `kcal, proteinG, carbsG, fatG`, each a [MacroRange].
class MacroTotals {
  const MacroTotals({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  static const MacroTotals zero = MacroTotals(
    kcal: MacroRange.zero,
    proteinG: MacroRange.zero,
    carbsG: MacroRange.zero,
    fatG: MacroRange.zero,
  );

  final MacroRange kcal;
  final MacroRange proteinG;
  final MacroRange carbsG;
  final MacroRange fatG;

  /// Independent-error combination of several totals (RSS per macro).
  static MacroTotals combine(Iterable<MacroTotals> all) {
    final list = all.toList();
    return MacroTotals(
      kcal: MacroRange.combine(list.map((t) => t.kcal)),
      proteinG: MacroRange.combine(list.map((t) => t.proteinG)),
      carbsG: MacroRange.combine(list.map((t) => t.carbsG)),
      fatG: MacroRange.combine(list.map((t) => t.fatG)),
    );
  }

  Map<String, dynamic> toJson() => {
        'kcal': kcal.toJson(),
        'proteinG': proteinG.toJson(),
        'carbsG': carbsG.toJson(),
        'fatG': fatG.toJson(),
      };

  factory MacroTotals.fromJson(Object? raw) {
    if (raw is! Map) return zero;
    return MacroTotals(
      kcal: MacroRange.fromJson(raw['kcal']),
      proteinG: MacroRange.fromJson(raw['proteinG']),
      carbsG: MacroRange.fromJson(raw['carbsG']),
      fatG: MacroRange.fromJson(raw['fatG']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MacroTotals &&
      other.kcal == kcal &&
      other.proteinG == proteinG &&
      other.carbsG == carbsG &&
      other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbsG, fatG);
}

enum MealSlot { breakfast, lunch, dinner, snack }

enum EntrySource { photo, describe, search, barcode, label, manual }

enum EntryConfidence { low, medium, high }

enum MatchQuality { exact, close, weak, none }

T? _byName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

/// One food line of an entry: a food, the portion range and per-100 g data.
class FoodItem {
  const FoodItem({
    required this.foodRef,
    required this.name,
    required this.grams,
    required this.per100g,
    this.matchQuality = MatchQuality.exact,
    this.source = FoodSource.user,
  });

  /// `gen:<id>` | `off:<barcode>` | `user:<id>` | `label`.
  final String foodRef;
  final String name;
  final MacroRange grams;
  final Per100g per100g;
  final MatchQuality matchQuality;
  final FoodSource source;

  static const int maxNameLength = 80;

  FoodItem copyWith({MacroRange? grams, String? name}) => FoodItem(
        foodRef: foodRef,
        name: name ?? this.name,
        grams: grams ?? this.grams,
        per100g: per100g,
        matchQuality: matchQuality,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'foodRef': foodRef,
        'name': name,
        'grams': grams.toJson(),
        'per100g': per100g.toJson(),
        'matchQuality': matchQuality.name,
        'sourceId': source.wireId,
      };

  /// Returns null when [raw] is not a map. Unknown enums degrade (see
  /// [FoodEntry.fromJson], which tracks degradation).
  static FoodItem? tryFromJson(Object? raw, {void Function()? onDegraded}) {
    if (raw is! Map) return null;
    final mq = _byName(MatchQuality.values, raw['matchQuality']);
    final src = FoodSource.tryParse(raw['sourceId']);
    if (mq == null || src == null) onDegraded?.call();
    final name = raw['name'];
    final ref = raw['foodRef'];
    return FoodItem(
      foodRef: ref is String ? ref : 'user:unknown',
      name: name is String ? name : '',
      grams: MacroRange.fromJson(raw['grams']),
      per100g: Per100g.fromJson(raw['per100g']),
      matchQuality: mq ?? MatchQuality.none,
      source: src ?? FoodSource.user,
    );
  }
}

/// `model: {id, version}` when the entry is AI-assisted.
class ModelRef {
  const ModelRef({required this.id, required this.version});
  final String id;
  final String version;

  Map<String, dynamic> toJson() => {'id': id, 'version': version};

  static ModelRef? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final v = raw['version'];
    if (id is! String || id.isEmpty) return null;
    return ModelRef(id: id, version: v is String ? v : '');
  }
}

/// A diary entry.
class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.day,
    required this.slot,
    required this.loggedAt,
    required this.name,
    required this.source,
    required this.confidence,
    required this.items,
    required this.totals,
    this.checkThese = const [],
    this.model,
    this.degraded = false,
  });

  static const int schema = 1;
  static const int maxItems = 30;
  static const int maxNameLength = 80;

  /// Client UUID (idempotent retries); the document id.
  final String id;

  /// Local date `yyyy-MM-dd`.
  final String day;
  final MealSlot slot;
  final DateTime loggedAt;
  final String name;
  final EntrySource source;
  final EntryConfidence confidence;
  final List<FoodItem> items;
  final MacroTotals totals;
  final List<CheckItem> checkThese;
  final ModelRef? model;

  /// True when [fromJson] replaced an unknown enum value; such an entry must
  /// not be written back.
  final bool degraded;

  static final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Problems that Firestore rules would reject; empty means writable.
  List<String> validate() {
    final p = <String>[];
    if (degraded) p.add('degraded: unknown enum value was replaced on read');
    if (!_dayPattern.hasMatch(day)) p.add('day must be yyyy-MM-dd');
    if (name.length > maxNameLength) p.add('name longer than $maxNameLength');
    if (items.isEmpty) p.add('items must not be empty');
    if (items.length > maxItems) p.add('more than $maxItems items');
    if (checkThese.length > CheckThese.maxChips) {
      p.add('more than ${CheckThese.maxChips} check-these items');
    }
    for (final i in items) {
      if (i.name.length > FoodItem.maxNameLength) {
        p.add('item name longer than ${FoodItem.maxNameLength}');
        break;
      }
    }
    return p;
  }

  FoodEntry copyWith({
    MealSlot? slot,
    String? name,
    List<FoodItem>? items,
    MacroTotals? totals,
    List<CheckItem>? checkThese,
    EntryConfidence? confidence,
  }) =>
      FoodEntry(
        id: id,
        day: day,
        slot: slot ?? this.slot,
        loggedAt: loggedAt,
        name: name ?? this.name,
        source: source,
        confidence: confidence ?? this.confidence,
        items: items ?? this.items,
        totals: totals ?? this.totals,
        checkThese: checkThese ?? this.checkThese,
        model: model,
        degraded: degraded,
      );

  /// Omits null/empty optional keys (`model`, empty `checkThese`).
  /// Throws [FormatException] when [validate] reports a problem.
  Map<String, dynamic> toJson() {
    final problems = validate();
    if (problems.isNotEmpty) {
      throw FormatException('FoodEntry refused: ${problems.join('; ')}');
    }
    return {
      'schema': schema,
      'day': day,
      'slot': slot.name,
      'loggedAt': loggedAt.toIso8601String(),
      'name': name,
      'source': source.name,
      'confidence': confidence.name,
      'items': [for (final i in items) i.toJson()],
      'totals': totals.toJson(),
      if (checkThese.isNotEmpty)
        'checkThese': [for (final c in checkThese) c.toJson()],
      if (model != null) 'model': model!.toJson(),
    };
  }

  /// Tolerant read. Unknown slot/source/confidence/matchQuality/sourceId
  /// degrade to a safe default and set [degraded]; rows that are not maps are
  /// dropped; unknown check codes are dropped.
  factory FoodEntry.fromJson(String id, Map<String, dynamic> json) {
    var degraded = false;
    void mark() => degraded = true;

    final slot = _byName(MealSlot.values, json['slot']);
    final source = _byName(EntrySource.values, json['source']);
    final confidence = _byName(EntryConfidence.values, json['confidence']);
    if (slot == null || source == null || confidence == null) mark();

    final items = <FoodItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final r in rawItems) {
        final it = FoodItem.tryFromJson(r, onDegraded: mark);
        if (it != null) items.add(it);
      }
    }

    final at = json['loggedAt'];
    final loggedAt = at is String
        ? (DateTime.tryParse(at) ?? DateTime.fromMillisecondsSinceEpoch(0))
        : at is DateTime
            ? at
            : DateTime.fromMillisecondsSinceEpoch(0);

    final name = json['name'];
    final day = json['day'];
    return FoodEntry(
      id: id,
      day: day is String ? day : '',
      slot: slot ?? MealSlot.snack,
      loggedAt: loggedAt,
      name: name is String ? name : '',
      source: source ?? EntrySource.manual,
      confidence: confidence ?? EntryConfidence.low,
      items: items,
      totals: MacroTotals.fromJson(json['totals']),
      checkThese: CheckThese.parseList(json['checkThese']),
      model: ModelRef.tryFromJson(json['model']),
      degraded: degraded,
    );
  }
}
