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
    this.video = const {},
    this.poster = const {},
    this.frames = const [],
    this.imageUrls = const [],
    this.primaryMuscles = const [],
    this.contraindications = const [],
    this.isStretch = false,
  });

  /// Stretching, mobility and Pilates work.
  ///
  /// Arrived with the video library and reached nothing: 65 exercises the
  /// catalog already knew were mobility work, with no way to ask for them.
  /// Operator: *"не вижу новые упражнения на растяжку егу и пилатес в списке
  /// категорий"*. They were there — the list had thirteen chips and none of
  /// them was this one.
  final bool isStretch;

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

  /// Demonstration clips keyed by the body performing them: `'girl'`, `'men'`.
  ///
  /// 343 of the 511 catalog entries carry one, most of them both. Two rather
  /// than one because the same movement looks different on different bodies
  /// and the operator's whole reason for the library was *"чтобы всем
  /// показывали то, что нужно"* — a woman's demonstration of a hip thrust is
  /// not interchangeable with a man's.
  final Map<String, String> video;

  /// Marks a url whose host has not been chosen yet.
  ///
  /// The catalog ships absolute urls so that picking a host is one constant to
  /// change rather than 653 rows to rewrite. Until that happens every one of
  /// them points here, and handing such a url to a video player produces a
  /// spinner that resolves into an error — worse than the stills it would have
  /// replaced. [playableVideoFor] is what keeps that off the screen.
  static const unresolvedHost = 'VIDEO_HOST_PLACEHOLDER';

  /// Which of the two bodies to show, from what the user told us about
  /// themselves. Null — and "prefer not to say" — means we were not told, so
  /// there is nothing to infer from and either clip is equally right.
  static String? bodyForGender(Object? gender) => switch (gender?.toString()) {
        'Gender.female' => 'girl',
        'Gender.male' => 'men',
        _ => null,
      };

  /// The clip to play, or null when there is nothing worth playing.
  ///
  /// Null in three cases, all of which must fall back to the stills: no clip
  /// at all, and the two that would otherwise render a broken player — a clip
  /// whose host is still [unresolvedHost], and a preference for a body this
  /// exercise was only filmed on the other of.
  String? playableVideoFor(String? body) {
    if (video.isEmpty) return null;
    // Preference first, then whichever exists. 33 exercises were filmed on one
    // body only, and showing the one we have beats showing nothing.
    final url = (body != null ? video[body] : null) ??
        video['men'] ??
        video.values.first;
    return url.contains(unresolvedHost) ? null : url;
  }

  /// Bundled still for the clip, keyed the same way as [video].
  ///
  /// Its whole job is to be on screen before the network has been asked for
  /// anything. Cut from the clip itself, so the poster IS the video's first
  /// position rather than a different photograph of the same movement — the
  /// swap from still to playing clip has nothing to jump.
  final Map<String, String> poster;

  /// The still to show while — or instead of — the clip.
  ///
  /// Falls back the same way [playableVideoFor] does, and for the same reason:
  /// showing the body we filmed beats showing nothing. Returns null only when
  /// this exercise has no clip at all, in which case the caller is on the
  /// stills path anyway.
  String? posterFor(String? body) {
    if (poster.isEmpty) return null;
    return (body != null ? poster[body] : null) ??
        poster['men'] ??
        poster.values.first;
  }

  /// Whether this exercise can show a real clip.
  ///
  /// Used to sort: the 168 entries without one go to the end of every list.
  /// Operator: *"Оставшиеся 168 убрать в конец списков"*. Not hidden — an
  /// exercise with written steps and a muscle map is still worth reaching,
  /// and hiding a third of the catalog to make the top of it look uniform
  /// is a trade nobody asked for.
  bool get hasVideo => video.values.any((u) => !u.contains(unresolvedHost));

  /// Bundled demo frames (start / end position of the movement). Looping
  /// them is how the app shows a movement without shipping video: it plays
  /// offline, weighs kilobytes, and comes from a public-domain source.
  final List<String> frames;

  /// Network-hosted start/end stills for catalog entries added after the
  /// original bundle (Free Exercise DB round 2, 2026-07-30). Not bundled
  /// into assets on purpose: 120+ exercises x 2 photos each would repeat the
  /// APK-size regression from the first bundle. Same public-domain source
  /// (raw.githubusercontent.com/yuhonas/free-exercise-db) as [frames],
  /// fetched over the network with the platform image cache instead.
  final List<String> imageUrls;

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
        video: Map<String, String>.unmodifiable(<String, String>{
          for (final e in (j['video'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        }),
        poster: Map<String, String>.unmodifiable(<String, String>{
          for (final e in (j['poster'] as Map? ?? const {}).entries)
            e.key as String: e.value as String,
        }),
        frames: List<String>.from(j['frames'] as List? ?? const []),
        imageUrls: List<String>.from(j['imageUrls'] as List? ?? const []),
        primaryMuscles:
            List<String>.from(j['primaryMuscles'] as List? ?? const []),
        contraindications:
            List<String>.from(j['contraindications'] as List? ?? const []),
        isStretch: j['isStretch'] as bool? ?? false,
      );

  /// Reads a `steps` list, dropping entries that are blank or whitespace.
  ///
  /// Not defensive padding: the upstream catalog really does ship one, and
  /// `barbell_squat_to_a_bench` has an empty string as its second step, which
  /// rendered as an empty numbered row in the workout player. Filtering here
  /// rather than in the UI keeps every consumer — and the translation
  /// step-count check — working from the same list.
  static List<String> parseSteps(Object? raw) =>
      List<String>.unmodifiable(<String>[
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
        video: video,
        poster: poster,
        frames: frames,
        imageUrls: imageUrls,
        primaryMuscles: primaryMuscles,
        contraindications: contraindications,
        isStretch: isStretch,
      );
}

/// A piece of gym equipment, identified by stable id. Recognition resolves
/// free-text machine names to these ids via the EquipmentAliasIndex.
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
