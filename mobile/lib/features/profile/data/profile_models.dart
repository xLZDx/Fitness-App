// Domain model for the 34-question onboarding questionnaire. Each section
// of the questionnaire maps to one nested object on [UserProfile]. Every
// field is nullable / has a default so a half-completed draft is valid.

// The ONE import this file carries, and only for `FitnessGoals.primary`. The
// direction is profile -> programmes and stays that way: `programme.dart` pulls
// in equipment and workout models, neither of which reaches back here, so there
// is no cycle to reason about. Checked before adding, not assumed.
import '../../programmes/data/programme.dart' show ProgrammeGoal;

// The second import, added in Gate M for `HealthHistory.screening`. Same check
// as above: `safety/data/par_q.dart` imports nothing at all, so the direction
// profile -> safety cannot become a cycle. The answers live on the profile
// rather than in their own store because they are exactly the kind of data
// `SensitiveProfile` exists to keep off the server, and a second store would
// have needed the same treatment written twice.
import '../../safety/data/health_flags.dart';
import '../../safety/data/par_q.dart' show ParQQuestion;

enum Gender { male, female, nonBinary, preferNotToSay }

enum ActivityLevel { sedentary, moderatelyActive, active, veryActive }

enum BloodPressure { low, normal, high }

/// Self-rated training experience.
///
/// `never` is FIRST so the declaration order reads as increasing — anything
/// that sorts or indexes these values gets the right answer for free, and a
/// reader does not have to check whether the list is ordered before trusting
/// it. It was added in O3: the design's first screen offers "никогда не
/// тренировался" as a distinct answer, and folding it into `beginner` would
/// throw away the one distinction that changes what a first programme should
/// look like.
enum FitnessTier { never, beginner, intermediate, advanced }

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

/// The closed set of body regions an exercise can be screened against.
///
/// ## Why a closed set at all
///
/// `bodyPart` was free text, typed into one comma-and-colon-delimited field
/// (`step_health.dart:64-82`), so the same knee arrived as "knee", "Knee
/// (right)", "левое колено" and "kneee". `_injuryHits` compensated with
/// symmetric substring matching, which is a guess that gets more expensive as
/// the catalog gets tagged: it will happily match "back" against "lower_back"
/// and, given the wrong pair, "hip" against "ship".
///
/// The tag vocabulary S3b is about to write onto 1,887 exercises has to be
/// finite and has to be the same on both sides. This is that vocabulary, named
/// once, on the side that already exists.
///
/// Nine regions. Not a taxonomy of every injury a person can have — a taxonomy
/// of what an exercise tag can usefully say. Anything that does not fit stays
/// as [Injury.note] and is never matched, which is honest: a rib injury that
/// silently matched "core" would be worse than one the app admits it cannot
/// screen for.
///
/// [upperBack] was the ninth, added for the redesign's body diagram, which
/// offers it as its own zone. It is deliberately NOT merged into [neck]: the
/// two carry different contraindications (an overhead press is a neck
/// question, a bent-over row is a thoracic one), and merging them would make
/// the filter answer one while claiming to have answered both.
///
/// It shipped with **zero** tagged exercises and screened nothing for as long
/// as that lasted — safe by construction rather than by luck, because
/// `CatalogSafetyCoverage.coversAllOf`
/// (`equipment/state/safety_coverage_providers.dart:58-61`) refuses to claim
/// screening for any region with no tags, so the user saw the disclosure
/// instead of a promise. P3 ran that batch: 207 exercises now carry
/// `upper_back` (11.0% of the catalog, between `wrist` at 188 and `ankle` at
/// 229), from rules in `scripts/catalog/tag_contraindications.py` with the
/// per-row evidence in `core/contraindications/upper_back.csv`. The zero was
/// invisible for three months because the tagger's guard only ran one way —
/// see `test_every_legal_region_has_rules`, which is the guard that now runs
/// the other.
///
/// Declared in anatomical order, top-down: [InjuryRegion.values] is what the
/// pickers iterate. Nothing serialises the index — [Injury.fromJson] matches
/// on `name` — so inserting in the middle is safe for stored profiles.
enum InjuryRegion {
  neck,
  upperBack,
  shoulder,
  elbow,
  wrist,
  lowerBack,
  hip,
  knee,
  ankle,
}

extension InjuryRegionTag on InjuryRegion {
  /// The token an exercise's `contraindications` entry must carry to conflict
  /// with this region. `lowerBack` -> `lower_back`, matching what
  /// `_normaliseTag` produces from "lower back".
  String get tag {
    switch (this) {
      case InjuryRegion.lowerBack:
        return 'lower_back';
      case InjuryRegion.neck:
        return 'neck';
      case InjuryRegion.upperBack:
        return 'upper_back';
      case InjuryRegion.shoulder:
        return 'shoulder';
      case InjuryRegion.elbow:
        return 'elbow';
      case InjuryRegion.wrist:
        return 'wrist';
      case InjuryRegion.hip:
        return 'hip';
      case InjuryRegion.knee:
        return 'knee';
      case InjuryRegion.ankle:
        return 'ankle';
    }
  }
}

class Injury {
  const Injury({
    required this.bodyPart,
    required this.type,
    this.region,
    this.note,
    this.confirmed = false,
  });

  /// What the user originally typed. Never overwritten — S1b migrates stored
  /// data by *adding* [region] beside this, not by replacing it, so a mapping
  /// that turns out wrong can still be undone from the original words.
  final String bodyPart;

  final String type;

  /// The screened region, or null when nothing has mapped it yet.
  final InjuryRegion? region;

  /// Free text the user wants recorded. **Never matched against anything.**
  /// It exists so "rib, hurts on rotation" has somewhere to live that does not
  /// pretend to be screenable.
  final String? note;

  /// True only once the user has explicitly said no region fits.
  ///
  /// Without this, an injury that structurally cannot map — rib, jaw, groin,
  /// none of the eight — is indistinguishable on every future load from one
  /// nobody has looked at yet, so the app would ask about it forever.
  /// `region == null && !confirmed` is the only state that means "still needs
  /// a human".
  final bool confirmed;

  /// True when this injury has been resolved one way or the other.
  bool get isResolved => region != null || confirmed;

  Injury copyWith({
    String? bodyPart,
    String? type,
    InjuryRegion? region,
    String? note,
    bool? confirmed,
    bool clearRegion = false,
  }) =>
      Injury(
        bodyPart: bodyPart ?? this.bodyPart,
        type: type ?? this.type,
        region: clearRegion ? null : (region ?? this.region),
        note: note ?? this.note,
        confirmed: confirmed ?? this.confirmed,
      );

  /// The single (de)serializer.
  ///
  /// These used to be dead code with zero production callers, while
  /// `firestore_profile_repository.dart` carried a second, hand-inlined
  /// implementation that cast `e['bodyPart']` straight into a required
  /// `String`. Two implementations of one shape drift, and the drift only
  /// surfaces on a document written by the other one. The repository calls
  /// these now.
  Map<String, dynamic> toJson() => {
        'bodyPart': bodyPart,
        'type': type,
        if (region != null) 'region': region!.name,
        if (note != null) 'note': note,
        if (confirmed) 'confirmed': true,
      };

  /// Reads both shapes without a version field.
  ///
  /// The old shape simply has no `region`/`confirmed` keys, so absence *is*
  /// the discriminator — the same structural-migration trick `completedAt`
  /// already uses in the repository (`if (raw is String) ... if (raw is
  /// Timestamp) ...`). A version number would have to be written by a
  /// migration that has not run, on documents that already exist.
  static Injury fromJson(Map<String, dynamic> j) => Injury(
        bodyPart: j['bodyPart'] as String? ?? '',
        type: j['type'] as String? ?? '',
        region: _regionByName(j['region']),
        note: j['note'] as String?,
        confirmed: j['confirmed'] == true,
      );

  static InjuryRegion? _regionByName(dynamic name) {
    if (name is! String) return null;
    for (final r in InjuryRegion.values) {
      if (r.name == name) return r;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Injury &&
          other.bodyPart == bodyPart &&
          other.type == type &&
          other.region == region &&
          other.note == note &&
          other.confirmed == confirmed;

  @override
  int get hashCode => Object.hash(bodyPart, type, region, note, confirmed);
}

class PersonalInfo {
  const PersonalInfo({
    int? age,
    this.birthYear,
    this.gender,
    this.heightCm,
    this.weightCurrentKg,
    this.weightTargetKg,
    this.activityLevel,
  }) : _storedAge = age;

  /// O8. The answer the screen now asks for.
  ///
  /// An age is a fact with a shelf life: stored once, it is wrong within a year
  /// and silently wrong thereafter, and nothing in the app would ever notice. A
  /// birth year does not go stale.
  final int? birthYear;

  /// The age written by a version of the app that predates [birthYear].
  ///
  /// Private and read only when [birthYear] is null, on the same principle as
  /// `EquipmentAccess._storedGymAccess`: dropping it would have silently
  /// un-answered the question for every existing profile, with nothing going
  /// red.
  final int? _storedAge;

  final Gender? gender;
  final int? heightCm;
  final double? weightCurrentKg;
  final double? weightTargetKg;
  final ActivityLevel? activityLevel;

  static const empty = PersonalInfo();

  /// Age in whole years as of [year], or the stored age for a profile that
  /// predates [birthYear].
  ///
  /// Takes the year rather than reading the clock so the arithmetic can be
  /// asserted without the answer changing on 1 January.
  ///
  /// **Accurate to ±1 year and the screen says so.** The month of birth has
  /// never been asked, here or in any earlier version, so someone born in
  /// December reads a year older than they are until their birthday. Rounding
  /// that away silently would be a worse answer than admitting it.
  int? ageAt(int year) => birthYear == null ? _storedAge : year - birthYear!;

  int? get age => ageAt(DateTime.now().year);

  bool get isComplete =>
      age != null &&
      gender != null &&
      heightCm != null &&
      weightCurrentKg != null &&
      activityLevel != null;

  PersonalInfo copyWith({
    int? age,
    int? birthYear,
    Gender? gender,
    int? heightCm,
    double? weightCurrentKg,
    double? weightTargetKg,
    ActivityLevel? activityLevel,
  }) =>
      PersonalInfo(
        // `_storedAge`, not `age`: the getter would hand back the DERIVED age
        // and freeze it as a stored one, so an unrelated edit years later would
        // quietly turn a birth year into a stale number.
        age: age ?? _storedAge,
        birthYear: birthYear ?? this.birthYear,
        gender: gender ?? this.gender,
        heightCm: heightCm ?? this.heightCm,
        weightCurrentKg: weightCurrentKg ?? this.weightCurrentKg,
        weightTargetKg: weightTargetKg ?? this.weightTargetKg,
        activityLevel: activityLevel ?? this.activityLevel,
      );
}

/// Resolves an enum value from its `name`, or null for anything else.
///
/// Generic where [Injury._regionByName] is not, because that one predates it
/// and is reachable only from `Injury`. New readers use this; the older one is
/// left alone rather than churned inside an unrelated gate.
T? _enumByNameOrNull<T extends Enum>(List<T> values, dynamic name) {
  if (name is! String) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
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
    this.screening = const {},
    this.flags = HealthFlags.empty,
  });

  final List<String> conditions;
  final List<String> allergies;
  final List<String> medications;
  final List<Injury> injuries;
  final List<String> physicalLimitations;
  final List<String> recentSurgeries;
  final BloodPressure? bloodPressure;
  final String? otherConcerns;

  /// PAR-Q+ answers, by question. A question with no entry is UNANSWERED, and
  /// `screen()` treats that as blocking — see `par_q.dart`. Do not "fix" a
  /// missing key by defaulting it to false anywhere; that is the one change
  /// that turns the screen back into decoration.
  final Map<ParQQuestion, bool> screening;

  /// The normalised half — the only part any rule is allowed to read.
  ///
  /// Gate N. The seven free-text fields above stay exactly as the user typed
  /// them, for their own reference and for a clinician they may show them to,
  /// and nothing interprets them. See `health_flags.dart` for why parsing them
  /// was rejected rather than merely deferred.
  final HealthFlags flags;

  static const empty = HealthHistory();

  /// How much of this block is in a form rules can act on.
  ///
  /// Computed rather than stored: a stored flag can disagree with the data it
  /// describes, and the disagreement would be invisible.
  ///
  /// `legacyUnreviewed` is the state that matters. It means free text exists
  /// from before the normalised questions did, and the user has not answered
  /// them — so the app holds health information it must not read and has none
  /// it may. Treated conservatively by the eligibility layer and surfaced as a
  /// prompt to re-answer, never as a guess at what the text meant.
  HealthNormalisationState get normalisation {
    if (!flags.isUnanswered) return HealthNormalisationState.normalised;
    final hasFreeText = conditions.isNotEmpty ||
        medications.isNotEmpty ||
        physicalLimitations.isNotEmpty ||
        recentSurgeries.isNotEmpty ||
        bloodPressure != null ||
        (otherConcerns?.isNotEmpty ?? false);
    return hasFreeText
        ? HealthNormalisationState.legacyUnreviewed
        : HealthNormalisationState.notProvided;
  }

  /// The single (de)serializer for this block, for the same reason
  /// [Injury.toJson] is: the shape had two implementations — the map literal
  /// inside [UserProfile.toJson] and the hand-inlined reader in
  /// `FirestoreProfileRepository._fromMap` — and two implementations of one
  /// shape drift. Both call these now, and so does the local store that keeps
  /// this block off the server.
  Map<String, dynamic> toJson() => {
        'conditions': conditions,
        'allergies': allergies,
        'medications': medications,
        'injuries': injuries.map((i) => i.toJson()).toList(),
        'physicalLimitations': physicalLimitations,
        'recentSurgeries': recentSurgeries,
        'bloodPressure': bloodPressure?.name,
        'otherConcerns': otherConcerns,
        'screening': {
          for (final e in screening.entries) e.key.name: e.value,
        },
        'flags': flags.toJson(),
      };

  /// Tolerant by design: a document written before a field existed, or by
  /// hand, must degrade to the empty value rather than throw. The reader this
  /// replaces used to cast straight into required Strings and did throw.
  static HealthHistory fromJson(Map<String, dynamic> j) => HealthHistory(
        conditions: List<String>.from(j['conditions'] ?? const []),
        allergies: List<String>.from(j['allergies'] ?? const []),
        medications: List<String>.from(j['medications'] ?? const []),
        injuries: ((j['injuries'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Injury.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        physicalLimitations:
            List<String>.from(j['physicalLimitations'] ?? const []),
        recentSurgeries: List<String>.from(j['recentSurgeries'] ?? const []),
        bloodPressure: _enumByNameOrNull(BloodPressure.values, j['bloodPressure']),
        otherConcerns: j['otherConcerns'] as String?,
        screening: _readScreening(j['screening']),
        flags: HealthFlags.fromJson(j['flags']),
      );

  /// Unknown keys and non-bool values are DROPPED, not coerced.
  ///
  /// A question this build does not know about cannot be answered by this
  /// build, and a value that is not a bool is not an answer. Both cases come
  /// back as "unanswered", which blocks — the tolerant direction everywhere
  /// else in this reader is the unsafe direction here.
  static Map<ParQQuestion, bool> _readScreening(Object? raw) {
    if (raw is! Map) return const {};
    final out = <ParQQuestion, bool>{};
    for (final entry in raw.entries) {
      final q = _enumByNameOrNull(ParQQuestion.values, entry.key);
      final v = entry.value;
      if (q != null && v is bool) out[q] = v;
    }
    return Map.unmodifiable(out);
  }

  /// True when nothing was ever answered. Used to decide whether a locally
  /// stored block should win over whatever the server still holds.
  bool get isEmpty =>
      conditions.isEmpty &&
      allergies.isEmpty &&
      medications.isEmpty &&
      injuries.isEmpty &&
      physicalLimitations.isEmpty &&
      recentSurgeries.isEmpty &&
      bloodPressure == null &&
      (otherConcerns == null || otherConcerns!.isEmpty) &&
      screening.isEmpty &&
      flags == HealthFlags.empty;

  HealthHistory copyWith({
    List<String>? conditions,
    List<String>? allergies,
    List<String>? medications,
    List<Injury>? injuries,
    List<String>? physicalLimitations,
    List<String>? recentSurgeries,
    BloodPressure? bloodPressure,
    String? otherConcerns,
    Map<ParQQuestion, bool>? screening,
    HealthFlags? flags,
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
        screening: screening ?? this.screening,
        flags: flags ?? this.flags,
      );
}

class FitnessGoals {
  const FitnessGoals({
    this.primary,
    this.weightLoss = false,
    this.muscleGain = false,
    this.endurance = false,
    this.strength = false,
    this.flexibility = false,
    this.generalFitness = false,
    this.specificSport,
    this.focusZones = const [],
  });

  /// The ONE goal the user picked first, in the programme layer's own
  /// vocabulary.
  ///
  /// Deliberately not derived from the booleans below, and they are
  /// deliberately not derived from it. The design's first screen asks "what is
  /// your main goal" and takes a single answer; the older multi-select asks
  /// what else interests you. "I mainly want strength, and I would also like
  /// to lose some weight" is a normal answer, and collapsing it either way
  /// loses information the plan generator will want.
  ///
  /// Typed as [ProgrammeGoal] rather than a private onboarding enum so the
  /// answer is usable for programme selection without a translation table —
  /// see that enum's own doc for why a second vocabulary was rejected.
  final ProgrammeGoal? primary;

  final bool weightLoss;
  final bool muscleGain;
  final bool endurance;
  final bool strength;
  final bool flexibility;
  final bool generalFitness;
  final String? specificSport;

  /// O6. The body areas the user wants prioritised, as a closed set.
  ///
  /// Lives beside the goals rather than in its own model because it answers the
  /// same question at a finer grain — "what am I training for" — and every
  /// reader that wants one will want the other.
  final List<FocusZone> focusZones;

  static const empty = FitnessGoals();

  bool get hasAny =>
      primary != null ||
      focusZones.isNotEmpty ||
      weightLoss ||
      muscleGain ||
      endurance ||
      strength ||
      flexibility ||
      generalFitness ||
      (specificSport != null && specificSport!.isNotEmpty);

  FitnessGoals copyWith({
    ProgrammeGoal? primary,
    bool? weightLoss,
    bool? muscleGain,
    bool? endurance,
    bool? strength,
    bool? flexibility,
    bool? generalFitness,
    String? specificSport,
    List<FocusZone>? focusZones,
  }) =>
      FitnessGoals(
        focusZones: focusZones ?? this.focusZones,
        primary: primary ?? this.primary,
        weightLoss: weightLoss ?? this.weightLoss,
        muscleGain: muscleGain ?? this.muscleGain,
        endurance: endurance ?? this.endurance,
        strength: strength ?? this.strength,
        flexibility: flexibility ?? this.flexibility,
        generalFitness: generalFitness ?? this.generalFitness,
        specificSport: specificSport ?? this.specificSport,
      );
}

/// O6 — what the user wants worked on.
///
/// Deliberately NOT [InjuryRegion]. That enum answers "what must be avoided";
/// this one answers "what to prioritise", and the two vocabularies genuinely
/// differ: priorities have `core` and `fullBody`, limitations have `wrist` and
/// `ankle`. Merging them would produce one enum in which half the values are
/// meaningless from either side, and a picker that offers "train your wrist".
enum FocusZone { chest, back, shoulders, arms, core, glutes, legs, fullBody }

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

/// Where the training happens.
///
/// `mixed` is not a hedge — "gym on weekdays, home at the weekend" is the
/// commonest real answer, and forcing it into one of the other three would make
/// every plan wrong half the week.
enum TrainingLocation { gym, home, outdoor, mixed }

/// What is available to train with, as a closed set the exercise filter can
/// actually match against.
///
/// `cameraScan` is the odd one out and stays anyway: on screen it is another
/// chip ("я распознаю оборудование камерой"), but it describes an intention,
/// not a piece of equipment. Anything selecting exercises must ignore it —
/// treating it as kit would let the filter offer a machine nobody has.
enum EquipmentKind {
  fullGym,
  machines,
  dumbbells,
  barbell,
  kettlebells,
  bands,
  bodyweight,
  cameraScan,
}

class EquipmentAccess {
  const EquipmentAccess({
    this.location,
    this.available = const [],
    bool? hasGymAccess,
    this.homeEquipment = const [],
  }) : _storedGymAccess = hasGymAccess;

  /// O4. The answer the design's screen 2 actually asks for.
  final TrainingLocation? location;

  /// O4. The equipment chips, as a closed set.
  final List<EquipmentKind> available;

  /// Free text for everything the closed set above cannot hold.
  ///
  /// Kept rather than replaced, on the same principle as `Injury.note`: what
  /// does not fit a category is stored and left out of matching, which is
  /// honest, instead of being forced into the nearest category, which is not.
  final List<String> homeEquipment;

  /// What was written into Firestore before [location] existed.
  ///
  /// Private, and read only when [location] is null. Profiles created before O4
  /// carry this and nothing else; dropping it would have silently un-answered
  /// the equipment question for every existing user, and nothing would have
  /// gone red — `hasGymAccess` would simply have started returning null.
  final bool? _storedGymAccess;

  /// Derived from [location] when there is one, else the stored legacy answer.
  ///
  /// A getter rather than a field so the two can never disagree. Existing
  /// readers (`step_answered.dart`, the exercise filter) did not have to change.
  bool? get hasGymAccess => switch (location) {
        TrainingLocation.gym || TrainingLocation.mixed => true,
        TrainingLocation.home || TrainingLocation.outdoor => false,
        null => _storedGymAccess,
      };

  static const empty = EquipmentAccess();

  EquipmentAccess copyWith({
    TrainingLocation? location,
    List<EquipmentKind>? available,
    bool? hasGymAccess,
    List<String>? homeEquipment,
  }) =>
      EquipmentAccess(
        location: location ?? this.location,
        available: available ?? this.available,
        hasGymAccess: hasGymAccess ?? _storedGymAccess,
        homeEquipment: homeEquipment ?? this.homeEquipment,
      );
}

/// O5 — how often, how long, and on which days the user PLANS to train.
///
/// Deliberately not folded into [FitnessLevel.frequencyPerWeek]. That field
/// records how much the person trains *today*; this one records what they are
/// signing up for. Merging them reads as tidier and destroys the only baseline
/// a plan generator could measure a ramp against — after the merge there is no
/// way to tell "trains twice a week, wants four" from "trains four already".
class TrainingSchedule {
  const TrainingSchedule({
    this.daysPerWeek,
    this.sessionMinutes,
    this.preferredWeekdays = const [],
  });

  /// 2..6 on screen. Not validated here: the questionnaire is the only writer
  /// and every answer in it is optional, so a range check in the model would
  /// only be able to throw on data that already exists in Firestore.
  final int? daysPerWeek;

  /// Exact minutes (30/45/60/75/90), not a bucket.
  ///
  /// The bucket ([WorkoutDuration]) cannot express 45 minutes — `m30to45` and
  /// `m45to60` both contain it — which is why the answer is stored in minutes
  /// and the bucket is derived from it, rather than the other way round.
  final int? sessionMinutes;

  /// `DateTime.monday` .. `DateTime.sunday`.
  final List<int> preferredWeekdays;

  static const empty = TrainingSchedule();

  /// [sessionMinutes] expressed in the coarse buckets the rest of the app
  /// already reads (`suggestion_builder.dart:135`).
  ///
  /// Boundaries are inclusive at the top of each bucket, so a 45-minute answer
  /// lands in `m30to45` rather than `m45to60`: the buckets are named for what
  /// they contain, and 45 appears in both names.
  WorkoutDuration? get durationBucket => switch (sessionMinutes) {
        null => null,
        final m when m < 15 => WorkoutDuration.under15,
        final m when m <= 30 => WorkoutDuration.m15to30,
        final m when m <= 45 => WorkoutDuration.m30to45,
        final m when m <= 60 => WorkoutDuration.m45to60,
        _ => WorkoutDuration.over60,
      };

  TrainingSchedule copyWith({
    int? daysPerWeek,
    int? sessionMinutes,
    List<int>? preferredWeekdays,
  }) =>
      TrainingSchedule(
        daysPerWeek: daysPerWeek ?? this.daysPerWeek,
        sessionMinutes: sessionMinutes ?? this.sessionMinutes,
        preferredWeekdays: preferredWeekdays ?? this.preferredWeekdays,
      );
}

/// O7 — what gets in the way.
///
/// Replaces the free-text "what stops you" box with a closed set, because a
/// sentence cannot be acted on: "не знаю какие упражнения выбрать" and "не
/// понимаю как пользоваться тренажёрами" ask the app for two different things,
/// and neither is reachable from a `String`.
///
/// [none] is mutually exclusive with the rest, and is a real answer rather than
/// an empty selection — "nothing stops me" and "has not answered yet" mean
/// different things to anything that decides what to offer.
enum TrainingBarrier {
  exerciseChoice,
  machineUse,
  techniqueDoubt,
  time,
  consistency,
  discomfort,
  none,
}

class MotivationPrefs {
  const MotivationPrefs({
    this.motivation,
    this.environments = const [],
    this.preferredDuration,
    this.barriers = const [],
  });

  final String? motivation;
  final List<WorkoutEnvironment> environments;

  /// Derived from `TrainingSchedule.sessionMinutes` since O5 — see
  /// `QuestionnaireDraft.updateSchedule`. Still stored, because the readers of
  /// the coarse bucket predate the schedule and should not have to change.
  final WorkoutDuration? preferredDuration;

  /// O7. What the user says gets in their way, as a closed set.
  final List<TrainingBarrier> barriers;

  static const empty = MotivationPrefs();

  MotivationPrefs copyWith({
    String? motivation,
    List<WorkoutEnvironment>? environments,
    WorkoutDuration? preferredDuration,
    List<TrainingBarrier>? barriers,
  }) =>
      MotivationPrefs(
        motivation: motivation ?? this.motivation,
        environments: environments ?? this.environments,
        preferredDuration: preferredDuration ?? this.preferredDuration,
        barriers: barriers ?? this.barriers,
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
    this.schedule = TrainingSchedule.empty,
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
  final TrainingSchedule schedule;
  final MotivationPrefs motivation;

  /// Set when the user submits the questionnaire. `null` means draft only.
  final DateTime? completedAt;

  bool get hasCompletedOnboarding => completedAt != null;

  /// The single serializer. Moved out of `FirestoreProfileRepository._toMap`
  /// so the data-export feature (L0c) reads the same shape the repository
  /// writes, instead of a third hand-inlined copy of it — the exact drift
  /// `Injury`'s own serializer already fixed once, for the same reason.
  Map<String, dynamic> toJson() => {
        'completedAt': completedAt?.toIso8601String(),
        'personal': {
          'birthYear': personal.birthYear,
          // Written as the DERIVED age, deliberately, exactly as `hasGymAccess`
          // is: an export taken last month or a Cloud Function still reading
          // this key gets a true answer rather than a stale one.
          'age': personal.age,
          'gender': personal.gender?.name,
          'heightCm': personal.heightCm,
          'weightCurrentKg': personal.weightCurrentKg,
          'weightTargetKg': personal.weightTargetKg,
          'activityLevel': personal.activityLevel?.name,
        },
        'health': health.toJson(),
        'goals': {
          'primary': goals.primary?.name,
          'weightLoss': goals.weightLoss,
          'muscleGain': goals.muscleGain,
          'endurance': goals.endurance,
          'strength': goals.strength,
          'flexibility': goals.flexibility,
          'generalFitness': goals.generalFitness,
          'specificSport': goals.specificSport,
          'focusZones': goals.focusZones.map((z) => z.name).toList(),
        },
        'level': {
          'frequencyPerWeek': level.frequencyPerWeek,
          'currentExercises': level.currentExercises,
          'tier': level.tier?.name,
          'basics': level.basics?.name,
        },
        'lifestyle': {
          'diet': lifestyle.diet.map((d) => d.name).toList(),
          'smoking': lifestyle.smoking?.name,
          'alcohol': lifestyle.alcohol?.name,
          'sleepHoursPerNight': lifestyle.sleepHoursPerNight,
          'stressLevel': lifestyle.stressLevel,
          'occupation': lifestyle.occupation?.name,
        },
        'equipment': {
          'location': equipment.location?.name,
          'available': equipment.available.map((e) => e.name).toList(),
          // Written as the DERIVED value, deliberately. Anything still reading
          // this key — an export taken last month, a Cloud Function — keeps
          // getting a true answer instead of a stale one, and the field stays
          // readable by a version of the app that predates `location`.
          'hasGymAccess': equipment.hasGymAccess,
          'homeEquipment': equipment.homeEquipment,
        },
        'schedule': {
          'daysPerWeek': schedule.daysPerWeek,
          'sessionMinutes': schedule.sessionMinutes,
          'preferredWeekdays': schedule.preferredWeekdays,
        },
        'motivation': {
          'motivation': motivation.motivation,
          'environments': motivation.environments.map((e) => e.name).toList(),
          // Since O5 this is the bucket derived from `schedule.sessionMinutes`
          // (kept in step by `QuestionnaireDraft.updateSchedule`). It is still
          // written under its old key so readers that predate the schedule —
          // an export taken last month, `suggestion_builder.dart:135` — keep
          // getting an answer instead of a null.
          'preferredDuration': motivation.preferredDuration?.name,
          'barriers': motivation.barriers.map((b) => b.name).toList(),
        },
      };

  UserProfile copyWith({
    PersonalInfo? personal,
    HealthHistory? health,
    FitnessGoals? goals,
    FitnessLevel? level,
    Lifestyle? lifestyle,
    EquipmentAccess? equipment,
    TrainingSchedule? schedule,
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
        schedule: schedule ?? this.schedule,
        motivation: motivation ?? this.motivation,
        completedAt: completedAt ?? this.completedAt,
      );

  factory UserProfile.empty(String uid) => UserProfile(uid: uid);
}
