import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/firebase/functions_region.dart';
import 'package:flutter/foundation.dart' show debugPrint, protected;

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
abstract class ClipUrlResolver {
  /// A playable URL for [reference], or null when it cannot be resolved.
  ///
  /// Null rather than throwing: the caller is a video block that already has a
  /// poster on screen, and "keep showing the still" is a better answer to a
  /// signing failure than an exception thrown into a build method.
  Future<String?> resolve(String reference);

  /// Resolves many at once — one round trip instead of forty. Missing entries
  /// are simply absent from the result.
  Future<Map<String, String>> resolveAll(Iterable<String> references);

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
  static const _cacheFor = Duration(minutes: 13);

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
    _cache[reference] = (url: url, until: _now().add(_cacheFor));
  }

  /// The one network call. Everything above it — passthrough, cache,
  /// de-duplication, chunking — is testable by overriding just this.
  ///
  /// Returns the references it managed to sign. A reference absent from the
  /// result was not signed, and the caller keeps its poster up.
  @protected
  Future<Map<String, String>> fetch(List<String> objects) async {
    if (objects.length == 1) {
      try {
        final result = await _functions
            .httpsCallable('clipUrl')
            .call<Map<String, dynamic>>({'object': objects.single});
        final url = result.data['url'] as String?;
        return (url == null || url.isEmpty) ? {} : {objects.single: url};
      } catch (e) {
        // Still swallowed — see [ClipUrlResolver.resolve]. The phone's job is
        // to keep the poster up. But it is counted and named now: the backend
        // log knows the reason and the phone did not even know it happened,
        // which is how a signing outage looked exactly like nobody watching.
        _noteFailure(objects.single, e);
        return {};
      }
    }
    try {
      final result = await _functions
          .httpsCallable('clipUrls')
          .call<Map<String, dynamic>>({'objects': objects});
      final urls = (result.data['urls'] as Map?) ?? const {};
      return {
        for (final e in urls.entries) e.key as String: e.value as String,
      };
    } catch (e) {
      _noteFailure('${objects.length} clips', e);
      return {};
    }
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
  Future<Map<String, String>> resolveAll(Iterable<String> references) async {
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
    if (ask.isEmpty) return out;

    // The backend caps a batch at 60. Chunking here rather than letting it
    // reject the call means a 200-clip prefetch works instead of failing
    // whole.
    for (var i = 0; i < ask.length; i += 60) {
      final chunk = ask.sublist(i, i + 60 > ask.length ? ask.length : i + 60);
      // A failed chunk costs those clips, not the whole prefetch — `fetch`
      // already returns an empty map rather than throwing.
      final got = await fetch(chunk);
      for (final entry in got.entries) {
        _store(entry.key, entry.value);
        out[entry.key] = entry.value;
      }
    }
    return out;
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

  @override
  Future<Map<String, String>> resolveAll(Iterable<String> references) async {
    final out = <String, String>{};
    for (final r in references) {
      final u = await resolve(r);
      if (u != null) out[r] = u;
    }
    return out;
  }
}
