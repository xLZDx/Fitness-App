import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/exercise_filter.dart';

/// The catalog shows animation or it shows nothing.
///
/// Operator, twice, over two builds: *"я до сих пор вижу старые картинки место
/// роликов, я просил их всех убрать чтобы было все одинаково"*. The first time
/// I read that as "the clips are not loading". It was not — the catalog was
/// deliberately falling back to photographs, and both fallbacks looked like
/// working features from the code's side.
///
/// Measured on the shipped file before this rule existed: 365 exercises with a
/// clip, 94 demonstrated by network photographs, 42 by bundled photographs, 10
/// by nothing. The bundled ones were the easy thing to miss — they are called
/// `frames`, they are animated by looping, and they still show a man in a gym
/// rather than the 3D render every clip shows.
void main() {
  ExerciseItem item({
    Map<String, String> video = const {},
    List<String> frames = const [],
    List<String> imageUrls = const [],
    String? videoUrl,
    String id = 'x',
  }) =>
      ExerciseItem(
        id: id,
        title: 'X',
        equipmentId: null,
        muscles: const [],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 10,
        summary: '',
        steps: const [],
        video: video,
        frames: frames,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
      );

  group('what survives the filter', () {
    test('a clip survives', () {
      final kept = withDemonstration([
        item(video: const {'men': 'https://cdn/x.mp4'}),
      ]);
      expect(kept, hasLength(1));
    });

    test('a licensed object key survives — it is a clip too', () {
      // The reference is not a url, and the filter must not mistake that for
      // "cannot be played". `ClipUrlResolver` turns it into one at play time.
      final kept = withDemonstration([
        item(video: const {'men': 'exercises/men/Legs/Barbell Squat.mp4'}),
      ]);
      expect(kept, hasLength(1));
    });

    test('bundled frames do NOT survive — they are photographs', () {
      final kept = withDemonstration([
        item(frames: const ['assets/exercises/a_0.jpg', 'assets/exercises/a_1.jpg']),
      ]);
      expect(kept, isEmpty,
          reason: 'looping two photographs is animation of the wrong thing');
    });

    test('network stills do NOT survive', () {
      final kept = withDemonstration([
        item(imageUrls: const ['https://raw.github/…/0.jpg', 'https://…/1.jpg']),
      ]);
      expect(kept, isEmpty);
    });

    test('an exercise with nothing does not survive', () {
      expect(withDemonstration([item()]), isEmpty);
    });

    test('a clip on an unresolved host does not survive', () {
      // Advertising a clip and then failing to play it is the failure the
      // player already guards; the list must not offer it in the first place.
      final kept = withDemonstration([
        item(video: {'men': 'https://${ExerciseItem.unresolvedHost}/a.mp4'}),
      ]);
      expect(kept, isEmpty);
    });

    test('the older singular videoUrl survives — the player still honours it', () {
      // Missed on the first pass. `WorkoutPlayerPage` plays
      // `playableVideoFor(body) ?? item.videoUrl`, so an entry carrying only
      // the legacy field is playable — and the filter hid it from every list
      // in the app. No shipped row uses it today, which is exactly why it was
      // easy to leave out and impossible to notice by looking at the catalog.
      final kept = withDemonstration([item(videoUrl: 'https://cdn/legacy.mp4')]);
      expect(kept, hasLength(1));
    });

    test('the filter agrees with the player, not with hasVideo', () {
      // If these two ever disagree, either a card appears in a list and then
      // refuses to play, or a playable exercise is invisible. Same chain, same
      // answer, by construction.
      final entries = [
        item(video: const {'men': 'https://cdn/a.mp4'}),
        item(video: {'men': 'https://${ExerciseItem.unresolvedHost}/a.mp4'}),
        item(videoUrl: 'https://cdn/legacy.mp4'),
        item(frames: const ['a.jpg', 'b.jpg']),
        item(),
      ];
      for (final e in entries) {
        final playerWouldShow =
            (e.playableVideoFor(null) ?? e.videoUrl) != null;
        expect(withDemonstration([e]).isNotEmpty, playerWouldShow, reason: e.id);
      }
    });
  });

  group('the shipped catalog', () {
    final rows =
        (jsonDecode(File('assets/data/exercises_vendor.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>()
            .map(ExerciseItem.fromJson)
            .toList();

    test('nothing the app shows is demonstrated by a photograph', () {
      // The whole point, asserted against the real file rather than a fixture.
      final shown = withDemonstration(rows);
      final byPhotograph = shown
          .where((e) => e.playableVideoFor(null) == null)
          .map((e) => e.id)
          .toList();
      expect(byPhotograph, isEmpty);

      for (final e in shown) {
        expect(e.playableVideoFor(null), isNotNull, reason: e.id);
      }
    });

    test('there is no gap left to hide', () {
      // This used to read "the gap is 156", counting the pre-purchase entries
      // the clip-only rule had to hide because they were demonstrated by a
      // photograph or by nothing. 365 -> 186 -> 337 over 2026-08-03 as
      // unlicensed scaffold clips came out and semantic re-matching put
      // licensed ones back; the catalog carrying that gap was removed on
      // 2026-08-04. Every shipped exercise now plays, so the assertion is the
      // stronger one: nothing is hidden, because there is nothing to hide.
      expect(rows, hasLength(1887));
      expect(withDemonstration(rows), hasLength(rows.length));
    });

    test('no entry is dropped for want of a usable clip', () {
      final dropped = rows.where((e) => e.playableVideoFor(null) == null);
      expect(dropped, isEmpty,
          reason: 'a vendor entry that cannot be played has no reason to ship');
      for (final e in rows) {
        expect(
            e.video.values.where((u) => u.contains(ExerciseItem.unresolvedHost)),
            isEmpty,
            reason: '${e.id} points at an unresolved host');
      }
    });
  });
}
