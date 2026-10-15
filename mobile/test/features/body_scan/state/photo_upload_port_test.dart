// C14: the signed-URL PUT (design s9). A scripted Dio adapter plays the
// server; the port must send the signed headers, retry transport/5xx with the
// 1/2/4 s backoff, never retry a 403 or other 4xx, honour expiry and cancel.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/state/body_scan_api.dart';
import 'package:fitness_app/features/body_scan/state/photo_upload_port.dart';

/// Each entry is a status code (int) or an exception to throw.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.script);
  final List<Object> script;
  final List<RequestOptions> seen = [];
  Completer<void>? hold;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    if (hold != null) {
      await Future.any([hold!.future, cancelFuture ?? Completer<void>().future]);
      if (options.cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(
            requestOptions: options, reason: options.cancelToken!.cancelError);
      }
    }
    final next = script.isEmpty ? 200 : script.removeAt(0);
    if (next is int) {
      return ResponseBody.fromString('', next);
    }
    throw next;
  }

  @override
  void close({bool force = false}) {}
}

BodyScanUploadTarget _target({int expires = 0}) => BodyScanUploadTarget(
      url: 'https://storage.example/obj?sig=1',
      headers: const {'Content-Type': 'image/jpeg', 'x-goog-meta': 'a'},
      expiresAtMs: expires,
    );

final _jpeg = Uint8List.fromList(List.generate(64, (i) => i));

DioException _transport(RequestOptions o) =>
    DioException.connectionError(requestOptions: o, reason: 'down');

({DioPhotoUploadPort port, _Adapter adapter, List<Duration> delays}) _make(
    List<Object> script,
    {int nowMs = 1000}) {
  final adapter = _Adapter(script);
  final dio = Dio()..httpClientAdapter = adapter;
  final delays = <Duration>[];
  final port = DioPhotoUploadPort(
    dio: dio,
    delay: (d) async => delays.add(d),
    nowMs: () => nowMs,
  );
  return (port: port, adapter: adapter, delays: delays);
}

Future<BodyScanApiException> _fail(Future<void> f) async {
  try {
    await f;
  } on BodyScanApiException catch (e) {
    return e;
  }
  fail('expected a BodyScanApiException');
}

void main() {
  test('backoff constants are 1, 2, 4 seconds', () {
    expect(kUploadBackoff,
        [const Duration(seconds: 1), const Duration(seconds: 2), const Duration(seconds: 4)]);
  });

  test('a 200 PUT sends the signed headers, the exact URL and content length',
      () async {
    final m = _make([200]);
    final progress = <int>[];
    await m.port.put(_target(), _jpeg, onProgress: (s, t) => progress.add(t));
    final o = m.adapter.seen.single;
    expect(o.method, 'PUT');
    expect(o.uri.toString(), 'https://storage.example/obj?sig=1');
    expect(o.headers['Content-Type'], 'image/jpeg');
    expect(o.headers['x-goog-meta'], 'a');
    expect(o.headers[Headers.contentLengthHeader], 64);
    expect(m.delays, isEmpty);
  });

  test('a 5xx is retried and the second 200 succeeds after a 1 s wait', () async {
    final m = _make([503, 200]);
    await m.port.put(_target(), _jpeg);
    expect(m.adapter.seen, hasLength(2));
    expect(m.delays, [const Duration(seconds: 1)]);
  });

  test('transport errors exhaust three attempts with 1 s then 2 s, then upload-failed',
      () async {
    final ro = RequestOptions(path: 'x');
    final m = _make([_transport(ro), _transport(ro), _transport(ro)]);
    final e = await _fail(m.port.put(_target(), _jpeg));
    expect(e.slug, 'upload-failed');
    expect(e.retriable, isTrue);
    expect(m.adapter.seen, hasLength(3));
    expect(m.delays, [const Duration(seconds: 1), const Duration(seconds: 2)],
        reason: 'no wait after the last attempt');
  });

  test('408 and 429 are retried like transport errors', () async {
    final m = _make([408, 429, 200]);
    await m.port.put(_target(), _jpeg);
    expect(m.adapter.seen, hasLength(3));
  });

  for (final s in [401, 403]) {
    test('$s means the URL expired: no retry, upload-url-expired (retriable)',
        () async {
      final m = _make([s, 200]);
      final e = await _fail(m.port.put(_target(), _jpeg));
      expect(e.slug, 'upload-url-expired');
      expect(e.retriable, isTrue);
      expect(m.adapter.seen, hasLength(1));
      expect(m.delays, isEmpty);
    });
  }

  for (final s in [400, 404, 413, 422]) {
    test('$s is rejected for good: no retry, not retriable', () async {
      final m = _make([s, 200]);
      final e = await _fail(m.port.put(_target(), _jpeg));
      expect(e.slug, 'upload-rejected');
      expect(e.retriable, isFalse);
      expect(m.adapter.seen, hasLength(1));
    });
  }

  test('three 500s give upload-failed', () async {
    final m = _make([500, 502, 504]);
    final e = await _fail(m.port.put(_target(), _jpeg));
    expect(e.slug, 'upload-failed');
    expect(m.adapter.seen, hasLength(3));
  });

  group('expiry', () {
    test('a URL already past expiresAtMs is refused without any request', () async {
      final m = _make([200], nowMs: 5000);
      final e = await _fail(m.port.put(_target(expires: 5000), _jpeg));
      expect(e.slug, 'upload-url-expired');
      expect(m.adapter.seen, isEmpty);
    });

    test('one millisecond before expiry still uploads', () async {
      final m = _make([200], nowMs: 4999);
      await m.port.put(_target(expires: 5000), _jpeg);
      expect(m.adapter.seen, hasLength(1));
    });

    test('expiresAtMs 0 means unknown and is never treated as expired', () async {
      final m = _make([200], nowMs: 9999999);
      await m.port.put(_target(expires: 0), _jpeg);
      expect(m.adapter.seen, hasLength(1));
    });
  });

  group('abortInFlight', () {
    test('with nothing in flight it is a harmless no-op', () {
      _make([]).port.abortInFlight();
    });

    test('aborting a pending PUT throws cancelled (not retriable) and stops retrying',
        () async {
      final m = _make([200]);
      m.adapter.hold = Completer<void>();
      final fut = _fail(m.port.put(_target(), _jpeg));
      for (var i = 0; i < 20 && m.adapter.seen.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      m.port.abortInFlight();
      final e = await fut;
      expect(e.slug, 'cancelled');
      expect(e.retriable, isFalse);
      expect(m.adapter.seen, hasLength(1), reason: 'a cancel is not retried');
      expect(m.delays, isEmpty);
    });

    test('a later put gets a fresh token and works after an earlier abort',
        () async {
      final m = _make([200]);
      m.port.abortInFlight();
      await m.port.put(_target(), _jpeg);
      expect(m.adapter.seen, hasLength(1));
    });
  });
}
