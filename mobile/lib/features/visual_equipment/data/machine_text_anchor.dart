/// B5b — identify a machine by the text printed ON the machine.
///
/// ## Why this exists
///
/// Measured on the operator's own 30 gym photos (2026-08-07,
/// `core/plans/B1_RECOGNITION_MEASUREMENT_2026-08-07.md` and the v2 eval):
///
/// - 18 of 30 frames carry the machine's name legibly on its own shroud or
///   instruction placard — `ABDUCTION / ADDUCTION`, `PEC FLY / REAR DELT`,
///   `ABDOMINAL`, `Leg Curl`, `ROW`, `SHOULDER`.
/// - The v2 classifier scored **5 of those same 18** on top-3.
///
/// The printed name was three times the signal the network was. That is not
/// luck: Nautilus, Star Trac, Precor, Technogym and Life Fitness all print the
/// exercise on the shroud because the gym's own members need it.
///
/// ## What this is NOT
///
/// It is not a replacement for the classifier and it must never become a
/// requirement. People photograph machines from wherever they are standing,
/// and half the time no text is in frame. This is an ADDITIONAL anchor that
/// is near-certain when it fires and silent when it does not — which is the
/// opposite failure mode to a 29-way softmax that always answers something.
///
/// ## Why the matching lives here and not in the ML Kit wrapper
///
/// Everything below is a pure function over a string. It is the part that can
/// be wrong in interesting ways, so it is the part that has to be testable
/// without a device, a camera or a plugin.
library;

/// A machine identified from text found on it.
class TextAnchorMatch {
  const TextAnchorMatch({
    required this.equipmentId,
    required this.matchedPhrase,
    required this.confidence,
  });

  final String equipmentId;

  /// The phrase that produced the match, as it was found. Shown to the user
  /// ("прочитано на тренажёре: ABDOMINAL") because an identification the user
  /// can check beats one they have to trust.
  final String matchedPhrase;

  /// Deliberately coarse — see [_kExact] and [_kPhrases]. This is not a
  /// probability and must not be rendered as a percentage next to the
  /// classifier's softmax, which IS one.
  final double confidence;

  @override
  String toString() =>
      'TextAnchorMatch($equipmentId, "$matchedPhrase", $confidence)';
}

/// Words that appear on nearly every machine of a given make and therefore
/// identify nothing. Left in the text they would let `INSPIRATION STRENGTH`
/// anchor whatever the phrase table happened to list first.
///
/// Brand names are stripped rather than merely ignored so they cannot form
/// part of a longer accidental match.
const Set<String> _kNoise = {
  'nautilus', 'inspiration', 'instinct', 'strength', 'startrac', 'star',
  'trac', 'precor', 'technogym', 'life', 'fitness', 'impact', 'matrix',
  'hammer', 'cybex', 'gym', 'series', 'pro', 'plus', 'max', 'model',
  'warning', 'caution', 'danger', 'read', 'instructions', 'before', 'use',
  'muscles', 'worked', 'lock', 'load', 'technology', 'adjust', 'seat',
  'start', 'finish', 'www', 'com', 'made', 'usa', 'patent', 'capacity',
  'weight', 'stack', 'lbs', 'kg',
};

/// Phrase -> catalogue id, for what manufacturers actually print.
///
/// The catalogue calls it `pec_deck`; the machine says `PEC FLY / REAR DELT`.
/// The catalogue says `hip_abductor_adductor`; the machine says
/// `ABDUCTION / ADDUCTION`. Every row here is a real string read off a real
/// machine in the operator's photos or from the manufacturer's public
/// placard artwork — none is invented, because a guessed phrase produces a
/// confident wrong answer, which is the exact defect this whole gate exists
/// to remove.
///
/// Keys are normalised (lowercase, letters and single spaces only).
const Map<String, String> _kPhrases = {
  // Read directly off the operator's photos.
  'abduction adduction': 'hip_abductor_adductor',
  'adduction abduction': 'hip_abductor_adductor',
  'hip abduction': 'hip_abductor_adductor',
  'hip adduction': 'hip_abductor_adductor',
  'pec fly rear delt': 'pec_deck',
  'pec fly': 'pec_deck',
  'rear delt': 'pec_deck',
  'chest fly': 'pec_deck',
  'leg curl': 'leg_curl',
  'seated leg curl': 'leg_curl',
  'prone leg curl': 'leg_curl',
  'lying leg curl': 'leg_curl',
  'leg extension': 'leg_extension',
  'leg press': 'leg_press',
  'lat pulldown': 'lat_pulldown',
  'lat pull down': 'lat_pulldown',
  'pulldown': 'lat_pulldown',
  'shoulder press': 'shoulder_press_machine',
  'chest press': 'chest_press_machine',
  'seated row': 'seated_row_machine',
  'low row': 'seated_row_machine',
  'high row': 'seated_row_machine',
  'abdominal': 'ab_crunch_machine',
  'ab crunch': 'ab_crunch_machine',
  'abdominal crunch': 'ab_crunch_machine',
  'back extension': 'back_extension',
  'lower back': 'back_extension',
  'torso rotation': 'rotary_torso_machine',
  'rotary torso': 'rotary_torso_machine',
  'torso twist': 'rotary_torso_machine',
  'biceps curl': 'bicep_curl_machine',
  'bicep curl': 'bicep_curl_machine',
  'arm curl': 'bicep_curl_machine',
  'triceps extension': 'tricep_extension_machine',
  'tricep extension': 'tricep_extension_machine',
  'triceps press': 'tricep_extension_machine',
  'lateral raise': 'lateral_raise_machine',
  'calf raise': 'calf_raise_machine',
  'seated calf': 'calf_raise_machine',
  'chin dip assist': 'assisted_pullup_machine',
  'chin dip': 'assisted_pullup_machine',
  'assisted chin': 'assisted_pullup_machine',
  'hack squat': 'hack_squat_machine',
  'smith machine': 'smith_machine',
  'glute kickback': 'glute_kickback_machine',
  'hip thrust': 'hip_thrust_machine',
  'preacher curl': 'preacher_curl_bench',
  'power cage': 'squat_rack',
  'squat rack': 'squat_rack',
  'power rack': 'squat_rack',
  'freedom rack': 'squat_rack',
  'functional trainer': 'cable_machine',
  'cable crossover': 'cable_machine',
  'stepmill': 'stair_climber',
  'stair climber': 'stair_climber',
  'stairmaster': 'stair_climber',
  'elliptical': 'elliptical',
  'treadmill': 'treadmill',
  'rowing machine': 'rowing_machine',
  'recumbent bike': 'recumbent_bike',
  'upright bike': 'exercise_bike',
  'leg raise': 'captains_chair',
  'captains chair': 'captains_chair',
};

/// Normalise to lowercase words separated by single spaces.
///
/// OCR of a curved shroud routinely returns `PEC FLY/REAR DELT`,
/// `ABDUCTION / ADDUCTION` and `Leg  Curl` with assorted separators, so
/// punctuation becomes a space rather than being deleted: deleting it would
/// weld `FLY/REAR` into `flyrear` and lose the match.
String normaliseText(String raw) {
  final lettersOnly = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), ' ');
  return lettersOnly.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Strip brand and boilerplate words, keeping order.
String _denoise(String normalised) {
  final kept = normalised
      .split(' ')
      .where((w) => w.length > 1 && !_kNoise.contains(w))
      .toList();
  return kept.join(' ');
}

/// Identify a machine from [recognisedText] — whatever OCR returned for the
/// whole frame, newlines and all.
///
/// [catalogue] is `equipmentId -> display name`, passed in rather than read
/// from disk so this stays pure and so the anchor cannot drift from the
/// catalogue the rest of the app uses.
///
/// Returns a RANKED LIST, not a single answer:
///
/// - **empty** — no machine name in the text. The common case by design, and
///   the caller falls back to the classifier.
/// - **one entry** — one machine named, and named unambiguously. This is the
///   case worth having: near-certain, and better than any 29-way softmax.
/// - **several entries** — the text names more than one machine and the text
///   alone cannot say which one the photo is of. Handing back candidates is
///   the honest shape; picking the longest phrase is how the operator's cable
///   station became a "chest press machine" at 0.92 during this very gate.
List<TextAnchorMatch> matchMachineText(
  String recognisedText, {
  required Map<String, String> catalogue,
}) {
  final normalised = normaliseText(recognisedText);
  if (normalised.isEmpty) return const [];
  final denoised = _denoise(normalised);
  if (denoised.isEmpty) return const [];

  // Longest phrase first: `pec fly rear delt` must win over `pec fly`, and
  // `hip abduction` over a bare `abduction` if one is ever added. Ties go to
  // the earlier position in the text, which on a placard is the heading.
  final phrases = _kPhrases.keys.toList()
    ..sort((a, b) {
      final byLength = b.length.compareTo(a.length);
      return byLength != 0 ? byLength : a.compareTo(b);
    });

  final hits = <String>[
    for (final phrase in phrases)
      if (_containsWords(denoised, phrase)) phrase,
  ];
  if (hits.isEmpty) {
    final byName = _matchByCatalogueName(denoised, catalogue);
    return byName == null ? const [] : [byName];
  }

  // Distinct TARGET MACHINES, not distinct phrases. "PEC FLY / REAR DELT" is
  // two phrases and one machine; that must not read as ambiguity.
  final distinct = <String>[];
  for (final p in hits) {
    final id = _kPhrases[p]!;
    if (!distinct.contains(id)) distinct.add(id);
  }

  if (distinct.length == 1) {
    return [
      TextAnchorMatch(
        equipmentId: distinct.first,
        matchedPhrase: hits.first,
        // High but never 1.0. OCR misreads, and a machine can carry a sticker
        // for a different machine; certainty is not ours to claim.
        confidence: 0.92,
      ),
    ];
  }

  // A multi-exercise station lists everything it can do, and taking the
  // longest phrase off that list is a confident wrong answer.
  //
  // The operator's photos 20260730_134401 and _134404 are exactly this: a
  // Nautilus Instinct dual-cable station whose decal reads "Lunge / Pulldown /
  // Shoulder Press / Biceps Curl / Torso Twist / Ab Crunch" on one side and
  // "Squat / Chest Press / Push Press / High Row / Push Down / Hip Glute
  // Press" on the other. Longest-first answered `shoulder_press_machine` at
  // 0.92 for the first and `chest_press_machine` for the second.
  //
  // Three distinct target machines on one placard is not a machine that does
  // three things badly -- it is a cable station, and saying so is worth more
  // than a list of its exercises.
  if (distinct.length >= 3) {
    return [
      TextAnchorMatch(
        equipmentId: 'cable_machine',
        matchedPhrase: hits.take(3).join(' + '),
        // Lower than a single clean read: this is an inference from the shape
        // of the placard, not a name printed on the shroud.
        confidence: 0.75,
      ),
    ];
  }

  // Exactly two. Could be two machines in one frame (the operator's Leg Curl
  // and Leg Extension stand side by side) or the short side of a station.
  // The text cannot tell those apart, so it does not try: both come back as
  // candidates and something else -- the classifier, or the user -- decides.
  //
  // The confidence is deliberately mediocre so neither reads as a settled
  // answer on its own -- both are returned as candidates, not a pick.
  return [
    for (final id in distinct)
      TextAnchorMatch(
        equipmentId: id,
        matchedPhrase: hits.firstWhere((p) => _kPhrases[p] == id),
        confidence: 0.55,
      ),
  ];
}

/// Fall back to the catalogue's own display names, so a machine labelled
/// exactly as the catalogue names it is matched without needing a row in
/// [_kPhrases].
TextAnchorMatch? _matchByCatalogueName(
  String denoised,
  Map<String, String> catalogue,
) {

  final byName = <String, String>{
    for (final e in catalogue.entries) normaliseText(e.value): e.key,
  };
  final names = byName.keys.where((n) => n.split(' ').length > 1).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    if (_containsWords(denoised, name)) {
      return TextAnchorMatch(
        equipmentId: byName[name]!,
        matchedPhrase: name,
        confidence: 0.88,
      );
    }
  }
  return null;
}

/// Whole-word subsequence test: `row` must not match inside `rowing`, and
/// `ab` must not match inside `abdominal`. Substring matching on OCR output
/// is how a single stray word turns into a confident wrong machine.
bool _containsWords(String haystack, String needle) {
  final h = haystack.split(' ');
  final n = needle.split(' ');
  if (n.isEmpty || n.length > h.length) return false;
  for (var i = 0; i + n.length <= h.length; i++) {
    var ok = true;
    for (var j = 0; j < n.length; j++) {
      if (h[i + j] != n[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
