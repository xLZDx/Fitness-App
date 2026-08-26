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

  // The prompt itself — subject phrasing, the Russian/English switch, the
  // no-starting-load-weight and no-health-data invariants, the safety close —
  // used to be pinned here against a pure `buildCoachPrompt(AiCoachContext)`
  // function. G1 moved prompt construction server-side; that coverage now
  // lives in `functions/src/__tests__/ai_coach_advice.test.ts`, against the
  // code that actually builds the prompt today. See `ai_coach_context.dart`'s
  // doc comment for why the Dart function was deleted rather than kept as an
  // untested duplicate.

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

    test('it sends exactly the context, not a client-built prompt', () async {
      // Pins the G1 seam: this service is transport only, and what crosses it
      // is the structured context the callable validates
      // (`ai_coach_advice.ts`'s `parseInput`) — never a free-form string the
      // phone assembled, which is exactly the arbitrary-prompt proxy that
      // gate was written to close off.
      AiCoachContext? sent;
      final svc = AiCoachService(ask: (ctx) async {
        sent = ctx;
        return 'ok';
      });
      final ctx = _ctx(source: AiCoachSource.exercise, name: 'Goblet Squat');
      await svc.advise(ctx);

      expect(sent, ctx);
    });
  });
}
