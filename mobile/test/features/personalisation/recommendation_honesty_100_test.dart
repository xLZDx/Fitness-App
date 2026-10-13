// Honesty audit of questionnaire-driven recommendations, 100 deterministic
// SYNTHETIC profiles (no Firebase, no network, no clock, no unseeded random).
//
// Runs the REAL decision code on the real bundled catalogue (read from disk):
//   plan        = safetyContextFor + buildPlan          (ai_planner/plan_builder.dart)
//   suggestions = eligibleExercises + sortByTierFit + buildSuggestions (home feed)
//   programme   = programmeFromProfile + programmeSpecFor + buildProgramme (enroll)
//
// It is a RATCHET: violation counts are collected (never stopping at the first)
// and compared with the embedded baseline of today's behaviour. It fails when a
// count grows, when a distinct-output count shrinks, or when a questionnaire
// input that currently influences output goes dead. It does NOT assert that
// the current violations are acceptable.
//
// Optional env: HONESTY_CSV=<path> writes the full violation list (+ .dead.txt).
// The summary printed on every run shows the measured counts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';
import 'package:fitness_app/features/home/data/suggestion_builder.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/personalisation/data/recommendation_hints.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_schedule.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/age_policy.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';

// ---------------------------------------------------------------- BASELINE --
// Behaviour after WS6 part 1 (age policy, wired inputs, honest reasons).
// Lower is better; absent key == 0 and must stay 0 (INJURY_CONTRA,
// EQUIPMENT_LABEL, DIFFICULTY_ABOVE_LEVEL, BLOCKED_BUT_PLANNED,
// CEILING_NOT_APPLIED, NONDETERMINISTIC, PLAN_EXCEEDS_SESSION_LENGTH,
// MINOR/SENIOR_NO_CAUTION_PATH, AGE_*, SENIOR_NO_BALANCE_MOBILITY,
// ADULT_GOT_AGE_WARNING, REASON_*, UNSCREENABLE_INJURY_NOT_DISCLOSED,
// GOAL_*). Before WS6: PLAN_EXCEEDS_SESSION_LENGTH 9, MINOR_NO_CAUTION_PATH 20,
// REASON_FALSE_BUILDS_STRENGTH 89, SENIOR_NO_CAUTION_PATH 10,
// REASON_INJURY_COUNT_NOT_INJURY_ONLY 36, UNSCREENABLE_INJURY_NOT_DISCLOSED 6,
// EQUIPMENT_ID_UNCLAIMED 474, GOAL_MAXEFFORT_FOR_REHAB_OR_MOBILITY 37,
// GOAL_MOBILITY_MISSING 12, GOAL_CARDIO_MISSING 10.
//
// The one remaining rule is a CATALOGUE defect (equipmentId such as
// `bench_press` / `squat_rack` on exercises whose label says dumbbell or
// barbell). The baseline is EXACT (measured 402 at the last catalogue state):
// both growth and shrinkage fail, so a catalogue repair forces the maintainer
// to lower it. The recommendation logic works with the current field semantics.
const Map<String, int> _baselineViolations = {
  'EQUIPMENT_ID_UNCLAIMED': 402,
};
// Higher is better (distinct non-refused outputs across the 100 profiles).
const Map<String, int> _baselineMinDistinct = {
  'plan': 74,
  'suggestions': 37,
  'programme': 73,
};
// Inputs that legitimately do not change output (reasons: see the library doc
// of `recommendation_hints.dart`). A dead field not listed here is a regression.
// `motivation.preferredDuration` is listed because every catalogue exercise has
// the same duration (10 min), so a duration preference cannot discriminate
// between exercises; session length is enforced via `schedule.sessionMinutes`.
const Set<String> _baselineDeadFields = {
  'equipment.gymId',
  'equipment.homeEquipment(text)',
  'goals.specificSport',
  'health.allergies(text)',
  'health.bloodPressure(legacy chip)',
  'health.conditions(text)',
  'health.medications(text)',
  'health.otherConcerns(text)',
  'health.physicalLimitations(text)',
  'health.recentSurgeries(text)',
  'level.currentExercises',
  'lifestyle.alcohol',
  'lifestyle.diet',
  'lifestyle.occupation',
  'lifestyle.smoking',
  'motivation.barriers',
  'motivation.environments',
  'motivation.motivation(text)',
  'motivation.preferredDuration',
  'personal.gender',
  'personal.heightCm',
  'personal.weightCurrentKg',
  'personal.weightTargetKg',
};

// ---------------------------------------------------------------- GENERATOR --
class _Lcg {
  _Lcg(this.s);
  int s;
  int next(int n) {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return (s >> 8) % n;
  }

  bool chance(int pct) => next(100) < pct;
  T pick<T>(List<T> l) => l[next(l.length)];
}

const _kNow = 2026;
final _kNowDate = DateTime(2026, 10, 13);
const _noDeload = DeloadVerdict(
    shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0);

Map<ParQQuestion, bool> _allNo() =>
    {for (final q in ParQQuestion.values) q: false};

const _restrictingQs = [
  ParQQuestion.heartConditionOrHighBloodPressure,
  ParQQuestion.dizzinessOrLossOfConsciousness,
  ParQQuestion.otherChronicCondition,
  ParQQuestion.prescribedMedication,
  ParQQuestion.musculoskeletalProblem,
];

Injury _inj(InjuryRegion r) =>
    Injury(bodyPart: r.name, type: 'strain', region: r);

List<Injury> _injurySet(int k) {
  switch (k) {
    case 3:
      return [_inj(InjuryRegion.knee)];
    case 4:
      return [_inj(InjuryRegion.lowerBack)];
    case 5:
      return [_inj(InjuryRegion.shoulder)];
    case 6:
      return [_inj(InjuryRegion.wrist)];
    case 7:
      return [_inj(InjuryRegion.hip)];
    case 8:
      return [_inj(InjuryRegion.ankle)];
    case 9:
      return [_inj(InjuryRegion.neck)];
    case 10:
      return [_inj(InjuryRegion.elbow)];
    case 11:
      return [_inj(InjuryRegion.upperBack)];
    case 12:
      return [_inj(InjuryRegion.knee), _inj(InjuryRegion.shoulder)];
    case 13:
      return [const Injury(bodyPart: 'Left knee', type: 'sprain')];
    case 14:
      return [
        const Injury(bodyPart: 'rib', type: 'bruise', confirmed: true)
      ];
    default:
      return const [];
  }
}

FitnessGoals _goals(int arche, _Lcg r) {
  final zones = <FocusZone>[
    if (arche != 7 && r.chance(40)) r.pick(FocusZone.values),
    if (arche == 7) ...[FocusZone.legs, FocusZone.core],
  ];
  switch (arche) {
    case 0:
      return FitnessGoals(
          primary: ProgrammeGoal.weightLoss, weightLoss: true, focusZones: zones);
    case 1:
      return FitnessGoals(
          primary: ProgrammeGoal.muscle, muscleGain: true, focusZones: zones);
    case 2:
      return FitnessGoals(
          primary: ProgrammeGoal.strength, strength: true, focusZones: zones);
    case 3:
      return FitnessGoals(
          primary: ProgrammeGoal.endurance, endurance: true, focusZones: zones);
    case 4:
      return FitnessGoals(
          primary: ProgrammeGoal.comeback,
          generalFitness: true,
          focusZones: zones);
    case 5:
      return FitnessGoals(
          primary: ProgrammeGoal.form, flexibility: true, focusZones: zones);
    case 6:
      return FitnessGoals(
          primary: ProgrammeGoal.form, generalFitness: true, focusZones: zones);
    default:
      return FitnessGoals(
          primary: ProgrammeGoal.strength,
          strength: true,
          weightLoss: true,
          muscleGain: true,
          focusZones: zones);
  }
}

EquipmentAccess _equip(int k) {
  switch (k) {
    case 0:
      return const EquipmentAccess(location: TrainingLocation.home);
    case 1:
      return const EquipmentAccess(location: TrainingLocation.home, available: [
        EquipmentKind.bands,
        EquipmentKind.dumbbells,
        EquipmentKind.cameraScan
      ]);
    case 2:
      return const EquipmentAccess(
          location: TrainingLocation.home,
          available: [EquipmentKind.dumbbells]);
    case 3:
      return const EquipmentAccess(location: TrainingLocation.gym);
    case 4:
      return const EquipmentAccess(location: TrainingLocation.outdoor);
    case 5:
      return const EquipmentAccess(location: TrainingLocation.mixed);
    case 6:
      return const EquipmentAccess(location: TrainingLocation.home, available: [
        EquipmentKind.kettlebells,
        EquipmentKind.barbell
      ]);
    default:
      return const EquipmentAccess();
  }
}

UserProfile _gen(int i) {
  final r = _Lcg(7919 * i + 13);
  const ages = [15, 17, 22, 30, 41, 55, 67, 78];
  final age = ages[(i * 3 + i ~/ 8) % 8];
  final arche = i % 8;
  final roll = r.next(100);
  var screening = _allNo();
  if (roll >= 62 && roll < 80) {
    screening[r.pick(_restrictingQs)] = true;
  } else if (roll >= 80 && roll < 88) {
    screening[r.chance(50)
        ? ParQQuestion.chestPain
        : ParQQuestion.medicallySupervisedOnly] = true;
  } else if (roll >= 88 && roll < 94) {
    screening.remove(ParQQuestion.values[r.next(ParQQuestion.values.length)]);
  } else if (roll >= 94) {
    screening[_restrictingQs[0]] = true;
    screening[_restrictingQs[4]] = true;
  }
  final restrictions = <MovementRestriction>{
    if (r.chance(30)) r.pick(MovementRestriction.values),
    if (r.chance(10)) r.pick(MovementRestriction.values),
  };
  var flags = HealthFlags(
    restrictions: restrictions,
    bloodPressure: r.pick<BloodPressureStatus?>([
      null,
      BloodPressureStatus.noKnownIssue,
      BloodPressureStatus.noKnownIssue,
      BloodPressureStatus.noKnownIssue,
      BloodPressureStatus.diagnosedHigh,
      BloodPressureStatus.managedWithClinician,
      BloodPressureStatus.unsure,
      BloodPressureStatus.diagnosedLow,
    ]),
    surgery: r.pick<SurgeryStatus?>([
      null,
      SurgeryStatus.none,
      SurgeryStatus.none,
      SurgeryStatus.clearedForNormalExercise,
      SurgeryStatus.unsure
    ]),
    clinicianAdvice: r.pick<ClinicianExerciseAdvice?>([
      null,
      ClinicianExerciseAdvice.noLimitsGiven,
      ClinicianExerciseAdvice.noLimitsGiven,
      ClinicianExerciseAdvice.limitsGiven,
      ClinicianExerciseAdvice.notAsked
    ]),
    professionalGuidance: r.chance(6)
        ? ProfessionalGuidanceNeed.reported
        : r.pick<ProfessionalGuidanceNeed?>(
            [null, ProfessionalGuidanceNeed.none, ProfessionalGuidanceNeed.none]),
  );
  var injuries = _injurySet((i * 11 + i ~/ 8) % 15);
  var equipment = _equip((i * 5 + i ~/ 8) % 8);
  var goals = _goals(arche, r);
  var birth = _kNow - age;
  final tier = FitnessTier.values[(i + i ~/ 4) % 4];

  // Explicit edge cases (override the sampled values).
  switch (i) {
    case 0:
      birth = _kNow - 15;
      equipment = _equip(0);
      flags = HealthFlags(restrictions: const {});
      screening = _allNo();
      injuries = const [];
    case 1:
      birth = _kNow - 17;
      equipment = _equip(3);
      flags = HealthFlags(restrictions: const {});
      screening = _allNo();
      injuries = const [];
    case 2:
      birth = _kNow - 78;
      equipment = _equip(3);
      injuries = _injurySet(3);
      flags = HealthFlags(restrictions: const {});
      screening = _allNo();
    case 3:
      flags = HealthFlags(
          restrictions: const {},
          professionalGuidance: ProfessionalGuidanceNeed.reported);
      screening = _allNo();
    case 4:
      screening = _allNo()
        ..[ParQQuestion.heartConditionOrHighBloodPressure] = true;
      flags = HealthFlags(restrictions: const {});
    case 5:
      screening = _allNo()..[ParQQuestion.chestPain] = true;
    case 6:
      screening = {};
    case 7:
      flags = HealthFlags(
          restrictions: const {}, surgery: SurgeryStatus.underRestrictions);
      screening = _allNo();
    case 8:
      flags = HealthFlags(
          restrictions: const {},
          clinicianAdvice: ClinicianExerciseAdvice.advisedAgainstExercise);
      screening = _allNo();
    case 9:
      flags = HealthFlags(
          restrictions: const {},
          bloodPressure: BloodPressureStatus.diagnosedHigh);
      screening = _allNo();
    case 10:
      screening = _allNo()
        ..[ParQQuestion.otherChronicCondition] = true
        ..[ParQQuestion.prescribedMedication] = true;
      flags = HealthFlags(restrictions: const {});
    case 11:
      goals = _goals(4, r);
      injuries = [_inj(InjuryRegion.knee), _inj(InjuryRegion.lowerBack)];
      equipment = _equip(3);
      flags = HealthFlags(restrictions: const {});
      screening = _allNo();
    case 12:
      goals = _goals(5, r);
      equipment = _equip(0);
      injuries = const [];
      flags = HealthFlags(restrictions: const {});
      screening = _allNo();
  }

  return UserProfile(
    uid: 'synthetic_$i',
    personal: PersonalInfo(
      birthYear: birth,
      gender: Gender.values[r.next(4)],
      heightCm: 150 + r.next(50),
      weightCurrentKg: 50.0 + r.next(60),
      weightTargetKg: 50.0 + r.next(50),
      activityLevel: ActivityLevel.values[r.next(4)],
    ),
    health: HealthHistory(
      injuries: injuries,
      screening: screening,
      flags: flags,
      conditions: r.chance(20) ? const ['asthma'] : const [],
      medications: r.chance(15) ? const ['metoprolol'] : const [],
    ),
    goals: goals,
    level: FitnessLevel(
      tier: tier,
      frequencyPerWeek: r.next(7),
      basics: BasicExerciseAbility.values[r.next(3)],
    ),
    lifestyle: Lifestyle(
      smoking: SmokingHabit.values[r.next(4)],
      alcohol: AlcoholHabit.values[r.next(4)],
      sleepHoursPerNight: 4 + r.next(6),
      stressLevel: 1 + r.next(10),
      occupation: OccupationActivity.values[r.next(4)],
    ),
    equipment: equipment,
    schedule: TrainingSchedule(
      daysPerWeek: 2 + r.next(5),
      sessionMinutes: r.pick(const [15, 30, 45, 60, 90]),
      preferredWeekdays: const [],
    ),
    motivation: MotivationPrefs(
      environments: [WorkoutEnvironment.values[r.next(5)]],
      barriers: [TrainingBarrier.values[r.next(7)]],
    ),
    completedAt: DateTime(2026, 1, 1),
  );
}

// ------------------------------------------------------------------ ORACLES --
String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9_\s]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');

const _regionTags = [
  'neck', 'upper_back', 'shoulder', 'elbow', 'wrist', 'lower_back', 'hip',
  'knee', 'ankle'
];

/// Tags the profile's own answers say must be avoided (independent of lib).
Set<String> _avoidTags(UserProfile p) {
  final out = <String>{};
  for (final inj in p.health.injuries) {
    if (inj.region != null) {
      out.add(inj.region!.tag);
    } else {
      final n = _norm(inj.bodyPart);
      for (final t in _regionTags) {
        if (n.contains(t)) out.add(t);
      }
    }
  }
  for (final r in p.health.flags.restrictions) {
    out.addAll(r.regionTags);
  }
  return out;
}

/// Tags from the INJURIES alone (the plan text says "an injury you reported").
Set<String> _injuryTags(UserProfile p) {
  final out = <String>{};
  for (final inj in p.health.injuries) {
    if (inj.region != null) {
      out.add(inj.region!.tag);
    } else {
      final n = _norm(inj.bodyPart);
      for (final t in _regionTags) {
        if (n.contains(t)) out.add(t);
      }
    }
  }
  return out;
}

bool _hasUnscreenableInjury(UserProfile p) => p.health.injuries.any((i) =>
    i.region == null &&
    !_regionTags.any((t) => _norm(i.bodyPart).contains(t)));

const _furniture = {
  'wall', 'chair', 'couch', 'doorway', 'stairs', 'a partner', 'balloon',
  'water bottle', 'tennis racket', 'padded stool', 'towel'
};
const _idKind = {
  'dumbbell': EquipmentKind.dumbbells,
  'barbell': EquipmentKind.barbell,
  'resistance_bands': EquipmentKind.bands,
  'kettlebell': EquipmentKind.kettlebells,
  'weight_plates': EquipmentKind.barbell,
};
const _labelKind = {
  'dumbbells': EquipmentKind.dumbbells,
  'dumbbell': EquipmentKind.dumbbells,
  'barbell': EquipmentKind.barbell,
  'bar': EquipmentKind.barbell,
  'ez bar': EquipmentKind.barbell,
  'trap bar': EquipmentKind.barbell,
  'weight plate': EquipmentKind.barbell,
  'landmine': EquipmentKind.barbell,
  'kettlebells': EquipmentKind.kettlebells,
  'resistance band': EquipmentKind.bands,
  'loop resistance band': EquipmentKind.bands,
  'resistance cable': EquipmentKind.bands,
};

Set<EquipmentKind>? _enforcedKinds(UserProfile p) {
  final e = p.equipment;
  final kinds = e.available.where((k) => k != EquipmentKind.cameraScan).toSet();
  final gym = e.location == TrainingLocation.gym ||
      e.location == TrainingLocation.mixed ||
      kinds.contains(EquipmentKind.fullGym);
  if (gym) return null;
  if (e.location == null && kinds.isEmpty) return null;
  return kinds;
}

/// null = ok, otherwise rule name.
String? _equipmentRule(ExerciseItem e, Set<EquipmentKind>? kinds) {
  if (kinds == null) return null;
  final label = (e.equipmentLabel ?? '').toLowerCase();
  for (final raw in label.split(',')) {
    final t = raw.trim();
    if (t.isEmpty ||
        t.startsWith('none') ||
        t.contains('mat') ||
        _furniture.contains(t)) {
      continue;
    }
    if (t.contains('machine')) {
      if (!kinds.contains(EquipmentKind.machines)) return 'EQUIPMENT_LABEL';
      continue;
    }
    final k = _labelKind[t];
    if (k != null && kinds.contains(k)) continue;
    if (kinds.contains(EquipmentKind.machines) &&
        const {'sled', 'treadmill', 'airbike', 'ski ergometer',
          'stationary exercise bike', 'hyperextension bench'}.contains(t)) {
      continue;
    }
    return 'EQUIPMENT_LABEL';
  }
  final id = e.equipmentId;
  if (id != null) {
    final k = _idKind[id];
    if (k == null || !kinds.contains(k)) {
      if (!kinds.contains(EquipmentKind.machines)) return 'EQUIPMENT_ID_UNCLAIMED';
    }
  }
  return null;
}

bool _cardioish(ExerciseItem e) =>
    e.vendorGroup == 'Calisthenics-Cardio-Plyo-Functional' ||
    const {'treadmill', 'rowing_machine', 'exercise_bike'}
        .contains(e.equipmentId);
final _impactRe = RegExp(
    r'jump|hop|hops|hopping|plyo|burpee|sprint|bound|skipping',
    caseSensitive: false);
bool _impact(ExerciseItem e) => _impactRe.hasMatch(e.title);
bool _balanceTitle(ExerciseItem e) => RegExp(
        r'balance|stork|tree pose|single[- ]leg stand|tai chi|heel[- ]to[- ]toe',
        caseSensitive: false)
    .hasMatch(e.title);
bool _maxEffort(ExerciseItem e) =>
    e.vendorGroup == 'Powerlifting' || e.difficulty == ExerciseDifficulty.advanced;

double? _oracleCeiling(UserProfile p) {
  var c = 1.10;
  final restricted = ParQQuestion.values.any((q) =>
      p.health.screening[q] == true && !kBlockingQuestions.contains(q));
  if (restricted) c = c < 0.8 ? c : 0.8;
  final f = p.health.flags;
  void cap(double v) => c = v < c ? v : c;
  switch (f.bloodPressure) {
    case BloodPressureStatus.diagnosedHigh:
    case BloodPressureStatus.diagnosedLow:
    case BloodPressureStatus.unsure:
      cap(0.8);
    case BloodPressureStatus.managedWithClinician:
      cap(0.9);
    default:
  }
  if (f.clinicianAdvice == ClinicianExerciseAdvice.limitsGiven) cap(0.8);
  if (f.clinicianAdvice == ClinicianExerciseAdvice.notAsked) cap(0.95);
  if (f.surgery == SurgeryStatus.unsure) cap(0.8);
  return c;
}

bool _oracleBlocked(UserProfile p) {
  final s = p.health.screening;
  final incomplete = ParQQuestion.values.any((q) => s[q] == null);
  return incomplete ||
      s[ParQQuestion.chestPain] == true ||
      s[ParQQuestion.medicallySupervisedOnly] == true ||
      p.health.flags.surgery == SurgeryStatus.underRestrictions ||
      p.health.flags.clinicianAdvice ==
          ClinicianExerciseAdvice.advisedAgainstExercise ||
      p.health.flags.professionalGuidance == ProfessionalGuidanceNeed.reported;
}

// -------------------------------------------------------------------- PATHS --
class _World {
  _World(this.all, this.byId, this.planPool, this.demo);
  final List<ExerciseItem> all;
  final Map<String, ExerciseItem> byId;
  final List<ExerciseItem> planPool;
  final List<ExerciseItem> demo;
}

_World _loadWorld() {
  final quarantine = (jsonDecode(
              File('assets/data/exercises_quarantine.json').readAsStringSync())
          as List)
      .map((e) => (e as Map)['id'] as String)
      .toSet();
  final eqIds = (jsonDecode(File('assets/data/equipment.json').readAsStringSync())
          as List)
      .map((e) => (e as Map)['id'] as String)
      .toSet();
  final all = (jsonDecode(
              File('assets/data/exercises_vendor.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>()
      .map(ExerciseItem.fromJson)
      .where((e) => !quarantine.contains(e.id))
      .toList(growable: false);
  final pool = [
    for (final e in all)
      if (e.equipmentId == null || eqIds.contains(e.equipmentId)) e
  ];
  return _World(all, {for (final e in all) e.id: e}, pool, withDemonstration(all));
}

class _Out {
  _Out(this.profile, this.safety);
  final UserProfile profile;
  final SafetyContext safety;
  PlanOutcome? plan;
  List<WorkoutSuggestion>? sugg; // null when UI gate (home_page.dart:162) hides it
  ProgrammeBuildResult? prog;
  int progDays = 0;
  String planSig = '', suggSig = '', progSig = '';
}

_Out _run(_World w, UserProfile p) {
  final ctx = safetyContextFor(p, now: _kNowDate);
  final hints = RecommendationHints.fromProfile(p);
  final o = _Out(p, ctx);
  o.plan = buildPlan(
    candidatePool: w.planPool,
    deficit: const {},
    deload: _noDeload,
    safety: ctx,
    targetMinutes: p.schedule.sessionMinutes ?? 45,
    hints: hints,
  );
  final safe = safeFor(w.demo, p);
  if (ctx.allowsAnyTraining) {
    final cands = sortByTierFit(eligibleExercises(safe, ctx), p.level.tier);
    o.sugg = buildSuggestions(
        candidates: cands,
        profile: p,
        recentLogs: const [],
        now: DateTime(2026, 10, 13));
  }
  final tpl = programmeFromProfile(p);
  // The cadence an enrolment really schedules: the capped day count, then the
  // weekdays the user ticked (programmeDayOffsets / programmeScheduledDays).
  o.progDays = programmeScheduledDays(
      daysPerWeek: programmeDaysPerWeek(tpl.daysPerWeek, p, now: _kNowDate),
      preferredWeekdays: p.schedule.preferredWeekdays);
  final muscles = programmeMuscles(tpl, p);
  final spec = programmeSpecFor(tpl.id,
      daysPerWeek: o.progDays,
      adaptation: programmeAdaptationFor(ctx, hints));
  if (!ctx.allowsAnyTraining || spec == null) {
    o.prog = const ProgrammeRefused([ProgrammeFinding(ProgrammeFault.blockedBySafety)]);
  } else {
    final focus = muscles.toSet();
    o.prog = buildProgramme(ProgrammeBuildRequest(
      spec: spec,
      catalogue: safe,
      safety: ctx,
      weeks: tpl.weeks,
      daysPerWeek: o.progDays,
      rank: focus.isEmpty
          ? null
          : (role, pool) => [
                ...pool.where((e) =>
                    e.primaryMuscles.any(focus.contains) ||
                    e.muscles.any(focus.contains)),
                ...pool.where((e) => !(e.primaryMuscles.any(focus.contains) ||
                    e.muscles.any(focus.contains))),
              ],
    ));
  }
  o.planSig = switch (o.plan!) {
    PlanReady(:final plan) =>
      'R|${plan.exercises.map((e) => e.id).join(',')}|${plan.intensityFactor}|${plan.title.name}|${plan.reasons.map((r) => r.runtimeType).join(',')}',
    PlanRefused(:final reasons) => 'X|${reasons.length}',
  };
  o.suggSig = o.sugg == null
      ? 'GATED'
      : o.sugg!.map((s) => '${s.exerciseId}:${s.reason.name}').join(',');
  o.progSig = switch (o.prog!) {
    ProgrammeBuilt(:final sessions) => 'B|${sessions.map((s) => s.exercises.map((e) => e.exercise.id).join('+')).join(',')}',
    ProgrammeRefused(:final findings) => 'X|${findings.map((f) => f.fault.name).join(',')}',
  };
  return o;
}

String _sig(_Out o) => '${o.planSig}#${o.suggSig}#${o.progSig}';

// ---------------------------------------------------------------- VIOLATIONS --
class _V {
  _V(this.id, this.rule, this.path, this.ex, this.detail);
  final String id, rule, path, ex, detail;
}

String _desc(UserProfile p) {
  final g = p.goals;
  return 'age=${p.personal.ageAt(_kNow)} tier=${p.level.tier?.name} '
      'goal=${g.primary?.name}${g.flexibility ? "+flex" : ""} '
      'equip=${p.equipment.location?.name}/${p.equipment.available.map((k) => k.name).join("+")} '
      'inj=${p.health.injuries.map((i) => i.region?.name ?? i.bodyPart).join("+")} '
      'restr=${p.health.flags.restrictions.map((r) => r.name).join("+")} '
      'min=${p.schedule.sessionMinutes} days=${p.schedule.daysPerWeek}';
}

List<_V> _check(_World w, _Out o, UserProfile adultTwin, _Out twin) {
  final p = o.profile;
  final id = p.uid;
  final vs = <_V>[];
  void v(String rule, String path, String ex, String detail) =>
      vs.add(_V(id, rule, path, ex, '${_desc(p)} :: $detail'));

  final avoid = _avoidTags(p);
  final kinds = _enforcedKinds(p);
  final beginner =
      p.level.tier == FitnessTier.never || p.level.tier == FitnessTier.beginner;
  final blocked = _oracleBlocked(p);
  final ceiling = _oracleCeiling(p)!;

  final byPath = <String, List<ExerciseItem>>{};
  if (o.plan case PlanReady(:final plan)) byPath['plan'] = plan.exercises;
  if (o.sugg != null) {
    byPath['suggestions'] = [
      for (final s in o.sugg!)
        if (w.byId[s.exerciseId] != null) w.byId[s.exerciseId]!
    ];
  }
  if (o.prog case ProgrammeBuilt(:final sessions)) {
    byPath['programme'] = {
      for (final s in sessions)
        for (final e in s.exercises) e.exercise.id: e.exercise
    }.values.toList();
  }

  for (final entry in byPath.entries) {
    for (final e in entry.value) {
      final hit = e.contraindications.where(avoid.contains).toList();
      if (hit.isNotEmpty) v('INJURY_CONTRA', entry.key, e.id, 'tags=$hit');
      final er = _equipmentRule(e, kinds);
      if (er != null) v(er, entry.key, e.id, 'label=${e.equipmentLabel} id=${e.equipmentId}');
      if (beginner && e.difficulty != ExerciseDifficulty.beginner) {
        v('DIFFICULTY_ABOVE_LEVEL', entry.key, e.id, 'difficulty=${e.difficulty.name}');
      }
    }
    final g = p.goals;
    final wantsCardio = g.weightLoss || g.endurance ||
        g.primary == ProgrammeGoal.weightLoss ||
        g.primary == ProgrammeGoal.endurance;
    bool feasible(bool Function(ExerciseItem) pred) => w.demo.any((e) =>
        pred(e) &&
        e.contraindications.every((c) => !avoid.contains(c)) &&
        _equipmentRule(e, kinds) == null);
    // A plan with no minutes left for one more (10-minute) item cannot hold the
    // cardio item next to a reserved senior balance item: not a violation.
    final noRoom = entry.key == 'plan' &&
        o.plan is PlanReady &&
        (o.plan as PlanReady).plan.estimatedMinutes + 10 >
            (p.schedule.sessionMinutes ?? 45);
    if (wantsCardio &&
        !noRoom &&
        feasible(_cardioish) &&
        !entry.value.any(_cardioish)) {
      v('GOAL_CARDIO_MISSING', entry.key, '-', 'no conditioning/cardio item in ${entry.value.length} items');
    }
    if (g.flexibility && feasible((e) => e.isStretch) &&
        !entry.value.any((e) => e.isStretch)) {
      v('GOAL_MOBILITY_MISSING', entry.key, '-', 'no stretch/mobility item in ${entry.value.length} items');
    }
    if (g.primary == ProgrammeGoal.comeback || g.flexibility) {
      for (final e in entry.value.where(_maxEffort)) {
        v('GOAL_MAXEFFORT_FOR_REHAB_OR_MOBILITY', entry.key, e.id,
            'group=${e.vendorGroup} difficulty=${e.difficulty.name}');
      }
    }
  }

  // Whole-person gate and ceiling.
  if (blocked) {
    if (o.plan is PlanReady) v('BLOCKED_BUT_PLANNED', 'plan', '-', 'plan produced for a profile the answers refuse');
    if (o.prog is ProgrammeBuilt) v('BLOCKED_BUT_PLANNED', 'programme', '-', 'programme built');
  } else if (o.plan case PlanReady(:final plan)) {
    if (plan.intensityFactor > ceiling + 1e-9) {
      v('CEILING_NOT_APPLIED', 'plan', '-', 'factor=${plan.intensityFactor} > ceiling=$ceiling');
    }
    final target = p.schedule.sessionMinutes ?? 45;
    if (plan.estimatedMinutes > target) {
      v('PLAN_EXCEEDS_SESSION_LENGTH', 'plan', '-', 'est=${plan.estimatedMinutes} > answered=$target');
    }
    // Reason truthfulness: injury-filter count vs what injuries alone removed.
    for (final r in plan.reasons) {
      if (r is InjuryFilterReason) {
        final injTags = _injuryTags(p);
        final injuryOnly =
            w.planPool.where((e) => e.contraindications.any(injTags.contains)).length;
        if (r.count != injuryOnly) {
          v('REASON_INJURY_COUNT_NOT_INJURY_ONLY', 'plan', '-',
              'text says ${r.count} conflict with an injury; injuries alone remove $injuryOnly');
        }
      }
    }
    if (_hasUnscreenableInjury(p) &&
        !plan.reasons.any((r) =>
            r is SafetyAdvisoryReason &&
            r.advisory.reason == BlockReason.unscreenableInjury)) {
      v('UNSCREENABLE_INJURY_NOT_DISCLOSED', 'plan', '-',
          'injury with no screenable region is silently ignored');
    }
  }
  if (o.sugg != null) {
    final g = p.goals;
    for (final s in o.sugg!) {
      final e = w.byId[s.exerciseId];
      if (e == null) continue;
      if ((s.reason == SuggestionReason.buildsStrength ||
              s.reason == SuggestionReason.buildsMuscle) &&
          (e.isStretch || e.vendorGroup == 'Yoga')) {
        v('REASON_FALSE_BUILDS_STRENGTH', 'suggestions', e.id,
            'card says ${s.reason.name} for stretch/yoga item (goal strength=${g.strength} muscle=${g.muscleGain})');
      }
    }
  }
  // Age policy: a different, cautious output AND a visible warning.
  final age = p.personal.ageAt(_kNow)!;
  final minor = age < 18;
  final senior = age >= 65;
  if (!blocked && o.plan is PlanReady && (minor || senior)) {
    if (_sig(o) == _sig(twin)) {
      v(minor ? 'MINOR_NO_CAUTION_PATH' : 'SENIOR_NO_CAUTION_PATH', 'all', '-',
          'output identical to a 30-year-old with the same answers');
    }
    final plan = (o.plan as PlanReady).plan;
    final want =
        minor ? BlockReason.ageMinorAdvisory : BlockReason.ageSeniorAdvisory;
    if (!plan.reasons.any((r) =>
            r is SafetyAdvisoryReason && r.advisory.reason == want) ||
        !o.safety.advisories.any((a) => a.reason == want)) {
      v('AGE_WARNING_MISSING', 'plan', '-', 'no visible age advisory for age $age');
    }
    for (final entry in byPath.entries) {
      for (final e in entry.value) {
        if (_maxEffort(e)) {
          v('AGE_MAXEFFORT', entry.key, e.id, 'max-effort item for age $age');
        }
        if (senior && _impact(e)) {
          v('AGE_HIGH_IMPACT', entry.key, e.id, 'high-impact item for age $age');
        }
      }
    }
    final cap = minor ? 0.8 : 0.85;
    if (plan.intensityFactor > cap + 1e-9) {
      v('AGE_INTENSITY_ABOVE_CAP', 'plan', '-',
          'factor=${plan.intensityFactor} > $cap');
    }
    final dayCap = minor ? 4 : 3;
    if (o.prog is ProgrammeBuilt && o.progDays > dayCap) {
      v('AGE_DAYS_ABOVE_CAP', 'programme', '-', 'days=${o.progDays} > $dayCap');
    }
    if (senior) {
      final balanceFeasible = w.demo.any((e) =>
          (e.isStretch || _balanceTitle(e)) &&
          !_maxEffort(e) &&
          e.contraindications.every((c) => !avoid.contains(c)) &&
          _equipmentRule(e, kinds) == null);
      if (balanceFeasible &&
          !plan.exercises.any((e) => e.isStretch || _balanceTitle(e))) {
        v('SENIOR_NO_BALANCE_MOBILITY', 'plan', '-',
            'plan has no mobility/balance item');
      }
    }
  }
  // Adults get no age advisory (the warning is not decoration on everybody).
  if (!minor &&
      !senior &&
      o.safety.advisories.any((a) =>
          a.reason == BlockReason.ageMinorAdvisory ||
          a.reason == BlockReason.ageSeniorAdvisory)) {
    v('ADULT_GOT_AGE_WARNING', 'all', '-', 'age $age');
  }
  return vs;
}

// -------------------------------------------------------------- PERTURBATION --
typedef _Mut = UserProfile Function(UserProfile);

UserProfile _h(UserProfile p, HealthHistory Function(HealthHistory) f) =>
    p.copyWith(health: f(p.health));
UserProfile _fl(UserProfile p, HealthFlags Function(HealthFlags) f) =>
    _h(p, (h) => h.copyWith(flags: f(h.flags)));

Map<String, List<_Mut>> _perturbations() => {
      'personal.birthYear': [
        (p) => p.copyWith(personal: p.personal.copyWith(birthYear: 2011)),
        (p) => p.copyWith(personal: p.personal.copyWith(birthYear: 1950)),
      ],
      'personal.gender': [
        for (final g in Gender.values)
          (p) => p.copyWith(personal: p.personal.copyWith(gender: g)),
      ],
      'personal.heightCm': [(p) => p.copyWith(personal: p.personal.copyWith(heightCm: 140))],
      'personal.weightCurrentKg': [(p) => p.copyWith(personal: p.personal.copyWith(weightCurrentKg: 140))],
      'personal.weightTargetKg': [(p) => p.copyWith(personal: p.personal.copyWith(weightTargetKg: 45))],
      'personal.activityLevel': [
        for (final a in ActivityLevel.values)
          (p) => p.copyWith(personal: p.personal.copyWith(activityLevel: a)),
      ],
      'goals.primary': [
        for (final g in ProgrammeGoal.values)
          (p) => p.copyWith(goals: p.goals.copyWith(primary: g)),
      ],
      'goals.weightLoss': [(p) => p.copyWith(goals: p.goals.copyWith(weightLoss: true))],
      'goals.muscleGain': [(p) => p.copyWith(goals: p.goals.copyWith(muscleGain: true))],
      'goals.endurance': [(p) => p.copyWith(goals: p.goals.copyWith(endurance: true))],
      'goals.strength': [(p) => p.copyWith(goals: p.goals.copyWith(strength: true))],
      'goals.flexibility': [(p) => p.copyWith(goals: p.goals.copyWith(flexibility: true))],
      'goals.generalFitness': [(p) => p.copyWith(goals: p.goals.copyWith(generalFitness: true))],
      'goals.specificSport': [(p) => p.copyWith(goals: p.goals.copyWith(specificSport: 'boxing'))],
      'goals.focusZones': [
        for (final z in FocusZone.values)
          (p) => p.copyWith(goals: p.goals.copyWith(focusZones: [z])),
      ],
      'level.tier': [
        for (final t in FitnessTier.values)
          (p) => p.copyWith(level: p.level.copyWith(tier: t)),
      ],
      'level.basics': [
        for (final b in BasicExerciseAbility.values)
          (p) => p.copyWith(level: p.level.copyWith(basics: b)),
      ],
      'level.frequencyPerWeek': [(p) => p.copyWith(level: p.level.copyWith(frequencyPerWeek: 0)), (p) => p.copyWith(level: p.level.copyWith(frequencyPerWeek: 6))],
      'level.currentExercises': [(p) => p.copyWith(level: p.level.copyWith(currentExercises: ['squat', 'deadlift']))],
      'lifestyle.diet': [(p) => p.copyWith(lifestyle: p.lifestyle.copyWith(diet: [DietaryPreference.vegan]))],
      'lifestyle.smoking': [
        for (final s in SmokingHabit.values)
          (p) => p.copyWith(lifestyle: p.lifestyle.copyWith(smoking: s)),
      ],
      'lifestyle.alcohol': [
        for (final a in AlcoholHabit.values)
          (p) => p.copyWith(lifestyle: p.lifestyle.copyWith(alcohol: a)),
      ],
      'lifestyle.sleepHoursPerNight': [(p) => p.copyWith(lifestyle: p.lifestyle.copyWith(sleepHoursPerNight: 3)), (p) => p.copyWith(lifestyle: p.lifestyle.copyWith(sleepHoursPerNight: 9))],
      'lifestyle.stressLevel': [(p) => p.copyWith(lifestyle: p.lifestyle.copyWith(stressLevel: 1)), (p) => p.copyWith(lifestyle: p.lifestyle.copyWith(stressLevel: 10))],
      'lifestyle.occupation': [
        for (final o in OccupationActivity.values)
          (p) => p.copyWith(lifestyle: p.lifestyle.copyWith(occupation: o)),
      ],
      'equipment.location': [
        for (final l in TrainingLocation.values)
          (p) => p.copyWith(equipment: p.equipment.copyWith(location: l)),
      ],
      'equipment.available': [
        for (final k in EquipmentKind.values)
          (p) => p.copyWith(equipment: p.equipment.copyWith(available: [k])),
      ],
      'equipment.homeEquipment(text)': [(p) => p.copyWith(equipment: p.equipment.copyWith(homeEquipment: ['pull-up bar']))],
      'equipment.gymId': [(p) => p.copyWith(equipment: p.equipment.copyWith(gymId: 'gym_42'))],
      'schedule.daysPerWeek': [
        for (final d in [2, 3, 4, 5, 6])
          (p) => p.copyWith(schedule: p.schedule.copyWith(daysPerWeek: d)),
      ],
      'schedule.sessionMinutes': [
        for (final m in [15, 30, 45, 60, 90])
          (p) => p.copyWith(schedule: p.schedule.copyWith(sessionMinutes: m)),
      ],
      'schedule.preferredWeekdays': [(p) => p.copyWith(schedule: p.schedule.copyWith(preferredWeekdays: [1, 3]))],
      'motivation.motivation(text)': [(p) => p.copyWith(motivation: p.motivation.copyWith(motivation: 'wedding'))],
      'motivation.environments': [
        for (final e in WorkoutEnvironment.values)
          (p) => p.copyWith(motivation: p.motivation.copyWith(environments: [e])),
      ],
      'motivation.preferredDuration': [
        for (final d in WorkoutDuration.values)
          (p) => p.copyWith(motivation: p.motivation.copyWith(preferredDuration: d)),
      ],
      'motivation.barriers': [
        for (final b in TrainingBarrier.values)
          (p) => p.copyWith(motivation: p.motivation.copyWith(barriers: [b])),
      ],
      'health.conditions(text)': [(p) => _h(p, (h) => h.copyWith(conditions: ['epilepsy', 'diabetes']))],
      'health.allergies(text)': [(p) => _h(p, (h) => h.copyWith(allergies: ['latex']))],
      'health.medications(text)': [(p) => _h(p, (h) => h.copyWith(medications: ['insulin']))],
      'health.physicalLimitations(text)': [(p) => _h(p, (h) => h.copyWith(physicalLimitations: ['cannot kneel']))],
      'health.recentSurgeries(text)': [(p) => _h(p, (h) => h.copyWith(recentSurgeries: ['knee replacement']))],
      'health.otherConcerns(text)': [(p) => _h(p, (h) => h.copyWith(otherConcerns: 'pregnant'))],
      'health.bloodPressure(legacy chip)': [
        for (final b in BloodPressure.values)
          (p) => _h(p, (h) => h.copyWith(bloodPressure: b)),
      ],
      'health.injuries(region)': [
        for (final r in InjuryRegion.values)
          (p) => _h(p, (h) => h.copyWith(injuries: [_inj(r)])),
      ],
      'health.injuries(unscreenable text)': [(p) => _h(p, (h) => h.copyWith(injuries: [const Injury(bodyPart: 'rib', type: 'x', confirmed: true)]))],
      'flags.restrictions': [
        for (final r in MovementRestriction.values)
          (p) => _fl(p, (f) => f.copyWith(restrictions: {r})),
      ],
      'flags.bloodPressure': [
        for (final b in BloodPressureStatus.values)
          (p) => _fl(p, (f) => f.copyWith(bloodPressure: b)),
      ],
      'flags.surgery': [
        for (final s in SurgeryStatus.values)
          (p) => _fl(p, (f) => f.copyWith(surgery: s)),
      ],
      'flags.clinicianAdvice': [
        for (final c in ClinicianExerciseAdvice.values)
          (p) => _fl(p, (f) => f.copyWith(clinicianAdvice: c)),
      ],
      'flags.professionalGuidance(pregnancy)': [
        for (final g in ProfessionalGuidanceNeed.values)
          (p) => _fl(p, (f) => f.copyWith(professionalGuidance: g)),
      ],
      for (final q in ParQQuestion.values)
        'parq.${q.name}': [
          (p) => _h(p, (h) => h.copyWith(screening: {...h.screening, q: true})),
          (p) => _h(p, (h) => h.copyWith(screening: {...h.screening, q: false})),
        ],
    };

// -------------------------------------------------------------------- TEST --
void main() {
  test('100 synthetic profiles: recommendation honesty ratchet', () {
    final w = _loadWorld();
    final profiles = [for (var i = 0; i < 100; i++) _gen(i)];
    expect(profiles.length, 100);
    expect({for (final p in profiles) p.uid}.length, 100);

    // Generator coverage guard: the grid must really be covered.
    final cov = <String, Set<Object?>>{
      'age<18': {for (final p in profiles) p.personal.ageAt(_kNow)! < 18},
      'age>=65': {for (final p in profiles) p.personal.ageAt(_kNow)! >= 65},
      'gender': {for (final p in profiles) p.personal.gender},
      'tier': {for (final p in profiles) p.level.tier},
      'goal': {for (final p in profiles) p.goals.primary},
      'location': {for (final p in profiles) p.equipment.location},
      'minutes': {for (final p in profiles) p.schedule.sessionMinutes},
      'days': {for (final p in profiles) p.schedule.daysPerWeek},
      'injRegion': {for (final p in profiles) for (final i in p.health.injuries) i.region},
      'restriction': {for (final p in profiles) for (final r in p.health.flags.restrictions) r},
      'guidance': {for (final p in profiles) p.health.flags.professionalGuidance},
      'smoking': {for (final p in profiles) p.lifestyle.smoking},
    };
    expect(cov['age<18']!.length, 2, reason: 'minors and adults both present');
    expect(cov['age>=65']!.length, 2);
    expect(cov['gender']!.length, 4);
    expect(cov['tier']!.length, 4);
    // Every programme goal (6 today) must appear as some profile's primary goal.
    expect(cov['goal'], containsAll(ProgrammeGoal.values),
        reason: 'every ProgrammeGoal needs at least one profile');
    expect(cov['goal']!.length, ProgrammeGoal.values.length);
    expect(cov['location']!.length, greaterThanOrEqualTo(5));
    expect(cov['minutes']!.length, 5);
    expect(cov['days']!.length, 5);
    expect(cov['injRegion']!.length, greaterThanOrEqualTo(9));
    expect(cov['restriction']!.length, greaterThanOrEqualTo(6));
    expect(cov['guidance']!.length, 3);
    expect(cov['smoking']!.length, 4);

    final violations = <_V>[];
    final outs = <_Out>[];
    var nondeterministic = 0;
    for (final p in profiles) {
      final o = _run(w, p);
      final again = _run(w, p);
      if (_sig(o) != _sig(again)) {
        nondeterministic++;
        violations.add(_V(p.uid, 'NONDETERMINISTIC', 'all', '-', _desc(p)));
      }
      final twinProfile = p.copyWith(
          personal: p.personal.copyWith(birthYear: _kNow - 30));
      violations.addAll(_check(w, o, twinProfile, _run(w, twinProfile)));
      outs.add(o);
    }

    // Distinct outputs.
    int distinct(String Function(_Out) f, bool Function(String) skip) =>
        outs.map(f).where((s) => !skip(s)).toSet().length;
    final distinctCounts = <String, int>{
      'plan': distinct((o) => o.planSig, (s) => s.startsWith('X')),
      'suggestions': distinct((o) => o.suggSig, (s) => s == 'GATED'),
      'programme': distinct((o) => o.progSig, (s) => s.startsWith('X')),
    };
    final refused = {
      'plan': outs.where((o) => o.planSig.startsWith('X')).length,
      'programme': outs.where((o) => o.progSig.startsWith('X')).length,
      'suggestionsGated': outs.where((o) => o.suggSig == 'GATED').length,
    };

    // Dead inputs: toggled on 24 non-gated base profiles; dead = no output change.
    final plainBases = outs.where((o) => o.sugg != null).take(24).toList();
    // Neutral twins (adult, active, sleeps and copes well, no stated duration):
    // a field that only ever matters when no other cap already binds must
    // still be seen as live, so these are probed as well.
    final neutralBases = [
      for (final b in plainBases.take(8))
        _run(
            w,
            b.profile.copyWith(
              personal: b.profile.personal.copyWith(
                  birthYear: _kNow - 35, activityLevel: ActivityLevel.active),
              lifestyle: b.profile.lifestyle
                  .copyWith(sleepHoursPerNight: 8, stressLevel: 3),
              level: b.profile.level.copyWith(basics: BasicExerciseAbility.yes),
              motivation: MotivationPrefs(
                  environments: b.profile.motivation.environments,
                  barriers: b.profile.motivation.barriers),
            )),
    ];
    final bases = [...plainBases, ...neutralBases];
    final baseSig = {for (final b in bases) b.profile.uid + (identical(b, bases.first) ? '' : '#${bases.indexOf(b)}'): _sig(b)};
    final dead = <String>[];
    _perturbations().forEach((field, muts) {
      var live = false;
      for (final b in bases) {
        for (final m in muts) {
          if (_sig(_run(w, m(b.profile))) != baseSig[b.profile.uid + (identical(b, bases.first) ? '' : '#${bases.indexOf(b)}')]) {
            live = true;
            break;
          }
        }
        if (live) break;
      }
      if (!live) dead.add(field);
    });

    final counts = <String, int>{};
    for (final v in violations) {
      counts[v.rule] = (counts[v.rule] ?? 0) + 1;
    }

    final csv = Platform.environment['HONESTY_CSV'];
    if (csv != null && csv.isNotEmpty) {
      String q(String s) => '"${s.replaceAll('"', '""')}"';
      File(csv).writeAsStringSync([
        'profile_id,rule,path,exercise_id,params_and_detail',
        for (final v in violations)
          [v.id, v.rule, v.path, v.ex, q(v.detail)].join(','),
      ].join('\n'));
      File('$csv.dead.txt').writeAsStringSync(
          'dead=${dead.join('\n')}\ndistinct=$distinctCounts\nrefused=$refused\ncounts=$counts\n');
    }

    final summary = StringBuffer()
      ..writeln('violations by rule: $counts')
      ..writeln('distinct outputs: $distinctCounts  refused/gated: $refused')
      ..writeln('nondeterministic: $nondeterministic')
      ..writeln('dead inputs (${dead.length}): ${dead.toList()..sort()}');
    // ignore: avoid_print
    print(summary);

    final failures = <String>[];
    counts.forEach((rule, n) {
      final allowed = _baselineViolations[rule] ?? 0;
      if (n > allowed) {
        final sample = violations.where((v) => v.rule == rule).take(5).map(
            (v) => '  ${v.id} ${v.path} ${v.ex} :: ${v.detail}');
        failures.add('$rule grew: $n > baseline $allowed\n${sample.join('\n')}');
      }
    });
    // Baselined rules are EXACT: a shrink must also fail so the maintainer
    // lowers the baseline and the ratchet cannot silently regain slack.
    _baselineViolations.forEach((rule, allowed) {
      final n = counts[rule] ?? 0;
      if (n < allowed) {
        failures.add('$rule shrank: $n < baseline $allowed. Good news: lower '
            '_baselineViolations[\'$rule\'] to $n (remove the key when it '
            'reaches 0).');
      }
    });
    distinctCounts.forEach((path, n) {
      final min = _baselineMinDistinct[path] ?? 0;
      if (n < min) failures.add('distinct $path outputs fell: $n < $min');
    });
    for (final f in dead) {
      if (!_baselineDeadFields.contains(f)) {
        failures.add('questionnaire input newly dead (no effect on any output): $f');
      }
    }
    expect(failures, isEmpty, reason: '${failures.join('\n')}\n\n$summary');
  }, timeout: const Timeout(Duration(minutes: 15)));

  // Canaries: hand-written expectations with LITERAL numbers. They deliberately
  // do not read kAdultFromAge / intensityCap / the oracles above, so a wrong
  // constant in the implementation cannot also corrupt the expectation.
  group('canary profiles (literal expectations)', () {
    late _World w;
    setUpAll(() => w = _loadWorld());

    UserProfile canary({
      int? birthYear,
      FitnessTier tier = FitnessTier.advanced,
      Map<ParQQuestion, bool>? screening,
      int days = 6,
    }) =>
        UserProfile.empty('canary').copyWith(
          personal: PersonalInfo(birthYear: birthYear),
          health: HealthHistory(
            injuries: const [],
            screening: screening ?? _allNo(),
            flags: HealthFlags(restrictions: const {}),
          ),
          goals: const FitnessGoals(primary: ProgrammeGoal.strength, strength: true),
          level: FitnessLevel(
              tier: tier, frequencyPerWeek: 3, basics: BasicExerciseAbility.yes),
          equipment: _equip(3),
          schedule: TrainingSchedule(
              daysPerWeek: days, sessionMinutes: 45, preferredWeekdays: const []),
          completedAt: DateTime(2026, 1, 1),
        );

    // Every exercise any of the three paths produced.
    List<ExerciseItem> everyExercise(_World w, _Out o) => [
          if (o.plan case PlanReady(:final plan)) ...plan.exercises,
          if (o.sugg != null)
            for (final s in o.sugg!)
              if (w.byId[s.exerciseId] != null) w.byId[s.exerciseId]!,
          if (o.prog case ProgrammeBuilt(:final sessions))
            for (final s in sessions) for (final e in s.exercises) e.exercise,
        ];

    test('15-year-old beginner: cap 0.8, no powerlifting or advanced work', () {
      final o = _run(w, canary(birthYear: 2026 - 15, tier: FitnessTier.beginner));
      expect(o.plan, isA<PlanReady>());
      final plan = (o.plan as PlanReady).plan;
      expect(plan.intensityFactor, lessThanOrEqualTo(0.8));
      expect(plan.exercises, isNotEmpty);
      final all = everyExercise(w, o);
      expect(all, isNotEmpty);
      for (final e in all) {
        expect(e.vendorGroup, isNot('Powerlifting'), reason: e.id);
        expect(e.difficulty, isNot(ExerciseDifficulty.advanced), reason: e.id);
        expect(e.difficulty, ExerciseDifficulty.beginner,
            reason: '${e.id}: beginner tier');
      }
      expect(
          plan.reasons.whereType<SafetyAdvisoryReason>().map((r) => r.advisory.reason),
          contains(BlockReason.ageMinorAdvisory));
    });

    test('70-year-old: cap 0.85, at most 3 days, no impact work, has balance/mobility',
        () {
      final o = _run(w, canary(birthYear: 2026 - 70, days: 6));
      expect(o.plan, isA<PlanReady>());
      final plan = (o.plan as PlanReady).plan;
      expect(plan.intensityFactor, lessThanOrEqualTo(0.85));
      expect(o.progDays, lessThanOrEqualTo(3));
      expect(o.progDays, greaterThan(0));
      final all = everyExercise(w, o);
      expect(all, isNotEmpty);
      final impact = RegExp(r'jump|\bhop|burpee|sprint', caseSensitive: false);
      for (final e in all) {
        expect(impact.hasMatch(e.title), isFalse, reason: 'impact title: ${e.title}');
      }
      expect(
          plan.exercises.any((e) =>
              e.isStretch ||
              e.vendorGroup == 'Yoga' ||
              e.vendorGroup == 'Stretching - Mobility' ||
              RegExp(r'balance', caseSensitive: false).hasMatch(e.title)),
          isTrue,
          reason: 'a senior plan must include a balance/mobility exercise');
    });

    test('screening-blocked profile yields no plan, no suggestions, no programme',
        () {
      final o = _run(
          w,
          canary(
              birthYear: 2026 - 35,
              screening: _allNo()..[ParQQuestion.chestPain] = true));
      expect(o.plan, isA<PlanRefused>());
      expect(o.sugg, isNull);
      expect(o.prog, isA<ProgrammeRefused>());
      expect(everyExercise(w, o), isEmpty);
    });

    test('adult with no age data is treated as an adult with no age warning', () {
      final o = _run(w, canary(birthYear: null, days: 5));
      expect(o.plan, isA<PlanReady>());
      final plan = (o.plan as PlanReady).plan;
      expect(o.safety.ageBand, AgeBand.adult);
      expect(o.safety.advisories, isEmpty);
      expect(plan.reasons.whereType<SafetyAdvisoryReason>(), isEmpty);
      expect(plan.intensityFactor, greaterThan(0.85),
          reason: 'no age cap may be applied to an unknown age');
      expect(o.progDays, 5, reason: 'no age cap on training days');
    });
  });
}
