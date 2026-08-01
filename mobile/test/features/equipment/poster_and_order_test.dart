import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';

/// The demo has something to show before the network answers, and the
/// exercises that can show a clip come first.
///
/// Both from the same screen recording of the catalog: a spinner where a
/// picture should have been, and a scroll through the Train tab in which the
/// first several exercises opened were all among the 168 without video.
ExerciseItem _ex(String id, {Map<String, String> video = const {}, Map<String, String> poster = const {}}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: const ['core'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
      video: video,
      poster: poster,
    );

void main() {
  group('the shipped catalog', () {
    late List<ExerciseItem> catalog;

    setUpAll(() {
      final raw = File('assets/data/exercises.json').readAsStringSync();
      catalog = (jsonDecode(raw) as List)
          .map((e) => ExerciseItem.fromJson(e as Map<String, dynamic>))
          .toList();
    });

    test('every exercise with a clip also has a still to show first', () {
      // The gap this closes: exercises carrying video ship with empty `frames`
      // AND empty `imageUrls`, so the player had literally nothing to put on
      // screen while the clip downloaded, and nothing at all offline.
      final withVideo = catalog.where((e) => e.hasVideo).toList();
      expect(withVideo, isNotEmpty);
      final missing = withVideo.where((e) => e.poster.isEmpty).toList();
      expect(missing, isEmpty,
          reason: '${missing.length} clips have no poster: '
              '${missing.take(5).map((e) => e.id).join(", ")}');
    });

    test('every poster names a file that is actually bundled', () {
      // A path in the catalog that is not on disk is a broken image at
      // runtime and a green test here, unless the file is checked.
      final broken = <String>[];
      for (final e in catalog) {
        for (final path in e.poster.values) {
          if (!File(path).existsSync()) broken.add('${e.id}: $path');
        }
      }
      expect(broken, isEmpty, reason: broken.take(5).join('\n'));
    });

    test('a poster is chosen for the body the clip will show', () {
      final both = catalog.firstWhere((e) => e.poster.length > 1);
      expect(both.posterFor('girl'), contains('/girl/'));
      expect(both.posterFor('men'), contains('/men/'));
      // No stated preference: whatever exists, never null while a clip does.
      expect(both.posterFor(null), isNotNull);
    });

    test('posters stay small enough to justify bundling them', () {
      // The reason this is affordable at all: 400px stills of a 3D render on
      // flat white. If a future library ships photographs, this fails and the
      // bundling decision gets revisited rather than silently adding 40 MB.
      final dir = Directory('assets/posters');
      final total = dir
          .listSync(recursive: true)
          .whereType<File>()
          .fold<int>(0, (a, f) => a + f.lengthSync());
      expect(total, lessThan(8 * 1024 * 1024),
          reason: 'posters grew to ${(total / 1048576).toStringAsFixed(1)} MB');
    });
  });

  group('order', () {
    test('exercises without a clip go last', () {
      final out = videoFirst([
        _ex('no-clip-1'),
        _ex('clip-1', video: {'men': 'https://x/a.mp4'}),
        _ex('no-clip-2'),
        _ex('clip-2', video: {'girl': 'https://x/b.mp4'}),
      ]);
      expect(out.map((e) => e.id).toList(),
          ['clip-1', 'clip-2', 'no-clip-1', 'no-clip-2']);
    });

    test('order within each group is preserved', () {
      // It composes with the "For you" ranking rather than replacing it: the
      // ranker still decides which muscles come first.
      final ranked = [
        _ex('a', video: {'men': 'https://x/1.mp4'}),
        _ex('b'),
        _ex('c', video: {'men': 'https://x/2.mp4'}),
        _ex('d'),
      ];
      expect(videoFirst(ranked).map((e) => e.id).toList(), ['a', 'c', 'b', 'd']);
    });

    test('an unresolved host does not count as having a clip', () {
      // Placeholder urls produce a player that spins and then fails, so an
      // exercise carrying one belongs with the undemonstrated ones.
      final placeholder =
          _ex('p', video: {'men': 'https://${ExerciseItem.unresolvedHost}/x.mp4'});
      expect(placeholder.hasVideo, isFalse);
      expect(videoFirst([placeholder, _ex('real', video: {'men': 'https://x/y.mp4'})])
          .first.id, 'real');
    });

    test('nothing is dropped', () {
      final input = [for (var i = 0; i < 20; i++) _ex('e$i', video: i.isEven ? {'men': 'u'} : {})];
      expect(videoFirst(input).length, input.length);
      expect(videoFirst(input).toSet(), input.toSet());
    });
  });
}
