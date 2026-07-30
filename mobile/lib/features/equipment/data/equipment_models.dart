/// Difficulty tier we surface alongside an exercise. Maps loosely to the
/// `FitnessTier` from the user profile so we can filter recommendations.
enum ExerciseDifficulty { beginner, intermediate, advanced }

/// A single exercise that can be performed on a piece of equipment, or
/// "no equipment" for the home-workout slice.
class ExerciseItem {
  const ExerciseItem({
    required this.id,
    required this.title,
    required this.equipmentId,
    required this.muscles,
    required this.difficulty,
    required this.durationMinutes,
    required this.summary,
    required this.steps,
    this.videoUrl,
    this.frames = const [],
    this.primaryMuscles = const [],
    this.contraindications = const [],
  });

  final String id;
  final String title;

  /// `null` means body-weight / "Workout at Home" exercise.
  final String? equipmentId;
  final List<String> muscles;
  final ExerciseDifficulty difficulty;
  final int durationMinutes;
  final String summary;
  final List<String> steps;

  /// Where the instructional video lives, when a real clip exists.
  final String? videoUrl;

  /// Bundled demo frames (start / end position of the movement). Looping
  /// them is how the app shows a movement without shipping video: it plays
  /// offline, weighs kilobytes, and comes from a public-domain source.
  final List<String> frames;

  /// The muscles the movement is FOR, as opposed to [muscles], which also
  /// carries the supporting ones. Drives the muscle map's colour weighting.
  final List<String> primaryMuscles;

  /// Health flags that should hide this exercise. `'knee'`, `'lower_back'`,
  /// etc. — when any matches the user's injury list, the exercise is
  /// filtered out.
  final List<String> contraindications;

  factory ExerciseItem.fromJson(Map<String, dynamic> j) => ExerciseItem(
        id: j['id'] as String,
        title: j['title'] as String,
        equipmentId: j['equipmentId'] as String?,
        muscles: List<String>.from(j['muscles'] as List? ?? const []),
        difficulty: ExerciseDifficulty.values.firstWhere(
          (d) => d.name == (j['difficulty'] as String? ?? 'beginner'),
          orElse: () => ExerciseDifficulty.beginner,
        ),
        durationMinutes: j['durationMinutes'] as int? ?? 10,
        summary: j['summary'] as String? ?? '',
        steps: parseSteps(j['steps']),
        videoUrl: j['videoUrl'] as String?,
        frames: List<String>.from(j['frames'] as List? ?? const []),
        primaryMuscles:
            List<String>.from(j['primaryMuscles'] as List? ?? const []),
        contraindications:
            List<String>.from(j['contraindications'] as List? ?? const []),
      );

  /// Reads a `steps` list, dropping entries that are blank or whitespace.
  ///
  /// Not defensive padding: the upstream catalog really does ship one, and
  /// `barbell_squat_to_a_bench` has an empty string as its second step, which
  /// rendered as an empty numbered row in the workout player. Filtering here
  /// rather than in the UI keeps every consumer — and the translation
  /// step-count check — working from the same list.
  static List<String> parseSteps(Object? raw) => List<String>.unmodifiable(<String>[
        for (final step in (raw as List? ?? const []))
          if (step is String && step.trim().isNotEmpty) step,
      ]);

  /// A copy with the display text replaced by a translation.
  ///
  /// Deliberately narrow: only the three text fields can change. Muscles,
  /// contraindications, frames, difficulty and duration all feed filtering,
  /// recommendation and injury logic, so a translation file must not be able to
  /// reach them — the worst a bad translation can do is read badly.
  ExerciseItem withText({
    required String title,
    required String summary,
    required List<String> steps,
  }) =>
      ExerciseItem(
        id: id,
        title: title,
        equipmentId: equipmentId,
        muscles: muscles,
        difficulty: difficulty,
        durationMinutes: durationMinutes,
        summary: summary,
        steps: steps,
        videoUrl: videoUrl,
        frames: frames,
        primaryMuscles: primaryMuscles,
        contraindications: contraindications,
      );
}

/// A piece of gym equipment, identified by stable id and matched at scan time
/// via QR codes shaped like `fitness://equipment/<id>`.
class EquipmentItem {
  const EquipmentItem({
    required this.id,
    required this.name,
    required this.manufacturer,
    required this.category,
    required this.description,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String manufacturer;
  final String category; // 'cardio' / 'strength' / 'free_weights' / ...
  final String description;
  final String? imageUrl;

  /// A copy with the display text replaced by a translation. Narrow on
  /// purpose, mirroring [ExerciseItem.withText]: id and category feed lookups
  /// and filtering, so a translation file must not be able to reach them.
  EquipmentItem withText({
    required String name,
    required String description,
  }) =>
      EquipmentItem(
        id: id,
        name: name,
        manufacturer: manufacturer,
        category: category,
        description: description,
        imageUrl: imageUrl,
      );

  factory EquipmentItem.fromJson(Map<String, dynamic> j) => EquipmentItem(
        id: j['id'] as String,
        name: j['name'] as String,
        manufacturer: j['manufacturer'] as String? ?? 'Unknown',
        category: j['category'] as String? ?? 'general',
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
      );
}

/// Decoded QR scan target. Returns null when the payload doesn't match our
/// scheme so the UI can show "unrecognised QR".
class ScanResult {
  const ScanResult({required this.equipmentId, required this.raw});
  final String equipmentId;
  final String raw;

  static ScanResult? tryParse(String? raw) {
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    if (uri.scheme != 'fitness') return null;
    if (uri.host != 'equipment') return null;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (id.isEmpty) return null;
    return ScanResult(equipmentId: id, raw: raw);
  }
}
