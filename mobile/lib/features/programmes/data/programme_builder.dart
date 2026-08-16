/// Programme construction by movement role, with a validator that can reject
/// what it builds.
///
/// ## What this replaces, measured
///
/// The shipped `strength_base` programme — 8 weeks, 4 days a week, 32 sessions
/// — was assembled by `_fillDay`, which takes the catalogue sorted by `id` and
/// walks CONSECUTIVE entries from an index. `strength_base` names no muscles,
/// so its pool was the whole catalogue in alphabetical order. The result was 32
/// sessions drawing on 14 distinct exercises, all of them yoga poses, sit-ups
/// and bicycle twists, under a title promising a strength base. The file's own
/// comment claimed variety "bounded by what the catalogue actually offers".
///
/// Alphabetical adjacency is not a training relationship. Nothing about
/// `_fillDay` could have produced a strength session, and no amount of tuning
/// its start index would have.
///
/// ## The shape of the replacement
///
/// ```
/// programme specification   (roles per session, frequency and volume targets)
///        ↓
/// eligible candidates       (the ONE safety layer: screening, injuries,
///        ↓                   normalised health restrictions, equipment)
/// role index                (movement_role.dart, derived, null-honest)
///        ↓
/// ranked within role        (personalisation: weekly volume deficit)
///        ↓
/// session allocation        (fill each declared slot, rotate across weeks)
///        ↓
/// validation                (structural, and able to say no)
///        ↓
/// ProgrammeBuildResult      (built, or refused with machine-readable findings)
/// ```
///
/// Every stage is deterministic. The personalisation stage ORDERS candidates
/// that are already eligible; it cannot introduce one, and it cannot remove the
/// last one from a slot. That ordering is the only place a learned or
/// model-derived signal is allowed to act — see [ProgrammeBuildRequest.rank].
library;

import '../../equipment/data/equipment_models.dart';
import '../../safety/data/eligibility.dart';
import 'movement_role.dart';

/// What one session of a programme must contain.
///
/// A list of role slots, in the order they should be performed. Compound
/// patterns first is a coaching convention, not a safety rule, and it lives in
/// the specification rather than in the builder so a different programme can
/// declare a different order.
class SessionSpec {
  const SessionSpec({required this.name, required this.slots});

  /// Stable key. Not a title — titles are localised, and this is data.
  final String name;

  final List<MovementRole> slots;
}

/// The rules a programme is built to and validated against.
///
/// Configuration, not constants scattered through the builder. `min`/`max`
/// bounds live here so a reviewer can disagree with a number in one place
/// rather than finding it inlined in a UI file.
class ProgrammeSpec {
  const ProgrammeSpec({
    required this.id,
    required this.sessions,
    this.minWeeklyFrequencyPerRole = 2,
    this.frequencyRoles = kPrimaryStrengthRoles,
    this.minWeeklySetsPerRole = 4,
    this.maxWeeklySetsPerRole = 30,
    this.setsPerSlot = 3,
    this.minSurvivingPrimaryRoles = 4,
  });

  final String id;

  /// The week's sessions, cycled in order.
  final List<SessionSpec> sessions;

  /// How often each of [frequencyRoles] must appear in a week.
  ///
  /// Two is the operator's stated target and the commonest recommendation for
  /// a trained pattern. `PRODUCT_HEURISTIC`; owner unassigned. It is checked
  /// per role rather than per muscle deliberately — mechanically forcing every
  /// small muscle to two direct exercises a week is not programming, it is
  /// arithmetic wearing programming's clothes.
  final int minWeeklyFrequencyPerRole;

  /// Which roles the frequency rule applies to.
  ///
  /// A programme that does not train a pattern at all is not in breach of a
  /// frequency rule for it — a push/pull split has no carry slot and should
  /// not be told it failed one. So this is the set of roles the spec DECLARES,
  /// intersected with this, and never the whole enum.
  final Set<MovementRole> frequencyRoles;

  final int minWeeklySetsPerRole;
  final int maxWeeklySetsPerRole;

  /// Programmed sets per filled slot.
  ///
  /// The unit volume is counted in. Counting exercise CARDS as volume — which
  /// is what the app did everywhere before Gate K — makes a one-set session and
  /// a five-set session the same number.
  final int setsPerSlot;

  /// How many of [kPrimaryStrengthRoles] must remain trainable for this to
  /// still be the programme it claims to be.
  ///
  /// Four of the seven. Below that a "strength base" is core work and
  /// stretches under a strength title, which is the exact thing Gate P exists
  /// to stop shipping. `PRODUCT_HEURISTIC`; owner unassigned.
  final int minSurvivingPrimaryRoles;

  /// The roles this programme actually declares.
  Set<MovementRole> get declaredRoles =>
      {for (final s in sessions) ...s.slots};
}

/// One exercise, placed.
class PlannedExercise {
  const PlannedExercise({
    required this.exercise,
    required this.role,
    required this.sets,
  });

  final ExerciseItem exercise;
  final MovementRole role;
  final int sets;
}

/// One session of a built programme.
class PlannedSession {
  const PlannedSession({
    required this.week,
    required this.dayIndex,
    required this.specName,
    required this.exercises,
  });

  final int week;
  final int dayIndex;
  final String specName;
  final List<PlannedExercise> exercises;

  int get totalSets =>
      exercises.fold(0, (sum, e) => sum + e.sets);
}

/// Why a programme could not be built, or why a built one is invalid.
enum ProgrammeFault {
  /// The safety layer refuses this person any training at all.
  blockedBySafety,

  /// No eligible candidate exists for a declared role.
  ///
  /// Reported as an ADAPTATION on a successful build, not as a refusal.
  /// Measured on the shipped catalogue: a reported knee injury removes all 95
  /// squat candidates and a reported shoulder injury removes all 86 overhead
  /// press candidates. Refusing the whole programme for that would tell a
  /// person with a sore knee that they may not train, which is both false and
  /// the opposite of what an injury-aware app is for. What the programme may
  /// not do is pretend the slot was filled.
  roleUnfillable,

  /// After adaptation, too little of the programme's own structure survives
  /// for it to be the programme it claims to be.
  ///
  /// The honest floor under [roleUnfillable]. A "strength base" left with core
  /// work and stretches is exactly the defect this gate removes, so it refuses
  /// rather than shipping under the title.
  structureNotViable,

  /// A session came out with nothing in it.
  emptySession,

  /// A role the spec declares appears fewer than [ProgrammeSpec
  /// .minWeeklyFrequencyPerRole] times in a week.
  frequencyBelowTarget,

  /// Weekly programmed sets for a role fall outside the configured band.
  volumeOutOfBand,

  /// The same exercise appears more than once in one session.
  repeatWithinSession,

  /// Two sessions in the same week are identical.
  duplicateSession,

  /// A step after construction — a ranker, a reviewer — produced an exercise
  /// the eligibility layer had excluded.
  ///
  /// The one fault that must never be reachable by design, and is checked
  /// anyway. See [validateProgramme].
  ineligibleExerciseIncluded,

  /// The programme has no declared role structure, so there is nothing to
  /// build it from.
  ///
  /// G-E. Until this existed, `programmeSpecFor` returning null routed the
  /// enrolment to `buildProgrammeSchedule`, which walked the catalogue in
  /// alphabetical order and called the result a programme. Every shipped
  /// template now has a spec — `programme_builder_test.dart` asserts it, and
  /// asserts each one actually builds — so this is reachable only by a
  /// template id that is not shipped: a stored enrolment from an older build,
  /// or a row written by hand.
  ///
  /// It refuses rather than falling back, and that IS the fix. "We cannot
  /// build this programme" is a true statement a user can act on; a plausible
  /// alphabetical list under a strength title is not.
  noDeclaredStructure,
}

/// A structural complaint about a programme.
class ProgrammeFinding {
  const ProgrammeFinding(this.fault, {this.role, this.detail});

  final ProgrammeFault fault;
  final MovementRole? role;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is ProgrammeFinding &&
      other.fault == fault &&
      other.role == role &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(fault, role, detail);

  @override
  String toString() => 'ProgrammeFinding(${fault.name}'
      '${role != null ? ', ${role!.name}' : ''}'
      '${detail != null ? ', $detail' : ''})';
}

/// A programme, or a refusal.
sealed class ProgrammeBuildResult {
  const ProgrammeBuildResult();
}

final class ProgrammeBuilt extends ProgrammeBuildResult {
  const ProgrammeBuilt(this.sessions, {this.adaptations = const []});
  final List<PlannedSession> sessions;

  /// What the programme could not do for this person, and did not pretend to.
  ///
  /// Surfaced rather than swallowed: a user whose knee removed every squat is
  /// owed the sentence "your programme has no squat in it because you told us
  /// about your knee", and a silent omission reads as an oversight.
  final List<ProgrammeFinding> adaptations;
}

/// No programme. Explicit, with the findings that stopped it.
///
/// The alternative — returning a programme that does not satisfy its own spec —
/// is what shipped: 32 sessions of yoga under a strength title, which nothing
/// could report because nothing was checking.
final class ProgrammeRefused extends ProgrammeBuildResult {
  const ProgrammeRefused(this.findings);
  final List<ProgrammeFinding> findings;
}

/// Everything a build needs.
class ProgrammeBuildRequest {
  const ProgrammeBuildRequest({
    required this.spec,
    required this.catalogue,
    required this.safety,
    required this.weeks,
    required this.daysPerWeek,
    this.rank,
  });

  final ProgrammeSpec spec;

  /// The unfiltered catalogue. Filtering happens HERE, through the one
  /// eligibility layer, rather than being the caller's responsibility — which
  /// is how the previous builder ended up trusting that somebody upstream had
  /// remembered.
  final List<ExerciseItem> catalogue;

  final SafetyContext safety;
  final int weeks;
  final int daysPerWeek;

  /// Optional personalisation: orders candidates within a role, best first.
  ///
  /// **This is the only door a learned signal comes through, and it is a
  /// permutation.** It receives a list that is already eligible and must return
  /// the same elements. A reordering cannot introduce an unsafe exercise; that
  /// is a property of the type, not a promise about the implementation, which
  /// is why the ML/AI stage is expressed this way rather than as a
  /// "suggest exercises" callback.
  ///
  /// [validateProgramme] re-checks the output against the eligibility layer
  /// anyway. A ranker that returns something it was not given is caught rather
  /// than trusted.
  final List<ExerciseItem> Function(MovementRole, List<ExerciseItem>)? rank;
}

/// Builds, then validates. Returns [ProgrammeRefused] if either stage fails.
/// Whether [candidate] holds exactly the objects in [original], reordered.
///
/// Identity, deliberately: `ExerciseItem` has no value equality, and even if it
/// did, "equal to a catalogue row" is a weaker statement than "is the catalogue
/// row". The whole point of the check is that a ranker cannot introduce an
/// object the eligibility layer never saw.
bool _isPermutationOf(List<ExerciseItem> candidate, List<ExerciseItem> original) {
  if (candidate.length != original.length) return false;
  final remaining = List<ExerciseItem>.of(original);
  for (final e in candidate) {
    var found = false;
    for (var i = 0; i < remaining.length; i++) {
      if (identical(remaining[i], e)) {
        remaining.removeAt(i);
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return remaining.isEmpty;
}

ProgrammeBuildResult buildProgramme(ProgrammeBuildRequest request) {
  final spec = request.spec;

  if (!request.safety.allowsAnyTraining) {
    return const ProgrammeRefused([ProgrammeFinding(ProgrammeFault.blockedBySafety)]);
  }
  if (request.weeks <= 0 || request.daysPerWeek <= 0 || spec.sessions.isEmpty) {
    return const ProgrammeRefused([ProgrammeFinding(ProgrammeFault.emptySession)]);
  }

  final eligible = eligibleExercises(request.catalogue, request.safety);
  final pools = byMovementRole(eligible);

  // Deterministic order before any ranking, so an unranked build is
  // reproducible from a bug report rather than dependent on catalogue order.
  for (final list in pools.values) {
    list.sort((a, b) => a.id.compareTo(b.id));
  }

  // A role with no eligible candidate is DROPPED from every session and
  // reported, rather than aborting the build. See [ProgrammeFault
  // .roleUnfillable] for the measurement that forced this.
  final adaptations = <ProgrammeFinding>[
    for (final role in spec.declaredRoles)
      if ((pools[role] ?? const []).isEmpty)
        ProgrammeFinding(ProgrammeFault.roleUnfillable, role: role),
  ];
  final trainable = spec.declaredRoles
      .where((r) => (pools[r] ?? const []).isNotEmpty)
      .toSet();
  final survivingPrimary = trainable.intersection(kPrimaryStrengthRoles);
  if (survivingPrimary.length < spec.minSurvivingPrimaryRoles) {
    return ProgrammeRefused([
      ...adaptations,
      ProgrammeFinding(ProgrammeFault.structureNotViable,
          detail: '${survivingPrimary.length} primary role(s) trainable, '
              '${spec.minSurvivingPrimaryRoles} required'),
    ]);
  }

  // Personalisation, applied per role and constrained to a permutation.
  final ranked = <MovementRole, List<ExerciseItem>>{};
  for (final entry in pools.entries) {
    final out = request.rank?.call(entry.key, List.of(entry.value)) ??
        entry.value;
    // A ranker that adds, drops or substitutes is ignored rather than obeyed.
    // Its job is order; anything else is the safety boundary moving, and the
    // deterministic list is what the programme is built from.
    //
    // Compared by IDENTITY, not by id. An id-set check accepts a list of
    // freshly built `ExerciseItem`s carrying the right ids and forged
    // `contraindications` / `equipmentId` — and those forged objects are what
    // the rest of this function would then plan, validate and schedule, so
    // `validateProgramme` would be re-checking the ranker's own fields instead
    // of the catalogue row. A ranker may hand back the objects it was given,
    // in whatever order it likes, and nothing else.
    ranked[entry.key] = _isPermutationOf(out, entry.value) ? out : entry.value;
  }

  final sessions = <PlannedSession>[];
  var cursor = 0;
  for (var week = 0; week < request.weeks; week++) {
    for (var day = 0; day < request.daysPerWeek; day++) {
      final template = spec.sessions[(week * request.daysPerWeek + day) %
          spec.sessions.length];
      final used = <String>{};
      final picked = <PlannedExercise>[];
      for (final role in template.slots) {
        final pool = ranked[role];
        if (pool == null || pool.isEmpty) continue;
        // Rotate through the pool as the programme runs, so week 8 is not week
        // 1. Never repeats within a session: the offset walks forward until it
        // finds something unused, which is bounded by the pool length.
        ExerciseItem? choice;
        for (var probe = 0; probe < pool.length; probe++) {
          final candidate = pool[(cursor + probe) % pool.length];
          if (used.add(candidate.id)) {
            choice = candidate;
            break;
          }
        }
        if (choice == null) continue;
        picked.add(PlannedExercise(
            exercise: choice, role: role, sets: spec.setsPerSlot));
        cursor++;
      }
      sessions.add(PlannedSession(
        week: week,
        dayIndex: day,
        specName: template.name,
        exercises: List.unmodifiable(picked),
      ));
    }
  }

  final findings = validateProgramme(sessions, spec, request,
      trainableRoles: trainable);
  if (findings.isNotEmpty) {
    return ProgrammeRefused([...adaptations, ...findings]);
  }
  return ProgrammeBuilt(List.unmodifiable(sessions),
      adaptations: List.unmodifiable(adaptations));
}

/// Structural validation. A programme is not valid because generation returned.
///
/// Runs against the FINISHED sessions, so it catches anything a later stage did
/// to them — a ranker, an AI review, a hand edit. That is the reason it re-runs
/// the eligibility check it could in principle trust the builder for.
List<ProgrammeFinding> validateProgramme(
  List<PlannedSession> sessions,
  ProgrammeSpec spec,
  ProgrammeBuildRequest request, {
  /// Roles that had candidates. Frequency and volume are only checked for
  /// these — a role the user's own restrictions removed is an adaptation, and
  /// reporting it a second time as a frequency failure would refuse every
  /// injured user a programme.
  Set<MovementRole>? trainableRoles,
}) {
  final findings = <ProgrammeFinding>[];
  if (sessions.isEmpty) {
    return const [ProgrammeFinding(ProgrammeFault.emptySession)];
  }

  for (final s in sessions) {
    if (s.exercises.isEmpty) {
      findings.add(ProgrammeFinding(ProgrammeFault.emptySession,
          detail: 'week ${s.week} day ${s.dayIndex}'));
      continue;
    }
    final ids = <String>{};
    for (final e in s.exercises) {
      if (!ids.add(e.exercise.id)) {
        findings.add(ProgrammeFinding(ProgrammeFault.repeatWithinSession,
            role: e.role, detail: e.exercise.id));
      }
      // The check that must never fire, and fires loudly if a later stage ever
      // reintroduces something the safety layer excluded.
      if (!evaluateExercise(e.exercise, request.safety,
              includeWholePerson: false)
          .isAllowed) {
        findings.add(ProgrammeFinding(
            ProgrammeFault.ineligibleExerciseIncluded,
            role: e.role,
            detail: e.exercise.id));
      }
      if (movementRoleOf(e.exercise) != e.role) {
        findings.add(ProgrammeFinding(ProgrammeFault.roleUnfillable,
            role: e.role, detail: e.exercise.id));
      }
    }
  }

  // Per week: frequency and volume, plus duplicate sessions.
  final byWeek = <int, List<PlannedSession>>{};
  for (final s in sessions) {
    (byWeek[s.week] ??= []).add(s);
  }
  final trainable = trainableRoles ?? spec.declaredRoles;
  // Frequency is asked only of the roles the spec names, because a spec that
  // schedules a core slot once a week is making a deliberate choice.
  final frequencyChecked =
      spec.declaredRoles.intersection(spec.frequencyRoles).intersection(trainable);
  // Volume is asked of EVERY declared, trainable role. The two used to share
  // one set, so `volumeOutOfBand` could not fire for a role outside
  // `frequencyRoles` — with the default `kPrimaryStrengthRoles` that is both
  // core roles, whose weekly sets were therefore never bounded at all. A fault
  // documented as "weekly programmed sets fall outside the configured band"
  // has to mean every role that has weekly programmed sets.
  final volumeChecked = spec.declaredRoles.intersection(trainable);
  for (final week in byWeek.entries) {
    final frequency = <MovementRole, int>{};
    final volume = <MovementRole, int>{};
    final signatures = <String>{};
    for (final s in week.value) {
      final signature =
          (s.exercises.map((e) => e.exercise.id).toList()..sort()).join(',');
      if (!signatures.add(signature) && week.value.length > 1) {
        findings.add(ProgrammeFinding(ProgrammeFault.duplicateSession,
            detail: 'week ${s.week}'));
      }
      final rolesToday = <MovementRole>{};
      for (final e in s.exercises) {
        rolesToday.add(e.role);
        volume[e.role] = (volume[e.role] ?? 0) + e.sets;
      }
      for (final r in rolesToday) {
        frequency[r] = (frequency[r] ?? 0) + 1;
      }
    }
    for (final role in frequencyChecked) {
      final f = frequency[role] ?? 0;
      if (f < spec.minWeeklyFrequencyPerRole) {
        findings.add(ProgrammeFinding(ProgrammeFault.frequencyBelowTarget,
            role: role, detail: 'week ${week.key}: $f'));
      }
    }
    for (final role in volumeChecked) {
      final v = volume[role] ?? 0;
      if (v < spec.minWeeklySetsPerRole || v > spec.maxWeeklySetsPerRole) {
        findings.add(ProgrammeFinding(ProgrammeFault.volumeOutOfBand,
            role: role, detail: 'week ${week.key}: $v sets'));
      }
    }
  }
  return List.unmodifiable(findings);
}

/// What a built programme actually contains.
///
/// Exists so a test can assert INVARIANTS — role coverage, frequency, volume —
/// instead of an expected list of exercise ids, which would pin the programme
/// to today's catalogue and go red on every vendor update.
class ProgrammeReport {
  const ProgrammeReport({
    required this.sessions,
    required this.uniqueExercises,
    required this.roles,
    required this.weeklyFrequency,
    required this.weeklySets,
  });

  final int sessions;
  final int uniqueExercises;
  final Set<MovementRole> roles;

  /// Sessions per week containing each role, averaged over the whole run and
  /// floored — the honest figure for a programme whose week is not uniform.
  final Map<MovementRole, int> weeklyFrequency;

  final Map<MovementRole, int> weeklySets;

  @override
  String toString() => 'ProgrammeReport(sessions: $sessions, '
      'unique: $uniqueExercises, roles: ${roles.map((r) => r.name).toList()}, '
      'frequency: ${weeklyFrequency.map((k, v) => MapEntry(k.name, v))}, '
      'sets: ${weeklySets.map((k, v) => MapEntry(k.name, v))})';
}

ProgrammeReport reportOn(List<PlannedSession> sessions) {
  final weeks = sessions.map((s) => s.week).toSet();
  final weekCount = weeks.isEmpty ? 1 : weeks.length;
  final frequency = <MovementRole, int>{};
  final sets = <MovementRole, int>{};
  final unique = <String>{};
  for (final s in sessions) {
    final rolesToday = <MovementRole>{};
    for (final e in s.exercises) {
      unique.add(e.exercise.id);
      rolesToday.add(e.role);
      sets[e.role] = (sets[e.role] ?? 0) + e.sets;
    }
    for (final r in rolesToday) {
      frequency[r] = (frequency[r] ?? 0) + 1;
    }
  }
  return ProgrammeReport(
    sessions: sessions.length,
    uniqueExercises: unique.length,
    roles: {for (final e in frequency.keys) e},
    weeklyFrequency:
        frequency.map((k, v) => MapEntry(k, v ~/ weekCount)),
    weeklySets: sets.map((k, v) => MapEntry(k, v ~/ weekCount)),
  );
}

/// Thrown by the enrol action when a programme cannot be built for this user.
///
/// An exception rather than a silently shorter schedule, because the caller is
/// an imperative action whose failure state the UI already renders. What must
/// not happen is a `Programme` row saved with no sessions under it, which is
/// how a user ends up enrolled in nothing.
class ProgrammeNotViable implements Exception {
  const ProgrammeNotViable(this.findings);
  final List<ProgrammeFinding> findings;

  @override
  String toString() => 'ProgrammeNotViable($findings)';
}
