// Functional tests of the V0 app wiring (app_wiring.dart): id sanitising,
// install id, writer proof, gateway field mapping, runtime start/stop, the
// binding provider (sign-in / sign-out / account change) and the status
// provider that feeds the chip. SQLite over sqflite_common_ffi, real files.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/core/config/workout_queue_flag.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/offline/app_wiring.dart';
import 'package:fitness_app/features/workouts/offline/command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/command_record.dart';
import 'package:fitness_app/features/workouts/offline/sender.dart';
import 'package:fitness_app/features/workouts/offline/sqlite_command_queue_store.dart';
import 'package:fitness_app/features/workouts/offline/status.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart'
    show setupFirebaseCoreMocks;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/offline_test_support.dart';

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// Counts sendAvailable calls; optionally throws.
class _CountingSender extends CommandSender {
  _CountingSender(CommandSender real, {this.throwing = false})
      : super(
          store: real.store,
          transport: real.transport,
          deviceInstallId: real.deviceInstallId,
          clientBuild: real.clientBuild,
          writerProof: real.writerProof,
        );
  final bool throwing;
  int calls = 0;
  @override
  Future<List<SendReport>> sendAvailable({int maxRecords = kQueueRecordCap}) async {
    calls++;
    if (throwing) throw StateError('boom');
    return <SendReport>[];
  }
}

Future<bool> _until(bool Function() ok, {int ms = 4000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    if (ok()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return ok();
}

Map<String, dynamic> _payload(CommandRecord r) =>
    jsonDecode(utf8.decode(r.canonicalBytes!)) as Map<String, dynamic>;

const _bytes43 = 43; // 32 bytes, base64url without padding

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late PathProviderPlatform savedPaths;
  final cleanup = <Future<void> Function()>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('app_wiring_');
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(tmp.path);
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    for (final c in cleanup.reversed) {
      try {
        await c();
      } catch (_) {}
    }
    cleanup.clear();
    PathProviderPlatform.instance = savedPaths;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ---------------------------------------------------------------------
  group('queueSafeId / queueSessionIdOf', () {
    test('keeps legal characters', () {
      expect(queueSafeId('Abc_09-z'), 'Abc_09-z');
    });
    final valid = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
    final nasty = <String>[
      '', ' ', 'a b', 'a b/c.d:eé\u{1F4AA}', '__x__', '____', '__proto__',
      'a' * 129, 'a' * 500, '_' * 300, 'é' * 10, 'day_a b', '日本語',
      'a\u0000b', '.',
    ];
    test('valid ids within max pass through unchanged', () {
      for (final raw in ['Abc_09-z', 'a', 'day_1', 'a' * 128, '_x', 'x_', '_a_',
          '-', 'ea_air_squat', 'a__b']) {
        expect(queueSafeId(raw), raw, reason: raw);
      }
      expect(queueSafeId('a' * 64, max: 64), 'a' * 64);
    });
    test('every other input yields a valid id: empty, reserved, bad chars, '
        'too long', () {
      for (final raw in nasty) {
        final id = queueSafeId(raw);
        expect(valid.hasMatch(id), isTrue, reason: 'raw=[$raw] id=$id');
        expect(RegExp(r'^__.*__$').hasMatch(id), isFalse, reason: id);
        expect(id, isNot(raw), reason: 'an invalid raw id must be rewritten');
      }
    });
    test('reserved __x__ and empty are rewritten, not kept', () {
      expect(queueSafeId('__x__'), startsWith('s_'));
      expect(queueSafeId(''), startsWith('s_'));
    });
    test('max is honoured (64) for long, reserved and empty inputs', () {
      for (final raw in ['a' * 200, '__x__', '', 'a b' * 40]) {
        final id = queueSafeId(raw, max: 64);
        expect(id.length, lessThanOrEqualTo(64), reason: raw);
        expect(RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id), isTrue);
      }
      expect(queueSafeId('a' * 65, max: 64), isNot('a' * 65));
      expect(queueSafeId('a' * 500), hasLength(lessThanOrEqualTo(128)));
    });
    test('deterministic: the same raw always gives the same id', () {
      for (final raw in nasty) {
        expect(queueSafeId(raw), queueSafeId(raw));
        expect(queueSafeId(raw, max: 64), queueSafeId(raw, max: 64));
      }
    });
    test('distinct raw ids that sanitise alike do not collide', () {
      final raws = <String>[
        'a.b', 'a_b', 'a b', 'a/b', 'a:b', 'a-b', 'aéb', 'aèb',
        '__x__', '__y__', '', ' ', '  ', 'é', 'è',
        'a' * 129, '${'a' * 128}b', '${'a' * 129}c', 'a' * 200,
      ];
      final ids = raws.map(queueSafeId).toList();
      expect(ids.toSet().length, raws.length, reason: ids.join(' | '));
      final ids64 = raws.map((r) => queueSafeId(r, max: 64)).toList();
      expect(ids64.toSet().length, raws.length);
    });
    test('a long id whose first 128 chars match another valid id does not '
        'collide with it', () {
      final base = 'a' * 128;
      expect(queueSafeId('${base}z'), isNot(queueSafeId(base)));
    });
    test('queueSessionIdOf is queueSafeId (the chip and the command agree)', () {
      expect(queueSessionIdOf('day_a b'), queueSafeId('day_a b'));
    });
  });

  // ---------------------------------------------------------------------
  group('loadOrCreateInstallId', () {
    test('creates a valid id once and returns the same id afterwards', () async {
      final a = await loadOrCreateInstallId();
      final b = await loadOrCreateInstallId();
      expect(a, b);
      expect(a, startsWith('i'));
      expect(a, matches(RegExp(r'^i[A-Za-z0-9_-]{22}$')));
    });
    test('persists under workout_queue_install_id_v1', () async {
      final id = await loadOrCreateInstallId();
      final p = await SharedPreferences.getInstance();
      expect(p.getString('workout_queue_install_id_v1'), id);
    });
    test('stable across a restart (fresh SharedPreferences over same values)',
        () async {
      final first = await loadOrCreateInstallId();
      SharedPreferences.setMockInitialValues(
          <String, Object>{'workout_queue_install_id_v1': first});
      SharedPreferences.resetStatic();
      expect(await loadOrCreateInstallId(), first);
    });
    test('an invalid stored value is replaced by a valid one', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'workout_queue_install_id_v1': 'has space'});
      SharedPreferences.resetStatic();
      final id = await loadOrCreateInstallId();
      expect(id, isNot('has space'));
      expect(id, matches(RegExp(r'^i[A-Za-z0-9_-]{22}$')));
      expect(await loadOrCreateInstallId(), id);
    });
    test('a reserved-form stored value (__x__) is replaced', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'workout_queue_install_id_v1': '__abc__'});
      SharedPreferences.resetStatic();
      final id = await loadOrCreateInstallId();
      expect(id, isNot('__abc__'));
    });
    test('two installs get different ids', () async {
      final a = await loadOrCreateInstallId();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      SharedPreferences.resetStatic();
      final b = await loadOrCreateInstallId();
      expect(a, isNot(b));
    });
  });

  // ---------------------------------------------------------------------
  group('WriterProofStore', () {
    test('creates a 32 byte base64url token without padding', () async {
      final tok = await WriterProofStore().proofFor('alice', 'sess1');
      expect(tok, isNotNull);
      expect(tok!.length, _bytes43);
      expect(tok, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(base64Url.decode(base64Url.normalize(tok)), hasLength(32));
    });
    test('same (uid, session) returns the same token, also across store '
        'instances (restart)', () async {
      final a = await WriterProofStore().proofFor('alice', 'sess1');
      final b = await WriterProofStore().proofFor('alice', 'sess1');
      final c = await WriterProofStore().proofFor('alice', 'sess1');
      expect(b, a);
      expect(c, a);
    });
    test('distinct per session and per uid', () async {
      final s = WriterProofStore();
      final a1 = await s.proofFor('alice', 'sess1');
      final a2 = await s.proofFor('alice', 'sess2');
      final b1 = await s.proofFor('bob', 'sess1');
      expect({a1, a2, b1}, hasLength(3));
    });
    test('the secret is written once, to the documented key', () async {
      final store = const FlutterSecureStorage();
      final tok = await WriterProofStore().proofFor('alice', 'sess1');
      expect(await store.read(key: 'workout_queue_writer_v1:alice:sess1'), tok);
    });
    test('uids longer than 64 sharing a 64 char prefix get distinct tokens',
        () async {
      final s = WriterProofStore();
      final a = await s.proofFor('${'u' * 64}A', 's');
      final b = await s.proofFor('${'u' * 64}B', 's');
      expect(a, isNot(b));
      expect(await WriterProofStore().proofFor('${'u' * 64}A', 's'), a);
    });
    test('an empty stored value is replaced by a fresh token', () async {
      FlutterSecureStorage.setMockInitialValues(
          <String, String>{'workout_queue_writer_v1:alice:s': ''});
      final tok = await WriterProofStore().proofFor('alice', 's');
      expect(tok, isNotEmpty);
      expect(await WriterProofStore().proofFor('alice', 's'), tok);
    });
    test('many sessions produce unique tokens', () async {
      final s = WriterProofStore();
      final seen = <String>{};
      for (var i = 0; i < 50; i++) {
        seen.add((await s.proofFor('alice', 'sess$i'))!);
      }
      expect(seen, hasLength(50));
    });
  });

  // ---------------------------------------------------------------------
  group('gateway + runtime over a real SQLite store', () {
    late TestClock clock;
    late StoreFactory factory;
    late FakeServer server;

    setUp(() {
      clock = TestClock();
      factory = StoreFactory.sqlite(clock, tmp);
      server = FakeServer();
    });

    Future<(ProviderContainer, WorkoutQueueRuntime)> build({
      String uid = kUid,
      CommandTransport? transport,
      bool openFuture = true,
    }) async {
      final store = await factory.open(uid);
      final proofs = WriterProofStore();
      final rt = WorkoutQueueRuntime(
        uid: uid,
        store: store,
        acceptor: acceptorFor(store, clock),
        sender: CommandSender(
          store: store,
          transport: transport ?? server,
          deviceInstallId: kDevice,
          clientBuild: 'test',
          writerProof: proofs.proofFor,
        ),
        pollInterval: const Duration(milliseconds: 30),
      );
      final c = ProviderContainer(overrides: [
        workoutCommandQueueEnabledProvider.overrideWithValue(true),
        if (openFuture)
          workoutQueueRuntimeFutureProvider
              .overrideWith((ref) => Future.value(rt)),
      ]);
      cleanup.add(() async {
        c.dispose();
        await rt.dispose();
      });
      return (c, rt);
    }

    QueuedSet qs({
      String session = 'day_d1',
      String exercise = 'ea_air_squat',
      String? day = 'd1',
      double? kg = 60,
      int? reps = 8,
    }) =>
        QueuedSet(
          sessionId: session,
          exerciseId: exercise,
          dayId: day,
          startedAtMs: 1700000000000,
          performedAtMs: 1700000100000,
          weightKg: kg,
          reps: reps,
        );

    test('acceptSet commits one durable record with the documented mapping',
        () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(qs());
      final recs = await rt.store.listAll();
      expect(recs, hasLength(1));
      final r = recs.single;
      expect(r.sessionId, 'day_d1');
      expect(r.exerciseId, 'ea_air_squat');
      expect(r.operation, 'CompleteSet');
      expect(r.intentKey, 'markComplete:day_d1:ea_air_squat:1');
      expect(r.logicalSetId, isNotNull);
      expect(r.sessionGeneration, 1);
      expect(r.acceptedEpoch, 0);
      expect(r.seq, 1);
      final p = _payload(r);
      final body = p['body'] as Map;
      expect(body['mode'], 'APPEND');
      expect(body['setId'], 'set_0001');
      expect(body['performedConfirmed'], true);
      expect(body['actualReps'], 8);
      expect(body['actualRepsConfirmed'], true);
      expect(body['targetReps'], isNull);
      expect(body['loadGrams'], 60000);
      expect(body['source'], 'app');
      expect(body['performedAtClientMs'], 1700000100000);
      expect(p['sessionInit'], {
        'titleKey': 'day:d1',
        'dayId': 'd1',
        'startedAtClientMs': 1700000000000,
      });
      expect(p['uid'], kUid);
      expect(p['originDeviceInstallId'], kDevice);
    });

    test('no day: titleKey default and dayId null', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(qs(day: null));
      final p = _payload((await rt.store.listAll()).single);
      expect((p['sessionInit'] as Map)['titleKey'], 'default');
      expect((p['sessionInit'] as Map)['dayId'], isNull);
    });

    test('null reps: actualReps null and actualRepsConfirmed false', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(qs(reps: null));
      final body = _payload((await rt.store.listAll()).single)['body'] as Map;
      expect(body['actualReps'], isNull);
      expect(body['actualRepsConfirmed'], false);
    });

    test('zero reps is a confirmed zero, not "unknown"', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(qs(reps: 0));
      final body = _payload((await rt.store.listAll()).single)['body'] as Map;
      expect(body['actualReps'], 0);
      expect(body['actualRepsConfirmed'], true);
    });

    test('null weight: loadGrams null; fractional kg rounds to grams',
        () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await g.acceptSet(qs(kg: null));
      await g.acceptSet(qs(exercise: 'e2', kg: 62.5));
      await g.acceptSet(qs(exercise: 'e3', kg: 0.0004));
      await g.acceptSet(qs(exercise: 'e4', kg: 0));
      final bodies = {
        for (final r in await rt.store.listAll())
          r.exerciseId: (_payload(r)['body'] as Map)['loadGrams']
      };
      expect(bodies['ea_air_squat'], isNull);
      expect(bodies['e2'], 62500);
      expect(bodies['e3'], 0);
      expect(bodies['e4'], 0);
    });

    test('ids are sanitised in the command and in the intent key', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(
          qs(session: 'day_a b', exercise: 'ex.1/x', day: 'a b'));
      final r = (await rt.store.listAll()).single;
      expect(r.sessionId, queueSafeId('day_a b'));
      expect(r.sessionId, isNot('day_a_b'));
      expect(r.exerciseId, queueSafeId('ex.1/x'));
      expect(r.intentKey,
          'markComplete:${queueSafeId('day_a b')}:${queueSafeId('ex.1/x')}:1');
      final init = _payload(r)['sessionInit'] as Map;
      expect(init['dayId'], queueSafeId('a b'));
      expect(init['titleKey'], 'day:${queueSafeId('a b', max: 64)}');
      expect(RegExp(r'^(default|day:[A-Za-z0-9_-]{1,64})$')
              .hasMatch(init['titleKey'] as String),
          isTrue);
    });

    test('raw ids a.b and a_b are two different commands (no collision)',
        () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await g.acceptSet(qs(exercise: 'a.b'));
      await g.acceptSet(qs(exercise: 'a_b'));
      expect(await rt.store.listAll(), hasLength(2));
    });

    test('reserved raw ids are accepted: session, exercise and day', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(
          qs(session: '__s__', exercise: '__x__', day: '__d__'));
      final r = (await rt.store.listAll()).single;
      expect(r.sessionId, queueSafeId('__s__'));
      final init = _payload(r)['sessionInit'] as Map;
      expect(init['titleKey'], 'day:${queueSafeId('__d__', max: 64)}');
    });

    test('two long day ids with the same 64 char prefix get different '
        'titleKeys', () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await g.acceptSet(qs(exercise: 'e1', day: '${'d' * 70}A'));
      await g.acceptSet(qs(exercise: 'e2', day: '${'d' * 70}B'));
      final keys = {
        for (final r in await rt.store.listAll())
          (_payload(r)['sessionInit'] as Map)['titleKey']
      };
      expect(keys, hasLength(2));
    });

    test('a 200 char day id: dayId capped at 128, titleKey day id capped at 64',
        () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(
          qs(session: 's' * 200, day: 'd' * 200));
      final r = (await rt.store.listAll()).single;
      expect(r.sessionId.length, lessThanOrEqualTo(128));
      expect(r.sessionId, queueSafeId('s' * 200));
      final init = _payload(r)['sessionInit'] as Map;
      expect((init['dayId'] as String).length, lessThanOrEqualTo(128));
      expect((init['titleKey'] as String).length, lessThanOrEqualTo(4 + 64));
      expect(init['titleKey'], 'day:${queueSafeId('d' * 200, max: 64)}');
    });

    test('a double tap yields ONE command (intent key stability)', () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await g.acceptSet(qs());
      await g.acceptSet(qs());
      await Future.wait([g.acceptSet(qs()), g.acceptSet(qs())]);
      final recs = await rt.store.listAll();
      expect(recs, hasLength(1));
      expect(recs.single.seq, 1);
    });

    test('a double tap with changed values keeps the FIRST values (queue is '
        'idempotent per intent; legacy save is the one that updates)', () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await g.acceptSet(qs(kg: 60, reps: 8));
      await g.acceptSet(qs(kg: 70, reps: 10));
      final body = _payload((await rt.store.listAll()).single)['body'] as Map;
      expect(body['loadGrams'], 60000);
      expect(body['actualReps'], 8);
    });

    test('different exercises of one session get seq 1 and 2, one per exercise',
        () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await g.acceptSet(qs(exercise: 'a'));
      await g.acceptSet(qs(exercise: 'b'));
      final recs = await rt.store.listAll();
      expect(recs.map((r) => r.exerciseId).toSet(), {'a', 'b'});
      expect(recs.map((r) => r.seq).toSet(), {1, 2});
    });

    test('record survives a restart (reopen the same database file)', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(qs());
      await rt.dispose();
      final reopened = await factory.open(kUid);
      final recs = await reopened.listAll();
      expect(recs, hasLength(1));
      expect(recs.single.state, CommandState.accepted);
      // The same tap after restart is still one command.
      final acceptor = acceptorFor(reopened, clock);
      final r2 = _gwOver(reopened, acceptor);
      await r2.acceptSet(qs());
      expect(await reopened.listAll(), hasLength(1));
    });

    test('runtime future is null (no account): acceptSet throws StateError and '
        'stores nothing', () async {
      final (c, rt) = await build(openFuture: false);
      await expectLater(c.read(workoutQueueGatewayProvider).acceptSet(qs()),
          throwsA(isA<StateError>()));
      expect(await rt.store.listAll(), isEmpty);
    });

    test('runtime future failed: acceptSet throws', () async {
      final (c, _) = await build(openFuture: false);
      final c2 = ProviderContainer(overrides: [
        workoutQueueRuntimeFutureProvider.overrideWith(
            (ref) => Future<WorkoutQueueRuntime>.error(StateError('open failed'))),
      ]);
      addTearDown(c2.dispose);
      c.dispose();
      await expectLater(c2.read(workoutQueueGatewayProvider).acceptSet(qs()),
          throwsA(isA<StateError>()));
    });

    test('invalid values (NaN kg) throw and store nothing', () async {
      final (c, rt) = await build(transport: _NeverSends());
      await expectLater(
          c.read(workoutQueueGatewayProvider).acceptSet(qs(kg: double.nan)),
          throwsA(anything));
      expect(await rt.store.listAll(), isEmpty);
    });

    test('values beyond the wire limits throw and store nothing', () async {
      final (c, rt) = await build(transport: _NeverSends());
      final g = c.read(workoutQueueGatewayProvider);
      await expectLater(g.acceptSet(qs(reps: 1001)), throwsA(anything));
      await expectLater(g.acceptSet(qs(kg: 1000.5)), throwsA(anything));
      await expectLater(g.acceptSet(qs(reps: -1)), throwsA(anything));
      expect(await rt.store.listAll(), isEmpty);
    });

    test('an id of the reserved form __x__ must still be accepted '
        '(defect probe: queueSafeId keeps it, canonicalisation rejects it)',
        () async {
      final (c, rt) = await build(transport: _NeverSends());
      await c.read(workoutQueueGatewayProvider).acceptSet(qs(exercise: '__x__'));
      expect(await rt.store.listAll(), hasLength(1));
    });

    test('after acceptSet the sender is kicked and the server gets the command '
        'with a writer proof and the install id', () async {
      final (c, rt) = await build();
      await c.read(workoutQueueGatewayProvider).acceptSet(qs());
      expect(await _until(() => server.received.isNotEmpty), isTrue);
      expect(server.received.single.writerProof, hasLength(_bytes43));
      expect(server.received.single.deviceInstallId, kDevice);
      expect(await _until(() => server.effects.length == 1), isTrue);
      final recs = await rt.store.listAll();
      expect(await _until(() => true), isTrue);
      await _until(() => false, ms: 100);
      expect((await rt.store.listAll()).single.state, CommandState.synced);
      expect(recs, hasLength(1));
    });

    test('the same writer proof is sent for the same session on resend',
        () async {
      server.faults.add(Fault.throwWithoutApplying);
      final (c, rt) = await build();
      await c.read(workoutQueueGatewayProvider).acceptSet(qs());
      expect(await _until(() => server.received.isNotEmpty), isTrue);
      await _until(() => false, ms: 100);
      rt.sender.resetBackoff();
      await rt.sender.sendAvailable();
      expect(server.received.length, greaterThanOrEqualTo(2));
      expect(server.received.map((e) => e.writerProof).toSet(), hasLength(1));
      expect(server.effects.length, 1);
    });

    test('runtime.start kicks at once and then on the timer; dispose stops it '
        'and closes the store without deleting', () async {
      final store = await factory.open(kUid);
      final counting = _CountingSender(senderFor(store, server, clock));
      final rt = WorkoutQueueRuntime(
        uid: kUid,
        store: store,
        acceptor: acceptorFor(store, clock),
        sender: counting,
        pollInterval: const Duration(milliseconds: 20),
      );
      await rt.acceptor.accept(intentOf('k1'));
      rt.start();
      expect(counting.calls, 1, reason: 'start() kicks immediately');
      expect(await _until(() => counting.calls >= 4), isTrue,
          reason: 'periodic timer keeps kicking');
      rt.start(); // second start must not add a second timer
      await rt.dispose();
      final after = counting.calls;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(counting.calls, after, reason: 'no kick after dispose');
      rt.kick();
      expect(counting.calls, after, reason: 'kick after dispose is a no-op');
      // Nothing deleted: a fresh store over the same file still has the record.
      final reopened = await factory.open(kUid);
      expect(await reopened.listAll(), hasLength(1));
    });

    test('a second start() does not create a second timer', () async {
      final store = await factory.open(kUid);
      final counting = _CountingSender(senderFor(store, server, clock));
      final rt = WorkoutQueueRuntime(
        uid: kUid,
        store: store,
        acceptor: acceptorFor(store, clock),
        sender: counting,
        pollInterval: const Duration(milliseconds: 50),
      );
      rt.start();
      rt.start();
      rt.start();
      await Future<void>.delayed(const Duration(milliseconds: 520));
      final calls = counting.calls;
      await rt.dispose();
      // 3 starts = 3 immediate kicks + ~10 ticks of ONE timer. Three timers
      // would give ~30 ticks.
      expect(calls, lessThan(20));
    });

    test('kick never throws when the sender throws', () async {
      final store = await factory.open(kUid);
      final counting =
          _CountingSender(senderFor(store, server, clock), throwing: true);
      final rt = WorkoutQueueRuntime(
        uid: kUid,
        store: store,
        acceptor: acceptorFor(store, clock),
        sender: counting,
      );
      rt.kick();
      rt.kick();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(counting.calls, 2);
      await rt.dispose();
    });

    test('dispose twice is safe', () async {
      final store = await factory.open(kUid);
      final rt = WorkoutQueueRuntime(
        uid: kUid,
        store: store,
        acceptor: acceptorFor(store, clock),
        sender: senderFor(store, server, clock),
      );
      await rt.dispose();
      await rt.dispose();
    });

    // -- status provider -------------------------------------------------
    test('status provider: null with no runtime', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final sub = c.listen(workoutQueueSessionStatusProvider('day_d1'), (_, __) {});
      addTearDown(sub.close);
      await _until(() => c.read(workoutQueueSessionStatusProvider('day_d1')).hasValue);
      expect(c.read(workoutQueueSessionStatusProvider('day_d1')).value, isNull);
    });

    test('status provider: zero counts for an empty queue, then pending after '
        'accept (transport offline), per queue session id', () async {
      final (c, _) = await build(transport: _NeverSends());
      final sub = c.listen(
          workoutQueueSessionStatusProvider('day_a b'), (_, __) {});
      addTearDown(sub.close);
      await _until(
          () => c.read(workoutQueueSessionStatusProvider('day_a b')).hasValue);
      final s0 = c.read(workoutQueueSessionStatusProvider('day_a b')).value;
      expect(s0?.pending ?? 0, 0);
      await c.read(workoutQueueGatewayProvider).acceptSet(qs(session: 'day_a b'));
      expect(
          await _until(() =>
              (c.read(workoutQueueSessionStatusProvider('day_a b')).valueOrNull
                      ?.pending ??
                  0) ==
              1),
          isTrue);
      // Another session is not affected.
      final other = c.read(workoutQueueSessionStatusProvider('other'));
      expect(other.valueOrNull?.pending ?? 0, 0);
    });

    test('status provider: synced after the server commits', () async {
      final (c, _) = await build();
      final sub = c.listen(workoutQueueSessionStatusProvider('day_d1'), (_, __) {});
      addTearDown(sub.close);
      await c.read(workoutQueueGatewayProvider).acceptSet(qs());
      expect(
          await _until(() =>
              (c.read(workoutQueueSessionStatusProvider('day_d1')).valueOrNull
                      ?.synced ??
                  0) ==
              1),
          isTrue);
      final s = c.read(workoutQueueSessionStatusProvider('day_d1')).value!;
      expect(s.pending, 0);
      expect(s.couldNotSync, 0);
    });

    test('status provider: could-not-sync after a terminal refusal', () async {
      server.scriptedCodes.add('INVALID_PAYLOAD');
      final (c, _) = await build();
      final sub = c.listen(workoutQueueSessionStatusProvider('day_d1'), (_, __) {});
      addTearDown(sub.close);
      await c.read(workoutQueueGatewayProvider).acceptSet(qs());
      expect(
          await _until(() =>
              (c.read(workoutQueueSessionStatusProvider('day_d1')).valueOrNull
                      ?.couldNotSync ??
                  0) ==
              1),
          isTrue);
    });
  });

  // ---------------------------------------------------------------------
  group('binding provider', () {
    late StreamController<AuthUser?> auth;

    ProviderContainer container({bool flag = true}) {
      final c = ProviderContainer(overrides: [
        workoutCommandQueueEnabledProvider.overrideWithValue(flag),
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      cleanup.add(() async {
        c.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      return c;
    }

    Future<void> pumpMicro() => Future<void>.delayed(const Duration(milliseconds: 30));

    setUp(() async {
      auth = StreamController<AuthUser?>.broadcast();
      cleanup.add(() async => auth.close());
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      setupFirebaseCoreMocks();
      try {
        await Firebase.initializeApp();
      } catch (_) {}
    });

    test('flag OFF: nothing is opened, the auth stream is not even listened '
        'to, no disk is touched', () async {
      final c = ProviderContainer(overrides: [
        workoutCommandQueueEnabledProvider.overrideWithValue(false),
        authUserProvider.overrideWith((ref) => throw StateError('must not read')),
      ]);
      addTearDown(c.dispose);
      c.read(workoutQueueBindingProvider);
      await pumpMicro();
      expect(c.read(workoutQueueRuntimeFutureProvider), isNull);
      expect(tmp.listSync(), isEmpty);
    });

    test('flag ON, signed out: no runtime', () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(null);
      await pumpMicro();
      expect(c.read(workoutQueueRuntimeFutureProvider), isNull);
    });

    test('flag ON: sign-in opens a runtime for that uid and creates the db '
        'under the app support dir', () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      expect(
          await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null),
          isTrue);
      final rt = await c.read(workoutQueueRuntimeFutureProvider)!;
      expect(rt.uid, 'alice');
      expect(rt.store.uid, 'alice');
      expect(
          Directory('${tmp.path}/offline_command_queue_db').existsSync(), isTrue);
    });

    test('sign-out disposes the store, clears the runtime and deletes nothing',
        () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null);
      final rt = await c.read(workoutQueueRuntimeFutureProvider)!;
      await c.read(workoutQueueGatewayProvider).acceptSet(_set());
      final filesBefore = _dbFiles(tmp).where((n) => n.endsWith('.db')).toList();
      expect(filesBefore, isNotEmpty);

      auth.add(null);
      expect(
          await _until(() => c.read(workoutQueueRuntimeFutureProvider) == null),
          isTrue);
      await pumpMicro();
      // The old store is closed: using it fails.
      await _released(tmp, 'alice');
      // Files are still there.
      expect(_dbFiles(tmp).where((n) => n.endsWith('.db')).toList(), filesBefore);

      // Sign-in again: the record is still in the queue (nothing was deleted).
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null);
      final rt2 = await c.read(workoutQueueRuntimeFutureProvider)!;
      expect(identical(rt2, rt), isFalse);
      expect(await rt2.store.listAll(), hasLength(1));
    });

    test('account change: alice store closed, bob opened with its own file; '
        'alice record not visible to bob', () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null);
      final aFut = c.read(workoutQueueRuntimeFutureProvider)!;
      final a = await aFut;
      await expectLater(_released(tmp, 'alice'), throwsA(anything));
      await c.read(workoutQueueGatewayProvider).acceptSet(_set());

      auth.add(const AuthUser(uid: 'bob', displayName: 'B'));
      expect(
          await _until(() {
            final f = c.read(workoutQueueRuntimeFutureProvider);
            return f != null && !identical(f, aFut);
          }),
          isTrue);
      final b = await c.read(workoutQueueRuntimeFutureProvider)!;
      expect(b.uid, 'bob');
      expect(await b.store.listAll(), isEmpty);
      await _released(tmp, 'alice');
      expect(_dbFiles(tmp).length, greaterThanOrEqualTo(2));
    });

    test('the same uid emitted twice does not reopen the store', () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null);
      final f1 = c.read(workoutQueueRuntimeFutureProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A Renamed'));
      await pumpMicro();
      expect(identical(c.read(workoutQueueRuntimeFutureProvider), f1), isTrue);
    });

    test('disposing the container closes the open store', () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null);
      final rt = await c.read(workoutQueueRuntimeFutureProvider)!;
      c.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _released(tmp, 'alice');
    });

    test('quick sign-out right after sign-in leaves no runtime and no open '
        'store (race)', () async {
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      auth.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(c.read(workoutQueueRuntimeFutureProvider), isNull);
      // The db file can be opened again => the previous instance was closed.
      final store = await StoreFactory.sqlite(TestClock(), tmp)
          .open('alice')
          .timeout(const Duration(seconds: 5));
      await store.dispose();
    });

    test('the retry timer is running for the bound runtime (a failing '
        'transport is probed again without a tap)', () async {
      // With the real callable transport there is no Firebase backend here, so
      // the send fails; what is asserted is only that the periodic machinery
      // does not crash the app and the record stays durable.
      final c = container();
      c.read(workoutQueueBindingProvider);
      auth.add(const AuthUser(uid: 'alice', displayName: 'A'));
      await _until(() => c.read(workoutQueueRuntimeFutureProvider) != null);
      await c.read(workoutQueueGatewayProvider).acceptSet(_set());
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final rt = await c.read(workoutQueueRuntimeFutureProvider)!;
      final recs = await rt.store.listAll();
      expect(recs, hasLength(1));
      expect(recs.single.state, isNot(CommandState.conflicted));
    });
  });

  test('flag default is OFF in this build', () {
    expect(kWorkoutCommandQueueEnabled, isFalse);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(workoutCommandQueueEnabledProvider), isFalse);
  });
}

QueuedSet _set() => const QueuedSet(
      sessionId: 'day_d1',
      exerciseId: 'ea_air_squat',
      dayId: 'd1',
      startedAtMs: 1700000000000,
      performedAtMs: 1700000100000,
      weightKg: 60,
      reps: 8,
    );

List<String> _dbFiles(Directory root) {
  final d = Directory('${root.path}/offline_command_queue_db');
  if (!d.existsSync()) return <String>[];
  return d.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toList()
    ..sort();
}

/// A transport that never answers, so records stay pending.
class _NeverSends implements CommandTransport {
  @override
  Future<TransportAnswer> send(CommandEnvelope envelope) =>
      Future<TransportAnswer>.error(const SocketException('offline'));
}

WorkoutQueueGateway _gwOver(CommandQueueStore store, dynamic acceptor) {
  final rt = WorkoutQueueRuntime(
    uid: store.uid,
    store: store,
    acceptor: acceptor,
    sender: _CountingSender(
        CommandSender(
          store: store,
          transport: _NeverSends(),
          deviceInstallId: kDevice,
          clientBuild: 't',
          writerProof: kDefaultTestProof,
        )),
  );
  final c = ProviderContainer(overrides: [
    workoutQueueRuntimeFutureProvider.overrideWith((ref) => Future.value(rt)),
  ]);
  addTearDown(c.dispose);
  return c.read(workoutQueueGatewayProvider);
}

/// Opens (and closes) the alice/bob database the binding uses. Succeeds only
/// when no other instance holds the file (single-instance guard).
Future<void> _released(Directory tmp, String uid) async {
  final s = await SqliteCommandQueueStore.open(
      uid: uid,
      path:
          '${tmp.path}/offline_command_queue_db/${sqliteQueueFileName(uid)}',
      factory: databaseFactoryFfi);
  await s.dispose();
}
