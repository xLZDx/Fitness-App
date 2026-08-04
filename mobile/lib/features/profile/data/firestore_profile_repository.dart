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

  Map<String, dynamic> _toMap(UserProfile p) => {
        'completedAt': p.completedAt?.toIso8601String(),
        'personal': {
          'age': p.personal.age,
          'gender': p.personal.gender?.name,
          'heightCm': p.personal.heightCm,
          'weightCurrentKg': p.personal.weightCurrentKg,
          'weightTargetKg': p.personal.weightTargetKg,
          'activityLevel': p.personal.activityLevel?.name,
        },
        'health': {
          'conditions': p.health.conditions,
          'allergies': p.health.allergies,
          'medications': p.health.medications,
          // Through Injury.toJson, not a second hand-inlined copy of the same
          // shape. The copy that used to be here did not know about `region`,
          // `note` or `confirmed`, which is exactly how a second serializer
          // fails: silently, on the fields added after it was written.
          'injuries': p.health.injuries.map((i) => i.toJson()).toList(),
          'physicalLimitations': p.health.physicalLimitations,
          'recentSurgeries': p.health.recentSurgeries,
          'bloodPressure': p.health.bloodPressure?.name,
          'otherConcerns': p.health.otherConcerns,
        },
        'goals': {
          'weightLoss': p.goals.weightLoss,
          'muscleGain': p.goals.muscleGain,
          'endurance': p.goals.endurance,
          'strength': p.goals.strength,
          'flexibility': p.goals.flexibility,
          'generalFitness': p.goals.generalFitness,
          'specificSport': p.goals.specificSport,
        },
        'level': {
          'frequencyPerWeek': p.level.frequencyPerWeek,
          'currentExercises': p.level.currentExercises,
          'tier': p.level.tier?.name,
          'basics': p.level.basics?.name,
        },
        'lifestyle': {
          'diet': p.lifestyle.diet.map((d) => d.name).toList(),
          'smoking': p.lifestyle.smoking?.name,
          'alcohol': p.lifestyle.alcohol?.name,
          'sleepHoursPerNight': p.lifestyle.sleepHoursPerNight,
          'stressLevel': p.lifestyle.stressLevel,
          'occupation': p.lifestyle.occupation?.name,
        },
        'equipment': {
          'hasGymAccess': p.equipment.hasGymAccess,
          'homeEquipment': p.equipment.homeEquipment,
        },
        'motivation': {
          'motivation': p.motivation.motivation,
          'environments':
              p.motivation.environments.map((e) => e.name).toList(),
          'preferredDuration': p.motivation.preferredDuration?.name,
        },
      };

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
      health: HealthHistory(
        conditions: List<String>.from(health['conditions'] ?? const []),
        allergies: List<String>.from(health['allergies'] ?? const []),
        medications: List<String>.from(health['medications'] ?? const []),
        // Same single implementation on the way back, and it no longer casts
        // straight into required Strings: a document written before this field
        // existed, or by a hand-edit, used to throw here rather than degrade.
        injuries: ((health['injuries'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Injury.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        physicalLimitations:
            List<String>.from(health['physicalLimitations'] ?? const []),
        recentSurgeries:
            List<String>.from(health['recentSurgeries'] ?? const []),
        bloodPressure:
            _enumByName(BloodPressure.values, health['bloodPressure']),
        otherConcerns: health['otherConcerns'] as String?,
      ),
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
    await _doc(profile.uid).set(_toMap(profile), SetOptions(merge: true));
    _cache[profile.uid] = profile;
  }

  @override
  Future<void> delete(String uid) async {
    await _doc(uid).delete();
    _cache.remove(uid);
  }
}
