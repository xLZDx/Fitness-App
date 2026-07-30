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

  test('the prompt embeds the machine name, the language and the muscle vocabulary',
      () {
    final prompt = AiExerciseGenerator.buildPromptForTest('Elliptical trainer', 'ru');
    expect(prompt, contains('Elliptical trainer'));
    expect(prompt, contains('Russian'));
    for (final m in AiExerciseGenerator.kMuscleVocab) {
      expect(prompt, contains(m));
    }
  });

  group('AiExerciseGenerator.generate with an injected ask', () {
    test('returns parsed exercises from the injected response', () async {
      String? seenPrompt;
      final gen = AiExerciseGenerator(ask: (p) async {
        seenPrompt = p;
        return '[{"title": "X", "steps": ["a"], "muscles": ["quads"], '
            '"primaryMuscles": ["quads"], "difficulty": "beginner", "durationMinutes": 8}]';
      });
      final out = await gen.generate(
          equipmentId: 'elliptical', machineName: 'Elliptical', languageCode: 'en');
      expect(out.single.equipmentId, 'elliptical');
      expect(seenPrompt, contains('Elliptical'));
    });

    test('an empty answer throws rather than caching nothing', () {
      final gen = AiExerciseGenerator(ask: (_) async => '');
      expect(
        () => gen.generate(
            equipmentId: 'x', machineName: 'X', languageCode: 'en'),
        throwsException,
      );
    });
  });
}
