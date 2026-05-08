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

  /// Where the instructional video lives (Phase 2B will use this).
  final String? videoUrl;

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
        steps: List<String>.from(j['steps'] as List? ?? const []),
        videoUrl: j['videoUrl'] as String?,
        contraindications:
            List<String>.from(j['contraindications'] as List? ?? const []),
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
