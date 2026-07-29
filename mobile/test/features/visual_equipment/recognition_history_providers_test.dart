import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/recognition_history.dart';
import 'package:fitness_app/features/visual_equipment/state/recognition_history_providers.dart';

void main() {
  final t0 = DateTime.utc(2026, 7, 29, 10, 0);

  RecognitionEntry entry(String id, {Duration after = Duration.zero}) =>
      RecognitionEntry(
        equipmentId: id,
        recognisedAt: t0.add(after),
        confidence: 0.6,
        source: RecognitionSource.live,
      );

  group('recognition history providers', () {
    test('the repository defaults to the in-memory mock', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(recognitionHistoryRepositoryProvider),
        isA<MockRecognitionHistoryRepository>(),
      );
    });

    test('recognitionHistoryProvider starts empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.listen(recognitionHistoryProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(recognitionHistoryProvider).valueOrNull, isEmpty);
    });

    test('recognitionHistoryProvider streams recorded machines newest first',
        () async {
      final repo = MockRecognitionHistoryRepository();
      final container = ProviderContainer(overrides: [
        recognitionHistoryRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ]);
      addTearDown(container.dispose);

      container.listen(recognitionHistoryProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      await repo.record(entry('bench'));
      await repo.record(entry('squat', after: const Duration(hours: 1)));
      await Future<void>.delayed(Duration.zero);

      final history = container.read(recognitionHistoryProvider).valueOrNull;
      expect(history?.map((e) => e.equipmentId), ['squat', 'bench']);
    });

    test('a de-duped repeat does not add a row to the exposed list', () async {
      final repo = MockRecognitionHistoryRepository();
      final container = ProviderContainer(overrides: [
        recognitionHistoryRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ]);
      addTearDown(container.dispose);

      container.listen(recognitionHistoryProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      await repo.record(entry('bench'));
      await repo.record(entry('bench', after: const Duration(minutes: 2)));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(recognitionHistoryProvider).valueOrNull, hasLength(1));
    });

    test('clear empties the exposed list', () async {
      final repo = MockRecognitionHistoryRepository();
      final container = ProviderContainer(overrides: [
        recognitionHistoryRepositoryProvider.overrideWith((ref) {
          ref.onDispose(repo.dispose);
          return repo;
        }),
      ]);
      addTearDown(container.dispose);

      container.listen(recognitionHistoryProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);

      await repo.record(entry('bench'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recognitionHistoryProvider).valueOrNull, hasLength(1));

      await repo.clear();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recognitionHistoryProvider).valueOrNull, isEmpty);
    });
  });
}
