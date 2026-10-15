/// Reduces any error to a closed, log-safe slug (D-67). A raw exception text
/// can embed object paths, URLs or user data, so only a slug may be persisted
/// in `ScanAnalysis.lastError` or sent to `recordError`.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';

import 'body_scan_api.dart';

final RegExp _slug = RegExp(r'^[a-z0-9][a-z0-9:_,-]{0,59}$');

/// A closed slug for [error]; never the exception message of an unknown type.
String scrubbedError(Object error) {
  if (error is BodyScanApiException) return error.slug;
  if (error is FirebaseFunctionsException) {
    // The server throws closed slugs as the HttpsError message.
    final m = error.message;
    if (m != null && _slug.hasMatch(m)) return m;
    return _slugOrFallback(error.code, 'callable-error');
  }
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) return 'upload-http-$status';
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'network-timeout',
      DioExceptionType.cancel => 'cancelled',
      _ => 'network-error',
    };
  }
  if (error is TimeoutException) return 'network-timeout';
  if (error is SocketException) return 'network-error';
  return 'unknown-error';
}

String _slugOrFallback(String? candidate, String fallback) =>
    candidate != null && _slug.hasMatch(candidate) ? candidate : fallback;
