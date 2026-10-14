import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/chunked_delete.dart';

/// A pretend collection: `fetch` returns up to `limit` of what is left,
/// `commit` removes them and records the size of every batch.
class _Collection {
  _Collection(int n) : left = List<int>.generate(n, (i) => i);
  final List<int> left;
  final batches = <int>[];
  int fetches = 0;

  Future<List<int>> fetch(int limit) async {
    fetches++;
    return left.take(limit).toList();
  }

  Future<void> commit(List<int> chunk) async {
    batches.add(chunk.length);
    left.removeRange(0, chunk.length);
  }
}

void main() {
  group('deleteInChunks', () {
    test('an empty collection commits nothing', () async {
      final c = _Collection(0);
      final n = await deleteInChunks<int>(fetch: c.fetch, commit: c.commit);
      expect(n, 0);
      expect(c.batches, isEmpty);
    });

    test('1000 documents go out as 400 + 400 + 200, none above 400', () async {
      final c = _Collection(1000);
      final n = await deleteInChunks<int>(fetch: c.fetch, commit: c.commit);
      expect(c.batches, [400, 400, 200]);
      expect(n, 1000);
      expect(c.left, isEmpty);
    });

    test('an exact multiple ends on an empty fetch and deletes everything',
        () async {
      final c = _Collection(800);
      await deleteInChunks<int>(fetch: c.fetch, commit: c.commit);
      expect(c.batches, [400, 400]);
      expect(c.left, isEmpty);
      expect(c.fetches, 3);
    });

    test('a short collection is one batch and one fetch', () async {
      final c = _Collection(7);
      await deleteInChunks<int>(fetch: c.fetch, commit: c.commit);
      expect(c.batches, [7]);
      expect(c.fetches, 1);
    });

    test('a failing commit stops the loop and surfaces', () async {
      final c = _Collection(900);
      var calls = 0;
      await expectLater(
        deleteInChunks<int>(
          fetch: c.fetch,
          commit: (chunk) async {
            if (++calls == 2) throw StateError('rejected');
            await c.commit(chunk);
          },
        ),
        throwsStateError,
      );
      expect(c.left.length, 500);
    });
  });
}
