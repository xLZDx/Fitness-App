/// Health answers in the only form this app is allowed to act on: explicit,
/// closed, and stated by the user about themselves.
///
/// ## Why the free text could not be used
///
/// Seven health fields were collected from the first release —
/// `conditions`, `allergies`, `medications`, `physicalLimitations`,
/// `recentSurgeries`, `bloodPressure`, `otherConcerns` — persisted device-local,
/// and read by nothing. Only `injuries` reached the exercise filter.
///
/// The obvious repair is to read the text. Gate M ruled that out and the ruling
/// stands: deciding that "metoprolol" is a beta blocker, that a beta blocker
/// caps heart rate, and that the plan should therefore change is clinical
/// reasoning performed by string matching. It is wrong in both directions — it
/// invents a restriction the user does not have, and misses one they do because
/// they spelled it differently — and the failure is silent.
///
/// So the fields are not parsed. They are asked again, in a form that has a
/// finite answer set and no medical inference in it: what the user cannot do,
/// not what they have.
///
/// ## What the catalogue can and cannot express
///
/// A restriction is only enforceable if the catalogue carries a tag that
/// distinguishes the exercises it applies to. Measured on the shipped catalogue,
/// `contraindications` is a nine-value region vocabulary — shoulder, hip,
/// elbow, knee, lower_back, upper_back, ankle, wrist, neck — and nothing else.
///
/// So `overhead` maps onto `shoulder` and is enforceable. `impact` does not map
/// onto anything: there is no jumping tag, and inferring one from a title would
/// be the same guess this file exists to refuse.
///
/// Both cases are represented. An unenforceable restriction does NOT quietly
/// pass — [MovementRestriction.regionTags] is empty for it, and
/// `eligibility.dart` turns that into a stated advisory rather than a silent
/// no-op. Telling the user "we cannot screen for this, check each session" is
/// the honest output; showing them a filtered list that never filtered is not.
library;

/// What the user has told us they cannot do, in movement terms.
///
/// Deliberately not diagnoses. "Deep knee flexion is limited" is something a
/// person knows about themselves; "you have patellofemoral pain syndrome" is
/// not something this app may conclude.
enum MovementRestriction {
  /// Reaching or pressing above the head.
  overhead(regionTags: {'shoulder', 'neck'}),

  /// Squatting or kneeling past roughly ninety degrees.
  deepKneeFlexion(regionTags: {'knee'}),

  /// Rounding the spine under load — sit-ups, loaded toe-touches, most
  /// crunches.
  loadedSpinalFlexion(regionTags: {'lower_back'}),

  /// Arching the spine — hyperextensions, some yoga backbends.
  spinalExtension(regionTags: {'lower_back', 'upper_back'}),

  /// Bearing weight through the hands and wrists — planks, push-ups,
  /// arm balances.
  wristLoading(regionTags: {'wrist', 'elbow'}),

  /// Jumping, running, anything with a landing.
  ///
  /// **Not enforceable.** No tag in the catalogue distinguishes impact work.
  impact(regionTags: {}),

  /// Standing for long periods.
  ///
  /// **Not enforceable.** Duration is stored, stance is not.
  prolongedStanding(regionTags: {}),

  /// Balance is unreliable — single-leg work, anything on one foot.
  ///
  /// **Not enforceable.** No stability tag exists.
  balance(regionTags: {}),

  /// Something the list above does not cover.
  ///
  /// **Not enforceable by construction**, and that is the point of offering it:
  /// a user whose limitation has no chip must be able to say so and be told the
  /// app cannot screen for it, rather than tick nothing and be told everything
  /// was checked.
  other(regionTags: {});

  const MovementRestriction({required this.regionTags});

  /// Which `ExerciseItem.contraindications` tags this restriction hides.
  ///
  /// Empty means the catalogue cannot express it. See the library doc: empty
  /// is a real answer here, not a missing one.
  final Set<String> regionTags;

  /// Whether the exercise filter can act on this at all.
  bool get isEnforceable => regionTags.isNotEmpty;
}

/// Blood pressure, as the user's own report of what a clinician told them.
///
/// Replaces the three-value `BloodPressure` chip, which offered `low` /
/// `normal` / `high` with no way to say "diagnosed and managed" or "I do not
/// know" — and which nothing read.
enum BloodPressureStatus {
  noKnownIssue,
  diagnosedLow,
  diagnosedHigh,

  /// Diagnosed, and being managed with a clinician's guidance.
  ///
  /// Distinct from [diagnosedHigh] because it is a different risk picture, and
  /// because collapsing them tells a person who is doing everything right that
  /// the app treats them as unmanaged.
  managedWithClinician,

  /// Answered, and the answer is "I do not know".
  ///
  /// Not the same as leaving the question blank, which is [notAnswered] by
  /// absence. This is an explicit statement of uncertainty and is treated the
  /// same as a diagnosis for gating, because uncertainty is not a clean bill.
  unsure,
}

/// Recent surgery, as a state rather than as a list of operations.
enum SurgeryStatus {
  none,

  /// Operated on, and still under restrictions from the surgical team.
  ///
  /// The one health answer in this file that BLOCKS rather than restricting.
  /// Post-operative restrictions are specific, time-limited and issued by
  /// someone who examined the person; a generated programme cannot know what
  /// they are, and "train around it" is not a thing an app may improvise.
  underRestrictions,

  /// Operated on, and discharged back to normal exercise.
  clearedForNormalExercise,

  /// Operated on, and the user does not know whether restrictions still apply.
  unsure,
}

/// What a clinician has said about exercising with the user's conditions or
/// medications.
///
/// One question covering both, because the answer this app can act on is the
/// same for both and asking twice buys nothing. The condition names and
/// medication names stay stored as the user's own words — for their reference
/// and for a clinician they may show it to — and are never read by any rule.
enum ClinicianExerciseAdvice {
  /// Asked, and told there are no exercise limits.
  noLimitsGiven,

  /// Asked, and given limits.
  limitsGiven,

  /// Told not to exercise, or to exercise only under supervision.
  advisedAgainstExercise,

  /// Never asked anyone.
  ///
  /// The commonest honest answer, and not a clean bill of health. Treated as a
  /// restriction rather than a block: blocking every user who has not seen a
  /// doctor would refuse the product to most of the people it is for, and
  /// PAR-Q+ (Gate M) already blocks the answers that warrant it.
  notAsked,
}

/// How much of the health block has been put into a form rules may act on.
///
/// Computed, never stored. A stored flag can disagree with the data it
/// describes; this cannot.
enum HealthNormalisationState {
  /// Nothing entered at all — a new user, or one who skipped the screen.
  notProvided,

  /// The normalised questions have been answered.
  normalised,

  /// Free text exists from a build before the normalised questions did, and
  /// the user has not answered them.
  ///
  /// The text is preserved exactly and is NOT interpreted. The state exists so
  /// the app can say "you told us something we can no longer read; please tell
  /// us again in a form we can act on" — rather than either guessing at it or
  /// pretending the fields were never filled in.
  legacyUnreviewed,
}

/// The normalised half of the health block.
///
/// Kept as its own value rather than as loose fields on `HealthHistory`, so the
/// eligibility layer can be handed exactly what it is allowed to read and
/// nothing else. Passing `HealthHistory` would put the free text within reach
/// of a rule, and within reach is where it eventually gets read.
class HealthFlags {
  const HealthFlags({
    this.restrictions = const {},
    this.bloodPressure,
    this.surgery,
    this.clinicianAdvice,
  });

  final Set<MovementRestriction> restrictions;
  final BloodPressureStatus? bloodPressure;
  final SurgeryStatus? surgery;
  final ClinicianExerciseAdvice? clinicianAdvice;

  static const empty = HealthFlags();

  /// True when none of the normalised questions has been answered.
  ///
  /// An empty [restrictions] set is NOT on its own evidence of this: "I have no
  /// movement restrictions" and "I have not been asked" are different answers
  /// and the set cannot tell them apart. The three enums can, which is why they
  /// are nullable and the set is not.
  bool get isUnanswered =>
      bloodPressure == null && surgery == null && clinicianAdvice == null;

  /// Restrictions the catalogue has no tag for.
  ///
  /// The eligibility layer states these to the user instead of silently
  /// filtering nothing.
  Set<MovementRestriction> get unenforceableRestrictions =>
      {for (final r in restrictions) if (!r.isEnforceable) r};

  /// Every `contraindications` tag the restrictions hide.
  Set<String> get blockedRegionTags => {
        for (final r in restrictions) ...r.regionTags,
      };

  Map<String, dynamic> toJson() => {
        'restrictions': [for (final r in restrictions) r.name],
        'bloodPressure': bloodPressure?.name,
        'surgery': surgery?.name,
        'clinicianAdvice': clinicianAdvice?.name,
      };

  /// Unknown names are DROPPED, not defaulted.
  ///
  /// Same rule as `HealthHistory._readScreening` and for the same reason: a
  /// value this build cannot name is not an answer this build may act on, and
  /// every default available here is a claim about the user's health.
  static HealthFlags fromJson(Object? raw) {
    if (raw is! Map) return empty;
    T? byName<T extends Enum>(List<T> values, Object? name) {
      if (name is! String) return null;
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    final rs = <MovementRestriction>{};
    final list = raw['restrictions'];
    if (list is List) {
      for (final entry in list) {
        final r = byName(MovementRestriction.values, entry);
        if (r != null) rs.add(r);
      }
    }
    return HealthFlags(
      restrictions: Set.unmodifiable(rs),
      bloodPressure:
          byName(BloodPressureStatus.values, raw['bloodPressure']),
      surgery: byName(SurgeryStatus.values, raw['surgery']),
      clinicianAdvice:
          byName(ClinicianExerciseAdvice.values, raw['clinicianAdvice']),
    );
  }

  HealthFlags copyWith({
    Set<MovementRestriction>? restrictions,
    BloodPressureStatus? bloodPressure,
    SurgeryStatus? surgery,
    ClinicianExerciseAdvice? clinicianAdvice,
  }) =>
      HealthFlags(
        restrictions: restrictions ?? this.restrictions,
        bloodPressure: bloodPressure ?? this.bloodPressure,
        surgery: surgery ?? this.surgery,
        clinicianAdvice: clinicianAdvice ?? this.clinicianAdvice,
      );

  @override
  bool operator ==(Object other) =>
      other is HealthFlags &&
      other.bloodPressure == bloodPressure &&
      other.surgery == surgery &&
      other.clinicianAdvice == clinicianAdvice &&
      other.restrictions.length == restrictions.length &&
      other.restrictions.containsAll(restrictions);

  @override
  int get hashCode => Object.hash(
        bloodPressure,
        surgery,
        clinicianAdvice,
        Object.hashAllUnordered(restrictions),
      );

  @override
  String toString() => 'HealthFlags(${restrictions.map((r) => r.name).toList()},'
      ' bp: ${bloodPressure?.name}, surgery: ${surgery?.name},'
      ' advice: ${clinicianAdvice?.name})';
}
