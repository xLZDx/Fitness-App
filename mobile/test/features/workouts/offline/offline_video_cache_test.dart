import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/offline_video_cache.dart';

void main() {
  group('InMemoryOfflineVideoCache', () {
    test('download then evict round-trips', () async {
      final cache = InMemoryOfflineVideoCache();
      await cache.download('https://example.com/v.mp4');
      expect(cache.isCached('https://example.com/v.mp4'), isTrue);
      expect(await cache.sizeBytes(), greaterThan(0));
      await cache.evict('https://example.com/v.mp4');
      expect(cache.isCached('https://example.com/v.mp4'), isFalse);
    });

    test('clear empties the store', () async {
      final cache = InMemoryOfflineVideoCache();
      await cache.download('https://example.com/a.mp4');
      await cache.download('https://example.com/b.mp4');
      await cache.clear();
      expect(await cache.sizeBytes(), 0);
    });

    test('localFile always null for in-memory impl', () async {
      final cache = InMemoryOfflineVideoCache();
      await cache.download('https://example.com/a.mp4');
      expect(await cache.localFile('https://example.com/a.mp4'), isNull);
    });
  });
}
