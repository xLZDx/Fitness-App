// C14 (D-67): every error is reduced to a closed, log-safe slug. A raw message
// can embed object paths, URLs or user data and must never survive.
import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/state/body_scan_api.dart';
import 'package:fitness_app/features/body_scan/state/scrubbed_error.dart';

DioException _dio(DioExceptionType t, {int? status}) {
  final ro = RequestOptions(path: 'https://x/secret?sig=abc');
  return DioException(
    requestOptions: ro,
    type: t,
    message: 'raw https://x/secret',
    response: status == null
        ? null
        : Response<void>(requestOptions: ro, statusCode: status),
  );
}

void main() {
  test('BodyScanApiException keeps its slug', () {
    expect(scrubbedError(const BodyScanApiException('blur-unavailable')),
        'blur-unavailable');
  });

  group('FirebaseFunctionsException', () {
    test('a slug-shaped message wins', () {
      expect(
          scrubbedError(FirebaseFunctionsException(
              message: 'consent-required', code: 'failed-precondition')),
          'consent-required');
    });
    test('a free-text message falls back to the code, not the text', () {
      final s = scrubbedError(FirebaseFunctionsException(
          message: 'failed at /users/u1/secret.jpg', code: 'internal'));
      expect(s, 'internal');
      expect(s, isNot(contains('secret')));
    });
    test('an unusable code falls back to callable-error', () {
      expect(
          scrubbedError(
              FirebaseFunctionsException(message: 'Bad Text', code: 'Bad Code')),
          'callable-error');
      expect(scrubbedError(FirebaseFunctionsException(message: '', code: '')),
          'callable-error');
    });
  });

  group('DioException', () {
    test('an HTTP status becomes upload-http-<status>, whatever the type', () {
      expect(scrubbedError(_dio(DioExceptionType.badResponse, status: 403)),
          'upload-http-403');
      expect(scrubbedError(_dio(DioExceptionType.connectionError, status: 503)),
          'upload-http-503');
    });
    test('timeouts', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(scrubbedError(_dio(t)), 'network-timeout', reason: '$t');
      }
    });
    test('cancel and the rest', () {
      expect(scrubbedError(_dio(DioExceptionType.cancel)), 'cancelled');
      expect(scrubbedError(_dio(DioExceptionType.connectionError)),
          'network-error');
      expect(scrubbedError(_dio(DioExceptionType.unknown)), 'network-error');
    });
    test('the signed URL never appears in the slug', () {
      for (final t in DioExceptionType.values) {
        final s = scrubbedError(_dio(t));
        expect(s, isNot(contains('secret')));
        expect(s, isNot(contains('sig=')));
      }
    });
  });

  test('timeouts and sockets', () {
    expect(scrubbedError(TimeoutException('x /path')), 'network-timeout');
    expect(scrubbedError(const SocketException('host a.b refused')),
        'network-error');
  });

  test('anything else is unknown-error and leaks nothing', () {
    for (final e in <Object>[
      StateError('open /users/uid123/p.jpg'),
      ArgumentError('x'),
      'plain string with token=abc',
      42,
    ]) {
      expect(scrubbedError(e), 'unknown-error');
    }
  });

  test('every produced slug matches the closed slug grammar', () {
    final slug = RegExp(r'^[a-z0-9][a-z0-9:_,-]{0,59}$');
    final all = <Object>[
      const BodyScanApiException('x-y'),
      FirebaseFunctionsException(message: 'Free Text', code: 'not-found'),
      _dio(DioExceptionType.badResponse, status: 500),
      _dio(DioExceptionType.cancel),
      TimeoutException('t'),
      const SocketException('s'),
      Object(),
    ];
    for (final e in all) {
      expect(scrubbedError(e), matches(slug), reason: '$e');
    }
  });
}
