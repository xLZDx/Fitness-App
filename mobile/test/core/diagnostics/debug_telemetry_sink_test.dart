// S02 test epic 3, U34 (design 8.1 client sink resilience) and U35 (telemetry
// schema parity client to server).
//
// Oracles are literals from the design: 3 retries with doubling backoff, a local
// buffer of at most 500 events and 64 KiB where the OLDEST is dropped, a
// dropped-event counter reported in the next batch and capped at 255, and a
// caller that never waits for the network.
import 'dart:async';
import 'dart:convert';

import 'package:fitness_app/core/diagnostics/debug_telemetry_schema.dart';
import 'package:fitness_app/core/diagnostics/debug_telemetry_sink.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/s02_paths.dart';

Map<String, Object?> _payload(int n, {String area = 'sync', String level = 'info'}) => {
      'events': [
        for (var i = 0; i < n; i++)
          {'at': '2026-10-16T12:00:00Z', 'level': level, 'area': area, 'message': 'm$i'},
      ],
      'droppedCount': 0,
    };

class _Rig {
  _Rig({this.maxBufferEvents, this.maxBufferBytes}) {
    sink = CallableDebugTelemetrySink(
      invoke: (batch) async {
        calls.add(jsonDecode(jsonEncode(batch)) as Map<String, dynamic>);
        await behaviour(batch);
      },
      delay: (d) async => delays.add(d),
      maxBufferEvents: maxBufferEvents ?? 500,
      maxBufferBytes: maxBufferBytes ?? 64 * 1024,
    );
  }

  final int? maxBufferEvents;
  final int? maxBufferBytes;
  late final CallableDebugTelemetrySink sink;
  final List<Map<String, dynamic>> calls = [];
  final List<Duration> delays = [];
  Future<void> Function(Map<String, Object?>) behaviour = (_) async {};

  void failWith(Object e) => behaviour = (_) async => throw e;
  void succeed() => behaviour = (_) async {};

  List<Map<String, dynamic>> get delivered => [
        for (final c in calls)
          for (final e in (c['events'] as List)) e as Map<String, dynamic>,
      ];
}

/// Problems found when comparing a client field table with the shared fixture.
List<String> parityProblems(
  Map<String, TelemetryFieldSpec> client,
  Map<String, dynamic> fixture, {
  int clientCounterMax = kTelemetryCounterMax,
}) {
  final out = <String>[];
  final server = (fixture['event'] as Map).cast<String, dynamic>();
  for (final k in server.keys) {
    if (!client.containsKey(k)) out.add('client lacks field $k');
  }
  for (final k in client.keys) {
    if (!server.containsKey(k)) out.add('client has extra field $k');
  }
  for (final e in client.entries) {
    final s = server[e.key] as Map<String, dynamic>?;
    if (s == null) continue;
    final c = e.value;
    if (s['required'] != c.required) out.add('${e.key}: required differs');
    if (s['kind'] == 'enum') {
      if (c.values == null) {
        out.add('${e.key}: server enum, client is not an enumeration');
      } else if (jsonEncode(s['values']) != jsonEncode(c.values)) {
        out.add('${e.key}: enumeration differs');
      }
    } else if (s['kind'] == 'counter') {
      if (c.max == null) {
        out.add('${e.key}: server counter, client is not a counter');
      } else if (c.max != s['max']) {
        out.add('${e.key}: max ${c.max} vs ${s['max']}');
      }
    }
    if (c.max != null && c.max! > 255) out.add('${e.key}: counter above 255');
  }
  if (fixture['counterMax'] != clientCounterMax) out.add('counterMax differs');
  for (final k in (fixture['serverDerived'] as List)) {
    if (client.containsKey(k)) out.add('server-derived $k declared by the client');
  }
  return out;
}

final RegExp _forbidden = RegExp(
    r'lat|lon|lng|coord|geo|hash|heart|bpm|place|city|address|location|venue|street|position|(^|[^a-z])hr([^a-z]|$)',
    caseSensitive: false);

/// Source text without comment lines.
String _code(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

List<String> forbiddenNames(Map<String, TelemetryFieldSpec> table) => [
      for (final e in table.entries) ...[
        if (_forbidden.hasMatch(e.key)) e.key,
        for (final v in e.value.values ?? const <String>[])
          if (_forbidden.hasMatch(v)) '${e.key}=$v',
      ],
    ];

void main() {
  group('U34 client sink resilience', () {
    test('defaults are the design values (3 retries, 1 s base, 500 events, 64 KiB)',
        () {
      final s = CallableDebugTelemetrySink(invoke: (_) async {});
      expect(s.maxRetries, 3);
      expect(s.baseBackoff, const Duration(seconds: 1));
      expect(s.maxBufferEvents, 500);
      expect(s.maxBufferBytes, 65536);
    });

    for (final failure in <String, Object>{
      'permission-denied': FirebaseException(plugin: 'cloud_functions', code: 'permission-denied'),
      'unavailable': FirebaseException(plugin: 'cloud_functions', code: 'unavailable'),
      'timeout': TimeoutException('deadline'),
      'plain error': StateError('boom'),
    }.entries) {
      test('a ${failure.key} failure never throws into the caller', () async {
        final r = _Rig()..failWith(failure.value);
        await r.sink.send(_payload(3));
        await r.sink.flush();
        expect(r.calls, isNotEmpty, reason: 'the callable was really attempted');
      });
    }

    test('a permanently failing callable is tried 1 + 3 times with 1 s, 2 s, 4 s '
        'backoff, then given up', () async {
      final r = _Rig()..failWith(StateError('down'));
      await r.sink.send(_payload(1));
      await r.sink.flush();
      expect(r.calls, hasLength(4));
      expect(r.delays, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
    });

    test('success on the second attempt stops retrying after one delay', () async {
      final r = _Rig();
      var n = 0;
      r.behaviour = (_) async {
        if (++n == 1) throw StateError('once');
      };
      await r.sink.send(_payload(1));
      await r.sink.flush();
      expect(r.calls, hasLength(2));
      expect(r.delays, [const Duration(seconds: 1)]);
      expect(r.sink.bufferedCount, 0);
    });

    test('a success sends each event exactly once and leaves nothing buffered',
        () async {
      final r = _Rig();
      await r.sink.send(_payload(130));
      await r.sink.flush();
      expect(r.delivered, hasLength(130));
      expect(r.calls.map((c) => (c['events'] as List).length), [100, 30]);
      expect(r.sink.bufferedCount, 0);
      expect(r.delays, isEmpty);
    });

    test('the send is NOT awaited on the user path: the caller returns while the '
        'callable is still pending', () async {
      final r = _Rig();
      final gate = Completer<void>();
      r.behaviour = (_) => gate.future;
      var returned = false;
      unawaited(r.sink.send(_payload(2)).then((_) => returned = true));
      await pumpEventQueue();
      expect(returned, isTrue, reason: 'caller must not wait for the network');
      expect(r.calls, hasLength(1), reason: 'the callable was started');
      gate.complete();
      await r.sink.flush();
      expect(r.sink.bufferedCount, 0);
    });

    test('the buffer never exceeds 500 events and drops the OLDEST', () async {
      final r = _Rig()..failWith(StateError('down'));
      await r.sink.send(_payload(400, area: 'auth'));
      await r.sink.flush();
      expect(r.sink.bufferedCount, 400);
      await r.sink.send(_payload(400, area: 'sync'));
      await r.sink.flush();
      expect(r.sink.bufferedCount, 500, reason: 'bounded at 500');
      expect(r.sink.bufferedBytes, lessThanOrEqualTo(64 * 1024));

      r.calls.clear();
      r.succeed();
      await r.sink.send({'events': <Object?>[]});
      await r.sink.flush();
      final events = r.delivered;
      expect(events, hasLength(500));
      expect(events.where((e) => e['component'] == 'auth'), hasLength(100));
      expect(events.where((e) => e['component'] == 'sync'), hasLength(400),
          reason: 'the newest events must all survive');
      expect(events.first['component'], 'auth');
      expect(events.last['component'], 'sync');
      expect(events.indexWhere((e) => e['component'] == 'sync'), 100,
          reason: 'order is oldest first');
      for (final c in r.calls) {
        expect((c['events'] as List).length, lessThanOrEqualTo(100));
      }
    });

    test('the dropped count is reported in the NEXT batch as a bounded counter',
        () async {
      final r = _Rig(maxBufferEvents: 60)..failWith(StateError('down'));
      await r.sink.send(_payload(100));
      await r.sink.flush();
      expect(r.sink.bufferedCount, 60);
      expect(r.sink.pendingDropped, 40);

      r.calls.clear();
      r.succeed();
      await r.sink.send({'events': <Object?>[]});
      await r.sink.flush();
      expect(r.calls.first['droppedCount'], 40);
      expect(r.calls.skip(1).where((c) => c.containsKey('droppedCount')), isEmpty,
          reason: 'reported once');
      expect(r.sink.pendingDropped, 0);

      r.calls.clear();
      await r.sink.send(_payload(1));
      await r.sink.flush();
      expect(r.calls.single.containsKey('droppedCount'), isFalse,
          reason: 'a reported count is not repeated');
    });

    test('a failed report keeps the dropped count for the next try', () async {
      final r = _Rig(maxBufferEvents: 10)..failWith(StateError('down'));
      await r.sink.send(_payload(30));
      await r.sink.flush();
      expect(r.sink.pendingDropped, 20);
      await r.sink.send({'events': <Object?>[]});
      await r.sink.flush();
      expect(r.sink.pendingDropped, 20);
    });

    test('the reported dropped count never exceeds 255', () async {
      final r = _Rig(maxBufferEvents: 10)..failWith(StateError('down'));
      for (var i = 0; i < 5; i++) {
        await r.sink.send(_payload(100));
        await r.sink.flush();
      }
      expect(r.sink.pendingDropped, greaterThan(255));
      r.calls.clear();
      r.succeed();
      await r.sink.send({'events': <Object?>[]});
      await r.sink.flush();
      expect(r.calls.first['droppedCount'], 255);
    });

    test('the byte cap evicts the oldest as well (small cap injected)', () async {
      final r = _Rig(maxBufferBytes: 1000)..failWith(StateError('down'));
      await r.sink.send(_payload(40, area: 'auth'));
      await r.sink.send(_payload(40, area: 'sync'));
      await r.sink.flush();
      expect(r.sink.bufferedBytes, lessThanOrEqualTo(1000));
      expect(r.sink.bufferedCount, inInclusiveRange(10, 20));
      r.calls.clear();
      r.succeed();
      await r.sink.send({'events': <Object?>[]});
      await r.sink.flush();
      expect(r.delivered.last['component'], 'sync');
      expect(r.delivered.every((e) => e['component'] == 'sync'), isTrue,
          reason: 'only the newest events fit');
      expect(r.calls.first['droppedCount'], 60);
    });

    test('the default 64 KiB cap holds for the largest closed-schema events',
        () async {
      final r = _Rig(maxBufferEvents: 100000)..failWith(StateError('down'));
      await r.sink.send(_payload(3000, area: 'recognition', level: 'debug'));
      await r.sink.flush();
      expect(r.sink.bufferedBytes, lessThanOrEqualTo(64 * 1024));
    });
  });

  group('U35 telemetry schema parity client to server', () {
    final fixture = jsonDecode(repoFile(
                'functions/src/__tests__/activity/fixtures/telemetry_schema.json')
            .readAsStringSync())
        as Map<String, dynamic>;

    test('the client field table equals the shared fixture', () {
      expect(parityProblems(kTelemetryEventFields, fixture), isEmpty);
      expect((fixture['event'] as Map).keys, isNotEmpty,
          reason: 'the instrument must see the fixture');
    });

    test('limits equal the fixture and the design (255, 100 events, 16 KiB)', () {
      expect(fixture['counterMax'], 255);
      expect(kTelemetryCounterMax, 255);
      expect(kTelemetryMaxEvents, fixture['maxEvents']);
      expect(kTelemetryMaxBatchBytes, fixture['maxBatchBytes']);
      expect(kTelemetryMaxEvents, 100);
      expect(kTelemetryMaxBatchBytes, 16384);
      for (final e in kTelemetryEventFields.entries) {
        if (e.value.max != null) expect(e.value.max, lessThanOrEqualTo(255));
      }
    });

    test('identity, uid and receivedAt are not client fields', () {
      for (final k in ['identity', 'uid', 'receivedAt']) {
        expect(kTelemetryEventFields.containsKey(k), isFalse, reason: k);
      }
      expect(fixture['serverDerived'], containsAll(['identity', 'uid', 'receivedAt']));
    });

    test('every string field is an enumeration, every number a capped counter',
        () {
      for (final e in kTelemetryEventFields.entries) {
        expect((e.value.values == null) != (e.value.max == null), isTrue,
            reason: '${e.key} is exactly one of enumeration / counter');
      }
    });

    test('the parity checker can fail (positive controls)', () {
      final t = Map<String, TelemetryFieldSpec>.of(kTelemetryEventFields);
      // A counter maximum above 255.
      expect(
          parityProblems({
            ...t,
            'count': const TelemetryFieldSpec.counter(65535, required: false)
          }, fixture),
          isNotEmpty);
      // An extra latitude field.
      expect(
          parityProblems({
            ...t,
            'lat': const TelemetryFieldSpec.counter(255, required: false)
          }, fixture),
          isNotEmpty);
      // `identity` as a free string (modelled as an empty enumeration).
      expect(
          parityProblems({
            ...t,
            'identity': const TelemetryFieldSpec.enumeration([], required: false)
          }, fixture),
          isNotEmpty);
      // A changed enumeration.
      expect(
          parityProblems({
            ...t,
            'level': const TelemetryFieldSpec.enumeration(['debug', 'info'],
                required: true)
          }, fixture),
          isNotEmpty);
      // A dropped field.
      expect(parityProblems(Map.of(t)..remove('seq'), fixture), isNotEmpty);
      // A wrong counterMax constant.
      expect(parityProblems(t, fixture, clientCounterMax: 256), isNotEmpty);
    });
  });

  group('U25 client event schema declares no location / heart-rate / place field',
      () {
    test('the real table has none', () {
      expect(forbiddenNames(kTelemetryEventFields), isEmpty);
    });

    test('the scanner flags every forbidden shape (positive controls)', () {
      for (final name in [
        'lat', 'latitude', 'lon', 'lng', 'longitude', 'coords', 'geohash',
        'hr', 'heartRate', 'bpm', 'place', 'placeName', 'city', 'address',
        'location', 'position',
      ]) {
        expect(
            forbiddenNames({
              ...kTelemetryEventFields,
              name: const TelemetryFieldSpec.counter(255, required: false),
            }),
            [name],
            reason: name);
      }
      // An enumeration VALUE naming a place is flagged too.
      expect(
          forbiddenNames({
            'component': const TelemetryFieldSpec.enumeration(['app', 'geohash'],
                required: true),
          }),
          ['component=geohash']);
    });
  });

  group('U34/I14 source guards', () {
    final text = _code(
        repoFile('mobile/lib/core/diagnostics/debug_telemetry_sink.dart').readAsStringSync());

    test('the sink uses the callable and does not write debug_sessions', () {
      expect(text, contains("httpsCallable('sendDebugTelemetry')"));
      expect(text, isNot(contains('debug_sessions')));
      expect(text, isNot(contains('cloud_firestore')));
      expect(RegExp(r"collection\(\s*'debug_sessions'").hasMatch(text), isFalse);
    });
  });
}
