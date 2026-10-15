/// Client of the `manageBodyScanData` callable (design s7.8, D-62): the bulk
/// privacy actions of the retention screen. Server contract in
/// `functions/src/body_scan/manage.ts`.
///
/// The server handles one page (200 scans) per call and answers
/// `nextCursor` while more remain, so every action here loops until the server
/// stops returning a cursor. Failures are reduced to a closed slug (D-67).
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/functions_region.dart';
import 'body_scan_api.dart' show BodyScanApiException, mapCallableError;

/// Upper bound on pages per action: 200 scans per page, so 500 pages is far
/// beyond any real account and only guards against a server that never stops.
const int kManageMaxPages = 500;

abstract class BodyScanManageApi {
  /// Makes a LOWERED retention retroactive; returns the scans processed.
  Future<int> applyRetention(int retentionDays);

  /// Deletes the photos of every scan; the estimates stay.
  Future<int> deleteAllPhotos();

  /// Deletes every scan's photos and turns the scans into tombstones.
  Future<int> deleteAllScans();
}

class CallableBodyScanManageApi implements BodyScanManageApi {
  CallableBodyScanManageApi([this._injected]);

  final FirebaseFunctions? _injected;

  FirebaseFunctions get _functions => _injected ?? functionsForRegion;

  Future<int> _run(String action, {int? retentionDays}) async {
    var processed = 0;
    String? cursor;
    String? fenceToken;
    for (var page = 0; page < kManageMaxPages; page++) {
      final Map<String, dynamic> body;
      try {
        final res = await _functions.httpsCallable('manageBodyScanData').call<Object?>({
          'action': action,
          if (retentionDays != null) 'retentionDays': retentionDays,
          if (cursor != null) 'cursor': cursor,
          if (cursor != null && fenceToken != null) 'fenceToken': fenceToken,
        });
        final raw = res.data;
        if (raw is! Map) {
          throw const BodyScanApiException('bad-response', retriable: true);
        }
        body = Map<String, dynamic>.from(raw);
      } on FirebaseFunctionsException catch (e) {
        throw mapCallableError(e);
      }
      final n = body['processed'];
      if (n is num) processed += n.toInt();
      final next = body['nextCursor'];
      if (next is! String || next.isEmpty) return processed;
      cursor = next;
      final token = body['fenceToken'];
      fenceToken = token is String ? token : null;
    }
    throw const BodyScanApiException('scan-manage-failed', retriable: true);
  }

  @override
  Future<int> applyRetention(int retentionDays) =>
      _run('applyRetention', retentionDays: retentionDays);

  @override
  Future<int> deleteAllPhotos() => _run('deleteAllPhotos');

  @override
  Future<int> deleteAllScans() => _run('deleteAllScans');
}

/// Constructing the client touches no Firebase API; with the cloud path off
/// nothing calls it.
final bodyScanManageApiProvider =
    Provider<BodyScanManageApi>((_) => CallableBodyScanManageApi());
