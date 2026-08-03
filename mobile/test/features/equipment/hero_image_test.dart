import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';

/// The image at the top of a machine's page.
///
/// Operator: *"фото должно быть превью ролика"*. It used to be a photograph
/// from the free-exercise-db import — properly licensed, and still the same
/// inconsistency the clip-only rule exists to end: every list, player and card
/// shows a 3D render on flat white, and then the machine header showed a man
/// in a gym.
void main() {
  ExerciseItem ex({
    required String id,
    Map<String, String> poster = const {},
    List<String> frames = const [],
    List<String> imageUrls = const [],
  }) =>
      ExerciseItem(
        id: id,
        title: id,
        equipmentId: 'lat_pulldown',
        muscles: const ['lats'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 10,
        summary: '',
        steps: const [],
        poster: poster,
        frames: frames,
        imageUrls: imageUrls,
      );

  Future<String?> heroFor(List<ExerciseItem> exercises) async {
    final container = ProviderContainer(overrides: [
      exercisesForEquipmentProvider('lat_pulldown')
          .overrideWith((ref) async => exercises),
    ]);
    addTearDown(container.dispose);
    return container.read(equipmentHeroImageProvider('lat_pulldown').future);
  }

  test('the header is the clip poster', () async {
    final hero = await heroFor([
      ex(id: 'a', poster: const {'men': 'assets/posters/men/a.jpg'}),
    ]);
    expect(hero, 'assets/posters/men/a.jpg');
  });

  test('a photograph is never used, even when there is nothing else', () async {
    // This is the whole change. Before, an exercise with photographs and no
    // poster produced a photograph header; the machine page was the last place
    // in the app still showing one.
    final hero = await heroFor([
      ex(id: 'a',
          frames: const ['assets/exercises/a_0.jpg'],
          imageUrls: const ['https://example.test/a.jpg']),
    ]);
    expect(hero, isNull);
  });

  test('it skips exercises with no poster to find one that has it', () async {
    final hero = await heroFor([
      ex(id: 'a', frames: const ['assets/exercises/a_0.jpg']),
      ex(id: 'b', poster: const {'girl': 'assets/posters/girl/b.jpg'}),
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
      ex(id: 'a', poster: const {'men': 'assets/posters/men/a.jpg'}),
    ]);
    expect(hero!.startsWith('http'), isFalse);
    expect(hero.startsWith('assets/'), isTrue);
  });
}
