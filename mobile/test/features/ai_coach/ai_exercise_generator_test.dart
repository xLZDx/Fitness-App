import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_coach/ai_exercise_generator.dart';

void main() {
  group('AiExerciseGenerator.parseResponse', () {
    test('parses a valid array into ExerciseItems with :: -delimited ids',
        () {
      final out = AiExerciseGenerator.parseResponse(
        '''[
          {"title": "Elliptical Warm-up", "steps": ["Step 1", "Step 2"],
           "muscles": ["quads", "glutes"], "primaryMuscles": ["quads"],
           "difficulty": "beginner", "durationMinutes": 8}
        ]''',
        equipmentId: 'elliptical',
      );
      expect(out.single.id, 'ai::elliptical::0');
      expect(out.single.title, 'Elliptical Warm-up');
      expect(out.single.muscles, ['quads', 'glutes']);
      expect(out.single.primaryMuscles, ['quads']);
      expect(out.single.durationMinutes, 8);
    });

    test('uses :: not _ so equipmentIds with underscores stay recoverable',
        () {
      final out = AiExerciseGenerator.parseResponse(
        '[{"title": "X", "steps": ["a"], "muscles": [], "primaryMuscles": [], '
        '"difficulty": "beginner", "durationMinutes": 6}]',
        equipmentId: 'hip_abductor_adductor',
      );
      // Splitting on '::' must recover the exact id even though it contains
      // underscores itself -- splitting on '_' would not.
      final parts = out.single.id.split('::');
      expect(parts, ['ai', 'hip_abductor_adductor', '0']);
    });

    test('drops a muscle name outside the vocabulary rather than passing it through',
        () {
      final out = AiExerciseGenerator.parseResponse(
        '[{"title": "X", "steps": ["a"], "muscles": ["quads", "neck", "abs"], '
        '"primaryMuscles": ["neck"], "difficulty": "beginner", "durationMinutes": 6}]',
        equipmentId: 'elliptical',
      );
      expect(out.single.muscles, ['quads']);
      expect(out.single.primaryMuscles, isEmpty);
    });

    test('tolerates markdown code fences', () {
      final out = AiExerciseGenerator.parseResponse(
        '```json\n[{"title": "X", "steps": ["a"], "muscles": [], '
        '"primaryMuscles": [], "difficulty": "beginner", "durationMinutes": 6}]\n```',
        equipmentId: 'elliptical',
      );
      expect(out, hasLength(1));
    });

    test('an item with no steps is skipped, not crashed on', () {
      final out = AiExerciseGenerator.parseResponse(
        '[{"title": "Bad", "steps": []}, '
        '{"title": "Good", "steps": ["a"], "muscles": [], "primaryMuscles": [], '
        '"difficulty": "beginner", "durationMinutes": 6}]',
        equipmentId: 'elliptical',
      );
      expect(out, hasLength(1));
      expect(out.single.title, 'Good');
    });

    test('an empty result throws instead of silently returning nothing', () {
      expect(
        () => AiExerciseGenerator.parseResponse('[]', equipmentId: 'x'),
        throwsException,
      );
    });

    test('non-JSON / non-array raises, not crashes', () {
      expect(
        () => AiExerciseGenerator.parseResponse('not json', equipmentId: 'x'),
        throwsException,
      );
      expect(
        () => AiExerciseGenerator.parseResponse('{"not": "an array"}',
            equipmentId: 'x'),
        throwsException,
      );
    });

    test('an unknown difficulty falls back to beginner', () {
      final out = AiExerciseGenerator.parseResponse(
        '[{"title": "X", "steps": ["a"], "muscles": [], "primaryMuscles": [], '
        '"difficulty": "expert", "durationMinutes": 6}]',
        equipmentId: 'x',
      );
      expect(out.single.difficulty.name, 'beginner');
    });
  });

  group('kMuscleVocab', () {
    test('matches the server copy in ai_exercise_generation.ts exactly', () {
      // The Dart-side half of the cross-tree parity guard: the TS test
      // (functions/src/__tests__/ai_exercise_generation.test.ts) reads THIS
      // file's actual kMuscleVocab source and asserts it equals the real TS
      // MUSCLE_VOCAB. This test is the mirror -- both sides assert against
      // the exact same 15-value literal, so either side drifting from that
      // shared expectation fails locally, even though this suite alone
      // cannot read the TS source the way the Functions suite can read this
      // one.
      expect(AiExerciseGenerator.kMuscleVocab, const [
        'adductors', 'back', 'biceps', 'calves', 'chest', 'core', 'forearms',
        'glutes', 'hamstrings', 'lats', 'lower_back', 'quads', 'shoulders',
        'traps', 'triceps',
      ]);
    });
  });

  group('the aiExerciseGeneration wire contract', () {
    test('buildExerciseGenerationRequest sends equipmentId and languageCode only', () {
      final body = buildExerciseGenerationRequest('elliptical', 'ru');
      expect(body, {'equipmentId': 'elliptical', 'languageCode': 'ru'});
    });

    test('extractExerciseGenerationText reads the text field', () {
      expect(extractExerciseGenerationText({'text': 'hello'}), 'hello');
      expect(extractExerciseGenerationText({}), isNull);
    });
  });

  group('AiExerciseGenerator.generate with an injected ask', () {
    test('sends equipmentId and languageCode, not a client-built prompt', () async {
      String? seenEquipmentId;
      String? seenLanguageCode;
      final gen = AiExerciseGenerator(ask: (equipmentId, languageCode) async {
        seenEquipmentId = equipmentId;
        seenLanguageCode = languageCode;
        return '[{"title": "X", "steps": ["a"], "muscles": ["quads"], '
            '"primaryMuscles": ["quads"], "difficulty": "beginner", "durationMinutes": 8}]';
      });
      final out = await gen.generate(equipmentId: 'elliptical', languageCode: 'en');
      expect(out.single.equipmentId, 'elliptical');
      expect(seenEquipmentId, 'elliptical');
      expect(seenLanguageCode, 'en');
    });

    test('an empty answer throws rather than caching nothing', () {
      final gen = AiExerciseGenerator(ask: (_, __) async => '');
      expect(
        () => gen.generate(equipmentId: 'x', languageCode: 'en'),
        throwsException,
      );
    });

    test('a response arriving after the model call would take but before the '
        'outer deadline is still accepted, not discarded', () async {
      // Regression for the timeout hierarchy: the server's own model budget
      // is 25s (functions/src/ai_exercise_generation.ts), and this class's
      // outer deadline is deliberately larger (35s) so a legitimately slow
      // -- but real -- answer isn't thrown away by a client timer racing the
      // server's own. Simulated with a short injected delay well under the
      // real 35s so the test itself stays fast; what matters is that
      // `.timeout()` waits for `_cloud` rather than firing early.
      final gen = AiExerciseGenerator(
        timeout: const Duration(milliseconds: 200),
        ask: (_, __) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return '[{"title": "X", "steps": ["a"], "muscles": [], '
              '"primaryMuscles": [], "difficulty": "beginner", "durationMinutes": 6}]';
        },
      );
      final out = await gen.generate(equipmentId: 'elliptical', languageCode: 'en');
      expect(out, hasLength(1));
    });

    test('a response that never arrives within the outer deadline throws, not hangs',
        () async {
      final gen = AiExerciseGenerator(
        timeout: const Duration(milliseconds: 50),
        ask: (_, __) async {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return '[]';
        },
      );
      await expectLater(
        gen.generate(equipmentId: 'elliptical', languageCode: 'en'),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
