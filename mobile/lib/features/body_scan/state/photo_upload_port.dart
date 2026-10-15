/// Upload of one blurred JPEG to a signed URL (design s9 "Upload"). The port
/// hides `dio` so the job runner is testable with a fake; the real
/// implementation PUTs with the headers the server signed, up to three
/// attempts with 1 / 2 / 4 s backoff. A 403 or an expired URL is NOT retried
/// here: the runner asks `createBodyScan` for fresh URLs (idempotent).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'body_scan_api.dart';

abstract class PhotoUploadPort {
  /// Uploads [jpeg] to [target]. Throws a [BodyScanApiException] with a closed
  /// slug: `upload-url-expired` (403 or past `expiresAtMs`, fetch new URLs),
  /// `upload-rejected` (other 4xx, not retriable) or `upload-failed`
  /// (transport or 5xx after all attempts, retriable).
  Future<void> put(
    BodyScanUploadTarget target,
    Uint8List jpeg, {
    void Function(int sent, int total)? onProgress,
  });

  /// Aborts a PUT in flight (user cancel); the pending `put` throws
  /// `cancelled`.
  void abortInFlight();
}

/// Backoff between attempts of one PUT.
const List<Duration> kUploadBackoff = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];

class DioPhotoUploadPort implements PhotoUploadPort {
  DioPhotoUploadPort({
    Dio? dio,
    Future<void> Function(Duration)? delay,
    int Function()? nowMs,
  })  : _dio = dio ?? Dio(),
        _delay = delay ?? Future<void>.delayed,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Dio _dio;
  final Future<void> Function(Duration) _delay;
  final int Function() _nowMs;
  CancelToken? _token;

  @override
  void abortInFlight() {
    _token?.cancel('user-cancelled');
  }

  @override
  Future<void> put(
    BodyScanUploadTarget target,
    Uint8List jpeg, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (target.expiresAtMs > 0 && _nowMs() >= target.expiresAtMs) {
      throw const BodyScanApiException('upload-url-expired');
    }
    final token = _token = CancelToken();
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _dio.put<void>(
          target.url,
          data: Stream<List<int>>.value(jpeg),
          cancelToken: token,
          onSendProgress: onProgress,
          options: Options(
            headers: {
              ...target.headers,
              Headers.contentLengthHeader: jpeg.length,
            },
            // The server answers 200; anything else is judged below.
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
        return;
      } on DioException catch (e) {
        last = e;
        if (CancelToken.isCancel(e)) {
          throw const BodyScanApiException('cancelled', retriable: false);
        }
        final status = e.response?.statusCode;
        if (status == 403 || status == 401) {
          throw const BodyScanApiException('upload-url-expired');
        }
        if (status != null && status >= 400 && status < 500 && status != 408 && status != 429) {
          throw const BodyScanApiException('upload-rejected', retriable: false);
        }
      }
      if (attempt < 2) await _delay(kUploadBackoff[attempt]);
    }
    assert(last != null);
    throw const BodyScanApiException('upload-failed');
  }
}
