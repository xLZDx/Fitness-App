// S02 test epic 16c: the real callable clients of remediation J2. Oracles:
// S02_DESIGN.md 17 item 25 and S02_REMEDIATION_J_TEST_NOTES.md (CLIENT J2 (c),
// (d)), not the code under test.
//
// `FirebaseFunctions` and `HttpsCallable` are faked (`Fake implements`), so the
// real `CloudFunctionsActivityStreamClient` and
// `CloudFunctionsActivityTombstonePusher` code runs; the fake records every
// callable name and payload, so "before any network call" is observable.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fitness_app/features/activity/repository/account_changed.dart';
import 'package:fitness_app/features/activity/repository/activity_stream_uploader.dart';
import 'package:fitness_app/features/activity/repository/cloud_functions_activity_tombstone_pusher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.owner);
  final _Fns owner;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    owner.sent.add(parameters as Map<String, Object?>);
    throw owner.error;
  }
}

class _Fns extends Fake implements FirebaseFunctions {
  _Fns(this.error);
  final Object error;
  final List<String> names = [];
  final List<Map<String, Object?>> sent = [];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    names.add(name);
    return _Callable(this);
  }
}

FirebaseFunctionsException _err(String code, [String message = '']) =>
    FirebaseFunctionsException(code: code, message: message);

final _changed = throwsA(isA<ConsentAccountChangedException>());

void main() {
  group('stream client: null expectedUid fails closed before any call', () {
    test('create', () async {
      final f = _Fns(_err('unavailable'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      await expectLater(
          c.create(activityId: 'a', bytes: 1, contentSha256: 's', expectedUid: null),
          _changed);
      expect(f.names, isEmpty, reason: 'no callable created');
      expect(f.sent, isEmpty);
    });

    test('commit', () async {
      final f = _Fns(_err('unavailable'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      await expectLater(
          c.commit(activityId: 'a', uploadId: 'u', expectedUid: null), _changed);
      expect(f.names, isEmpty);
      expect(f.sent, isEmpty);
    });
  });

  group('stream client: payload carries the initiating uid', () {
    test('create sends expectedUid with the request fields', () async {
      final f = _Fns(_err('unavailable'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      await expectLater(
          c.create(activityId: 'a', bytes: 7, contentSha256: 's', expectedUid: 'A'),
          throwsA(isA<StreamUploadTransient>()));
      expect(f.names, ['createActivityStreamUpload']);
      expect(f.sent.single,
          {'expectedUid': 'A', 'activityId': 'a', 'bytes': 7, 'contentSha256': 's'});
    });

    test('commit sends expectedUid with the request fields', () async {
      final f = _Fns(_err('unavailable'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      await expectLater(
          c.commit(activityId: 'a', uploadId: 'u', expectedUid: 'A'),
          throwsA(isA<StreamUploadTransient>()));
      expect(f.names, ['commitActivityStream']);
      expect(f.sent.single,
          {'expectedUid': 'A', 'activityId': 'a', 'uploadId': 'u'});
    });
  });

  group('stream client: server refusal mapping', () {
    test('failed-precondition + account_changed -> ConsentAccountChanged '
        '(create and commit)', () async {
      final f = _Fns(_err('failed-precondition', 'account_changed'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      await expectLater(
          c.create(activityId: 'a', bytes: 1, contentSha256: 's', expectedUid: 'A'),
          _changed);
      await expectLater(
          c.commit(activityId: 'a', uploadId: 'u', expectedUid: 'A'), _changed);
      expect(f.sent, hasLength(2), reason: 'the calls were really sent');
    });

    test('failed-precondition + account_deleting is NOT mapped: it stays a '
        'refusal carrying the message', () async {
      final f = _Fns(_err('failed-precondition', 'account_deleting'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      for (final run in <Future<void> Function()>[
        () => c.create(
            activityId: 'a', bytes: 1, contentSha256: 's', expectedUid: 'A'),
        () => c.commit(activityId: 'a', uploadId: 'u', expectedUid: 'A'),
      ]) {
        Object? caught;
        try {
          await run();
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<StreamUploadRefused>());
        expect(caught, isNot(isA<ConsentAccountChangedException>()));
      }
    });

    test('another code with the message account_changed is NOT mapped',
        () async {
      final f = _Fns(_err('permission-denied', 'account_changed'));
      final c = CloudFunctionsActivityStreamClient(functions: f);
      Object? caught;
      try {
        await c.commit(activityId: 'a', uploadId: 'u', expectedUid: 'A');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StreamUploadRefused>());
    });
  });

  group('tombstone pusher', () {
    test('null expectedUid -> ConsentAccountChanged before any callable',
        () async {
      final f = _Fns(_err('unavailable'));
      await expectLater(
          CloudFunctionsActivityTombstonePusher(functions: f).push('a', null),
          _changed);
      expect(f.names, isEmpty);
      expect(f.sent, isEmpty);
    });

    test('the request carries expectedUid and the activity id', () async {
      final f = _Fns(_err('unavailable'));
      await expectLater(
          CloudFunctionsActivityTombstonePusher(functions: f).push('a', 'A'),
          throwsA(isA<FirebaseFunctionsException>()));
      expect(f.names, ['deleteActivity']);
      expect(f.sent.single, {'activityId': 'a', 'expectedUid': 'A'});
    });

    test('failed-precondition + account_changed -> ConsentAccountChanged',
        () async {
      final f = _Fns(_err('failed-precondition', 'account_changed'));
      await expectLater(
          CloudFunctionsActivityTombstonePusher(functions: f).push('a', 'A'),
          _changed);
      expect(f.sent, hasLength(1));
    });

    test('account_deleting is NOT mapped: the original exception is rethrown',
        () async {
      final f = _Fns(_err('failed-precondition', 'account_deleting'));
      Object? caught;
      try {
        await CloudFunctionsActivityTombstonePusher(functions: f).push('a', 'A');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FirebaseFunctionsException>());
      expect((caught! as FirebaseFunctionsException).message, 'account_deleting');
    });
  });
}
