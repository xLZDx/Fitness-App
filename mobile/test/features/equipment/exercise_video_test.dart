import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/offline_video_providers.dart';

/// Reading the video library out of the catalog and deciding what to play.
///
/// The field shipped before anything read it: 343 exercises carried a clip and
/// `ExerciseItem` parsed `videoUrl` singular, so the catalog advertised a
/// library the app could not see. This is the wiring, and the two refusals
/// that matter more than the wiring — a clip on a host that does not exist
/// yet, and a body the exercise was not filmed on — because either one turns
/// a working page of photographs into a player that spins and then fails.

ExerciseItem item({
  Map<String, String> video = const {},
  String? videoUrl,
  List<String> frames = const [],
}) =>
    ExerciseItem(
      id: 'x',
      title: 'X',
      equipmentId: null,
      muscles: const ['core'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 5,
      summary: '',
      steps: const ['a'],
      video: video,
      videoUrl: videoUrl,
      frames: frames,
    );

const _host = 'https://cdn.example.com/exercises';
const _both = {
  'girl': '$_host/girl/Abs/Crunch.mp4',
  'men': '$_host/men/abs/Crunch.mp4'
};

void main() {
  group('parsing', () {
    test('the catalog on disk really does reach the model', () {
      // The whole point. Read the shipped file rather than a fixture, because
      // the defect being guarded is "the field is in the JSON and nowhere
      // else".
      final rows =
          (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>();
      final parsed = rows.map(ExerciseItem.fromJson).toList();

      expect(parsed, hasLength(511));
      expect(parsed.where((e) => e.video.isNotEmpty), hasLength(343));
      expect(parsed.where((e) => e.video.length == 2), hasLength(310));
      for (final e in parsed.where((e) => e.video.isNotEmpty)) {
        expect(e.video.keys, everyElement(anyOf('girl', 'men')), reason: e.id);
      }
    });

    test('an exercise with no clip parses to an empty map, not a crash', () {
      expect(
          ExerciseItem.fromJson(const {
            'id': 'a',
            'title': 'A',
            'muscles': ['core'],
            'steps': ['s'],
          }).video,
          isEmpty);
    });
  });

  group('choosing which body to show', () {
    test('the stated preference wins', () {
      expect(item(video: _both).playableVideoFor('girl'), _both['girl']);
      expect(item(video: _both).playableVideoFor('men'), _both['men']);
    });

    test('no preference still plays something', () {
      // Null covers both "has not filled in a profile" and "prefer not to
      // say". Neither is a reason to show nothing.
      expect(item(video: _both).playableVideoFor(null), isNotNull);
    });

    test('a body we do not have falls back to the one we do', () {
      // 33 exercises were filmed once. Showing the clip we have beats showing
      // the photographs because the user is not the gender in it.
      final one = {'men': _both['men']!};
      expect(item(video: one).playableVideoFor('girl'), _both['men']);
    });

    test('gender maps to a body only when it says something', () {
      expect(ExerciseItem.bodyForGender(null), isNull);
      expect(ExerciseItem.bodyForGender('Gender.preferNotToSay'), isNull);
      expect(ExerciseItem.bodyForGender('Gender.nonBinary'), isNull);
      expect(ExerciseItem.bodyForGender('Gender.female'), 'girl');
      expect(ExerciseItem.bodyForGender('Gender.male'), 'men');
    });
  });

  group('refusing to play what cannot be played', () {
    test('a url on the unchosen host is not offered', () {
      // Every url in the catalog is like this today. Handing one to the
      // player produces a spinner that resolves into an error, which is
      // strictly worse than the photographs it would have replaced.
      final unhosted = {
        'girl': 'https://${ExerciseItem.unresolvedHost}/exercises/girl/A/B.mp4',
        'men': 'https://${ExerciseItem.unresolvedHost}/exercises/men/a/B.mp4',
      };
      expect(item(video: unhosted).playableVideoFor('girl'), isNull);
      expect(item(video: unhosted).playableVideoFor(null), isNull);
    });

    test('the whole shipped catalog is unplayable right now', () {
      // Stated rather than implied. This fails the day a host is chosen,
      // which is exactly when someone should come back and read this file.
      final rows =
          (jsonDecode(File('assets/data/exercises.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>()
              .map(ExerciseItem.fromJson);
      expect(rows.where((e) => e.playableVideoFor(null) != null), isEmpty);
    });

    test('no clip at all is null, not an empty string', () {
      expect(item().playableVideoFor('men'), isNull);
    });
  });

  group('offline prefetch', () {
    ScheduledSession session(String exerciseId) => ScheduledSession(
          id: 's',
          exerciseId: exerciseId,
          exerciseTitle: 'E',
          scheduledFor: DateTime(2026, 8, 1),
          durationMinutes: 10,
        );

    test('queues both bodies, so editing a profile does not un-cache a set',
        () {
      final resolve = videoUrlResolverFor([
        ExerciseItem(
          id: 'e1',
          title: 'E',
          equipmentId: null,
          muscles: const ['core'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 5,
          summary: '',
          steps: const ['a'],
          video: _both,
        ),
      ]);
      expect(resolve(session('e1')).whereType<String>(),
          unorderedEquals(_both.values));
    });

    test('a one-body exercise is queued once, not twice', () {
      final resolve = videoUrlResolverFor([
        ExerciseItem(
          id: 'e1',
          title: 'E',
          equipmentId: null,
          muscles: const ['core'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 5,
          summary: '',
          steps: const ['a'],
          video: {'men': _both['men']!},
        ),
      ]);
      expect(resolve(session('e1')).whereType<String>(), hasLength(1));
    });

    test('an unknown exercise resolves to nothing without throwing', () {
      expect(videoUrlResolverFor(const [])(session('nope')).whereType<String>(),
          isEmpty);
    });
  });
}
