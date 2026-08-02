import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
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

class FileOfflineVideoCache implements OfflineVideoCache {
  FileOfflineVideoCache({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<Directory> _cacheDir() async {
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
    return await f.exists() ? f : null;
  }

  @override
  Future<File> download(String url,
      {String? from, ProgressCallback? onProgress}) async {
    final dir = await _cacheDir();
    final dest = File('${dir.path}/${_filenameFor(url)}');
    if (await dest.exists()) return dest;
    final tmp = File('${dest.path}.part');
    await _dio.download(
      from ?? url,
      tmp.path,
      onReceiveProgress: onProgress,
      options: Options(
        // Avoid hanging the user's session on a flaky CDN; bail and
        // fall back to streaming if the download takes too long.
        receiveTimeout: const Duration(minutes: 5),
      ),
    );
    await tmp.rename(dest.path);
    return dest;
  }

  @override
  Future<void> evict(String url) async {
    final f = await localFile(url);
    if (f != null && await f.exists()) {
      await f.delete();
    }
  }

  @override
  Future<int> sizeBytes() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final ent in dir.list()) {
      if (ent is File) {
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
