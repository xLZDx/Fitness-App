// The three Firestore reference types are faked by implementing them: no
// Firestore fake is a dependency of this project, and the type is sealed only
// for outside packages' benefit, not at runtime.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/firestore_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';

/// `FirestoreWorkoutSessionRepository.save` must not wait for a server ack:
/// offline, a Firestore write future never completes, and "Mark complete"
/// spun until the network came back (NEW-OFFLINE-LOG). No Firestore fake is a
/// dependency of this project, so the three reference types the repository
/// touches are hand-written; everything else throws via `noSuchMethod`.
class _FakeDoc implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this.id, this.onSet);

  @override
  final String id;
  final Future<void> Function(String id, Map<String, dynamic> data) onSet;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCol(onSet);

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) =>
      onSet(id, data);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeCol implements CollectionReference<Map<String, dynamic>> {
  _FakeCol(this.onSet);
  final Future<void> Function(String id, Map<String, dynamic> data) onSet;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _FakeDoc(path!, onSet);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeFirestore implements FirebaseFirestore {
  _FakeFirestore(this.onSet);
  final Future<void> Function(String id, Map<String, dynamic> data) onSet;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCol(onSet);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

WorkoutSession _session() => WorkoutSession(
      id: 'sess-1',
      title: 'Leg day',
      exercises: const [],
      startedAt: DateTime(2026, 10, 13, 9),
      completedAt: DateTime(2026, 10, 13, 10),
      status: WorkoutSessionStatus.completed,
    );

void main() {
  testWidgets('an unacknowledged write is released at 4 s, not before',
      (tester) async {
    final never = Completer<void>();
    final written = <String, Map<String, dynamic>>{};
    final repo = FirestoreWorkoutSessionRepository(_FakeFirestore((id, data) {
      written[id] = data;
      return never.future;
    }));

    var done = false;
    final f = repo.save('alice', _session()).then((_) => done = true);

    await tester.pump(const Duration(seconds: 3));
    expect(written.keys, ['sess-1'], reason: 'the write was issued');
    expect(written['sess-1']!['title'], 'Leg day');
    expect(done, isFalse, reason: 'still inside the 4 s bound');

    await tester.pump(const Duration(seconds: 2));
    await f;
    expect(done, isTrue, reason: 'timeout completes normally, no error');
  });

  testWidgets('a write that is acknowledged returns without waiting',
      (tester) async {
    final repo = FirestoreWorkoutSessionRepository(
        _FakeFirestore((id, data) async {}));

    var done = false;
    final f = repo.save('alice', _session()).then((_) => done = true);
    await tester.pump(const Duration(milliseconds: 10));
    await f;
    expect(done, isTrue);
  });

  testWidgets('a write that fails before the timeout still reports the error',
      (tester) async {
    final repo = FirestoreWorkoutSessionRepository(_FakeFirestore(
        (id, data) => Future<void>.error(StateError('permission-denied'))));

    await expectLater(
        repo.save('alice', _session()), throwsA(isA<StateError>()));
  });
}
