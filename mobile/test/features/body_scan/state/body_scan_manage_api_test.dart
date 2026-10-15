// C16 functional tests: the manageBodyScanData client (design s7.8, D-62, D-67).
// A fake FirebaseFunctions records every callable invocation; the client must
// page on nextCursor, sum `processed`, send the right action payload, and map
// failures to closed slugs.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_api.dart'
    show BodyScanApiException;
import 'package:fitness_app/features/body_scan/state/body_scan_manage_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this._data);
  final T _data;
  @override
  T get data => _data;
}

typedef _Responder = Object? Function(Map<String, Object?> payload, int call);

class _Callable extends Fake implements HttpsCallable {
  _Callable(this._fn);
  final _FakeFunctions _fn;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final payload = Map<String, Object?>.from(parameters as Map);
    _fn.payloads.add(payload);
    final out = _fn.responder(payload, _fn.payloads.length);
    if (out is Exception) throw out;
    return _Result<T>(out as T);
  }
}

class _FakeFunctions extends Fake implements FirebaseFunctions {
  _FakeFunctions(this.responder);
  final _Responder responder;
  final List<Map<String, Object?>> payloads = [];
  final List<String> names = [];

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    names.add(name);
    return _Callable(this);
  }
}

CallableBodyScanManageApi _api(_FakeFunctions f) =>
    CallableBodyScanManageApi(f);

void main() {
  group('paging on nextCursor', () {
    test('applyRetention loops until no cursor and sums processed', () async {
      final f = _FakeFunctions((p, n) => switch (n) {
            1 => {'processed': 200, 'nextCursor': 'c1'},
            2 => {'processed': 200, 'nextCursor': 'c2'},
            _ => {'processed': 37},
          });
      final total = await _api(f).applyRetention(30);

      expect(total, 437);
      expect(f.payloads, hasLength(3));
      expect(f.names.toSet(), {'manageBodyScanData'});
      expect(f.payloads[0], {'action': 'applyRetention', 'retentionDays': 30});
      expect(f.payloads[1],
          {'action': 'applyRetention', 'retentionDays': 30, 'cursor': 'c1'});
      expect(f.payloads[2],
          {'action': 'applyRetention', 'retentionDays': 30, 'cursor': 'c2'});
    });

    test('deleteAllPhotos sends the action without retentionDays and pages',
        () async {
      final f = _FakeFunctions((p, n) => n == 1
          ? {'processed': 5, 'nextCursor': 'x'}
          : {'processed': 2, 'nextCursor': ''});
      final total = await _api(f).deleteAllPhotos();
      expect(total, 7);
      expect(f.payloads[0], {'action': 'deleteAllPhotos'});
      expect(f.payloads[1], {'action': 'deleteAllPhotos', 'cursor': 'x'});
      expect(f.payloads, hasLength(2),
          reason: 'an empty cursor string ends the loop');
    });

    test('deleteAllScans sends its own action', () async {
      final f = _FakeFunctions((p, n) => {'processed': 3});
      expect(await _api(f).deleteAllScans(), 3);
      expect(f.payloads.single, {'action': 'deleteAllScans'});
    });

    test('a single page without a cursor makes exactly one call', () async {
      final f = _FakeFunctions((p, n) => {'processed': 0});
      expect(await _api(f).deleteAllPhotos(), 0);
      expect(f.payloads, hasLength(1));
    });

    test('missing or non-numeric processed counts as zero; cursor still '
        'followed', () async {
      final f = _FakeFunctions((p, n) => n == 1
          ? {'processed': 'many', 'nextCursor': 'c'}
          : {'nextCursor': null});
      expect(await _api(f).deleteAllScans(), 0);
      expect(f.payloads, hasLength(2));
    });

    test('a numeric processed given as double is truncated into the sum',
        () async {
      final f = _FakeFunctions((p, n) => {'processed': 4.0});
      expect(await _api(f).deleteAllPhotos(), 4);
    });

    test('a server that never stops is cut off at kManageMaxPages with a '
        'retriable scan-manage-failed', () async {
      final f = _FakeFunctions((p, n) => {'processed': 1, 'nextCursor': 'again'});
      await expectLater(
        _api(f).deleteAllScans(),
        throwsA(isA<BodyScanApiException>()
            .having((e) => e.slug, 'slug', 'scan-manage-failed')
            .having((e) => e.retriable, 'retriable', isTrue)),
      );
      expect(f.payloads, hasLength(kManageMaxPages));
    });
  });

  group('failures map to closed slugs (D-67)', () {
    test('a non-map response is bad-response and stops paging', () async {
      final f = _FakeFunctions((p, n) => 'oops');
      await expectLater(
        _api(f).deleteAllPhotos(),
        throwsA(isA<BodyScanApiException>()
            .having((e) => e.slug, 'slug', 'bad-response')
            .having((e) => e.retriable, 'retriable', isTrue)),
      );
      expect(f.payloads, hasLength(1));
    });

    test('a callable error in the middle of paging surfaces its slug and '
        'does not continue', () async {
      final f = _FakeFunctions((p, n) => n == 1
          ? {'processed': 200, 'nextCursor': 'c1'}
          : FirebaseFunctionsException(
              message: 'feature-disabled', code: 'failed-precondition'));
      await expectLater(
        _api(f).applyRetention(90),
        throwsA(isA<BodyScanApiException>()
            .having((e) => e.slug, 'slug', 'feature-disabled')
            .having((e) => e.retriable, 'retriable', isFalse)
            .having((e) => e.code, 'code', 'failed-precondition')),
      );
      expect(f.payloads, hasLength(2));
    });

    test('a raw SDK message is never leaked: it is replaced by the code',
        () async {
      final f = _FakeFunctions((p, n) => FirebaseFunctionsException(
          message: 'Internal error at /srv/app/index.js:42 for uid=abc',
          code: 'unavailable'));
      await expectLater(
        _api(f).deleteAllScans(),
        throwsA(isA<BodyScanApiException>()
            .having((e) => e.slug, 'slug', 'unavailable')
            .having((e) => e.retriable, 'retriable', isTrue)),
      );
    });
  });
}
