import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/machine_card.dart';

/// A machine the app has nothing for, and what the user is told about it.
///
/// Operator: *"если есть в каталоге то показывать из каталога сразу, а если нет
/// объяснить человеку, что за железка перед ним и что на нем можно делать и
/// сохранить карточку тренажера чтобы мы потом добавили ролик и детали"* — and,
/// asked whether the card should be visible: *"пользователю тоже видна как
/// «контент готовится»"*.
///
/// So the card is a user-facing answer, not a silent bug report. These tests
/// hold the two properties that make it one: the same machine photographed
/// twice is one card with a rising count, and nothing about it pretends to be
/// content we do not have.
void main() {
  MachineCard card({
    String name = 'Hack Squat Machine',
    int timesSeen = 1,
    DateTime? first,
    String? photo,
  }) =>
      MachineCard(
        id: machineCardId(name),
        name: name,
        summary: 'A sled on rails you push with your legs.',
        uses: const ['Quad-focused squats', 'Calf raises'],
        firstSeenAt: first ?? DateTime(2026, 8, 3, 10),
        timesSeen: timesSeen,
        photoPath: photo,
      );

  group('one machine, one card', () {
    test('the id ignores case and spacing', () {
      // Two people photographing the same machine in two gyms must raise the
      // count on one card — that count is what decides which missing clip gets
      // filmed first, so splitting it defeats the purpose of recording at all.
      expect(machineCardId('Lat Pulldown'), machineCardId('lat  pulldown'));
      expect(machineCardId('LAT PULLDOWN'), machineCardId('Lat Pulldown'));
    });

    test('the id survives Russian names', () {
      // The model answers in the user's language and the launch market is
      // Russian. An id rule that stripped Cyrillic would collapse every Russian
      // machine name to one empty slug, and every machine in the country would
      // share a card.
      final a = machineCardId('Гакк-машина');
      expect(a, isNot('machine'), reason: 'Cyrillic must survive the slug');
      expect(a, contains('гакк'));
    });

    test('punctuation is not a different machine', () {
      // Written the other way round first, asserting that a hyphen and a space
      // produce different ids. That was a reflex, not a thought: `Гакк-машина`
      // and `гакк машина` are one machine, and splitting their card splits the
      // count that decides what gets filmed.
      expect(machineCardId('Гакк-машина'), machineCardId('гакк машина'));
      expect(machineCardId('Leg-Press'), machineCardId('leg press'));
    });

    test('an empty or symbol-only name still gets an id', () {
      expect(machineCardId(''), isNotEmpty);
      expect(machineCardId('???'), isNotEmpty);
    });

    test('seeing it again raises the count and keeps the first sighting', () {
      final first = card();
      final again = first.seenAgain(DateTime(2026, 8, 4, 9));
      expect(again.timesSeen, 2);
      expect(again.firstSeenAt, first.firstSeenAt);
      expect(again.lastSeenAt, DateTime(2026, 8, 4, 9));
      expect(again.id, first.id);
    });

    test('a sighting with no photo does not erase the one we have', () {
      // The photo is the only evidence of what the user actually pointed at,
      // and it is where filming the missing clip starts.
      final withPhoto = card(photo: '/tmp/a.jpg');
      expect(withPhoto.seenAgain(DateTime(2026, 8, 4)).photoPath, '/tmp/a.jpg');
      expect(
        withPhoto.seenAgain(DateTime(2026, 8, 4), photoPath: '/tmp/b.jpg')
            .photoPath,
        '/tmp/b.jpg',
      );
    });
  });

  group('what the user is offered', () {
    test('a card defaults to "being prepared", never to done', () {
      expect(card().status, MachineCardStatus.preparing);
    });

    test('it carries something to read and something to try', () {
      // The point of showing the card at all: the user aimed at a machine and
      // deserves an answer, even when the answer is not a clip.
      expect(card().summary, isNotEmpty);
      expect(card().uses, isNotEmpty);
    });

    test('the outside-video query names the machine', () {
      // There is no clip today and there will not be one today, so sending the
      // user somewhere that has one beats an empty page.
      expect(card(name: 'Pendulum Squat').searchQuery,
          contains('Pendulum Squat'));
    });
  });

  group('round trip', () {
    test('survives json', () {
      final before = MachineCard(
        id: machineCardId('Belt Squat'),
        name: 'Belt Squat',
        summary: 's',
        uses: const ['a', 'b'],
        firstSeenAt: DateTime(2026, 8, 3, 10),
        lastSeenAt: DateTime(2026, 8, 4, 11),
        timesSeen: 3,
        photoPath: '/tmp/x.jpg',
        recognisedAs: 'Hack Squat Machine',
        confidence: 0.41,
      );
      expect(MachineCard.fromJson(before.toJson()), before);
    });

    test('an unknown status does not lose the card', () {
      // A newer build writing a status this one has never heard of is a reason
      // to show the machine as still being prepared, not to drop it.
      final json = card().toJson()..['status'] = 'somethingNewer';
      expect(MachineCard.fromJson(json).status, MachineCardStatus.preparing);
    });

    test('a malformed date falls back rather than throwing', () {
      final json = card().toJson()..['firstSeenAt'] = 'not a date';
      expect(() => MachineCard.fromJson(json), returnsNormally);
    });

    test('missing optional fields are absent, not null-filled', () {
      final json = card().toJson();
      expect(json.containsKey('photoPath'), isFalse);
      expect(json.containsKey('recognisedAs'), isFalse);
    });
  });
}
