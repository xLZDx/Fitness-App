// Domain model for the 34-question onboarding questionnaire. Each section
// of the questionnaire maps to one nested object on [UserProfile]. Every
// field is nullable / has a default so a half-completed draft is valid.

enum Gender { male, female, nonBinary, preferNotToSay }

enum ActivityLevel { sedentary, moderatelyActive, active, veryActive }

enum BloodPressure { low, normal, high }

enum FitnessTier { beginner, intermediate, advanced }

enum BasicExerciseAbility { yes, partial, no }

enum SmokingHabit { never, former, occasional, regular }

enum AlcoholHabit { none, light, moderate, heavy }

enum OccupationActivity { sedentary, lightlyActive, active, veryActive }

enum DietaryPreference {
  vegetarian,
  vegan,
  glutenFree,
  dairyFree,
  halal,
  kosher,
  none
}

enum WorkoutEnvironment {
  highIntensity,
  relaxed,
  groupClasses,
  oneOnOne,
  outdoor
}

enum WorkoutDuration { under15, m15to30, m30to45, m45to60, over60 }

class Injury {
  const Injury({required this.bodyPart, required this.type});
  final String bodyPart;
  final String type;

  Map<String, dynamic> toJson() => {'bodyPart': bodyPart, 'type': type};

  static Injury fromJson(Map<String, dynamic> j) => Injury(
        bodyPart: j['bodyPart'] as String,
        type: j['type'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Injury && other.bodyPart == bodyPart && other.type == type;

  @override
  int get hashCode => Object.hash(bodyPart, type);
}

class PersonalInfo {
  const PersonalInfo({
    this.age,
    this.gender,
    this.heightCm,
    this.weightCurrentKg,
    this.weightTargetKg,
    this.activityLevel,
  });

  final int? age;
  final Gender? gender;
  final int? heightCm;
  final double? weightCurrentKg;
  final double? weightTargetKg;
  final ActivityLevel? activityLevel;

  static const empty = PersonalInfo();

  bool get isComplete =>
      age != null &&
      gender != null &&
      heightCm != null &&
      weightCurrentKg != null &&
      activityLevel != null;

  PersonalInfo copyWith({
    int? age,
    Gender? gender,
    int? heightCm,
    double? weightCurrentKg,
    double? weightTargetKg,
    ActivityLevel? activityLevel,
  }) =>
      PersonalInfo(
        age: age ?? this.age,
        gender: gender ?? this.gender,
        heightCm: heightCm ?? this.heightCm,
        weightCurrentKg: weightCurrentKg ?? this.weightCurrentKg,
        weightTargetKg: weightTargetKg ?? this.weightTargetKg,
        activityLevel: activityLevel ?? this.activityLevel,
      );
}

class HealthHistory {
  const HealthHistory({
    this.conditions = const [],
    this.allergies = const [],
    this.medications = const [],
    this.injuries = const [],
    this.physicalLimitations = const [],
    this.recentSurgeries = const [],
    this.bloodPressure,
    this.otherConcerns,
  });

  final List<String> conditions;
  final List<String> allergies;
  final List<String> medications;
  final List<Injury> injuries;
  final List<String> physicalLimitations;
  final List<String> recentSurgeries;
  final BloodPressure? bloodPressure;
  final String? otherConcerns;

  static const empty = HealthHistory();

  HealthHistory copyWith({
    List<String>? conditions,
    List<String>? allergies,
    List<String>? medications,
    List<Injury>? injuries,
    List<String>? physicalLimitations,
    List<String>? recentSurgeries,
    BloodPressure? bloodPressure,
    String? otherConcerns,
  }) =>
      HealthHistory(
        conditions: conditions ?? this.conditions,
        allergies: allergies ?? this.allergies,
        medications: medications ?? this.medications,
        injuries: injuries ?? this.injuries,
        physicalLimitations: physicalLimitations ?? this.physicalLimitations,
        recentSurgeries: recentSurgeries ?? this.recentSurgeries,
        bloodPressure: bloodPressure ?? this.bloodPressure,
        otherConcerns: otherConcerns ?? this.otherConcerns,
      );
}

class FitnessGoals {
  const FitnessGoals({
    this.weightLoss = false,
    this.muscleGain = false,
    this.endurance = false,
    this.strength = false,
    this.flexibility = false,
    this.generalFitness = false,
    this.specificSport,
  });

  final bool weightLoss;
  final bool muscleGain;
  final bool endurance;
  final bool strength;
  final bool flexibility;
  final bool generalFitness;
  final String? specificSport;

  static const empty = FitnessGoals();

  bool get hasAny =>
      weightLoss ||
      muscleGain ||
      endurance ||
      strength ||
      flexibility ||
      generalFitness ||
      (specificSport != null && specificSport!.isNotEmpty);

  FitnessGoals copyWith({
    bool? weightLoss,
    bool? muscleGain,
    bool? endurance,
    bool? strength,
    bool? flexibility,
    bool? generalFitness,
    String? specificSport,
  }) =>
      FitnessGoals(
        weightLoss: weightLoss ?? this.weightLoss,
        muscleGain: muscleGain ?? this.muscleGain,
        endurance: endurance ?? this.endurance,
        strength: strength ?? this.strength,
        flexibility: flexibility ?? this.flexibility,
        generalFitness: generalFitness ?? this.generalFitness,
        specificSport: specificSport ?? this.specificSport,
      );
}

class FitnessLevel {
  const FitnessLevel({
    this.frequencyPerWeek,
    this.currentExercises = const [],
    this.tier,
    this.basics,
  });

  final int? frequencyPerWeek;
  final List<String> currentExercises;
  final FitnessTier? tier;
  final BasicExerciseAbility? basics;

  static const empty = FitnessLevel();

  FitnessLevel copyWith({
    int? frequencyPerWeek,
    List<String>? currentExercises,
    FitnessTier? tier,
    BasicExerciseAbility? basics,
  }) =>
      FitnessLevel(
        frequencyPerWeek: frequencyPerWeek ?? this.frequencyPerWeek,
        currentExercises: currentExercises ?? this.currentExercises,
        tier: tier ?? this.tier,
        basics: basics ?? this.basics,
      );
}

class Lifestyle {
  const Lifestyle({
    this.diet = const [],
    this.smoking,
    this.alcohol,
    this.sleepHoursPerNight,
    this.stressLevel,
    this.occupation,
  });

  final List<DietaryPreference> diet;
  final SmokingHabit? smoking;
  final AlcoholHabit? alcohol;
  final int? sleepHoursPerNight;
  final int? stressLevel; // 1–10
  final OccupationActivity? occupation;

  static const empty = Lifestyle();

  Lifestyle copyWith({
    List<DietaryPreference>? diet,
    SmokingHabit? smoking,
    AlcoholHabit? alcohol,
    int? sleepHoursPerNight,
    int? stressLevel,
    OccupationActivity? occupation,
  }) =>
      Lifestyle(
        diet: diet ?? this.diet,
        smoking: smoking ?? this.smoking,
        alcohol: alcohol ?? this.alcohol,
        sleepHoursPerNight: sleepHoursPerNight ?? this.sleepHoursPerNight,
        stressLevel: stressLevel ?? this.stressLevel,
        occupation: occupation ?? this.occupation,
      );
}

class EquipmentAccess {
  const EquipmentAccess({this.hasGymAccess, this.homeEquipment = const []});

  final bool? hasGymAccess;
  final List<String> homeEquipment;

  static const empty = EquipmentAccess();

  EquipmentAccess copyWith({
    bool? hasGymAccess,
    List<String>? homeEquipment,
  }) =>
      EquipmentAccess(
        hasGymAccess: hasGymAccess ?? this.hasGymAccess,
        homeEquipment: homeEquipment ?? this.homeEquipment,
      );
}

class MotivationPrefs {
  const MotivationPrefs({
    this.motivation,
    this.environments = const [],
    this.preferredDuration,
  });

  final String? motivation;
  final List<WorkoutEnvironment> environments;
  final WorkoutDuration? preferredDuration;

  static const empty = MotivationPrefs();

  MotivationPrefs copyWith({
    String? motivation,
    List<WorkoutEnvironment>? environments,
    WorkoutDuration? preferredDuration,
  }) =>
      MotivationPrefs(
        motivation: motivation ?? this.motivation,
        environments: environments ?? this.environments,
        preferredDuration: preferredDuration ?? this.preferredDuration,
      );
}

class UserProfile {
  const UserProfile({
    required this.uid,
    this.personal = PersonalInfo.empty,
    this.health = HealthHistory.empty,
    this.goals = FitnessGoals.empty,
    this.level = FitnessLevel.empty,
    this.lifestyle = Lifestyle.empty,
    this.equipment = EquipmentAccess.empty,
    this.motivation = MotivationPrefs.empty,
    this.completedAt,
  });

  final String uid;
  final PersonalInfo personal;
  final HealthHistory health;
  final FitnessGoals goals;
  final FitnessLevel level;
  final Lifestyle lifestyle;
  final EquipmentAccess equipment;
  final MotivationPrefs motivation;

  /// Set when the user submits the questionnaire. `null` means draft only.
  final DateTime? completedAt;

  bool get hasCompletedOnboarding => completedAt != null;

  UserProfile copyWith({
    PersonalInfo? personal,
    HealthHistory? health,
    FitnessGoals? goals,
    FitnessLevel? level,
    Lifestyle? lifestyle,
    EquipmentAccess? equipment,
    MotivationPrefs? motivation,
    DateTime? completedAt,
  }) =>
      UserProfile(
        uid: uid,
        personal: personal ?? this.personal,
        health: health ?? this.health,
        goals: goals ?? this.goals,
        level: level ?? this.level,
        lifestyle: lifestyle ?? this.lifestyle,
        equipment: equipment ?? this.equipment,
        motivation: motivation ?? this.motivation,
        completedAt: completedAt ?? this.completedAt,
      );

  factory UserProfile.empty(String uid) => UserProfile(uid: uid);
}
