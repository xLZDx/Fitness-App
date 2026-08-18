import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import 'video_failure.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, protected, visibleForTesting;

/// Turns a catalog clip reference into a URL a player can open.
///
/// ## Two kinds of reference, on purpose
///
/// The catalog holds either:
///
///   * an absolute `https://…` URL — the original library, served from a
///     public bucket; or
///   * an object path like `exercises/men/Legs/barbell squat.mp4` — the
///     licensed library, served from a private bucket.
///
/// The first is passed through untouched. The second is exchanged for a
/// short-lived signed URL through the `clipUrl` function.
///
/// Keeping both is not indecision, it is the migration: the app must keep
/// playing the 343 clips it already serves while the licensed library is
/// imported behind it. When the last public URL is gone the passthrough can go
/// with it, and until then a single `startsWith('http')` is the whole seam.
///
/// ## Why the app cannot just hold the licensed URLs
///
/// The vendor's permission to host their footage is conditional on users not
/// receiving "raw files, public storage folders, or permanent downloadable
/// links". A URL baked into a shipped catalog is a permanent downloadable
/// link by definition.
/// What a batch resolution actually achieved.
///
/// A bare `Map` could say which clips were signed and nothing else, so a
/// prefetch stopped halfway by the daily limit was indistinguishable from one
/// where half the objects were simply missing. The offline prefetch is the
/// only caller, and "38 of 84, and the reason the other 46 are absent" is the
/// one thing it needs to tell a user honestly.
class ClipBatch {
  const ClipBatch({required this.urls, this.quotaExhausted = false});

  /// Reference -> playable URL, for everything that WAS signed. Never
  /// discarded because a later chunk was refused: the earlier chunks were
  /// charged for and delivered, and throwing them away would make the app
  /// pay twice for the same clips tomorrow.
  final Map<String, String> urls;

  /// The backend refused on the daily budget partway through.
  ///
  /// Distinct from "some clips are missing", which has many causes and no
  /// remedy the user can act on. This one ends by itself at the next UTC
  /// midnight, and that is the whole reason it is worth a separate field.
  final bool quotaExhausted;
}

abstract class ClipUrlResolver {
  /// A playable URL for [reference], or null when it cannot be resolved.
  ///
  /// Null rather than throwing: the caller is a video block that already has a
  /// poster on screen, and "keep showing the still" is a better answer to a
  /// signing failure than an exception thrown into a build method.
  ///
  /// The ONE exception is [ClipQuotaExhausted], which is thrown rather than
  /// swallowed. Null means "something went wrong and the app cannot say
  /// what"; a quota refusal is the opposite -- the backend said exactly what
  /// happened and when it ends, and flattening that into the same null made
  /// a deliberate, self-resolving refusal look identical to a signing outage
  /// on the screen. The caller already catches, so this reaches the failure
  /// note the same way every other named failure does.
  Future<String?> resolve(String reference);

  /// Resolves many at once — one round trip instead of forty. Missing
  /// entries are simply absent from [ClipBatch.urls].
  ///
  /// Returns rather than throws on a quota refusal, unlike [resolve]. The
  /// single-clip caller has one clip and nothing to keep; a batch caller has
  /// everything the earlier chunks already signed, and an exception would
  /// discard exactly that.
  Future<ClipBatch> resolveBatch(Iterable<String> references);

  /// How many backend calls have failed since the app started.
  ///
  /// Keeping the poster up on a signing failure is the right thing to show a
  /// user and the wrong thing to leave as the *only* record. A partial outage
  /// — signing broken for some clips, or for some users — is indistinguishable
  /// from nobody having opened the video tab, because the failure path returns
  /// an empty map and says nothing. This is the number that tells them apart,
  /// and at 1,000 concurrent users it is the difference between noticing a
  /// degradation and hearing about it from a review.
  int get failureCount;
}

/// Calls the backend, and remembers what it got.
class FunctionsClipUrlResolver implements ClipUrlResolver {
  FunctionsClipUrlResolver({
    FirebaseFunctions? functions,
    DateTime Function()? now,
  })  : _injected = functions,
        _now = now ?? DateTime.now;

  final FirebaseFunctions? _injected;
  final DateTime Function() _now;

  /// Resolved on first use, not in the constructor.
  ///
  /// `FirebaseFunctions.instanceFor` throws unless `Firebase.initializeApp`
  /// has run, and this class is built inside a Riverpod provider — so eager
  /// construction made the provider unusable in any test, and made a subclass
  /// that overrides the network call drag Firebase in anyway.
  FirebaseFunctions get _functions =>
      _injected ?? functionsForRegion;

  /// A URL arrives with at least 15 minutes of life. Cached for 13, so one
  /// handed to a player always has at least two minutes left in it — a clip
  /// that starts playing and then 403s part-way through would be a far more
  /// confusing failure than one that never starts.
  ///
  /// "At least 15" rather than "exactly 15" since the backend began reusing
  /// one signature for everyone who asks inside a five-minute window: it mints
  /// for twenty and stops handing an entry out once fifteen remain, precisely
  /// so this margin is unaffected. See `functions/src/video_urls.ts`,
  /// REUSE_MINUTES. The 13 here is the number that must never exceed the
  /// backend's guarantee.
  @visibleForTesting
  static const cacheFor = Duration(minutes: 13);

  final Map<String, ({String url, DateTime until})> _cache = {};

  /// In-flight requests, so a list that shows the same exercise twice does not
  /// ask the backend twice.
  final Map<String, Future<String?>> _pending = {};

  int _failures = 0;

  @override
  int get failureCount => _failures;

  /// One place the swallow is recorded, so both call sites cannot drift.
  void _noteFailure(String what, Object error) {
    _failures++;
    debugPrint('clip url failed ($what) [$_failures this session]: $error');
  }

  static bool isDirect(String reference) => reference.startsWith('http');

  String? _fresh(String reference) {
    final hit = _cache[reference];
    if (hit == null) return null;
    if (hit.until.isBefore(_now())) {
      _cache.remove(reference);
      return null;
    }
    return hit.url;
  }

  void _store(String reference, String url) {
    _cache[reference] = (url: url, until: _now().add(cacheFor));
  }

  /// The one network call. Everything above it — passthrough, cache,
  /// de-duplication, chunking — is testable by overriding just this.
  ///
  /// Returns the references it managed to sign. A reference absent from the
  /// result was not signed, and the caller keeps its poster up.
  @protected
  Future<Map<String, String>> fetch(List<String> objects) async {
    if (objects.length == 1) {
      return guarded(objects.single, () async {
        final result = await _functions
            .httpsCallable('clipUrl')
            .call<Map<String, dynamic>>({'object': objects.single});
        final url = result.data['url'] as String?;
        return (url == null || url.isEmpty) ? {} : {objects.single: url};
      });
    }
    return guarded('${objects.length} clips', () async {
      final result = await _functions
          .httpsCallable('clipUrls')
          .call<Map<String, dynamic>>({'objects': objects});
      final urls = (result.data['urls'] as Map?) ?? const {};
      return {
        for (final e in urls.entries) e.key as String: e.value as String,
      };
    });
  }

  /// The failure policy for a backend call, shared by both call shapes.
  ///
  /// It takes the call as a closure rather than sitting inside `fetch`
  /// because a `catch` wrapped around a real `FirebaseFunctions` invocation
  /// is unreachable from a test: nothing can enter it, so a mutation inside
  /// it survives. That is not hypothetical — the batch path's copy of this
  /// policy was mutated to swallow every quota refusal and the whole suite
  /// stayed green. Here it is one method, reachable with any throwing
  /// closure, and there is one copy of the decision instead of two that can
  /// drift.
  ///
  /// A refusal is rethrown; everything else is swallowed and counted. The
  /// phone's job on an ordinary failure is to keep the poster up, but the
  /// backend log knowing the reason while the phone did not even know it
  /// happened is how a signing outage looked exactly like nobody watching.
  @visibleForTesting
  Future<Map<String, String>> guarded(
    String label,
    Future<Map<String, String>> Function() call,
  ) async {
    try {
      return await call();
    } catch (e) {
      _noteFailure(label, e);
      return swallowOrThrow(e);
    }
  }

  /// Swallow, or rethrow. Pure, so the decision itself is testable with no
  /// resolver at all.
  @visibleForTesting
  static Map<String, String> swallowOrThrow(Object error) {
    final refusal = asQuotaRefusal(error);
    if (refusal != null) throw refusal;
    return const {};
  }

  /// Recognises the backend's deliberate daily-budget refusal.
  ///
  /// `resource-exhausted` is what `enforceDailyQuota` throws
  /// (`functions/src/abuse_guard.ts`), and it is a documented gRPC status
  /// code rather than a message this could drift away from. Returns the
  /// domain exception carrying the backend's own sentence, or null when the
  /// failure was something else entirely.
  static ClipQuotaExhausted? asQuotaRefusal(Object error) {
    if (error is! FirebaseFunctionsException) return null;
    if (error.code != 'resource-exhausted') return null;
    final m = error.message?.trim();
    return ClipQuotaExhausted(m == null || m.isEmpty ? null : m);
  }

  @override
  Future<String?> resolve(String reference) {
    if (isDirect(reference)) return Future.value(reference);
    final cached = _fresh(reference);
    if (cached != null) return Future.value(cached);
    final inFlight = _pending[reference];
    if (inFlight != null) return inFlight;

    final future = fetch([reference]).then((got) {
      final url = got[reference];
      if (url != null) _store(reference, url);
      return url;
    });
    _pending[reference] = future;
    return future.whenComplete(() => _pending.remove(reference));
  }

  @override
  Future<ClipBatch> resolveBatch(Iterable<String> references) async {
    final out = <String, String>{};
    final ask = <String>[];
    for (final r in references.toSet()) {
      if (isDirect(r)) {
        out[r] = r;
        continue;
      }
      final cached = _fresh(r);
      if (cached != null) {
        out[r] = cached;
      } else {
        ask.add(r);
      }
    }
    if (ask.isEmpty) return ClipBatch(urls: out);

    // The backend caps a batch at 60. Chunking here rather than letting it
    // reject the call means a 200-clip prefetch works instead of failing
    // whole.
    var quotaExhausted = false;
    for (var i = 0; i < ask.length; i += 60) {
      final chunk = ask.sublist(i, i + 60 > ask.length ? ask.length : i + 60);
      final Map<String, String> got;
      try {
        // An ordinary failed chunk costs those clips, not the whole prefetch:
        // `fetch` returns an empty map rather than throwing.
        got = await fetch(chunk);
      } on ClipQuotaExhausted {
        // Keep going, and this is not an oversight. The obvious move is to
        // stop -- the budget is per-day and per-account, so surely the next
        // chunk is refused too. The backend does not work that way:
        // `enforceDailyQuota` refuses on `used + cost > limit`
        // (`functions/src/abuse_guard.ts`), and `clipUrls` passes the
        // chunk's OWN SIZE as `cost` (`functions/src/video_urls.ts`). A
        // refusal therefore proves only that THIS chunk does not fit in what
        // is left, and the last chunk of a prefetch is usually the short one.
        // 1,190 of 1,200 objects spent still leaves room for a trailing
        // chunk of ten; stopping here threw those ten away.
        //
        // A refused chunk is charged nothing -- the transaction throws before
        // it writes -- so the price of continuing is one wasted round trip per
        // remaining chunk, at most three for a 200-clip week. What the earlier
        // chunks signed stays in `out` regardless: it was charged for, and
        // discarding it would mean paying for those clips again tomorrow.
        quotaExhausted = true;
        continue;
      }
      for (final entry in got.entries) {
        _store(entry.key, entry.value);
        out[entry.key] = entry.value;
      }
    }
    return ClipBatch(urls: out, quotaExhausted: quotaExhausted);
  }
}

/// Hands back whatever it was given. For tests and for the widget suite, which
/// has no Firebase.
class PassthroughClipUrlResolver implements ClipUrlResolver {
  PassthroughClipUrlResolver({this.fail = false});

  /// Makes every non-direct reference resolve to null, to exercise the
  /// "signing failed, keep the poster" path.
  final bool fail;

  final List<String> asked = [];

  int _failures = 0;

  @override
  int get failureCount => _failures;

  @override
  Future<String?> resolve(String reference) async {
    asked.add(reference);
    if (FunctionsClipUrlResolver.isDirect(reference)) return reference;
    if (fail) {
      _failures++;
      return null;
    }
    return 'https://signed.example/$reference?sig=test';
  }

  /// Deliberately has no way to report a quota refusal.
  ///
  /// It carried a `quota` flag briefly. Nothing ever passed it, and it could
  /// only have simulated "refused from the very first chunk" -- this class
  /// does not chunk, so the case that actually matters, partway-through, was
  /// exactly the one it could not produce. A double that can only prove the
  /// easy half of a contract is worse than no double: see the note on
  /// [FunctionsClipUrlResolver.guarded] for what an untested copy of this
  /// policy already cost once. The quota paths are proved against the real
  /// resolver instead, in `prefetch_outcome_test.dart`.
  @override
  Future<ClipBatch> resolveBatch(Iterable<String> references) async {
    final out = <String, String>{};
    for (final r in references) {
      final u = await resolve(r);
      if (u != null) out[r] = u;
    }
    return ClipBatch(urls: out);
  }
}
