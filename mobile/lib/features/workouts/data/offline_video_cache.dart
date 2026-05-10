import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// On-disk cache for instructional videos so the app works in gym
/// basements with no signal. Premium-tier feature gated by the caller —
/// this layer doesn't know about subscriptions.
///
/// Each URL is hashed (sha1) into a stable filename inside the app's
/// document directory. The cache is *idempotent* — calling
/// [download] for an already-cached URL is a no-op that completes
/// immediately. [localFile] returns the file iff it exists.
abstract class OfflineVideoCache {
  Future<File?> localFile(String url);
  Future<File> download(String url, {ProgressCallback? onProgress});
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
      {ProgressCallback? onProgress}) async {
    final dir = await _cacheDir();
    final dest = File('${dir.path}/${_filenameFor(url)}');
    if (await dest.exists()) return dest;
    final tmp = File('${dest.path}.part');
    await _dio.download(
      url,
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
      {ProgressCallback? onProgress}) async {
    _store[url] = _FakeBlob(url, 1024 * 1024);
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
}

class _FakeBlob {
  _FakeBlob(this.url, this.bytes);
  final String url;
  final int bytes;
}
