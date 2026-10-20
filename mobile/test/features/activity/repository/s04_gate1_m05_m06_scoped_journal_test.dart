// S04 gate 1, findings M-05 and M-06 on UidScopedActivityJournal.
//
// M-05: an owner-checked put already handed to a delegate finishes before that
//       delegate is closed or wiped (bounded to 5 s); putForOwner is refused
//       from the moment wipeForUid(uid) is called.
// M-06: the durable wipe marker fails closed. A marker that cannot be written
//       aborts the transition (wipeForUid throws, no other uid binds until a
//       wipe succeeds); a marker that cannot be read is never read as absent.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/activity/repository/journal_file_system.dart';
import 'package:fitness_app/features/activity/repository/journal_layout.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import '../../../support/journal_harness.dart' show idFor, journalSession;

const String _root = '/scopes';

class _Entry extends Fake implements JournalEntry {}

/// A delegate that records its lifecycle in a shared event log and can hold a
/// put open.
class _Delegate extends Fake implements ActivityJournal {
  _Delegate(this.scopeId, this.events, this.label);

  final String label;

  final String scopeId;
  final List<String> events;
  Completer<void>? putGate;
  int closes = 0;
  int wipes = 0;

  @override
  Future<JournalRecoveryReport> start() async => JournalRecoveryReport();

  @override
  Future<JournalEntry> put(ActivitySession session,
      {JournalSyncState? syncState,
      int? baseRev,
      Map<String, Object?>? baseSummary}) async {
    events.add('$label.put.start');
    final g = putGate;
    if (g != null) await g.future;
    events.add('$label.put.end');
    return _Entry();
  }

  @override
  Future<void> close() async {
    closes++;
    events.add('$label.close');
  }

  @override
  Future<void> wipe() async {
    wipes++;
    events.add('$label.wipe');
  }

  @override
  Future<List<JournalEntry>> list() async => const [];
}

/// Memory file system whose marker I/O can fail.
class _MarkerFs extends MemoryJournalFileSystem {
  _MarkerFs() : super(() => DateTime.utc(2026, 10, 20));

  bool failMarkerWrite = false;
  bool failMarkerRead = false;

  static bool _isMarker(String p) => p.contains(kWipedMarkerSuffix);

  @override
  Future<JournalWriteHandle> openWrite(String path, {bool append = false}) {
    if (failMarkerWrite && _isMarker(path)) {
      throw const FileSystemExceptionStub('marker create failed');
    }
    return super.openWrite(path, append: append);
  }

  @override
  Future<bool> exists(String path) {
    if (failMarkerRead && _isMarker(path)) {
      throw const FileSystemExceptionStub('marker read failed');
    }
    return super.exists(path);
  }
}

class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub(this.message);
  final String message;
}

class _World {
  _World() {
    journal = UidScopedActivityJournal(
      factory: (scopeId) async {
        final label = <String, String>{
          for (final u in ['A', 'B']) activityJournalScopeId(u): u,
        }[scopeId]!;
        final d = _Delegate(scopeId, events, label);
        delegates.add(d);
        return d;
      },
      fileSystem: fs,
      scopesRoot: () async => _root,
    );
  }

  final _MarkerFs fs = _MarkerFs();
  final List<String> events = [];
  final List<_Delegate> delegates = [];
  late final UidScopedActivityJournal journal;

  _Delegate delegateOf(String uid) =>
      delegates.lastWhere((d) => d.scopeId == activityJournalScopeId(uid));
}

Future<void> _pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final session = journalSession(idFor(1), seed: 1);

  group('M-05 in-flight owner-checked puts', () {
    test('an unbind (switch to B) waits for the put in flight before it '
        'closes the delegate of A', () async {
      final w = _World();
      expect(await w.journal.bindUid('A'), isTrue);
      final a = w.delegateOf('A')..putGate = Completer<void>();

      final put = w.journal.putForOwner('A', session);
      await _pump();
      expect(a.events_contains('A.put.start'), isTrue);

      final bind = w.journal.bindUid('B');
      await _pump();
      expect(a.closes, 0, reason: 'the put is still running: no close yet');

      a.putGate!.complete();
      await put; // the put succeeds, it was not cut off
      expect(await bind, isTrue);
      expect(a.closes, 1);
      expect(w.events.indexOf('A.put.end'), lessThan(w.events.indexOf('A.close')),
          reason: 'close strictly after the put finished');
      expect(w.journal.boundUid, 'B');
    });

    test('an unbind(null) waits for the put in flight as well', () async {
      final w = _World();
      await w.journal.bindUid('A');
      final a = w.delegateOf('A')..putGate = Completer<void>();
      final put = w.journal.putForOwner('A', session);
      await _pump();
      final unbind = w.journal.bindUid(null);
      await _pump();
      expect(a.closes, 0);
      a.putGate!.complete();
      await put;
      await unbind;
      expect(a.closes, 1);
      expect(w.journal.isBound, isFalse);
    });

    test('a put that never finishes holds the close for at most 5 s of fake '
        'time, then the delegate is closed anyway', () {
      fakeAsync((fa) {
        final w = _World();
        var bound = false;
        w.journal.bindUid('A').then((v) => bound = v);
        fa.flushMicrotasks();
        expect(bound, isTrue);
        final a = w.delegateOf('A')..putGate = Completer<void>();
        w.journal.putForOwner('A', session).ignore();
        fa.flushMicrotasks();

        var switched = false;
        w.journal.bindUid('B').then((v) => switched = v);
        fa.flushMicrotasks();
        fa.elapse(const Duration(seconds: 4));
        expect(a.closes, 0, reason: 'still inside the 5 s window');
        expect(switched, isFalse);

        fa.elapse(const Duration(seconds: 2));
        expect(a.closes, 1, reason: 'the bound is exceeded: closed');
        expect(switched, isTrue);
      });
    });

    test('wipeForUid(A) waits for the put in flight before it wipes', () async {
      final w = _World();
      await w.journal.bindUid('A');
      final a = w.delegateOf('A')..putGate = Completer<void>();
      final put = w.journal.putForOwner('A', session);
      await _pump();
      final wipe = w.journal.wipeForUid('A');
      await _pump();
      expect(w.events, isNot(contains('A.close')));
      a.putGate!.complete();
      await put;
      await wipe;
      final firstEnd = w.events.indexOf('A.put.end');
      expect(firstEnd, greaterThanOrEqualTo(0));
      expect(w.events.indexOf('A.close'), greaterThan(firstEnd));
    });

    test('putForOwner is refused as soon as wipeForUid(A) is CALLED, and '
        'after it finished', () async {
      final w = _World();
      await w.journal.bindUid('A');
      final wipe = w.journal.wipeForUid('A');
      // No await: the wipe has not even started its queued work yet.
      expect(() => w.journal.putForOwner('A', session),
          throwsA(isA<JournalUnbound>()));
      await wipe;
      expect(() => w.journal.putForOwner('A', session),
          throwsA(isA<JournalUnbound>()));
      expect(w.delegates.where((d) => d.events.contains('A.put.start')), isEmpty,
          reason: 'no put reached any delegate');
    });

    test('a wrong expected uid is still refused and a right one still works',
        () async {
      final w = _World();
      await w.journal.bindUid('A');
      expect(() => w.journal.putForOwner('B', session),
          throwsA(isA<JournalUnbound>()));
      await w.journal.putForOwner('A', session);
      expect(w.events, containsAll(['A.put.start', 'A.put.end']));
    });
  });

  group('M-06 durable wipe marker fails closed', () {
    test('a marker that cannot be created: wipeForUid throws, bindUid(other) '
        'is refused, a later successful wipe lets bind through', () async {
      final w = _World();
      expect(await w.journal.bindUid('A'), isTrue);
      w.fs.failMarkerWrite = true;

      await expectLater(w.journal.wipeForUid('A'),
          throwsA(isA<FileSystemExceptionStub>()),
          reason: 'the caller sees the failure (wipe-incomplete path)');
      expect(w.journal.isBound, isFalse, reason: 'the old binding was dropped');
      expect(w.delegateOf('A').wipes, 0, reason: 'nothing wiped without a marker');

      expect(await w.journal.bindUid('B'), isFalse,
          reason: 'no other uid may bind until the wipe succeeds');
      expect(w.journal.isBound, isFalse);
      expect(await w.journal.bindUid('A'), isFalse);

      w.fs.failMarkerWrite = false;
      await w.journal.wipeForUid('A'); // succeeds now
      expect(await w.journal.bindUid('B'), isTrue);
      expect(w.journal.boundUid, 'B');
    });

    test('the same failure when A is NOT bound (relaunch retry) throws and '
        'blocks nothing wrongly', () async {
      final w = _World();
      expect(await w.journal.bindUid('B'), isTrue);
      w.fs.failMarkerWrite = true;
      await expectLater(w.journal.wipeForUid('A'),
          throwsA(isA<FileSystemExceptionStub>()));
      expect(w.journal.boundUid, 'B', reason: 'a foreign wipe does not unbind B');
      w.fs.failMarkerWrite = false;
      await w.journal.wipeForUid('A');
      expect(w.journal.boundUid, 'B');
    });

    test('a marker that cannot be read: bindUid returns false and stays '
        'unbound; readable again it binds', () async {
      final w = _World();
      w.fs.failMarkerRead = true;
      expect(await w.journal.bindUid('A'), isFalse);
      expect(w.journal.isBound, isFalse);
      expect(w.journal.boundUid, isNull);
      expect(w.delegates, isEmpty, reason: 'the scope was never opened');
      expect(await w.journal.bindUid('A'), isFalse, reason: 'retry still closed');

      w.fs.failMarkerRead = false;
      expect(await w.journal.bindUid('A'), isTrue);
      expect(w.journal.boundUid, 'A');
    });

    test('an unreadable marker unbinds a journal bound to another uid '
        '(switch fails closed)', () async {
      final w = _World();
      expect(await w.journal.bindUid('A'), isTrue);
      w.fs.failMarkerRead = true;
      expect(await w.journal.bindUid('B'), isFalse);
      expect(w.journal.isBound, isFalse);
      expect(w.delegateOf('A').closes, 1);
    });

    test('a present marker (wiped scope) still refuses the bind', () async {
      final w = _World();
      await w.journal.bindUid('A');
      await w.journal.wipeForUid('A');
      expect(await w.journal.bindUid('A'), isFalse);
    });
  });
}

extension on _Delegate {
  bool events_contains(String e) => events.contains(e);
}
