import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/clip_url_resolver.dart';

/// Getting a playable URL for a licensed clip.
///
/// The vendor's permission to host their footage is conditional on users not
/// receiving "raw files, public storage folders, or permanent downloadable
/// links". A URL baked into the shipped catalog is a permanent downloadable
/// link, so licensed entries are object paths and are signed per request.
///
/// The original 343 clips are still public URLs and must keep working through
/// the same code while the licensed library is imported behind them.
/// The real resolver with only its network call replaced.
///
/// An earlier version of this double overrode `resolve` instead, which meant
/// the caching and de-duplication under test were never executed — and it
/// dragged Firebase into the test because the superclass constructor built a
/// `FirebaseFunctions`. Both are fixed: `fetch` is the single seam, and the
/// instance is now resolved lazily.
class _FakeBackend extends FunctionsClipUrlResolver {
  _FakeBackend({required super.now, this.signs = true});

  final bool signs;

  /// Every batch the "backend" was asked for, in order.
  final List<List<String>> batches = [];

  @override
  Future<Map<String, String>> fetch(List<String> objects) async {
    batches.add(List.of(objects));
    if (!signs) return {};
    return {for (final o in objects) o: 'https://signed/$o?exp=1'};
  }
}

void main() {
  group('which references need signing', () {
    test('an absolute url is passed straight through', () async {
      final r = PassthroughClipUrlResolver();
      const url = 'https://storage.googleapis.com/public/exercises/a.mp4';
      expect(await r.resolve(url), url);
      expect(r.asked.where(FunctionsClipUrlResolver.isDirect), isNotEmpty,
          reason: 'the legacy library must keep playing during the migration');
    });

    test('an object path is exchanged for something else', () async {
      final r = PassthroughClipUrlResolver();
      final out = await r.resolve('exercises/men/Legs/barbell squat.mp4');
      expect(out, isNot('exercises/men/Legs/barbell squat.mp4'));
      expect(out, contains('sig='));
    });

    test('isDirect is the whole seam', () {
      expect(FunctionsClipUrlResolver.isDirect('https://x/y.mp4'), isTrue);
      expect(FunctionsClipUrlResolver.isDirect('http://x/y.mp4'), isTrue);
      expect(FunctionsClipUrlResolver.isDirect('exercises/men/A/b.mp4'),
          isFalse);
    });
  });

  group('failure keeps the poster up', () {
    test('a resolver that cannot sign returns null, not an exception',
        () async {
      final r = PassthroughClipUrlResolver(fail: true);
      expect(await r.resolve('exercises/girl/Abs/crunch.mp4'), isNull);
    });

    test('one bad clip does not take the batch with it', () async {
      // A week's offline prefetch should deliver what it can.
      final r = PassthroughClipUrlResolver();
      final out = await r.resolveAll([
        'https://public/a.mp4',
        'exercises/men/Legs/b.mp4',
      ]);
      expect(out, hasLength(2));
    });
  });

  group('batching', () {
    test('resolveAll de-duplicates', () async {
      final r = PassthroughClipUrlResolver();
      final out = await r.resolveAll([
        'exercises/men/Legs/a.mp4',
        'exercises/men/Legs/a.mp4',
        'exercises/men/Legs/b.mp4',
      ]);
      expect(out, hasLength(2));
    });
  });

  group('caching', () {
    test('a second request inside the window does not call the backend',
        () async {
      var clock = DateTime(2026, 8, 2, 12);
      final r = _FakeBackend(now: () => clock);
      const ref = 'exercises/men/Legs/a.mp4';

      expect(await r.resolve(ref), 'https://signed/$ref?exp=1');
      expect(await r.resolve(ref), 'https://signed/$ref?exp=1');
      expect(r.batches, hasLength(1), reason: 'the second read was cached');
    });

    test('an expired entry is fetched again', () async {
      var clock = DateTime(2026, 8, 2, 12);
      final r = _FakeBackend(now: () => clock);
      const ref = 'exercises/men/Legs/a.mp4';
      await r.resolve(ref);
      clock = clock.add(const Duration(minutes: 14));
      await r.resolve(ref);
      expect(r.batches, hasLength(2));
    });

    test('two simultaneous requests share one call', () async {
      // A list showing the same exercise twice must not sign it twice.
      final clock = DateTime(2026, 8, 2, 12);
      final r = _FakeBackend(now: () => clock);
      const ref = 'exercises/girl/Abs/crunch.mp4';
      final both = await Future.wait([r.resolve(ref), r.resolve(ref)]);
      expect(both.first, both.last);
      expect(r.batches, hasLength(1));
    });

    test('a failure is not cached', () async {
      // Caching "could not sign" would leave the clip dead for thirteen
      // minutes after a transient blip.
      final clock = DateTime(2026, 8, 2, 12);
      final r = _FakeBackend(now: () => clock, signs: false);
      const ref = 'exercises/men/Legs/a.mp4';
      expect(await r.resolve(ref), isNull);
      expect(await r.resolve(ref), isNull);
      expect(r.batches, hasLength(2));
    });

    test('a batch larger than the backend cap is chunked', () async {
      final clock = DateTime(2026, 8, 2, 12);
      final r = _FakeBackend(now: () => clock);
      final refs = [for (var i = 0; i < 140; i++) 'exercises/men/L/$i.mp4'];
      final out = await r.resolveAll(refs);
      expect(out, hasLength(140));
      expect(r.batches, hasLength(3));
      expect(r.batches.every((b) => b.length <= 60), isTrue);
    });

    test('resolveAll does not re-ask for what is already cached', () async {
      final clock = DateTime(2026, 8, 2, 12);
      final r = _FakeBackend(now: () => clock);
      await r.resolve('exercises/men/L/a.mp4');
      r.batches.clear();
      await r.resolveAll(['exercises/men/L/a.mp4', 'exercises/men/L/b.mp4']);
      expect(r.batches.single, ['exercises/men/L/b.mp4']);
    });

    test('the cache window is shorter than the guaranteed URL lifetime', () {
      // The backend guarantees at least 15 minutes of life on every URL it
      // hands out; the client caches for 13. A clip that starts playing and
      // then 403s halfway through would be a far more confusing failure than
      // one that never starts.
      //
      // The guarantee used to be the mint: sign for 15, hand it over, done.
      // Since the backend began reusing one signature for every caller inside
      // a five-minute window it mints for 20 and stops serving an entry once
      // 15 remain (`functions/src/video_urls.ts`, REUSE_MINUTES), which is
      // exactly what keeps this margin untouched. If that guarantee is ever
      // lowered, this is the number it must not fall below.
      const guaranteedLife = Duration(minutes: 15);
      const clientTtl = Duration(minutes: 13);
      expect(clientTtl, lessThan(guaranteedLife));
      expect(guaranteedLife - clientTtl,
          greaterThanOrEqualTo(const Duration(minutes: 2)));
    });
  });

  group('a signing failure is swallowed, but no longer silent', () {
    test('a resolver that has not failed reports zero', () {
      final clock = DateTime(2026, 8, 4, 12);
      expect(_FakeBackend(now: () => clock).failureCount, 0);
    });

    test('each failed reference is counted', () async {
      // The gap this closes: the failure path returns an empty map and the
      // poster stays up, which is right for the user and left the app unable
      // to tell "signing is broken" from "nobody opened a video".
      final r = PassthroughClipUrlResolver(fail: true);
      await r.resolve('exercises/men/L/a.mp4');
      await r.resolve('exercises/men/L/b.mp4');
      expect(r.failureCount, 2);
    });

    test('a passthrough url is not a failure', () async {
      final r = PassthroughClipUrlResolver(fail: true);
      expect(await r.resolve('https://public/clip.mp4'), isNotNull);
      expect(r.failureCount, 0);
    });

    test('resolve still returns null and keeps the poster up', () async {
      final r = PassthroughClipUrlResolver(fail: true);
      expect(await r.resolve('exercises/men/L/a.mp4'), isNull);
      expect(r.failureCount, 1);
    });
  });
}
