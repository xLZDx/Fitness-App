import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'equipment_models.dart';
import 'equipment_repository.dart';

class AssetEquipmentRepository implements EquipmentRepository {
  AssetEquipmentRepository();

  List<EquipmentItem>? _equipment;
  List<ExerciseItem>? _exercises;

  Future<void> _ensureLoaded() async {
    if (_equipment != null && _exercises != null) return;
    final eqJson = await rootBundle.loadString('assets/data/equipment.json');
    final exJson = await rootBundle.loadString('assets/data/exercises.json');
    _equipment = (jsonDecode(eqJson) as List)
        .cast<Map<String, dynamic>>()
        .map(EquipmentItem.fromJson)
        .toList(growable: false);
    _exercises = (jsonDecode(exJson) as List)
        .cast<Map<String, dynamic>>()
        .map(ExerciseItem.fromJson)
        .toList(growable: false);
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
