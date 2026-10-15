/// Storage ports of the food diary: entries `users/{uid}/food_entries/{id}`
/// (design s5.6) and saved foods `users/{uid}/saved_foods/{id}` (s5.7), plus
/// in-memory fakes for tests and the signed-out default. No Flutter imports.
library;

import 'dart:async';

import '../data/food_entry.dart';

/// A food the user saved for reuse (per-100 g values; a serving is optional).
class SavedFood {
  const SavedFood({
    required this.id,
    required this.name,
    required this.per100g,
    this.servingG,
    this.barcode,
    this.createdAt,
  });

  /// Client-side cap (rules only bound the SHAPE of one document).
  static const int maxCount = 500;
  static const int maxNameLength = 80;

  final String id;
  final String name;
  final Per100g per100g;
  final double? servingG;
  final String? barcode;
  final DateTime? createdAt;

  List<String> validate() {
    final p = <String>[];
    if (name.trim().isEmpty) p.add('name must not be empty');
    if (name.length > maxNameLength) p.add('name longer than $maxNameLength');
    if (!per100g.isWithinRulesBounds) p.add('per100g outside 0..1000');
    final s = servingG;
    if (s != null && !(s.isFinite && s > 0 && s <= 100000)) {
      p.add('servingG outside 0..100000');
    }
    final b = barcode;
    if (b != null && b.length > 32) p.add('barcode longer than 32');
    return p;
  }

  Map<String, dynamic> toJson() {
    final problems = validate();
    if (problems.isNotEmpty) {
      throw FormatException('SavedFood refused: ${problems.join('; ')}');
    }
    return {
      'schema': 1,
      'name': name,
      'per100g': per100g.toJson(),
      if (servingG != null) 'servingG': servingG,
      if (barcode != null) 'barcode': barcode,
    };
  }

  /// Null when the document is not a usable saved food.
  static SavedFood? tryFromJson(String id, Map<String, dynamic> json) {
    final name = json['name'];
    final per = json['per100g'];
    if (name is! String || per is! Map) return null;
    final s = json['servingG'];
    final b = json['barcode'];
    final c = json['createdAt'];
    return SavedFood(
      id: id,
      name: name,
      per100g: Per100g.fromJson(per),
      servingG: s is num && s.isFinite && s > 0 ? s.toDouble() : null,
      barcode: b is String ? b : null,
      createdAt: c is DateTime ? c : null,
    );
  }
}

abstract class FoodDiaryRepository {
  /// Entries of one local day (`yyyy-MM-dd`), oldest first. Replays the latest
  /// value. Unreadable documents are skipped.
  Stream<List<FoodEntry>> watchDay(String uid, String day);

  /// Idempotent create-or-replace under the entry's own client id. Throws
  /// [FormatException] for an entry the rules would refuse.
  Future<void> put(String uid, FoodEntry entry);

  Future<void> delete(String uid, String entryId);
}

abstract class SavedFoodsRepository {
  Stream<List<SavedFood>> watchAll(String uid);

  /// Throws [StateError] when [SavedFood.maxCount] is already reached and the
  /// id is new; [FormatException] for an invalid food.
  Future<void> put(String uid, SavedFood food);

  Future<void> delete(String uid, String foodId);
}

class InMemoryDiaryRepository implements FoodDiaryRepository {
  final Map<String, Map<String, FoodEntry>> _byUid = {};
  final Map<String, StreamController<void>> _bell = {};
  int writes = 0;
  bool offline = false;

  StreamController<void> _c(String uid) =>
      _bell.putIfAbsent(uid, () => StreamController<void>.broadcast());

  List<FoodEntry> _day(String uid, String day) {
    final list = [
      for (final e in (_byUid[uid] ?? const <String, FoodEntry>{}).values)
        if (e.day == day) e,
    ]..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return list;
  }

  @override
  Stream<List<FoodEntry>> watchDay(String uid, String day) async* {
    yield _day(uid, day);
    await for (final _ in _c(uid).stream) {
      yield _day(uid, day);
    }
  }

  @override
  Future<void> put(String uid, FoodEntry entry) async {
    if (offline) throw StateError('offline');
    entry.toJson(); // same refusal as the Firestore path
    (_byUid[uid] ??= {})[entry.id] = entry;
    writes++;
    _c(uid).add(null);
  }

  @override
  Future<void> delete(String uid, String entryId) async {
    if (offline) throw StateError('offline');
    _byUid[uid]?.remove(entryId);
    _c(uid).add(null);
  }

  void dispose() {
    for (final c in _bell.values) {
      c.close();
    }
  }
}

class InMemorySavedFoodsRepository implements SavedFoodsRepository {
  final Map<String, Map<String, SavedFood>> _byUid = {};
  final Map<String, StreamController<void>> _bell = {};

  StreamController<void> _c(String uid) =>
      _bell.putIfAbsent(uid, () => StreamController<void>.broadcast());

  List<SavedFood> _all(String uid) => [
        ...(_byUid[uid] ?? const <String, SavedFood>{}).values,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  @override
  Stream<List<SavedFood>> watchAll(String uid) async* {
    yield _all(uid);
    await for (final _ in _c(uid).stream) {
      yield _all(uid);
    }
  }

  @override
  Future<void> put(String uid, SavedFood food) async {
    food.toJson();
    final map = _byUid[uid] ??= {};
    if (!map.containsKey(food.id) && map.length >= SavedFood.maxCount) {
      throw StateError('saved foods limit reached');
    }
    map[food.id] = food;
    _c(uid).add(null);
  }

  @override
  Future<void> delete(String uid, String foodId) async {
    _byUid[uid]?.remove(foodId);
    _c(uid).add(null);
  }

  void dispose() {
    for (final c in _bell.values) {
      c.close();
    }
  }
}
