import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show ProgressCallback;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/clip_url_resolver.dart';
import 'package:fitness_app/features/equipment/data/video_failure.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/subscription/data/subscription_models.dart';
import 'package:fitness_app/features/subscription/state/subscription_providers.dart';
import 'package:fitness_app/features/workouts/data/offline_video_cache.dart';
import 'package:fitness_app/features/workouts/data/prefetch_outcome.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/offline_video_providers.dart';

/// A week's prefetch that stops at the daily limit, told truthfully.
///
/// Before this, the prefetch had two reportable outcomes: it finished, or it
/// threw. The case that actually happens sat between them — some clips on the
/// device, some not — and the two reasons a clip can be absent are opposites:
///
///   * something failed, which the user can do nothing about;
///   * the daily budget was reached, which nothing failed for and which ends
///     by itself at the next UTC midnight.
///
/// The batch resolver swallowed the second into the first, and the notifier
/// had nowhere to put it anyway. The invariant this file exists to hold is the
/// one that made that swallow tempting in the first place:
///
///     WHAT AN EARLIER CHUNK SIGNED IS NEVER DISCARDED
///     BECAUSE A LATER CHUNK WAS REFUSED.
///
/// Those clips were charged for. Throwing them away means paying for them
/// again tomorrow, and telling the user their week failed while most of it is
/// on their phone.
void main() {
  group('PrefetchOutcome states', () {
    test('the five distinguishable outcomes are actually distinguishable', () {
      // The whole point of the type. If any two of these collapse, the screen
      // cannot tell a refusal from a fault and the gate is undone.
      const complete = PrefetchOutcome(requested: 84, ready: 84);
      const partialQuota =
          PrefetchOutcome(requested: 84, ready: 38, quotaExhausted: true);
      const partialFailed = PrefetchOutcome(requested: 84, ready: 38);
      const noneQuota =
          PrefetchOutcome(requested: 84, ready: 0, quotaExhausted: true);
      const noneFailed = PrefetchOutcome(requested: 84, ready: 0);
      const empty = PrefetchOutcome(requested: 0, ready: 0);

      final states = [
        complete.state,
        partialQuota.state,
        partialFailed.state,
        noneQuota.state,
        noneFailed.state,
        empty.state,
      ];
      expect(states.toSet(), hasLength(6),
          reason: 'two outcomes collapsed into one state');
      expect(complete.state, PrefetchState.complete);
      expect(partialQuota.state, PrefetchState.partialQuota);
      expect(partialFailed.state, PrefetchState.partialFailed);
      expect(noneQuota.state, PrefetchState.noneQuota);
      expect(noneFailed.state, PrefetchState.noneFailed);
      expect(empty.state, PrefetchState.nothingScheduled);
    });

    test('an empty week is not a failure', () {
      const empty = PrefetchOutcome(requested: 0, ready: 0);
      expect(empty.complete, isTrue);
      expect(empty.nothingScheduled, isTrue);
      expect(empty.emptyHanded, isFalse,
          reason: 'delivering nothing when nothing was asked for is success');
    });

    test('missing is what the week needs and does not have', () {
      const o = PrefetchOutcome(requested: 84, ready: 38);
      expect(o.missing, 46);
      expect(o.complete, isFalse);
    });

    test('ready can never exceed requested', () {
      expect(() => PrefetchOutcome(requested: 1, ready: 2),
          throwsA(isA<AssertionError>()));
    });
  });

  group('ClipBatch: a refused chunk does not cost the signed ones', () {
    test('quota partway through keeps every earlier chunk', () async {
      // Two chunks of sixty. The first signs, the second is refused. The
      // mutation this kills is `out.clear()` -- or an exception -- on the
      // refusal, which is exactly what the resolver did before the gate.
      final r = _QuotaAfter(chunks: 1);
      final refs = [for (var i = 0; i < 140; i++) 'exercises/men/L/$i.mp4'];

      final batch = await r.resolveBatch(refs);

      expect(batch.quotaExhausted, isTrue);
      expect(batch.urls, hasLength(60),
          reason: 'the first chunk was charged for and delivered');
      expect(r.batches, hasLength(3),
          reason: 'a refusal is about ONE chunk not fitting the remaining '
              'budget, so the loop keeps offering the rest -- see the '
              'trailing-chunk test below for why that matters');
    });

    test('a refused chunk does not condemn a smaller one behind it', () async {
      // The case the first version of this loop got wrong. It stopped on the
      // first refusal, justified by "the budget is per-day, so the rest would
      // be refused too". The backend does not say that: `enforceDailyQuota`
      // refuses on `used + cost > limit` and `clipUrls` passes the chunk's own
      // length as `cost`, so a refusal proves only that THIS chunk is too big
      // for what is left.
      //
      // 140 references chunk as 60 + 60 + 20 against a budget of 100:
      //   60 fits    (used 0   -> 60)
      //   60 refused (60 + 60 > 100, and charges nothing)
      //   20 fits    (60 + 20 <= 100)
      // Eighty clips, sixty of which the old `break` threw away while telling
      // the user the limit had made them unobtainable.
      final r = _BudgetOf(100);
      final refs = [for (var i = 0; i < 140; i++) 'exercises/men/L/$i.mp4'];

      final batch = await r.resolveBatch(refs);

      expect(batch.urls, hasLength(80),
          reason: 'the trailing chunk fitted in what the budget had left');
      expect(batch.urls.containsKey('exercises/men/L/139.mp4'), isTrue,
          reason: 'a reference from the chunk AFTER the refusal');
      expect(batch.quotaExhausted, isTrue,
          reason: 'part of the week was still refused on the limit, and that '
              'is what the user has to be told');
      expect(r.charged, 80);
    });

    test('quota on the first chunk yields nothing but still says why',
        () async {
      final r = _QuotaAfter(chunks: 0);
      final refs = [for (var i = 0; i < 140; i++) 'exercises/men/L/$i.mp4'];

      final batch = await r.resolveBatch(refs);

      expect(batch.urls, isEmpty);
      expect(batch.quotaExhausted, isTrue,
          reason: 'zero results with a reason is not zero results without one');
    });

    test('quota on the exact chunk boundary keeps exactly what was signed',
        () async {
      // 120 references is two whole chunks. The refusal lands on the third
      // call, which does not exist -- so nothing is refused and the flag must
      // stay false. An off-by-one here would report a limit that was never
      // reached.
      final r = _QuotaAfter(chunks: 2);
      final refs = [for (var i = 0; i < 120; i++) 'exercises/men/L/$i.mp4'];

      final batch = await r.resolveBatch(refs);

      expect(batch.urls, hasLength(120));
      expect(batch.quotaExhausted, isFalse);
      expect(r.batches, hasLength(2));
    });

    test('an ordinary chunk failure is not a quota refusal', () async {
      // The positive control for the whole gate: a signing outage must not
      // acquire a "daily limit reached" message it has not earned.
      final r = _FailsEverything();
      final refs = [for (var i = 0; i < 70; i++) 'exercises/men/L/$i.mp4'];

      final batch = await r.resolveBatch(refs);

      expect(batch.urls, isEmpty);
      expect(batch.quotaExhausted, isFalse);
      expect(r.batches, hasLength(2),
          reason: 'an ordinary failure does not stop the remaining chunks');
    });

    test('a direct url needs no signing and no quota', () async {
      final r = _QuotaAfter(chunks: 0);
      final batch = await r.resolveBatch(['https://public/a.mp4']);
      expect(batch.urls, {'https://public/a.mp4': 'https://public/a.mp4'});
      expect(batch.quotaExhausted, isFalse,
          reason: 'nothing was asked of the backend');
    });

    test('everything succeeding stays a complete success', () async {
      final r = _QuotaAfter(chunks: 99);
      final refs = [for (var i = 0; i < 10; i++) 'exercises/men/L/$i.mp4'];
      final batch = await r.resolveBatch(refs);
      expect(batch.urls, hasLength(10));
      expect(batch.quotaExhausted, isFalse);
    });

    test('an empty request asks nothing and claims nothing', () async {
      final r = _QuotaAfter(chunks: 0);
      final batch = await r.resolveBatch(const <String>[]);
      expect(batch.urls, isEmpty);
      expect(batch.quotaExhausted, isFalse);
      expect(r.batches, isEmpty);
    });
  });

  group('the prefetch reports what it achieved', () {
    test('a full week is complete', () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _container(cache);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(
        overrideSessions: [_session('a'), _session('b')],
        videoUrlsFor: (s) => ['https://cdn/${s.exerciseId}.mp4'],
      );

      final o = container.read(offlinePrefetchActionProvider).value!;
      expect(o.state, PrefetchState.complete);
      expect(o.ready, 2);
      expect(o.requested, 2);
    });

    test('quota partway through is PARTIAL + LIMIT, and the clips stay',
        () async {
      // The headline case. One chunk of two signs, the other is refused, and
      // the outcome must carry BOTH the count that landed and the reason the
      // rest did not.
      final cache = InMemoryOfflineVideoCache();
      final container = _container(cache, resolver: _PartialQuota());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(
        overrideSessions: [_session('a')],
        videoUrlsFor: (s) => const [
          'exercises/men/L/keep.mp4',
          'exercises/men/L/refused.mp4',
        ],
      );

      final o = container.read(offlinePrefetchActionProvider).value!;
      expect(o.state, PrefetchState.partialQuota);
      expect(o.ready, 1);
      expect(o.requested, 2);
      expect(cache.isCached('exercises/men/L/keep.mp4'), isTrue,
          reason: 'the signed clip was charged for; it must reach the device');
      expect(container.read(offlinePrefetchActionProvider).hasError, isFalse,
          reason: 'a partial week is a result, not an exception');
    });

    test('an ordinary signing failure is PARTIAL + FAILED, never the limit',
        () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _container(cache, resolver: _SignsNothing());
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(
        overrideSessions: [_session('a')],
        videoUrlsFor: (s) => const ['exercises/men/L/a.mp4'],
      );

      final o = container.read(offlinePrefetchActionProvider).value!;
      expect(o.state, PrefetchState.noneFailed);
      expect(o.quotaExhausted, isFalse,
          reason: 'this is the control: an outage must not borrow the '
              'limit message, which promises a reset that will not fix it');
    });

    test('a download that fails costs its clip, not the week', () async {
      // Before this the download loop had no try/catch: one refused write
      // threw out of the loop, the state became an error, and every clip
      // already on the device went unreported.
      final cache = _RefusesOne('https://cdn/b.mp4');
      final container = _container(cache);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(
        overrideSessions: [_session('a')],
        videoUrlsFor: (s) => const ['https://cdn/a.mp4', 'https://cdn/b.mp4'],
      );

      final state = container.read(offlinePrefetchActionProvider);
      expect(state.hasError, isFalse);
      final o = state.value!;
      expect(o.ready, 1);
      expect(o.requested, 2);
      expect(o.state, PrefetchState.partialFailed);
      expect(cache.isCached('https://cdn/a.mp4'), isTrue);
    });

    test('an empty week reports nothing scheduled, not success or failure',
        () async {
      final cache = InMemoryOfflineVideoCache();
      final container = _container(cache);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(
        overrideSessions: [_session('a')],
        videoUrlsFor: (s) => const [null],
      );

      final o = container.read(offlinePrefetchActionProvider).value!;
      expect(o.state, PrefetchState.nothingScheduled);
    });

    test('running it again does not carry the previous outcome forward',
        () async {
      // Retry must not inherit `quotaExhausted` from the run before it, or
      // the card would keep announcing a limit that has since reset.
      final cache = InMemoryOfflineVideoCache();
      final resolver = _PartialQuota();
      final container = _container(cache, resolver: resolver);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final notifier =
          container.read(offlinePrefetchActionProvider.notifier);
      await notifier.prefetchNext7Days(
        overrideSessions: [_session('a')],
        videoUrlsFor: (s) => const [
          'exercises/men/L/keep.mp4',
          'exercises/men/L/refused.mp4',
        ],
      );
      expect(container.read(offlinePrefetchActionProvider).value!.state,
          PrefetchState.partialQuota);

      resolver.refuse = false;
      await notifier.prefetchNext7Days(
        overrideSessions: [_session('a')],
        videoUrlsFor: (s) => const [
          'exercises/men/L/keep.mp4',
          'exercises/men/L/refused.mp4',
        ],
      );

      final o = container.read(offlinePrefetchActionProvider).value!;
      expect(o.state, PrefetchState.complete);
      expect(o.quotaExhausted, isFalse);
    });

    test('a refusal carries a reason, not an English sentence', () async {
      // The text a free user reads now lives in the .arb files. Composing it
      // in a notifier and rendering it with `toString()` shipped one language
      // to every locale.
      final cache = InMemoryOfflineVideoCache();
      final container = _container(cache, tier: SubscriptionTier.free);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(offlinePrefetchActionProvider.notifier)
          .prefetchNext7Days(overrideSessions: [_session('a')]);

      final error = container.read(offlinePrefetchActionProvider).error;
      expect(error, isA<PrefetchRefused>());
      expect((error! as PrefetchRefused).reason, PrefetchRefusal.notSubscribed);
      expect('$error', isNot(contains('Supporter')),
          reason: 'the words belong to the screen, not to the state layer');
    });
  });
}

// ---------------------------------------------------------------- fixtures

ScheduledSession _session(String id) => ScheduledSession(
      id: 's_$id',
      exerciseId: id,
      exerciseTitle: 'x',
      scheduledFor: DateTime.now().add(const Duration(days: 1)),
      durationMinutes: 20,
    );

ProviderContainer _container(
  OfflineVideoCache cache, {
  SubscriptionTier tier = SubscriptionTier.standard,
  ClipUrlResolver? resolver,
}) {
  return ProviderContainer(overrides: [
    effectiveTierProvider.overrideWithValue(tier),
    entitlementStatusProvider.overrideWithValue(EntitlementStatus.resolved),
    authUserProvider.overrideWith((_) => Stream.value(
          const AuthUser(uid: 'u1', email: 'a@b.com', displayName: 'T'),
        )),
    offlineVideoCacheProvider.overrideWithValue(cache),
    clipUrlResolverProvider
        .overrideWithValue(resolver ?? PassthroughClipUrlResolver()),
  ]);
}

/// The real chunking and accumulation, with a backend that refuses after
/// [chunks] successful calls.
///
/// Extends the production resolver rather than reimplementing it: the
/// behaviour under test IS the chunk loop, and a double that reimplemented it
/// would be testing itself.
class _QuotaAfter extends FunctionsClipUrlResolver {
  _QuotaAfter({required this.chunks}) : super(now: DateTime.now);

  final int chunks;
  final List<List<String>> batches = [];

  @override
  Future<Map<String, String>> fetch(List<String> objects) async {
    batches.add(List.of(objects));
    if (batches.length > chunks) {
      throw const ClipQuotaExhausted('It resets tomorrow.');
    }
    return {for (final o in objects) o: 'https://signed/$o'};
  }
}

/// The real quota model: a per-day budget that refuses a call only when THAT
/// call does not fit in what is left, and charges nothing when it refuses.
///
/// Mirrors `enforceDailyQuota` (`functions/src/abuse_guard.ts`): the check is
/// `used + cost > limit`, inside a transaction that throws before it writes,
/// with `cost` supplied by `clipUrls` as the number of objects asked for
/// (`functions/src/video_urls.ts`). The budget below is a plain number chosen
/// to straddle two chunk sizes; it is not derived from the resolver's chunk
/// constant, so a change to that constant fails this test instead of moving
/// the goalposts with it.
class _BudgetOf extends FunctionsClipUrlResolver {
  _BudgetOf(this.limit) : super(now: DateTime.now);

  final int limit;
  int charged = 0;

  @override
  Future<Map<String, String>> fetch(List<String> objects) async {
    if (charged + objects.length > limit) {
      throw const ClipQuotaExhausted('It resets tomorrow.');
    }
    charged += objects.length;
    return {for (final o in objects) o: 'https://signed/$o'};
  }
}

/// A backend that fails for a reason that is NOT the daily limit.
class _FailsEverything extends FunctionsClipUrlResolver {
  _FailsEverything() : super(now: DateTime.now);

  final List<List<String>> batches = [];

  @override
  Future<Map<String, String>> fetch(List<String> objects) async {
    batches.add(List.of(objects));
    return const {};
  }
}

/// Signs the reference containing `keep`, refuses the rest on quota.
class _PartialQuota implements ClipUrlResolver {
  bool refuse = true;

  @override
  int get failureCount => 0;

  @override
  Future<String?> resolve(String reference) async => 'https://signed/x';

  @override
  Future<ClipBatch> resolveBatch(Iterable<String> references) async {
    final urls = <String, String>{};
    var hitQuota = false;
    for (final r in references) {
      if (r.contains('keep') || !refuse) {
        urls[r] = 'https://signed/$r';
      } else {
        hitQuota = true;
      }
    }
    return ClipBatch(urls: urls, quotaExhausted: hitQuota);
  }
}

/// Signs nothing, for a reason it cannot name.
class _SignsNothing implements ClipUrlResolver {
  @override
  int get failureCount => 1;

  @override
  Future<String?> resolve(String reference) async => null;

  @override
  Future<ClipBatch> resolveBatch(Iterable<String> references) async =>
      const ClipBatch(urls: {});
}

/// A cache that refuses to write one particular url.
class _RefusesOne extends InMemoryOfflineVideoCache {
  _RefusesOne(this.refused);

  final String refused;

  @override
  Future<File> download(String url,
      {String? from, ProgressCallback? onProgress}) async {
    if (url == refused) throw const FileSystemException('disk full');
    return super.download(url, from: from, onProgress: onProgress);
  }
}
