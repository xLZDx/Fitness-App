import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/machine_card.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_card_repository.dart';

/// The store behind "мои тренажёры" and behind our own answer to "what do we
/// film next".
///
/// The count is the whole point of keeping these, so the tests that matter are
/// the ones about when it moves and when it does not.
void main() {
  MachineCard card({
    String name = 'Гакк-машина',
    DateTime? at,
    int timesSeen = 1,
    String? photo,
    MachineCardStatus status = MachineCardStatus.preparing,
    String summary = 'Салазки на наклонных рельсах.',
    List<String> uses = const ['Приседания'],
  }) {
    final t = at ?? DateTime(2026, 8, 3, 10);
    return MachineCard(
      id: machineCardId(name),
      name: name,
      summary: summary,
      uses: uses,
      firstSeenAt: t,
      lastSeenAt: t,
      timesSeen: timesSeen,
      photoPath: photo,
      status: status,
    );
  }

  group('scanning the same machine twice', () {
    test('is one card, not two', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 3, 10)));
      await repo.save(card(at: DateTime(2026, 8, 4, 10)));
      final all = await repo.list();
      expect(all, hasLength(1));
      expect(all.single.timesSeen, 2);
    });

    test('a second shot moments later does not inflate the count', () async {
      // Tapping the shutter again because the first frame was blurry is one
      // encounter. If it read as two it would out-vote a machine two different
      // people actually went looking for — and that ordering is the only
      // reason these are stored.
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 3, 10, 0)));
      await repo.save(card(at: DateTime(2026, 8, 3, 10, 2)));
      expect((await repo.list()).single.timesSeen, 1);
    });

    test('the first sighting is kept and the latest moves forward', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 3, 10)));
      await repo.save(card(at: DateTime(2026, 8, 9, 18)));
      final c = (await repo.list()).single;
      expect(c.firstSeenAt, DateTime(2026, 8, 3, 10));
      expect(c.lastSeenAt, DateTime(2026, 8, 9, 18));
    });

    test('an out-of-order write does not move the machine backwards', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 9, 18)));
      await repo.save(card(at: DateTime(2026, 8, 3, 10)));
      final c = (await repo.list()).single;
      expect(c.firstSeenAt, DateTime(2026, 8, 3, 10));
      expect(c.lastSeenAt, DateTime(2026, 8, 9, 18));
    });

    test('a sighting with no photo does not erase the one we have', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 3), photo: '/tmp/a.jpg'));
      await repo.save(card(at: DateTime(2026, 8, 9)));
      expect((await repo.list()).single.photoPath, '/tmp/a.jpg');
    });

    test('the name recorded first wins', () async {
      // The model can phrase it differently on a second photo. Renaming the
      // card under the user is churn, and it would split our own reading of
      // what is being asked for.
      final repo = MockMachineCardRepository();
      await repo.save(card(name: 'Гакк-машина', at: DateTime(2026, 8, 3)));
      await repo.save(card(name: 'гакк машина', at: DateTime(2026, 8, 9)));
      final all = await repo.list();
      expect(all, hasLength(1));
      expect(all.single.name, 'Гакк-машина');
    });

    test('a thin first description is filled in by a fuller second', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 3), uses: const []));
      await repo.save(card(at: DateTime(2026, 8, 9), uses: const ['Приседания']));
      expect((await repo.list()).single.uses, ['Приседания']);
    });
  });

  group('a decision already taken survives a new photo', () {
    test('a machine we have since added stays in the catalog', () async {
      // Otherwise scanning it again puts a machine we already shipped back
      // under «контент готовится».
      final repo = MockMachineCardRepository();
      await repo.save(card(
          at: DateTime(2026, 8, 3), status: MachineCardStatus.inCatalog));
      await repo.save(card(at: DateTime(2026, 8, 9)));
      expect((await repo.list()).single.status, MachineCardStatus.inCatalog);
    });

    test('a machine we declined stays declined', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(
          at: DateTime(2026, 8, 3), status: MachineCardStatus.declined));
      await repo.save(card(at: DateTime(2026, 8, 9)));
      expect((await repo.list()).single.status, MachineCardStatus.declined);
    });

    test('a fresh card can still be promoted', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(at: DateTime(2026, 8, 3)));
      await repo.save(card(
          at: DateTime(2026, 8, 9), status: MachineCardStatus.inCatalog));
      expect((await repo.list()).single.status, MachineCardStatus.inCatalog);
    });
  });

  group('the list', () {
    test('is newest sighting first', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(name: 'A', at: DateTime(2026, 8, 1)));
      await repo.save(card(name: 'B', at: DateTime(2026, 8, 5)));
      await repo.save(card(name: 'C', at: DateTime(2026, 8, 3)));
      expect((await repo.list()).map((c) => c.name), ['B', 'C', 'A']);
    });

    test('a machine seen again floats back to the top', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(name: 'A', at: DateTime(2026, 8, 1)));
      await repo.save(card(name: 'B', at: DateTime(2026, 8, 5)));
      await repo.save(card(name: 'A', at: DateTime(2026, 8, 9)));
      expect((await repo.list()).first.name, 'A');
    });

    test('starts empty', () async {
      expect(await MockMachineCardRepository().list(), isEmpty);
    });

    test('the returned list cannot be mutated by a caller', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card());
      final all = await repo.list();
      expect(() => all.clear(), throwsUnsupportedError);
    });
  });

  group('watching', () {
    test('replays what is already there to a new subscriber', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card());
      expect(await repo.watch().first, hasLength(1));
    });

    test('emits on every save', () async {
      final repo = MockMachineCardRepository();
      final seen = <int>[];
      final sub = repo.watch().listen((l) => seen.add(l.length));
      await repo.save(card(name: 'A'));
      await repo.save(card(name: 'B'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [0, 1, 2]);
    });

    test('a de-duped repeat does not add a row', () async {
      final repo = MockMachineCardRepository();
      final seen = <int>[];
      final sub = repo.watch().listen((l) => seen.add(l.length));
      await repo.save(card(at: DateTime(2026, 8, 3)));
      await repo.save(card(at: DateTime(2026, 8, 9)));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [0, 1, 1]);
    });
  });

  group('the user removing things', () {
    test('remove drops one machine', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card(name: 'A'));
      await repo.save(card(name: 'B'));
      await repo.remove(machineCardId('A'));
      expect((await repo.list()).map((c) => c.name), ['B']);
    });

    test('removing something absent is not an error', () async {
      final repo = MockMachineCardRepository();
      await repo.remove('nothing');
      expect(await repo.list(), isEmpty);
    });

    test('clear empties the list', () async {
      final repo = MockMachineCardRepository();
      await repo.save(card());
      await repo.clear();
      expect(await repo.list(), isEmpty);
    });
  });
}
