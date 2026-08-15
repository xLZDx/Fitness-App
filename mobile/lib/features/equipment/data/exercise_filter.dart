import '../../profile/data/profile_models.dart';
import 'equipment_models.dart';

/// Pure recommendation utilities for the equipment catalog.
///
/// All inputs are treated as immutable and the returned lists are fresh
/// copies — callers can sort/insert without mutating shared state.

/// Normalises a free-text body part / contraindication tag so that
/// "left knee", "Knee (Right)", and "knee" all collapse to the same token.
String _normaliseTag(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_\s]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
}

/// True when [injury] should hide an exercise tagged with [contraindication].
/// Match is symmetric and substring-aware so "lower_back" matches "back" and
/// vice versa, but unrelated parts ("ankle" vs "shoulder") never collide.
bool _injuryHits(String injury, String contraindication) {
  final a = _normaliseTag(injury);
  final b = _normaliseTag(contraindication);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  return a.contains(b) || b.contains(a);
}

/// True when [exercise] conflicts with any of [injuries].
///
/// The single-item form of [filterContraindicated], and the reason it exists:
/// a deep link, a scheduled session and a reminder each arrive holding one
/// exercise id, never a list. Before this, the only way to ask the question
/// was to build a one-element list and check whether it came back empty —
/// which is why the three of them each ended up not asking it at all.
bool isContraindicated(ExerciseItem exercise, Iterable<Injury> injuries) {
  if (exercise.contraindications.isEmpty) return false;
  for (final c in exercise.contraindications) {
    for (final i in injuries) {
      if (_injuryMatches(i, c)) return true;
    }
  }
  return false;
}

/// Exact on a mapped region, substring on legacy free text.
///
/// A mapped [Injury.region] and an exercise tag are drawn from the same closed
/// vocabulary (`InjuryRegion.tag`, and the tags S3b writes), so comparing them
/// exactly is not a restriction — it is what makes the vocabulary worth
/// having. Substring matching cannot say no: it hits "back" against
/// "lower_back", which is usually right, and "hip" against "ship", which is
/// not, and it gets more expensive to reason about as the catalog gets tagged.
///
/// Unmapped injuries keep the old substring behaviour, because that is all
/// free text supports and every stored injury is free text until S1b migrates
/// it. Neither path ever reads [Injury.note] — text the user wanted recorded
/// is not text the app may screen on.
bool _injuryMatches(Injury injury, String contraindication) {
  final region = injury.region;
  if (region != null) return _normaliseTag(contraindication) == region.tag;
  return _injuryHits(injury.bodyPart, contraindication);
}

/// Drops any exercise whose [ExerciseItem.contraindications] overlaps the
/// user's reported injuries. Exercises with no contraindication tags are
/// always kept.
List<ExerciseItem> filterContraindicated(
  Iterable<ExerciseItem> exercises,
  Iterable<Injury> injuries,
) {
  if (injuries.isEmpty) return exercises.toList(growable: false);
  final list = injuries.toList(growable: false);
  return exercises
      .where((ex) => !isContraindicated(ex, list))
      .toList(growable: false);
}

/// How many exercises in [exercises] carry the tags [filterContraindicated]
/// reads, out of how many there are.
///
/// ## Why a filter needs a coverage number at all
///
/// [filterContraindicated] keeps any exercise with no tags — see
/// `if (ex.contraindications.isEmpty) return true;` above. For one untagged
/// row among many that is the only safe default. When *every* row is untagged
/// the same line makes the filter a total no-op: it runs on every surface,
/// removes nothing, and reports a truthful zero for the wrong reason.
///
/// Measured on the shipped catalog the day this was written: 0 of 1,887
/// exercises carried a single tag, while eight places in the product told the
/// user their injuries were being filtered for. Nothing in the code could have
/// reported that, because a filter that cannot fire is not a bug in the
/// filter. This is the number that reports it.
///
/// That is history now — the tagging batches landed, and the live number is
/// pinned from both sides by `kSafetyCoverageFloor` in
/// `test/features/equipment/safety_coverage_test.dart`, which is deliberately
/// the only place a count is written down. Restating it in prose here is what
/// made this paragraph wrong for months: a comment cannot be raised by a
/// tagging batch, and nothing goes red when it stops being true.
typedef SafetyCoverage = ({int tagged, int total});

SafetyCoverage safetyCoverage(Iterable<ExerciseItem> exercises) {
  var tagged = 0;
  var total = 0;
  for (final e in exercises) {
    total++;
    if (e.contraindications.isNotEmpty) tagged++;
  }
  return (tagged: tagged, total: total);
}

/// How many exercises carry each region's tag.
///
/// ## Why the total is not enough
///
/// [safetyCoverage] answers "can the filter fire at all", which was the right
/// question while the answer was zero. It became the wrong one the moment the
/// first tagging batch landed: 50 tagged knees make `tagged > 0` true for
/// everybody, including a user whose only injury is a shoulder and for whom
/// coverage would still be zero. The honesty banner would disarm and the app
/// would resume telling them their injuries were screened for.
///
/// Every [InjuryRegion] now carries a non-zero count, so no user is in that
/// position today — but the per-region shape is what has to be asked, because
/// "no region is empty" is a fact about this catalogue and not a property of
/// the code.
///
/// A claim about screening is only ever true per injury, so this is the shape
/// the claim has to be evaluated against.
Map<InjuryRegion, int> safetyCoverageByRegion(
  Iterable<ExerciseItem> exercises,
) {
  final counts = {for (final r in InjuryRegion.values) r: 0};
  final byTag = {for (final r in InjuryRegion.values) r.tag: r};
  for (final e in exercises) {
    for (final raw in e.contraindications) {
      final region = byTag[_normaliseTag(raw)];
      if (region != null) counts[region] = counts[region]! + 1;
    }
  }
  return counts;
}

extension SafetyCoverageFraction on SafetyCoverage {
  /// Share of the catalog that carries a tag, 0.0 to 1.0.
  ///
  /// An empty catalog is 0.0 — uncovered, not vacuously complete. The other
  /// choice reads as 100% and would quietly disarm every caller asking "is
  /// coverage below the floor?" at the one moment it matters most: when the
  /// catalog failed to load at all.
  double get fraction => total == 0 ? 0 : tagged / total;
}

int _difficultyRank(ExerciseDifficulty d) {
  switch (d) {
    case ExerciseDifficulty.beginner:
      return 0;
    case ExerciseDifficulty.intermediate:
      return 1;
    case ExerciseDifficulty.advanced:
      return 2;
  }
}

int _tierRank(FitnessTier t) {
  switch (t) {
    // Ranks the same as `beginner`, and that is the whole answer, not a
    // shortcut: the catalogue's easiest grade IS `ExerciseDifficulty.beginner`,
    // so there is nothing below it to sort someone towards. `never` earns its
    // own enum value because a first programme should be built differently, not
    // because a different exercise ordering exists to give it.
    case FitnessTier.never:
    case FitnessTier.beginner:
      return 0;
    case FitnessTier.intermediate:
      return 1;
    case FitnessTier.advanced:
      return 2;
  }
}

/// Stable-sorts so exercises closest to [tier] come first. Beginners see
/// beginner → intermediate → advanced; advanced users see the inverse so
/// challenging work surfaces first.
List<ExerciseItem> sortByTierFit(
  Iterable<ExerciseItem> exercises,
  FitnessTier? tier,
) {
  final list = exercises.toList();
  if (tier == null) return list;
  final target = _tierRank(tier);
  list.sort((a, b) {
    final da = (_difficultyRank(a.difficulty) - target).abs();
    final db = (_difficultyRank(b.difficulty) - target).abs();
    if (da != db) return da.compareTo(db);
    // Within the same distance, prefer the easier one for beginners and
    // the harder one for advanced users.
    if (target == 0) {
      return _difficultyRank(a.difficulty).compareTo(_difficultyRank(b.difficulty));
    }
    if (target == 2) {
      return _difficultyRank(b.difficulty).compareTo(_difficultyRank(a.difficulty));
    }
    return 0;
  });
  return list;
}

/// Only the exercises the app can demonstrate with a moving picture.
///
/// ## Why a photograph is not an acceptable fallback
///
/// The catalog used to demonstrate an exercise three ways: a clip, two bundled
/// frames looped by `ExerciseDemo`, or two network stills shown the same way.
/// The last two look like a fallback in code and like a different app on
/// screen — they are photographs of a man in a gym, while every clip is a 3D
/// render on flat white. Operator, twice: *"я до сих пор вижу старые картинки
/// место роликов, я просил их всех убрать чтобы было все одинаково"*.
///
/// Measured before writing this: of 511 exercises, 365 carry a clip, 94 are
/// demonstrated by network photographs, 42 by bundled photographs, and 10 by
/// nothing at all. Both sets of "frames" are photographs — the bundled ones
/// came from the same free-exercise-db import as the network ones, so calling
/// them animation was only ever true of the mechanism, never of the content.
///
/// That leaves exactly one rule that satisfies "only animation": an exercise
/// the app cannot play is an exercise the app does not show. 146 entries of the
/// 511 fall out, which is the honest size of the gap rather than a number
/// softened by putting a photograph in front of it.
///
/// The test mirrors the player's own chain exactly —
/// `playableVideoFor(body) ?? videoUrl` — rather than `hasVideo`. An entry must
/// never pass this filter and then fail to produce anything on screen, and it
/// must never be hidden while the player would happily have played it.
///
/// The `videoUrl` half matters even though no shipped row uses it today: it is
/// the older singular field, the player still honours it, and leaving it out
/// here made a perfectly playable exercise vanish from every list. Two tests
/// caught that within a minute of the filter being written.
List<ExerciseItem> withDemonstration(Iterable<ExerciseItem> exercises) =>
    exercises
        .where((e) => e.playableVideoFor(null) != null || e.videoUrl != null)
        .toList(growable: false);

/// Safety only: contraindicated exercises removed, order left exactly as
/// given.
///
/// Split out of [recommended], which fused this with [sortByTierFit] and gave
/// callers no way to take one without the other. Everything that needs the
/// safety guarantee but has its own idea of ordering — the For-you ranker, the
/// offline prefetch list, a single deep-linked exercise — was therefore
/// choosing between "ranked twice" and "not screened at all", and more than
/// one of them chose the second.
///
/// A null [profile] returns the input untouched. That is correct for a signed-
/// out user, who has no injuries to screen against, and catastrophic for a
/// user whose profile merely has not arrived yet — see
/// `screeningProfileProvider`, which is why no caller passes a sampled
/// `.valueOrNull` any more.
List<ExerciseItem> safeFor(
  Iterable<ExerciseItem> exercises,
  UserProfile? profile,
) {
  if (profile == null) return exercises.toList(growable: false);
  return filterContraindicated(exercises, profile.health.injuries);
}

/// The catalogue muscle tokens a questionnaire focus zone stands for.
///
/// [FocusZone] (`profile_models.dart`) is the vocabulary the user picks from;
/// `ExerciseItem.muscles` is the vendor's. They are not the same list and never
/// will be — "arms" is one chip and three tokens.
///
/// Deliberately the SAME grouping `kFilterMuscles` (`workouts_page.dart:76-84`)
/// already uses for the Train tab's chips, rather than a second table saying
/// the same thing. Two tables mapping one vocabulary onto another drift, and
/// the day they drifted a user would see one set of exercises under "Arms" on
/// one screen and a different set under "Arms" on another. They are not merged
/// into one constant only because `WorkoutsFilter` is a UI enum that also
/// carries `forYou` and `machines`, which are not muscles at all.
///
/// Measured against the shipped catalogue before this was written: the vendor
/// tags exercises with exactly 15 muscle tokens, and every one of them appears
/// below. No zone resolves to a token nothing is tagged with.
///
/// [FocusZone.fullBody] returns the empty set. "Everything" is the absence of a
/// restriction, not a sixteenth muscle — and a caller that treated it as one
/// would filter the catalogue down to nothing.
Set<String> focusZoneMuscles(FocusZone zone) => switch (zone) {
      FocusZone.chest => const {'chest'},
      FocusZone.back => const {'back', 'lats', 'traps', 'lower_back'},
      FocusZone.shoulders => const {'shoulders'},
      FocusZone.arms => const {'biceps', 'triceps', 'forearms'},
      FocusZone.core => const {'core'},
      FocusZone.glutes => const {'glutes'},
      FocusZone.legs => const {'quads', 'hamstrings', 'calves', 'adductors'},
      FocusZone.fullBody => const {},
    };

/// Which vendor equipment labels each questionnaire chip covers.
///
/// The labels are the vendor's own free text, and there are 99 distinct values
/// across the 1,887 shipped rows. Matching is EXACT on the lower-cased label,
/// never by substring, for the same reason `_furnitureNotEquipment`
/// (`equipment_models.dart:86`) is an exact set: a substring rule for
/// [EquipmentKind.barbell] would match "bar" inside "Pull Up Bar" and quietly
/// promise a home user a pull-up bar they never said they own. The one label
/// that appears in both cases and letters ("Smith Machine" / "Smith machine",
/// "Weight Plate" / "weight plate", "Ab Roller" / "Ab roller") is handled by
/// lower-casing, not by a second entry.
///
/// [EquipmentKind.bodyweight] maps to nothing on purpose: an exercise that
/// needs no equipment is admitted by [availableWith] unconditionally, before
/// this table is ever consulted. [EquipmentKind.fullGym] is likewise absent —
/// it short-circuits the whole filter.
const Map<EquipmentKind, Set<String>> _kindLabels = {
  EquipmentKind.dumbbells: {'dumbbells', 'dumbbell'},
  EquipmentKind.barbell: {
    'barbell',
    'bar',
    'ez bar',
    'trap bar',
    'fixed pole bar',
    'weight plate',
    // A landmine is a barbell in a pivot; without the bar there is nothing to
    // put in it.
    'landmine',
  },
  EquipmentKind.kettlebells: {'kettlebells'},
  EquipmentKind.bands: {
    'resistance band',
    'loop resistance band',
    'resistance cable',
  },
  // Gym apparatus that does not have the word "machine" in its label. Anything
  // that DOES is caught by the substring rule in [_partCovered] instead.
  EquipmentKind.machines: {
    'sled',
    'treadmill',
    'airbike',
    'ski ergometer',
    'stationary exercise bike',
    'hyperextension bench',
  },
};

/// True when one comma-separated piece of an equipment label is covered by the
/// kit the user says they have.
///
/// "machine" is matched as a SUBSTRING, and it is the only one that is. The
/// asymmetry is deliberate and safe in a way the others are not: every label
/// containing the word is a gym machine, so over-matching can only ever hit
/// something [EquipmentKind.machines] genuinely covers. There are 30-odd such
/// labels and the vendor adds more with every catalogue update; enumerating
/// them would be a list that silently rots into under-matching, which fails in
/// the direction of hiding exercises a gym user can do.
bool _partCovered(String part, Set<EquipmentKind> kinds) {
  final p = part.trim().toLowerCase();
  if (p.isEmpty) return true;
  if (kinds.contains(EquipmentKind.machines) && p.contains('machine')) {
    return true;
  }
  for (final k in kinds) {
    if (_kindLabels[k]?.contains(p) ?? false) return true;
  }
  return false;
}

/// Only the exercises the user can actually perform with what they told the
/// questionnaire they have.
///
/// ## Why this runs before the schedule is generated, not inside it
///
/// Equipment is a hard constraint, not a preference. `buildProgrammeSchedule`
/// relaxes a constraint rather than dropping a day when a slot has no
/// candidates (`programme_schedule.dart`, the muscle fallback), which is right
/// for a muscle — a chest day that becomes a general day is still a workout —
/// and wrong for equipment: relaxing it hands a barbell bench press to someone
/// who owns a resistance band. Filtering the catalogue BEFORE generation makes
/// that structurally impossible instead of relying on the generator to
/// remember, because the unavailable rows are not in the list it draws from.
///
/// ## What counts as available
///
/// * A gym answer — [TrainingLocation.gym], [TrainingLocation.mixed], or the
///   [EquipmentKind.fullGym] chip — allows everything. A gym has the machines.
/// * An exercise that needs nothing (`ExerciseItem.needsEquipment`) is always
///   allowed. Anyone can do a push-up, whatever they ticked.
/// * Otherwise every comma-separated part of the vendor's label must be
///   covered by a chip the user selected. All parts, not any: "Barbell, Box"
///   needs both.
///
/// ## "Nothing selected" is two different answers, and they are not the same
///
/// A profile with no location AND no chips has told us nothing, and returns
/// everything untouched: "has not told us yet" is not "owns nothing", and
/// reading it as the latter would generate a bodyweight-only programme for a
/// gym member who skipped one screen — the null-means-two-things trap
/// `screeningProfileProvider` (`equipment_providers.dart:44-64`) exists to
/// avoid on the safety side.
///
/// But a profile that names [TrainingLocation.home] or
/// [TrainingLocation.outdoor] and ticks no chips has answered, and its answer
/// is "nothing" — so it gets bodyweight work only. Keying this on the chips
/// alone was wrong in exactly the commonest real flow: the onboarding step
/// counts as answered the moment a location is tapped (`step_answered.dart:157`,
/// `e.location != null || ...`), the chips are never required, so tapping
/// "Home" and pressing Next produced a profile the app calls answered — and a
/// programme full of barbell work for someone who never claimed a barbell.
///
/// [EquipmentKind.cameraScan] is dropped before anything is matched, because it
/// is an intention rather than a possession — required by that enum's own doc
/// (`profile_models.dart:586-589`).
///
/// ## The 89 rows that contradict themselves
///
/// Measured on the shipped catalogue: 535 rows carry a "None"/"none"/"None
/// (Bodyweight)" label, and 89 of those ALSO carry an `equipmentId` (27 of them
/// `bench_press`). `needsEquipment` believes the id, so those rows arrive here
/// claiming both. They are treated as needing the equipment: a label reading
/// "None" on a row that names a bench press is the half more likely to be the
/// data-entry mistake, and the cost of being wrong is a missing exercise rather
/// than a user under a barbell they do not own.
List<ExerciseItem> availableWith(
  Iterable<ExerciseItem> exercises,
  EquipmentAccess access,
) =>
    exercises
        .where((e) => isAvailableWith(e, access))
        .toList(growable: false);

/// The single-exercise form of [availableWith].
///
/// Extracted in Gate N so the eligibility layer (`safety/data/eligibility.dart`)
/// can ask the equipment question about ONE candidate without building a
/// one-element list — the same reason [isContraindicated] exists beside
/// [filterContraindicated], and the same failure it prevents: measured before
/// this existed, equipment was applied on two of the six surfaces that surface
/// exercises, because the only way to ask was to call a list filter and four
/// call sites simply did not.
///
/// All of the reasoning in [availableWith]'s doc lives here now, because this
/// is where the decision is made.
bool isAvailableWith(ExerciseItem e, EquipmentAccess access) {
  final kinds =
      access.available.where((k) => k != EquipmentKind.cameraScan).toSet();
  final atGym = access.location == TrainingLocation.gym ||
      access.location == TrainingLocation.mixed ||
      kinds.contains(EquipmentKind.fullGym);
  if (atGym) return true;
  // Neither half of the question answered — see the doc above. With a location
  // named, an empty chip list is the answer "nothing", and filtering proceeds.
  if (access.location == null && kinds.isEmpty) return true;

  if (!e.needsEquipment) return true;
  final label = e.equipmentLabel;
  if (label == null || label.trim().isEmpty) return false;
  final parts = label.split(',');
  // The contradiction described above: the label says nothing is needed while
  // an `equipmentId` names a machine. Believe the id.
  if (e.equipmentId != null &&
      parts.every((p) => p.trim().toLowerCase().startsWith('none'))) {
    return false;
  }
  return parts.every((p) => _partCovered(p, kinds));
}

/// Full pipeline: hide contraindicated exercises, then surface tier-fit ones
/// first. Profile may be null (returns the input untouched, copied).
///
/// Deliberately does NOT apply [withDemonstration]. The two filters answer
/// different questions and their counts are reported separately —
/// `RecommendedExercises.hiddenForInjury` means "hidden because of your
/// injuries", and folding an undemonstrable exercise into that number would
/// tell the user their knee is why a treadmill walk is missing.
List<ExerciseItem> recommended(
  Iterable<ExerciseItem> exercises,
  UserProfile? profile,
) {
  if (profile == null) return exercises.toList(growable: false);
  return sortByTierFit(safeFor(exercises, profile), profile.level.tier);
}
