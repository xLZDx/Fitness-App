import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/offline_video_cache.dart';

/// P2d. Every test the cache had ran against `InMemoryOfflineVideoCache`.
/// `FileOfflineVideoCache` — the one that writes to disk, and the one both
/// audit findings are about — had none, so neither the abandoned `.part` files
/// nor the missing quota could be seen by the suite.
///
/// These run the real file I/O against a temp directory, the same way
/// `photo_store_test.dart` does. Only the network fetch is faked, and it is
/// faked through the seam the class exposes for it rather than through Dio's
/// internals.

/// Writes [bytes] of filler, or throws when [failWith] is set.
VideoFetch _fetch({int bytes = 1024, Object? failWith, List<String>? seen}) {
  return (url, savePath, {onProgress}) async {
    seen?.add(url);
    if (failWith != null) {
      // Partway through, like a real timeout: the file already exists on disk
      // when the failure lands. A fetch that threw before writing anything
      // would leave nothing to clean up and prove nothing.
      await File(savePath).writeAsBytes(List.filled(bytes, 0));
      throw failWith;
    }
    await File(savePath).writeAsBytes(List.filled(bytes, 0));
  };
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline_video_cache_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  List<File> filesIn(Directory d) =>
      d.listSync().whereType<File>().toList(growable: false);

  group('a failed download leaves nothing behind', () {
    test('the partial is deleted and the error still reaches the caller',
        () async {
      final cache = FileOfflineVideoCache(
        directory: dir,
        fetch: _fetch(failWith: StateError('timeout')),
      );

      await expectLater(
        cache.download('clip-a'),
        throwsA(isA<StateError>()),
      );

      expect(filesIn(dir), isEmpty);
      expect(await cache.sizeBytes(), 0);
    });

    test('repeated failures do not accumulate one dead file each', () async {
      final cache = FileOfflineVideoCache(
        directory: dir,
        fetch: _fetch(failWith: StateError('timeout')),
      );

      for (var i = 0; i < 5; i++) {
        await cache.download('clip-$i').catchError((_) => File('unused'));
      }

      expect(filesIn(dir), isEmpty);
    });

    test('a partial left by a killed process is swept on the next download',
        () async {
      // Nothing in Dart runs when the app is killed mid-transfer, so the
      // catch in `download` cannot reach this one.
      final orphan = File('${dir.path}/deadbeef.mp4.part');
      await orphan.writeAsBytes(List.filled(4096, 0));

      final cache = FileOfflineVideoCache(directory: dir, fetch: _fetch());
      await cache.download('clip-a');

      expect(await orphan.exists(), isFalse);
      expect(filesIn(dir).length, 1);
    });
  });

  /// Backdates a cached clip.
  ///
  /// Sleeping instead would be both slower and useless: `FileStat.modified`
  /// comes back with its sub-second part zeroed on this platform — measured,
  /// two files written 10 ms apart report the same instant — so a test that
  /// leaned on millisecond delays would be asserting a resolution the
  /// filesystem does not have, and would pass or fail on where the second
  /// boundary happened to land.
  Future<void> age(File f, Duration by) =>
      f.setLastModified(DateTime.now().subtract(by));

  group('the library is bounded', () {
    test('an over-quota download evicts, and never the clip just fetched',
        () async {
      // Room for two clips of 1000 bytes, not three.
      final cache = FileOfflineVideoCache(
        directory: dir,
        maxBytes: 2500,
        fetch: _fetch(bytes: 1000),
      );

      final first = await cache.download('clip-a');
      await age(first, const Duration(days: 2));
      final second = await cache.download('clip-b');
      await age(second, const Duration(days: 1));
      final third = await cache.download('clip-c');

      expect(await cache.sizeBytes(), lessThanOrEqualTo(2500));
      expect(await third.exists(), isTrue,
          reason: 'returning a File that was evicted reports a download that '
              'did not survive its own completion');
      expect(await first.exists(), isFalse,
          reason: 'the oldest clip is the one that goes');
    });

    test('staying under the quota evicts nothing', () async {
      final cache = FileOfflineVideoCache(
        directory: dir,
        maxBytes: 1024 * 1024,
        fetch: _fetch(bytes: 1000),
      );

      await cache.download('clip-a');
      await cache.download('clip-b');

      expect(filesIn(dir).length, 2);
      expect(await cache.sizeBytes(), 2000);
    });

    test('playing a clip protects it from the next eviction', () async {
      final cache = FileOfflineVideoCache(
        directory: dir,
        maxBytes: 2500,
        fetch: _fetch(bytes: 1000),
      );

      final a = await cache.download('clip-a');
      final b = await cache.download('clip-b');
      // clip-a is the older DOWNLOAD of the two.
      await age(a, const Duration(days: 2));
      await age(b, const Duration(days: 1));

      // The user then watches clip-a. That is what "least recently USED" has
      // to mean, or a favourite clip is evicted for being old.
      expect(await cache.localFile('clip-a'), isNotNull);

      await cache.download('clip-c');

      expect(await a.exists(), isTrue,
          reason: 'clip-a was the most recently used, so clip-b goes instead');
      expect(await cache.localFile('clip-b'), isNull);
    });
  });

  group('the cache is still a cache', () {
    test('a second download of the same key does not refetch', () async {
      final seen = <String>[];
      final cache = FileOfflineVideoCache(
        directory: dir,
        fetch: _fetch(seen: seen),
      );

      await cache.download('clip-a');
      await cache.download('clip-a');

      expect(seen.length, 1);
    });

    test('the key is what it is filed under, not what was fetched', () async {
      // The signed URL expires in fifteen minutes; filing under it would mean
      // the cache never hits again.
      final seen = <String>[];
      final cache = FileOfflineVideoCache(
        directory: dir,
        fetch: _fetch(seen: seen),
      );

      await cache.download('exercises/girl/Legs/Squat.mp4',
          from: 'https://signed.example/abc?exp=123');

      expect(seen.single, 'https://signed.example/abc?exp=123');
      expect(await cache.localFile('exercises/girl/Legs/Squat.mp4'), isNotNull);
      expect(await cache.localFile('https://signed.example/abc?exp=123'),
          isNull);
    });

    test('sizeBytes ignores a partial mid-flight', () async {
      final stray = File('${dir.path}/inflight.mp4.part');
      await stray.writeAsBytes(List.filled(9999, 0));

      final cache = FileOfflineVideoCache(directory: dir, fetch: _fetch());

      expect(await cache.sizeBytes(), 0,
          reason: 'a partial is not a clip anyone can watch');
    });
  });
}
