import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_coach/ai_coach_context.dart';
import 'package:fitness_app/features/ai_coach/ai_coach_service.dart';

/// The two things about this feature most worth pinning are both invisible:
/// what the model is actually asked, and what the answer is cached under.
///
/// Coverage before this gate was two cases living in
/// `test/features/visual_equipment/gemini_equipment_service_test.dart` — there
/// only because both services talk to the same model. They moved here, and the
/// one case they had that these did not (a Cyrillic subject name surviving into
/// the prompt) is kept below.

AiCoachContext _ctx({
  AiCoachSource source = AiCoachSource.equipment,
  String id = 'eq-042',
  String name = 'Leg Press',
  String lang = 'en',
}) =>
    AiCoachContext(
      source: source,
      subjectId: id,
      subjectName: name,
      languageCode: lang,
    );

void main() {
  group('the cache key', () {
    // `aiCoachAdviceProvider` is an autoDispose.family keyed on this object.
    // Riverpod matches family arguments by `==`, so equality here IS the cache,
    // and a class without it would miss on every rebuild and re-bill the quota.

    test('two contexts describing the same request are equal', () {
      expect(_ctx(), equals(_ctx()));
      expect(_ctx().hashCode, equals(_ctx().hashCode));
    });

    test('a different id is a different request even under the same name', () {
      // The defect this type was introduced to fix. The old key was the display
      // name, and the catalog holds 1,887 vendor rows in which duplicate labels
      // across manufacturers are ordinary — so two machines could serve each
      // other's advice with nothing on screen to suggest it.
      expect(_ctx(id: 'eq-042'), isNot(equals(_ctx(id: 'eq-317'))));
    });

    test('language is part of the key', () {
      // Otherwise switching the interface to Russian would show the cached
      // English answer until the sheet happened to be disposed.
      expect(_ctx(lang: 'en'), isNot(equals(_ctx(lang: 'ru'))));
    });

    test('source is part of the key', () {
      expect(
        _ctx(source: AiCoachSource.equipment),
        isNot(equals(_ctx(source: AiCoachSource.exercise))),
      );
    });
  });

  group('the prompt', () {
    test('names the subject', () {
      expect(buildCoachPrompt(_ctx(name: 'Leg Press')), contains('Leg Press'));
    });

    test('asks in Russian when the interface is Russian', () {
      expect(buildCoachPrompt(_ctx(lang: 'ru')), contains('In Russian'));
      expect(buildCoachPrompt(_ctx(lang: 'en')), contains('In English'));
    });

    test('an exercise is performed, not stood at', () {
      // The old prompt opened with "The user is standing at:" for every subject.
      // Correct for a leg press, wrong for a Romanian deadlift — and the model
      // answers the question it was asked.
      final machine = buildCoachPrompt(_ctx(source: AiCoachSource.equipment));
      final movement = buildCoachPrompt(
        _ctx(source: AiCoachSource.exercise, name: 'Romanian Deadlift'),
      );

      expect(machine, contains('standing at the machine'));
      expect(movement, contains('about to perform the exercise'));
      expect(movement, isNot(contains('standing at')));
    });

    test('it still carries the safety close', () {
      // The sheet shows a "not medical advice" disclaimer, but the disclaimer
      // is not the safety instruction — this line is, and it is inside the
      // generated text where the user is actually reading.
      expect(buildCoachPrompt(_ctx()), contains('stop on sharp pain'));
    });

    test('a Cyrillic subject name survives into the prompt', () {
      // Carried over from the old location. Worth keeping separately from the
      // "names the subject" case: the interesting failure is an encoding one,
      // and an ASCII fixture cannot show it.
      final prompt = buildCoachPrompt(_ctx(name: 'Гакк-машина', lang: 'ru'));
      expect(prompt, contains('Гакк-машина'));
      expect(prompt, contains('In Russian'));
    });

    test('it carries no health payload', () {
      // Gate H1a moved injuries, conditions, medications, smoking and alcohol
      // off the server and onto the phone. This prompt is the shortest path
      // back off it, so the absence is asserted rather than assumed.
      final prompt = buildCoachPrompt(_ctx()).toLowerCase();
      for (final leak in const [
        'injur',
        'medication',
        'condition',
        'smok',
        'alcohol',
        'diagnos',
      ]) {
        expect(prompt, isNot(contains(leak)), reason: 'leaked "$leak"');
      }
    });
  });

  group('the service', () {
    test('returns the model text, trimmed', () async {
      final svc = AiCoachService(ask: (_) async => '  advice  ');
      expect(await svc.advise(_ctx()), 'advice');
    });

    test('an empty answer is an error, not an empty sheet', () async {
      // A model that returns nothing used to render as a blank panel with a
      // disclaimer under it, which reads as "the coach has nothing to say
      // about this machine" rather than as a failure the user can retry.
      final svc = AiCoachService(ask: (_) async => '   ');
      expect(() => svc.advise(_ctx()), throwsA(isA<Exception>()));
    });

    test('a null answer is an error too', () async {
      final svc = AiCoachService(ask: (_) async => null);
      expect(() => svc.advise(_ctx()), throwsA(isA<Exception>()));
    });

    test('it sends exactly the built prompt', () async {
      // Pins the seam: the service is transport, the prompt is data. If someone
      // re-inlines the prompt here, the pure-function tests above stop covering
      // what actually goes over the wire.
      String? sent;
      final svc = AiCoachService(ask: (p) async {
        sent = p;
        return 'ok';
      });
      final ctx = _ctx(source: AiCoachSource.exercise, name: 'Goblet Squat');
      await svc.advise(ctx);

      expect(sent, buildCoachPrompt(ctx));
    });
  });
}
