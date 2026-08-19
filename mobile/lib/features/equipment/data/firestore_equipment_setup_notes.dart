import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'equipment_setup_note.dart';
import 'equipment_setup_note_repository.dart';

/// Firestore-backed setup notes, at `users/{uid}/equipment_setup_notes/{id}`.
///
/// Needs no rules change: `match /users/{uid}/{coll}/{document=**}`
/// (firestore.rules) already covers this subcollection, the same way it
/// already covers `machine_cards` and `recognised_equipment` --
/// `equipment_setup_notes` is not the server-only `subscription`.
///
/// Signed out, every method degrades to a no-op / null result rather than
/// throwing, matching every other repository in this feature.
class FirestoreEquipmentSetupNoteRepository
    implements EquipmentSetupNoteRepository {
  FirestoreEquipmentSetupNoteRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _injectedDb = firestore,
        _injectedAuth = auth;

  final FirebaseFirestore? _injectedDb;
  final FirebaseAuth? _injectedAuth;

  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('equipment_setup_notes');

  @override
  Future<EquipmentSetupNote?> get({
    required String equipmentId,
    required String gymId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final id = equipmentSetupNoteId(equipmentId: equipmentId, gymId: gymId);
    final snap = await _col(uid).doc(id).get();
    final data = snap.data();
    if (data == null) return null;
    return _fromFirestore(data);
  }

  @override
  Future<void> save(EquipmentSetupNote note) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _col(uid).doc(note.id).set(_toFirestore(note), SetOptions(merge: false));
  }

  @override
  Future<void> delete({
    required String equipmentId,
    required String gymId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final id = equipmentSetupNoteId(equipmentId: equipmentId, gymId: gymId);
    await _col(uid).doc(id).delete();
  }
}

EquipmentSetupNote? _fromFirestore(Map<String, dynamic> data) {
  final normalised = Map<String, dynamic>.from(data);
  final raw = normalised['updatedAt'];
  if (raw is Timestamp) {
    normalised['updatedAt'] = raw.toDate().toUtc().toIso8601String();
  }
  return EquipmentSetupNote.fromJson(normalised);
}

Map<String, dynamic> _toFirestore(EquipmentSetupNote note) => note.toJson();
