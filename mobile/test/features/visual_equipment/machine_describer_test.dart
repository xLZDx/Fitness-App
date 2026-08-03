import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/machine_card.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_describer.dart';

/// The second question about a photo the catalog could not answer.
///
/// What these tests hold is the line between "an answer" and "a filled field".
/// The card goes on the user's screen marked «контент готовится», so a name the
/// model invented for a dog, or a row with nothing to read, is worse than the
/// empty state it replaced.
void main() {
  const good = '''
{"isGymEquipment": true,
 "name": "Тренажёр Гакк-приседания",
 "summary": "Наклонная платформа с салазками. Нагружает квадрицепсы.",
 "uses": ["Приседания в гакк-машине", "Подъёмы на носки", "Обратные приседания"]}
''';

  GeminiMachineDescriber describer(String answer) => GeminiMachineDescriber(
        ask: (_, __) async => answer,
        photoBytes: (_) async => Uint8List(0),
      );

  group('an answer becomes a card', () {
    test('name, explanation and things to try all survive', () async {
      final card = await describer(good).describe(
        path: '/tmp/gym.jpg',
        now: DateTime(2026, 8, 3, 12),
      );
      expect(card, isNotNull);
      expect(card!.name, 'Тренажёр Гакк-приседания');
      expect(card.summary, contains('квадрицепс'));
      expect(card.uses, hasLength(3));
      expect(card.status, MachineCardStatus.preparing);
    });

    test('the id comes from the name, so a second sighting finds the card',
        () async {
      final card = await describer(good).describe(path: '/tmp/a.jpg');
      expect(card!.id, machineCardId('Тренажёр Гакк-приседания'));
    });

    test('the photo is kept', () async {
      // Filming the missing clip starts from the machine the user actually
      // pointed at, not from the word the model chose for it.
      final card = await describer(good).describe(path: '/tmp/gym.jpg');
      expect(card!.photoPath, '/tmp/gym.jpg');
    });

    test('what the recogniser nearly said is carried through', () async {
      // A card whose classifier was 40% sure of a lat pulldown is different
      // evidence from one it had no idea about, and only the record can tell
      // them apart later.
      final card = await describer(good).describe(
        path: '/tmp/a.jpg',
        recognisedAs: 'lat pulldown',
        confidence: 0.4,
      );
      expect(card!.recognisedAs, 'lat pulldown');
      expect(card.confidence, 0.4);
    });

    test('a fenced answer still parses', () async {
      final card = await describer('```json\n$good\n```')
          .describe(path: '/tmp/a.jpg');
      expect(card, isNotNull);
    });
  });

  group('what does not become a card', () {
    test('a photo the model says is not equipment', () async {
      // The prompt gives it an explicit way out, and it has to be believed:
      // otherwise the answer to a photo of a dog is a confident description of
      // a rowing machine.
      final card = await describer('{"isGymEquipment": false}')
          .describe(path: '/tmp/dog.jpg');
      expect(card, isNull);
    });

    test('an answer with no explanation', () async {
      // A row in "my machines" that names a machine and says nothing about it
      // promises content nobody could film, because nobody would know what it
      // was.
      final card = await describer('{"name": "Что-то", "summary": "  "}')
          .describe(path: '/tmp/a.jpg');
      expect(card, isNull);
    });

    test('an answer with no name', () async {
      final card = await describer('{"summary": "Хороший тренажёр"}')
          .describe(path: '/tmp/a.jpg');
      expect(card, isNull);
    });

    test('prose instead of JSON', () async {
      final card = await describer('I think that is a leg press!')
          .describe(path: '/tmp/a.jpg');
      expect(card, isNull);
    });

    test('an empty reply', () async {
      expect(await describer('   ').describe(path: '/tmp/a.jpg'), isNull);
    });
  });

  group('failure is quiet, because the user has already been told once', () {
    test('a thrown request returns null instead of failing the scan', () async {
      final svc = GeminiMachineDescriber(
        ask: (_, __) async => throw StateError('no network'),
        photoBytes: (_) async => Uint8List(0),
      );
      expect(await svc.describe(path: '/tmp/a.jpg'), isNull);
    });

    test('an unreadable photo returns null', () async {
      final svc = GeminiMachineDescriber(
        ask: (_, __) async => good,
        photoBytes: (_) async => throw StateError('gone'),
      );
      expect(await svc.describe(path: '/tmp/missing.jpg'), isNull);
    });

    test('a stalled request gives up on the deadline', () async {
      // This is the user's SECOND wait on one photo. The operator's report of
      // "долго ждёт и ничего" was a vision call with no deadline at all, and
      // this path must not reintroduce one.
      final svc = GeminiMachineDescriber(
        ask: (_, __) => Future.delayed(const Duration(seconds: 30), () => good),
        photoBytes: (_) async => Uint8List(0),
        timeout: const Duration(milliseconds: 30),
      );
      expect(await svc.describe(path: '/tmp/a.jpg'), isNull);
    });
  });

  group('the shape of "uses"', () {
    Future<MachineCard?> withUses(Object uses) => describer(jsonEncode({
          'isGymEquipment': true,
          'name': 'X',
          'summary': 'Y',
          'uses': uses,
        })).describe(path: '/tmp/a.jpg');

    test('blank and duplicate lines are dropped', () async {
      final card = await withUses(['Приседания', '  ', 'Приседания', 'Жим']);
      expect(card!.uses, ['Приседания', 'Жим']);
    });

    test('a paragraph is not a line and is dropped', () async {
      final card = await withUses(['Приседания', 'x' * 200]);
      expect(card!.uses, ['Приседания']);
    });

    test('more than five is capped', () async {
      final card = await withUses(List.generate(9, (i) => 'Упражнение $i'));
      expect(card!.uses, hasLength(5));
    });

    test('no usable lines still leaves a readable card', () async {
      // Half the promise is "what is this", and that half is intact. An empty
      // list shows nothing; it does not invent an exercise to fill the space.
      final card = await withUses(const <String>[]);
      expect(card, isNotNull);
      expect(card!.uses, isEmpty);
    });

    test('a string where a list was asked for does not crash', () async {
      final card = await withUses('приседания');
      expect(card!.uses, isEmpty);
    });
  });

  group('the question itself', () {
    test('asks in the user language', () async {
      expect(GeminiMachineDescriber.buildPrompt('ru'),
          contains('in Russian'));
      expect(GeminiMachineDescriber.buildPrompt('en'),
          contains('in English'));
    });

    test('offers no list to choose from', () async {
      // The classifier pins the answer to our 48 machines so it cannot invent
      // a page we do not have. Here there is no page by definition, and a
      // constrained vocabulary would return the wrong name for the machine the
      // user is standing in front of.
      final prompt = GeminiMachineDescriber.buildPrompt('ru');
      expect(prompt, isNot(contains('lat pulldown')));
      expect(prompt, contains('isGymEquipment'));
    });
  });
}
