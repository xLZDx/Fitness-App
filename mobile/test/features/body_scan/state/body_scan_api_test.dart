// C14: the body-scan callable client (design s7). A fake FirebaseFunctions
// records every callable; the client must build the exact payloads, parse
// tolerant responses and map every failure to a CLOSED slug (D-67).
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/body_scan/state/body_scan_api.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this._data);
  final T _data;
  @override
  T get data => _data;
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this._fn);
  final _Fn _fn;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final payload = Map<String, Object?>.from(parameters as Map);
    _fn.payloads.add(payload);
    final out = _fn.responder(payload);
    if (out is Exception) throw out;
    return _Result<T>(out as T);
  }
}

class _Fn extends Fake implements FirebaseFunctions {
  _Fn(this.responder);
  final Object? Function(Map<String, Object?>) responder;
  final List<Map<String, Object?>> payloads = [];
  final List<String> names = [];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    names.add(name);
    return _Callable(this);
  }
}

const _est = {
  'bodyFatPct': 21.5,
  'rangeLowPct': 18.0,
  'rangeHighPct': 25.0,
  'confidence': 'medium',
  'modelId': 'cloud-m',
  'modelVersion': '2',
};

Future<CreateScanResult> _create(CallableBodyScanApi api,
        {Map<ScanPose, bool> manual = const {}}) =>
    api.createBodyScan(
      scanId: 's1',
      takenAt: DateTime.utc(2026, 10, 1, 8),
      sexAtBirth: 'male',
      heightCm: 175,
      weightKg: 80.5,
      manualOverride: manual,
    );

void main() {
  group('mapCallableError', () {
    BodyScanApiException m(String code, String msg) => mapCallableError(
        FirebaseFunctionsException(message: msg, code: code));

    test('a closed-slug message is kept, anything else falls back to the code',
        () {
      expect(m('failed-precondition', 'consent-required').slug,
          'consent-required');
      expect(m('internal', 'Boom at /users/u1/x.jpg').slug, 'internal');
      expect(m('internal', 'UPPER').slug, 'internal');
      expect(m('', '').slug, 'callable-error');
      expect(m('internal', 'a' * 61).slug, 'internal',
          reason: 'over 60 chars is not a slug');
      expect(m('x', 'a' * 60).slug, 'a' * 60);
    });

    test('retriable slugs and codes', () {
      for (final s in [
        'estimate-in-progress',
        'scan-not-ready',
        'scan-create-conflict',
        'scan-create-failed',
        'scan-estimate-failed',
        'scan-delete-failed',
        'upload-url-failed',
        'scan-failed',
        'missing-upload:front',
      ]) {
        expect(m('failed-precondition', s).retriable, isTrue, reason: s);
      }
      for (final c in [
        'unavailable',
        'deadline-exceeded',
        'internal',
        'aborted',
        'unknown',
        'cancelled',
      ]) {
        expect(m(c, '').retriable, isTrue, reason: c);
      }
    });

    test('refusals are not retriable', () {
      for (final s in [
        'consent-required',
        'feature-disabled',
        'provider-not-configured',
        'account-deleting',
        'invalid-input',
      ]) {
        expect(m('failed-precondition', s).retriable, isFalse, reason: s);
      }
      expect(m('permission-denied', '').retriable, isFalse);
      expect(m('invalid-argument', '').retriable, isFalse);
    });

    test('scan-cancelled is never retriable even on a retriable code', () {
      final e = m('aborted', 'scan-cancelled');
      expect(e.slug, 'scan-cancelled');
      expect(e.retriable, isFalse);
      expect(e.isScanCancelled, isTrue);
      expect(e.code, 'aborted');
    });

    test('isMissingUpload matches the prefix only', () {
      expect(m('x', 'missing-upload:side').isMissingUpload, isTrue);
      expect(m('x', 'upload-missing').isMissingUpload, isFalse);
    });

    test('toString carries the slug, never a message', () {
      expect(const BodyScanApiException('abc').toString(),
          'BodyScanApiException(abc)');
    });
  });

  group('createBodyScan', () {
    test('sends the exact payload and parses a pending response', () async {
      final f = _Fn((_) => {
            'status': 'pending',
            'provider': {
              'id': 'cloud',
              'version': '3',
              'provisional': false,
              'requiresPhotos': true,
            },
            'uploads': {
              'front': {
                'url': 'https://u/f',
                'headers': {'Content-Type': 'image/jpeg', 'n': 5},
                'expiresAtMs': 1234.0,
              },
              'side': {'url': 'https://u/s'},
              'back': {'nourl': true},
            },
          });
      final r =
          await _create(CallableBodyScanApi(f), manual: {ScanPose.side: true});
      expect(f.names, ['createBodyScan']);
      expect(f.payloads.single, {
        'scanId': 's1',
        'takenAtMs': DateTime.utc(2026, 10, 1, 8).millisecondsSinceEpoch,
        'subject': {'sexAtBirth': 'male', 'heightCm': 175, 'weightKg': 80.5},
        'capture': {
          'manualOverride': {'front': false, 'side': true, 'back': false},
        },
      });
      expect(r.done, isFalse);
      expect(r.scanId, 's1');
      expect(r.estimate, isNull);
      expect(r.provider.id, 'cloud');
      expect(r.provider.version, '3');
      expect(r.provider.requiresPhotos, isTrue);
      expect(r.provider.provisional, isFalse);
      expect(r.uploads.keys, [ScanPose.front, ScanPose.side],
          reason: 'an entry without a url string is dropped');
      final fr = r.uploads[ScanPose.front]!;
      expect(fr.url, 'https://u/f');
      expect(fr.headers, {'Content-Type': 'image/jpeg', 'n': '5'});
      expect(fr.expiresAtMs, 1234);
      expect(r.uploads[ScanPose.side]!.expiresAtMs, 0);
      expect(r.uploads[ScanPose.side]!.headers, isEmpty);
    });

    test('a done replay carries the estimate with the provisional flag',
        () async {
      final f = _Fn((_) => {
            'status': 'done',
            'provider': {'id': 'p', 'version': '1', 'provisional': true},
            'estimate': _est,
          });
      final r = await _create(CallableBodyScanApi(f));
      expect(r.done, isTrue);
      expect(r.estimate!.value, 21.5);
      expect(r.estimate!.provisional, isTrue);
      expect(r.provider.requiresPhotos, isFalse);
      expect(r.uploads, isEmpty);
    });

    test('a garbage provider reads as an empty, photo-less provider', () async {
      final f = _Fn((_) => {'status': 'pending', 'provider': 'x'});
      final r = await _create(CallableBodyScanApi(f));
      expect(r.provider.id, '');
      expect(r.provider.requiresPhotos, isFalse);
    });

    test('a non-map response is the retriable bad-response slug', () async {
      final f = _Fn((_) => 'nope');
      await expectLater(
          _create(CallableBodyScanApi(f)),
          throwsA(isA<BodyScanApiException>()
              .having((e) => e.slug, 'slug', 'bad-response')
              .having((e) => e.retriable, 'retriable', isTrue)));
    });

    test('a FirebaseFunctionsException becomes a closed slug', () async {
      final f = _Fn((_) => FirebaseFunctionsException(
          message: 'consent-required', code: 'failed-precondition'));
      await expectLater(
          _create(CallableBodyScanApi(f)),
          throwsA(isA<BodyScanApiException>()
              .having((e) => e.slug, 'slug', 'consent-required')
              .having((e) => e.retriable, 'retriable', isFalse)
              .having((e) => e.code, 'code', 'failed-precondition')));
    });
  });

  group('estimateBodyScan', () {
    test('done with an estimate', () async {
      final f = _Fn((_) => {
            'status': 'done',
            'estimate': _est,
            'provider': {'provisional': false},
          });
      final r = await CallableBodyScanApi(f).estimateBodyScan('s1');
      expect(f.names, ['estimateBodyScan']);
      expect(f.payloads.single, {'scanId': 's1'});
      expect(r.estimate.modelId, 'cloud-m');
      expect(r.estimate.provisional, isFalse);
      expect(r.scanId, 's1');
    });

    test(
        'not done, or an unreadable estimate, is scan-estimate-failed (retriable)',
        () async {
      for (final body in <Map<String, Object?>>[
        {'status': 'pending', 'estimate': _est},
        {'status': 'done'},
        {
          'status': 'done',
          'estimate': {'bodyFatPct': 'x'}
        },
      ]) {
        final f = _Fn((_) => body);
        await expectLater(
            CallableBodyScanApi(f).estimateBodyScan('s1'),
            throwsA(isA<BodyScanApiException>()
                .having((e) => e.slug, 'slug', 'scan-estimate-failed')
                .having((e) => e.retriable, 'retriable', isTrue)),
            reason: '$body');
      }
    });
  });

  group('deleteBodyScan', () {
    test('sends scanId and photosOnly', () async {
      final f = _Fn((_) => {'ok': true});
      await CallableBodyScanApi(f).deleteBodyScan('s1_r2', photosOnly: true);
      expect(f.names, ['deleteBodyScan']);
      expect(f.payloads.single, {'scanId': 's1_r2', 'photosOnly': true});
    });

    test('a server failure surfaces as a slug', () async {
      final f = _Fn((_) => FirebaseFunctionsException(
          message: 'unavailable', code: 'unavailable'));
      await expectLater(
          CallableBodyScanApi(f).deleteBodyScan('s1', photosOnly: false),
          throwsA(isA<BodyScanApiException>()
              .having((e) => e.retriable, 'retriable', isTrue)));
    });
  });
}
