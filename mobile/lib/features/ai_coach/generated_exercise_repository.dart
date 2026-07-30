import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../equipment/data/equipment_models.dart';

/// Caches AI-generated exercises so a machine is only ever billed once per
/// (user, machine, language) — reopening its page reads the saved answer
/// instead of asking Gemini again. Keyed by `<equipmentId>_<languageCode>`
/// rather than equipmentId alone: a language switch must not serve English
/// text under a Russian UI (or vice versa).
abstract class GeneratedExerciseRepository {
  Future<List<ExerciseItem>?> get(String equipmentId, String languageCode);
  Future<void> save(
      String equipmentId, String languageCode, List<ExerciseItem> items);
}

class MockGeneratedExerciseRepository implements GeneratedExerciseRepository {
  final Map<String, List<ExerciseItem>> _store = {};

  String _key(String equipmentId, String lang) => '${equipmentId}_$lang';

  @override
  Future<List<ExerciseItem>?> get(String equipmentId, String languageCode) async =>
      _store[_key(equipmentId, languageCode)];

  @override
  Future<void> save(
      String equipmentId, String languageCode, List<ExerciseItem> items) async {
    _store[_key(equipmentId, languageCode)] = items;
  }
}

/// Firestore-backed: `users/{uid}/generated_exercises/{equipmentId}_{lang}`,
/// mirroring the recognised-equipment store's per-user layout. Signed out
/// degrades to a no-op / null read rather than throwing, so generation still
/// works (just uncached) before auth has settled.
class FirestoreGeneratedExerciseRepository
    implements GeneratedExerciseRepository {
  FirestoreGeneratedExerciseRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _injectedDb = firestore,
        _injectedAuth = auth;

  final FirebaseFirestore? _injectedDb;
  final FirebaseAuth? _injectedAuth;

  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('generated_exercises');

  @override
  Future<List<ExerciseItem>?> get(String equipmentId, String languageCode) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await _col(uid).doc('${equipmentId}_$languageCode').get();
    final data = snap.data();
    if (data == null) return null;
    final raw = data['items'];
    if (raw is! String) return null;
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(ExerciseItem.fromJson)
        .toList();
  }

  @override
  Future<void> save(
      String equipmentId, String languageCode, List<ExerciseItem> items) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _col(uid).doc('${equipmentId}_$languageCode').set({
      'items': jsonEncode(items.map(_toJson).toList()),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Map<String, dynamic> _toJson(ExerciseItem e) => {
        'id': e.id,
        'title': e.title,
        'equipmentId': e.equipmentId,
        'muscles': e.muscles,
        'primaryMuscles': e.primaryMuscles,
        'difficulty': e.difficulty.name,
        'durationMinutes': e.durationMinutes,
        'summary': e.summary,
        'steps': e.steps,
        'contraindications': e.contraindications,
      };
}
