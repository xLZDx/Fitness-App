import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import 'equipment_models.dart';
import 'equipment_repository.dart';

/// Reads the bundled catalog, optionally translated.
///
/// `exercises_vendor.json` is the base and the only source of structure: ids,
/// muscles, machine links and clips all come from it in every language. A
/// translation is a text-only overlay keyed by exercise id
/// (`exercises_vendor.<code>.json`) patched over that base, so a language can
/// never add, drop or re-tag an exercise.
class AssetEquipmentRepository implements EquipmentRepository {
  AssetEquipmentRepository({this.languageCode = 'en'});

  /// Which translation overlay to apply. `'en'` means "the base, unmodified".
  final String languageCode;

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

    // One catalog, since 2026-08-04. The pre-purchase `exercises.json` (511
    // entries, of which 337 could be demonstrated) was removed once its clips
    // were found to be ~99.5% duplicates of vendor footage and every machine
    // it linked had vendor exercises of its own.
    _exercises =
        List<ExerciseItem>.unmodifiable(await _loadCatalog('exercises_vendor'));
  }

  /// One catalog file plus its translation overlay.
  ///
  /// Still a named-catalog loader rather than an inlined read: the overlay
  /// contract it enforces — text only, keyed by id, never able to add or
  /// re-tag an exercise — is the thing worth keeping in one place.
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
    final quarantined = await _loadQuarantine();
    final base = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(ExerciseItem.fromJson)
        .where((e) => !quarantined.contains(e.id))
        .toList(growable: false);
    return applyTranslations(
        base, await _loadOverlay('assets/data/$name.$languageCode.json'));
  }

  /// Ids the catalogue still contains and no user may be offered.
  ///
  /// C1. The 2026-08-15 audit found rows that are not exercises — the first
  /// being `ea_major_groups_muscle_body`, a single step describing a standing
  /// position with no movement after it. A card like that cannot be fixed by
  /// rewriting its text, because there is nothing behind it to describe.
  ///
  /// Withheld here rather than deleted from the JSON, for two reasons. The
  /// external audit is pinned to all 1,887 ids and cross-references them in
  /// both directions, so removing a row would make that evidence stop matching
  /// the shipped catalogue for a reason a later reader could not reconstruct.
  /// And a deletion says nothing about WHY, whereas
  /// `exercises_quarantine.json` carries the reason next to the id.
  ///
  /// This is the only load path — equipment browsing, the workout player, the
  /// For You feed and the generated plan all resolve through this repository —
  /// so a withheld id is withheld everywhere rather than on the surfaces
  /// somebody remembered to filter.
  ///
  /// A missing or malformed file quarantines NOTHING and says so. Failing open
  /// is the deliberate choice: the alternative failure, a parse error taking
  /// the whole catalogue down, costs every user the entire library to enforce a
  /// list that today holds one entry.
  Future<Set<String>> _loadQuarantine() async {
    try {
      final raw =
          await rootBundle.loadString('assets/data/exercises_quarantine.json');
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['id'] as String)
          .toSet();
    } catch (e) {
      debugPrint('exercise quarantine list unusable, withholding nothing: $e');
      return const <String>{};
    }
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
    if (title is! String || title.trim().isEmpty) return item;
    final steps = ExerciseItem.parseSteps(entry['steps']);
    // Read separately from the steps: "why this matters" lives in its own
    // field precisely because it cannot live in `summary`, which is pinned to
    // step one. Forgetting it here is invisible in the data — both files carry
    // the Russian text and the ratchet passes — but every Russian reader gets
    // the English paragraph, because `withText` otherwise keeps the base row's.
    final purposeText = (entry['purpose'] as String?)?.trim();
    final purpose = (purposeText == null || purposeText.isEmpty)
        ? null
        : purposeText;
    // An overlay with no steps used to discard the whole entry, title and
    // all. That was safe while the pre-purchase catalog was the visible half
    // — every one of its rows had instructions. The purchased library ships
    // 403 of 1,887 with a title and no steps at all, so after that catalog
    // was removed on 2026-08-04 this guard was silently leaving a fifth of
    // the app reading English under a Russian UI, with a perfectly good
    // translation sitting unused in the overlay file.
    //
    // Keeping the base steps rather than blanking them is the other half:
    // an overlay that loses its steps must not be able to delete
    // instructions the user needs, in any language.
    if (steps.isEmpty) {
      return item.withText(
        title: title,
        summary: item.summary,
        steps: item.steps,
        purpose: purpose,
      );
    }
    return item.withText(
      title: title,
      summary: steps.first,
      steps: steps,
      purpose: purpose,
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
