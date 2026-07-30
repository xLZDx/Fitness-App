import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import 'equipment_models.dart';
import 'equipment_repository.dart';

/// Reads the bundled catalog, optionally translated.
///
/// The English `exercises.json` is the base and the only source of structure:
/// ids, muscles, contraindications and frames all come from it in every
/// language. A translation is a text-only overlay keyed by exercise id
/// (`exercises.<code>.json`) patched over that base, so a language can never
/// add, drop or re-tag an exercise.
class AssetEquipmentRepository implements EquipmentRepository {
  AssetEquipmentRepository({this.languageCode = 'en'});

  /// Which translation overlay to apply. `'en'` means "the base, unmodified".
  final String languageCode;

  List<EquipmentItem>? _equipment;
  List<ExerciseItem>? _exercises;

  Future<void> _ensureLoaded() async {
    if (_equipment != null && _exercises != null) return;
    final eqJson = await rootBundle.loadString('assets/data/equipment.json');
    final exJson = await rootBundle.loadString('assets/data/exercises.json');
    final eqBase = (jsonDecode(eqJson) as List)
        .cast<Map<String, dynamic>>()
        .map(EquipmentItem.fromJson)
        .toList(growable: false);
    _equipment = applyEquipmentTranslations(
        eqBase, await _loadOverlay('assets/data/equipment.$languageCode.json'));
    final base = (jsonDecode(exJson) as List)
        .cast<Map<String, dynamic>>()
        .map(ExerciseItem.fromJson)
        .toList(growable: false);
    _exercises = applyTranslations(
        base, await _loadOverlay('assets/data/exercises.$languageCode.json'));
  }

  /// Loads the translation overlay, or returns empty on any failure.
  ///
  /// Isolated from the base load on purpose. Every screen that shows an
  /// exercise — equipment browsing, the workout player, the For You feed, the
  /// generated plan — resolves through this one repository, so letting a
  /// missing or malformed translation file throw would take the whole catalog
  /// down in BOTH languages to deliver a translation. Falling back to English
  /// is the only acceptable failure mode, and it is logged rather than
  /// swallowed so it stays diagnosable.
  Future<Map<String, dynamic>> _loadOverlay(String path) async {
    if (languageCode == 'en') return const <String, dynamic>{};
    try {
      final raw = await rootBundle.loadString(path);
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (e) {
      debugPrint('translation overlay $path unusable, falling back to '
          'English: $e');
      return const <String, dynamic>{};
    }
  }

  /// Patches translated equipment text over [base] — same contract as
  /// [applyTranslations]: text only, one entry per base entry, missing ids
  /// keep English. Before this overlay existed the machine pages showed
  /// English descriptions under a fully Russian UI (operator screenshot,
  /// 13:25 — 'Motorised running belt…' under 'Описание').
  @visibleForTesting
  static List<EquipmentItem> applyEquipmentTranslations(
    List<EquipmentItem> base,
    Map<String, dynamic> overlay,
  ) {
    if (overlay.isEmpty) return base;
    return List<EquipmentItem>.unmodifiable(<EquipmentItem>[
      for (final item in base) _translateEquipment(item, overlay[item.id]),
    ]);
  }

  static EquipmentItem _translateEquipment(EquipmentItem item, Object? entry) {
    if (entry is! Map) return item;
    final name = entry['name'];
    final description = entry['description'];
    if (name is! String || name.trim().isEmpty) return item;
    return item.withText(
      name: name,
      description:
          description is String && description.trim().isNotEmpty
              ? description
              : item.description,
    );
  }

  /// Patches translated text over [base].
  ///
  /// Returns one entry per entry of [base], in the same order, always: an id
  /// absent from the overlay keeps its English text rather than disappearing.
  /// `summary` is taken from the first step because that is what the base
  /// catalog does — an invariant the test suite pins on the English data, so it
  /// fails loudly if a future catalog rebuild breaks it instead of silently
  /// leaving Russian summaries in English.
  @visibleForTesting
  static List<ExerciseItem> applyTranslations(
    List<ExerciseItem> base,
    Map<String, dynamic> overlay,
  ) {
    if (overlay.isEmpty) return base;
    return List<ExerciseItem>.unmodifiable(<ExerciseItem>[
      for (final item in base) _translate(item, overlay[item.id]),
    ]);
  }

  static ExerciseItem _translate(ExerciseItem item, Object? entry) {
    if (entry is! Map) return item;
    final title = entry['title'];
    final steps = ExerciseItem.parseSteps(entry['steps']);
    if (title is! String || title.trim().isEmpty || steps.isEmpty) return item;
    return item.withText(
      title: title,
      summary: steps.first,
      steps: steps,
    );
  }

  /// Test-only: pre-seed the cache without going through asset loading.
  void seedForTests({
    required List<EquipmentItem> equipment,
    required List<ExerciseItem> exercises,
  }) {
    _equipment = List.unmodifiable(equipment);
    _exercises = List.unmodifiable(exercises);
  }

  @override
  Future<List<EquipmentItem>> listEquipment() async {
    await _ensureLoaded();
    return _equipment!;
  }

  @override
  Future<EquipmentItem?> findEquipment(String id) async {
    await _ensureLoaded();
    for (final e in _equipment!) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async {
    await _ensureLoaded();
    return _exercises!
        .where((e) => e.equipmentId == equipmentId)
        .toList(growable: false);
  }

  @override
  Future<List<ExerciseItem>> bodyweightExercises() async {
    await _ensureLoaded();
    return _exercises!
        .where((e) => e.equipmentId == null)
        .toList(growable: false);
  }
}
