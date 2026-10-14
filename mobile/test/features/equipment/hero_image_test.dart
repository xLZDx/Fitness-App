import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';

/// The image at the top of a machine's page.
///
/// Operator: *"фото должно быть превью ролика"*. It used to be a photograph
/// from the free-exercise-db import — properly licensed, and still the same
/// inconsistency the clip-only rule exists to end: every list, player and card
/// shows a 3D render on flat white, and then the machine header showed a man
/// in a gym.
///
/// Since the bench-press page showed a man curling dumbbells, the header is
/// also only ever an exercise that NAMES the machine; see `equipment_hero.dart`
/// and `equipment_hero_contract_test.dart` for the real-catalogue contract.
void main() {
  ExerciseItem ex({
    required String id,
    Map<String, String> poster = const {},
    List<String> frames = const [],
    List<String> imageUrls = const [],
    String? label,
  }) =>
      ExerciseItem(
        id: id,
        title: id,
        equipmentId: 'lat_pulldown',
        equipmentLabel: label,
        muscles: const ['lats'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 10,
        summary: '',
        steps: const [],
        poster: poster,
        frames: frames,
        imageUrls: imageUrls,
      );

  final index = EquipmentAliasIndex.fromJson({
    'lat_pulldown': ['lat pulldown', 'pulldown'],
    'barbell': ['barbell'],
  });

  // Seeded through the repository rather than by overriding the per-equipment
  // provider: that provider is private now, because five call sites read past
  // its "use the recommended feed instead" doc-comment. Overriding the
  // repository is also the more honest fixture — it exercises the same lookup
  // the app performs.
  Future<String?> heroFor(List<ExerciseItem> exercises,
      {String? preferred}) async {
    final repo = AssetEquipmentRepository()
      ..seedForTests(
        equipment: [
          EquipmentItem(
            id: 'lat_pulldown',
            name: 'Lat pulldown',
            manufacturer: 'Any',
            category: 'strength',
            description: 'd',
            heroExerciseId: preferred,
          ),
        ],
        exercises: exercises,
      );
    final container = ProviderContainer(overrides: [
      equipmentRepositoryProvider.overrideWithValue(repo),
      equipmentAliasIndexProvider.overrideWith((ref) async => index),
      // The header is injury-screened now, so the profile has to resolve
      // before it can answer. Stated rather than inherited: an unresolved
      // profile leaves it loading forever, which is the correct behaviour and
      // a confusing test failure.
      screeningProfileProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
    return container.read(equipmentHeroImageProvider('lat_pulldown').future);
  }

  test('the header is the clip poster', () async {
    final hero = await heroFor([
      ex(
          id: 'ea_lat_pulldown_a',
          poster: const {'men': 'assets/posters/men/a.jpg'}),
    ]);
    expect(hero, 'assets/posters/men/a.jpg');
  });

  test('a photograph is never used, even when there is nothing else', () async {
    // An exercise with photographs and no poster used to produce a photograph
    // header; the machine page was the last place in the app still showing one.
    final hero = await heroFor([
      ex(
          id: 'ea_lat_pulldown_a',
          frames: const ['assets/exercises/a_0.jpg'],
          imageUrls: const ['https://example.test/a.jpg']),
    ]);
    expect(hero, isNull);
  });

  test('it skips exercises with no poster to find one that has it', () async {
    final hero = await heroFor([
      ex(id: 'ea_lat_pulldown_a', frames: const ['assets/exercises/a_0.jpg']),
      ex(
          id: 'ea_lat_pulldown_b',
          poster: const {'girl': 'assets/posters/girl/b.jpg'}),
    ]);
    expect(hero, 'assets/posters/girl/b.jpg');
  });

  test('a machine with nothing gets no header rather than a placeholder',
      () async {
    expect(await heroFor(const []), isNull);
  });

  test('the path is a bundled asset, so it renders offline', () async {
    // `equipment_detail_page` branches on `startsWith('http')` to choose
    // between Image.network and Image.asset. A poster is always bundled, so
    // this header can no longer depend on the network.
    final hero = await heroFor([
      ex(
          id: 'ea_lat_pulldown_a',
          poster: const {'men': 'assets/posters/men/a.jpg'}),
    ]);
    expect(hero!.startsWith('http'), isFalse);
    expect(hero.startsWith('assets/'), isTrue);
  });

  group('the header depicts the machine, not whatever can be done near it', () {
    test('an exercise that does not name the machine is not used', () async {
      final hero = await heroFor([
        ex(
            id: 'ea_alternating_biceps_curl_seated_dumbbells',
            poster: const {'men': 'assets/posters/men/curl.jpg'}),
      ]);
      expect(hero, isNull, reason: 'no header beats a wrong header');
    });

    test('a naming exercise wins over an earlier non-naming one', () async {
      final hero = await heroFor([
        ex(
            id: 'ea_alternating_biceps_curl_seated_dumbbells',
            poster: const {'men': 'assets/posters/men/curl.jpg'}),
        ex(
            id: 'ea_wide_grip_lat_pulldown',
            poster: const {'men': 'assets/posters/men/pull.jpg'}),
      ]);
      expect(hero, 'assets/posters/men/pull.jpg');
    });

    test('the plain movement beats its variations, in any input order',
        () async {
      final a = ex(
          id: 'ea_lat_pulldown_behind_neck',
          poster: const {'men': 'assets/posters/men/long.jpg'});
      final b = ex(
          id: 'ea_lat_pulldown',
          poster: const {'men': 'assets/posters/men/short.jpg'});
      expect(await heroFor([a, b]), 'assets/posters/men/short.jpg');
      expect(await heroFor([b, a]), 'assets/posters/men/short.jpg');
    });

    test('the vendor label names the machine when the id slug does not',
        () async {
      final hero = await heroFor([
        ex(
            id: 'ea_wide_grip_row',
            label: 'Lat Pulldown Machine',
            poster: const {'men': 'assets/posters/men/label.jpg'}),
      ]);
      expect(hero, 'assets/posters/men/label.jpg');
    });

    test('the machine row can name its hero exercise', () async {
      final hero = await heroFor([
        ex(
            id: 'ea_lat_pulldown',
            poster: const {'men': 'assets/posters/men/plain.jpg'}),
        ex(
            id: 'ea_chosen_variation',
            poster: const {'men': 'assets/posters/men/chosen.jpg'}),
      ], preferred: 'ea_chosen_variation');
      expect(hero, 'assets/posters/men/chosen.jpg');
    });

    test('a named hero that has no poster falls back to the ranking',
        () async {
      final hero = await heroFor([
        ex(
            id: 'ea_lat_pulldown',
            poster: const {'men': 'assets/posters/men/plain.jpg'}),
        ex(id: 'ea_chosen_variation'),
      ], preferred: 'ea_chosen_variation');
      expect(hero, 'assets/posters/men/plain.jpg');
    });
  });
}
