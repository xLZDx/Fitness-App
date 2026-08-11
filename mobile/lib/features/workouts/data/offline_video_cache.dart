import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// On-disk cache for instructional videos so the app works in gym
/// basements with no signal. Premium-tier feature gated by the caller —
/// this layer doesn't know about subscriptions.
///
/// Each key is hashed (sha1) into a stable filename inside the app's
/// document directory. The cache is *idempotent* — calling
/// [download] for an already-cached key is a no-op that completes
/// immediately. [localFile] returns the file iff it exists.
///
/// ## The key is the catalog reference, never the URL it was fetched from
///
/// Licensed clips live in a private bucket and are reached through a signed
/// URL that expires after fifteen minutes, so the URL is different on every
/// request. Hashing it would produce a new filename each time: nothing would
/// ever be found, and a premium user's "downloaded for offline" library would
/// silently re-download itself forever while reporting success.
///
/// So [download] takes the stable key first and the thing to fetch second.
/// For the public library the two are the same string and [from] can be
/// omitted, which is why every existing call site still reads correctly.
abstract class OfflineVideoCache {
  Future<File?> localFile(String url);

  /// Caches under [url]; fetches [from] when the two differ.
  Future<File> download(String url,
      {String? from, ProgressCallback? onProgress});
  Future<void> evict(String url);
  Future<int> sizeBytes();
  Future<void> clear();
}

/// Ceiling on how much disk the offline library may occupy.
///
/// This is a CHOSEN number, not a measured one. Nothing in the repo records
/// what a clip weighs — `lib/core/assets/asset_bootstrap.dart:18` is the
/// nearest evidence, and it only says bundled assets run 4-15 MB and that
/// anything bigger goes down this download-on-demand path, so a clip is
/// plausibly at or above the top of that range.
///
/// A gibibyte is picked as a disk-safety ceiling: large enough that a normal
/// week of scheduled sessions fits without eviction, small enough that the app
/// cannot quietly consume a budget phone's free space. If a real week is ever
/// measured to exceed it, the honest fix is to change this number with the
/// measurement next to it — not to remove the bound.
const int kOfflineVideoCacheMaxBytes = 1024 * 1024 * 1024;

/// Fetches [url] to [savePath]. The seam that makes this class testable.
///
/// Same reason `PhotoSource` exists in the photos feature
/// (`features/progress_photos/data/local_progress_photos_repository.dart:14`):
/// a test needs to make a download FAIL on demand, and reaching into Dio's
/// adapter to do that tests Dio, not this cache.
typedef VideoFetch = Future<void> Function(
  String url,
  String savePath, {
  ProgressCallback? onProgress,
});

class FileOfflineVideoCache implements OfflineVideoCache {
  FileOfflineVideoCache({
    Dio? dio,
    Directory? directory,
    this.maxBytes = kOfflineVideoCacheMaxBytes,
    VideoFetch? fetch,
  })  : _directory = directory,
        _fetch = fetch ?? _dioFetch(dio ?? Dio());

  /// Injected in tests so the real file I/O runs against a temp directory,
  /// exactly as `PhotoStore` does (`progress_photos/data/photo_store.dart:27`).
  /// Null in production, where the documents directory is resolved lazily.
  final Directory? _directory;
  final VideoFetch _fetch;

  /// Disk ceiling. Once past it, least-recently-used clips are dropped.
  final int maxBytes;

  static const String _partSuffix = '.part';

  Future<void>? _sweep;

  static VideoFetch _dioFetch(Dio dio) {
    return (url, savePath, {onProgress}) async {
      await dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          // Avoid hanging the user's session on a flaky CDN; bail and
          // fall back to streaming if the download takes too long.
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    };
  }

  Future<Directory> _cacheDir() async {
    final override = _directory;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/offline_videos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _filenameFor(String url) {
    final hash = crypto.sha1.convert(url.codeUnits).toString();
    final ext = _extOf(url);
    return '$hash$ext';
  }

  String _extOf(String url) {
    final dot = url.lastIndexOf('.');
    if (dot < 0 || dot < url.length - 5) return '.mp4';
    final candidate = url.substring(dot).split('?').first.toLowerCase();
    return candidate.length <= 5 ? candidate : '.mp4';
  }

  @override
  Future<File?> localFile(String url) async {
    final dir = await _cacheDir();
    final f = File('${dir.path}/${_filenameFor(url)}');
    if (!await f.exists()) return null;
    // The "recently used" half of the eviction order. There is no index file
    // to keep in sync -- the modification time IS the record, so it cannot
    // drift out of agreement with what is on disk.
    //
    // Not `accessed`: Android mounts with relatime, so read times are updated
    // at the kernel's discretion and a clip watched daily can look untouched.
    //
    // Granularity is ONE SECOND, measured, not assumed: `FileStat.modified`
    // comes back with its sub-second part zeroed (two files written 10 ms
    // apart report the same instant). So clips used within the same second are
    // indistinguishable and evict in whatever order the sort leaves them. That
    // is tolerable -- the case this exists for is a clip watched today against
    // one downloaded last week -- but it does mean a prefetch loop that
    // overruns the quota drops an arbitrary one of its own second's downloads
    // rather than a considered one.
    try {
      await f.setLastModified(DateTime.now());
    } catch (e) {
      // Never fail a playback lookup over bookkeeping. The cost of landing
      // here is that eviction order degrades toward "oldest download first",
      // which is the behaviour this replaced -- not a broken cache.
      debugPrint('offline video: could not touch ${f.path}: $e');
    }
    return f;
  }

  @override
  Future<File> download(String url,
      {String? from, ProgressCallback? onProgress}) async {
    await _sweepPartials();
    final dir = await _cacheDir();
    final dest = File('${dir.path}/${_filenameFor(url)}');
    if (await dest.exists()) return dest;
    final tmp = File('${dest.path}$_partSuffix');
    try {
      await _fetch(from ?? url, tmp.path, onProgress: onProgress);
      await tmp.rename(dest.path);
    } catch (_) {
      // A timeout on a flaky CDN is the EXPECTED failure here, and it left the
      // half-written file behind forever: nothing resumes it (no Range header
      // is ever sent), nothing serves it, and `sizeBytes` does not even report
      // it. A user on bad signal in a gym basement -- the exact person this
      // feature exists for -- accumulated one dead file per failed attempt.
      await _deleteQuietly(tmp, 'partial from a failed download');
      rethrow;
    }
    await _enforceQuota(keepPath: dest.path);
    return dest;
  }

  /// Deletes `.part` files no download is responsible for any more.
  ///
  /// The `catch` in [download] cannot cover the case this exists for: the app
  /// being killed or crashing mid-transfer, where no Dart code runs at all.
  /// Swept once per instance, and the provider builds one -- so in practice
  /// once per app start, before the first byte of the first download.
  Future<void> _sweepPartials() {
    return _sweep ??= () async {
      final dir = await _cacheDir();
      await for (final ent in dir.list()) {
        if (ent is File && ent.path.endsWith(_partSuffix)) {
          await _deleteQuietly(ent, 'partial left by an earlier run');
        }
      }
    }();
  }

  /// Drops least-recently-used clips until the library fits [maxBytes].
  Future<void> _enforceQuota({required String keepPath}) async {
    final dir = await _cacheDir();
    final entries = <_CachedClip>[];
    var total = 0;
    await for (final ent in dir.list()) {
      if (ent is! File || ent.path.endsWith(_partSuffix)) continue;
      final stat = await ent.stat();
      total += stat.size;
      entries.add(_CachedClip(ent, stat.size, stat.modified));
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final clip in entries) {
      if (total <= maxBytes) break;
      // Never the clip that was just fetched. Evicting it would return a File
      // that is already gone, so a caller would be told the download succeeded
      // and then find nothing there.
      if (clip.file.path == keepPath) continue;
      if (await _deleteQuietly(clip.file, 'over the $maxBytes byte quota')) {
        total -= clip.size;
      }
    }
  }

  /// Returns whether the file is gone. Never throws: one undeletable file must
  /// not stop the others being freed, and none of these deletions is something
  /// the user asked for or should be told about.
  Future<bool> _deleteQuietly(File file, String why) async {
    try {
      if (await file.exists()) await file.delete();
      return true;
    } catch (e) {
      debugPrint('offline video: could not delete ${file.path} ($why): $e');
      return false;
    }
  }

  @override
  Future<void> evict(String url) async {
    final f = await localFile(url);
    if (f != null && await f.exists()) {
      await f.delete();
    }
  }

  /// How much the finished library weighs.
  ///
  /// Partials are excluded on purpose: they are not clips anyone can watch, and
  /// counting them would make the number climb during a download and drop again
  /// when it finished, which reads as the cache losing data.
  @override
  Future<int> sizeBytes() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final ent in dir.list()) {
      if (ent is File && !ent.path.endsWith(_partSuffix)) {
        total += await ent.length();
      }
    }
    return total;
  }

  @override
  Future<void> clear() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return;
    await for (final ent in dir.list()) {
      if (ent is File) await ent.delete();
    }
  }
}

/// In-memory mock for tests + the default Provider binding.
class InMemoryOfflineVideoCache implements OfflineVideoCache {
  final Map<String, _FakeBlob> _store = {};

  @override
  Future<File?> localFile(String url) async => null;

  @override
  Future<File> download(String url,
      {String? from, ProgressCallback? onProgress}) async {
    // Keyed on [url] like the real one, so a test that caches a licensed
    // reference and then looks it up behaves the same way the device does.
    _store[url] = _FakeBlob(from ?? url, 1024 * 1024);
    onProgress?.call(1024 * 1024, 1024 * 1024);
    // Tests don't actually need the File handle; return a synthetic.
    return File('memory://$url');
  }

  @override
  Future<void> evict(String url) async {
    _store.remove(url);
  }

  @override
  Future<int> sizeBytes() async {
    var total = 0;
    for (final b in _store.values) {
      total += b.bytes;
    }
    return total;
  }

  @override
  Future<void> clear() async => _store.clear();

  bool isCached(String url) => _store.containsKey(url);

  /// What was actually fetched for [url], as opposed to what it is filed
  /// under. The two differ for licensed clips, and a test that cannot see the
  /// difference cannot catch the cache being keyed on an expiring URL.
  String? fetchedFor(String url) => _store[url]?.url;
}

class _FakeBlob {
  _FakeBlob(this.url, this.bytes);
  final String url;
  final int bytes;
}

class _CachedClip {
  _CachedClip(this.file, this.size, this.modified);
  final File file;
  final int size;
  final DateTime modified;
}
