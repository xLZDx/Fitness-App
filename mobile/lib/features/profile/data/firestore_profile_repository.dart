// Wired up during Phase 1B. Reads/writes profiles at
//   /users/{uid}/profile/main
// Use the Firebase Emulator Suite for tests — see
// `core/PHASE_1B_FIREBASE_SETUP.md`.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'profile_models.dart';
import 'profile_repository.dart';

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, UserProfile> _cache = {};

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid).collection('profile').doc('main');

  T? _enumByName<T extends Enum>(List<T> values, dynamic name) {
    if (name is! String) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  UserProfile _fromMap(String uid, Map<String, dynamic> map) {
    DateTime? completedAt;
    final raw = map['completedAt'];
    if (raw is String) completedAt = DateTime.tryParse(raw);
    if (raw is Timestamp) completedAt = raw.toDate();
    final personal = (map['personal'] as Map?) ?? const {};
    final health = (map['health'] as Map?) ?? const {};
    final goals = (map['goals'] as Map?) ?? const {};
    final level = (map['level'] as Map?) ?? const {};
    final lifestyle = (map['lifestyle'] as Map?) ?? const {};
    final equipment = (map['equipment'] as Map?) ?? const {};
    final motivation = (map['motivation'] as Map?) ?? const {};
    return UserProfile(
      uid: uid,
      personal: PersonalInfo(
        age: personal['age'] as int?,
        gender: _enumByName(Gender.values, personal['gender']),
        heightCm: personal['heightCm'] as int?,
        weightCurrentKg: (personal['weightCurrentKg'] as num?)?.toDouble(),
        weightTargetKg: (personal['weightTargetKg'] as num?)?.toDouble(),
        activityLevel:
            _enumByName(ActivityLevel.values, personal['activityLevel']),
      ),
      // One reader for this block, on the model. The inlined copy that used to
      // live here was the second implementation of a shape that also had a map
      // literal in `UserProfile.toJson` -- the drift `Injury.fromJson` was
      // extracted to stop, repeated one level up. The local store that keeps
      // this block off the server needs the same reader, which is what forced
      // the issue.
      //
      // Documents written before H1a still carry a populated `health` here,
      // and are still parsed. H1b is what empties them.
      health: HealthHistory.fromJson(Map<String, dynamic>.from(health)),
      goals: FitnessGoals(
        weightLoss: goals['weightLoss'] ?? false,
        muscleGain: goals['muscleGain'] ?? false,
        endurance: goals['endurance'] ?? false,
        strength: goals['strength'] ?? false,
        flexibility: goals['flexibility'] ?? false,
        generalFitness: goals['generalFitness'] ?? false,
        specificSport: goals['specificSport'] as String?,
      ),
      level: FitnessLevel(
        frequencyPerWeek: level['frequencyPerWeek'] as int?,
        currentExercises:
            List<String>.from(level['currentExercises'] ?? const []),
        tier: _enumByName(FitnessTier.values, level['tier']),
        basics: _enumByName(BasicExerciseAbility.values, level['basics']),
      ),
      lifestyle: Lifestyle(
        diet: ((lifestyle['diet'] as List?) ?? const [])
            .map((d) => _enumByName(DietaryPreference.values, d))
            .whereType<DietaryPreference>()
            .toList(),
        smoking: _enumByName(SmokingHabit.values, lifestyle['smoking']),
        alcohol: _enumByName(AlcoholHabit.values, lifestyle['alcohol']),
        sleepHoursPerNight: lifestyle['sleepHoursPerNight'] as int?,
        stressLevel: lifestyle['stressLevel'] as int?,
        occupation:
            _enumByName(OccupationActivity.values, lifestyle['occupation']),
      ),
      equipment: EquipmentAccess(
        hasGymAccess: equipment['hasGymAccess'] as bool?,
        homeEquipment:
            List<String>.from(equipment['homeEquipment'] ?? const []),
      ),
      motivation: MotivationPrefs(
        motivation: motivation['motivation'] as String?,
        environments: ((motivation['environments'] as List?) ?? const [])
            .map((e) => _enumByName(WorkoutEnvironment.values, e))
            .whereType<WorkoutEnvironment>()
            .toList(),
        preferredDuration: _enumByName(
            WorkoutDuration.values, motivation['preferredDuration']),
      ),
      completedAt: completedAt,
    );
  }

  @override
  Stream<UserProfile?> watch(String uid) =>
      _doc(uid).snapshots().map((snap) {
        if (!snap.exists) {
          _cache.remove(uid);
          return null;
        }
        final data = snap.data();
        if (data == null) return null;
        final p = _fromMap(uid, data);
        _cache[uid] = p;
        return p;
      });

  @override
  UserProfile? cached(String uid) => _cache[uid];

  @override
  Future<UserProfile?> load(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    final p = _fromMap(uid, snap.data()!);
    _cache[uid] = p;
    return p;
  }

  @override
  Future<void> save(UserProfile profile) async {
    // profile.toJson() -- the single serializer, per the same reasoning that
    // already applies to Injury.toJson(). This used to be a private inline
    // map (`_toMap`) and that shape's only copy; the data-export feature
    // (L0c) needed the same JSON with no Firestore connection to build it
    // from, which is what moved it onto the model.
    await _doc(profile.uid).set(profile.toJson(), SetOptions(merge: true));
    _cache[profile.uid] = profile;
  }

  @override
  Future<void> delete(String uid) async {
    await _doc(uid).delete();
    _cache.remove(uid);
  }
}
