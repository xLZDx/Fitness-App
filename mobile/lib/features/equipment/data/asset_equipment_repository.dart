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
  AssetEquipmentRepository({
    this.languageCode = 'en',
    this.includeLegacy = true,
  });

  /// Which translation overlay to apply. `'en'` means "the base, unmodified".
  final String languageCode;

  /// Whether the original 511 exercises are part of the catalog.
  ///
  /// Two libraries live side by side. `exercises.json` is the one built before
  /// the purchase — 511 entries carrying Russian text, injury
  /// contraindications and links to the 52 machines the scanner knows, of
  /// which 365 can be demonstrated. `exercises_vendor.json` is the purchased
  /// library: 1,899 movements, every one with a clip, and no contraindications
  /// or machine links of its own yet.
  ///
  /// The operator asked to be able to drop the first at any moment, so the
  /// switch exists from the day the second arrives rather than being retrofitted
  /// once something depends on the mixture.
  final bool includeLegacy;

  List<EquipmentItem>? _equipment;
  List<ExerciseItem>? _exercises;

  Future<void> _ensureLoaded() async {
    if (_equipment != null && _exercises != null) return;
    final eqJson = await rootBundle.loadString('assets/data/equipment.json');
    final eqBase = (jsonDecode(eqJson) as List)
        .cast<Map<String, dynamic>>()
        .map(EquipmentItem.fromJson)
        .toList(growable: false);
    _equipment = applyEquipmentTranslations(
        eqBase, await _loadOverlay('assets/data/equipment.$languageCode.json'));

    final exercises = <ExerciseItem>[
      if (includeLegacy)
        ...await _loadCatalog('exercises'),
      ...await _loadCatalog('exercises_vendor'),
    ];
    _exercises = List<ExerciseItem>.unmodifiable(exercises);
  }

  /// One catalog file plus its translation overlay.
  ///
  /// The vendor list is loaded through exactly the same path as the original,
  /// including the overlay contract — text only, keyed by id, never able to add
  /// or re-tag an exercise. Giving it its own loader would have been a second
  /// place for that contract to be enforced, and therefore a second place for
  /// it to stop being enforced.
  Future<List<ExerciseItem>> _loadCatalog(String name) async {
    late final String raw;
    try {
      raw = await rootBundle.loadString('assets/data/$name.json');
    } catch (e) {
      // A missing catalog is survivable when the other one is present, and
      // taking the whole app down for it would be worse than showing half the
      // library. Logged, never silent.
      debugPrint('catalog $name.json unusable: $e');
      return const <ExerciseItem>[];
    }
    final base = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(ExerciseItem.fromJson)
        .toList(growable: false);
    return applyTranslations(
        base, await _loadOverlay('assets/data/$name.$languageCode.json'));
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
