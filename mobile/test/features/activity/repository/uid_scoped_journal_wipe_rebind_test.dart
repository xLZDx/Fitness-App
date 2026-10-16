// S02 remediation F2 (test epic 12b): no rebind after a wipe, boundUid/isBound
// and key-deletion failure. Oracles: docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md
// heading F2 items 1 and 2, S02_DESIGN.md section 17 items 22 and 23 and the
// promise "deleting my account erases my data and nothing brings it back", not
// the code under test.
//
// The scoped journal is the REAL one over real files (ScopedJournalWorld); the
// secure store is a fake whose delete can fail.
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_aware_local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

/// Forwards what the scoped journal calls and throws from `close()`.
class _ThrowingClose extends Fake implements ActivityJournal {
  _ThrowingClose(this.inner);

  final ActivityJournal inner;
  int closes = 0;

  @override
  Future<JournalRecoveryReport> start() => inner.start();

  @override
  Future<List<JournalEntry>> list() => inner.list();

  @override
  Future<void> wipe() => inner.wipe();

  @override
  Future<void> close() async {
    closes++;
    await inner.close();
    throw StateError('close failed');
  }
}

void main() {
  late ScopedJournalWorld w;

  setUp(() async => w = await ScopedJournalWorld.create());
  tearDown(() => w.dispose());

  UidScopedActivityJournal j() => w.journal;

  String keyOf(String uid) =>
      '${SecureStorageJournalKeyProvider.keyName}.${activityJournalScopeId(uid)}';

  Future<void> putFor(String uid, int n) async {
    expect(await j().bindUid(uid), isTrue);
    await j().put(journalSession(idFor(n), seed: n));
  }

  Future<List<String>> ids() async =>
      [for (final e in await j().list()) e.id]..sort();

  group('item 1: no rebind after a wipe of the bound uid', () {
    test('wipeForUid(A) then bindUid(A) is refused and creates no file, no key '
        'and does not even open the scope', () async {
      await putFor('A', 1);
      await w.writeSide('A', 'sources/a.json', '{}');
      await j().wipeForUid('A');
      final opensAfterWipe = w.opened.length;
      final dirsAfterWipe = await w.scopeDirs();
      expect(await w.snapshot('A'), isEmpty, reason: 'no file of A survives');
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);

      expect(await j().bindUid('A'), isFalse);

      expect(w.opened.length, opensAfterWipe, reason: 'the factory was not asked');
      expect(await w.scopeDirs(), dirsAfterWipe, reason: 'no directory appeared');
      expect(await w.snapshot('A'), isEmpty, reason: 'no file appeared');
      expect(w.storage.values.containsKey(keyOf('A')), isFalse,
          reason: 'no key was created for the deleted account');
      expect(j().isBound, isFalse);
      expect(j().boundUid, isNull);
    });

    test('a same-uid re-emission storm stays refused', () async {
      await putFor('A', 1);
      await j().wipeForUid('A');
      for (var i = 0; i < 3; i++) {
        expect(await j().bindUid('A'), isFalse, reason: 'attempt $i');
      }
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
      expect(await w.snapshot('A'), isEmpty);
    });

    test('bindUid(null) ends the refusal, even though nothing was bound',
        () async {
      await putFor('A', 1);
      await j().wipeForUid('A');
      expect(j().isBound, isFalse, reason: 'precondition: the wipe unbound it');
      expect(await j().bindUid(null), isTrue);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), isEmpty, reason: 'a clean new scope, old data gone');
    });

    test('binding another uid ends the refusal', () async {
      await putFor('A', 1);
      await j().wipeForUid('A');
      expect(await j().bindUid('B'), isTrue);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), isEmpty);
    });

    test('the refusal is only for the wiped uid: B binds at once', () async {
      await putFor('A', 1);
      await j().wipeForUid('A');
      expect(await j().bindUid('B'), isTrue);
      expect(j().boundUid, 'B');
    });

    test('the refusal unbinds a journal that is bound to something else',
        () async {
      await putFor('A', 1);
      await j().wipeForUid('A');
      expect(await j().bindUid('B'), isTrue);
      // B is bound; wipe of B, then refusal of B must not leave B bound.
      await j().wipeForUid('B');
      expect(await j().bindUid('B'), isFalse);
      expect(j().isBound, isFalse);
    });

    test('remediation G4: a wipe of a NON-bound uid refuses a later bind of '
        'that uid until bindUid(null) clears the marker', () async {
      await putFor('A', 1);
      expect(await j().bindUid('B'), isTrue);
      await j().wipeForUid('A');
      expect(await j().bindUid('A'), isFalse);
      expect(await j().bindUid(null), isTrue);
      expect(await j().bindUid('A'), isTrue);
      expect(await ids(), isEmpty);
    });

    test('a wipe of the bound uid that FAILS still refuses a rebind of it',
        () async {
      await putFor('A', 1);
      w.storage.failDeletes = true;
      await expectLater(j().wipeForUid('A'), throwsA(isA<StateError>()));
      final opens = w.opened.length;
      expect(await j().bindUid('A'), isFalse,
          reason: 'the marker retries the wipe; nothing may reopen the scope');
      expect(w.opened.length, opens);
      expect(j().isBound, isFalse);
    });
  });

  group('boundUid and isBound in every state', () {
    test('never bound', () {
      expect(j().boundUid, isNull);
      expect(j().isBound, isFalse);
    });

    test('after bindUid(A)', () async {
      expect(await j().bindUid('A'), isTrue);
      expect(j().boundUid, 'A');
      expect(j().isBound, isTrue);
    });

    test('after bindUid(null)', () async {
      await j().bindUid('A');
      await j().bindUid(null);
      expect(j().boundUid, isNull);
      expect(j().isBound, isFalse);
    });

    test('after a switch A to B', () async {
      await j().bindUid('A');
      await j().bindUid('B');
      expect(j().boundUid, 'B');
      expect(j().isBound, isTrue);
    });

    test('after the wipe of the bound uid', () async {
      await j().bindUid('A');
      await j().wipeForUid('A');
      expect(j().boundUid, isNull);
      expect(j().isBound, isFalse);
    });

    test('after the wipe of another uid the bound one stays bound', () async {
      await putFor('A', 1);
      await j().bindUid('B');
      await j().wipeForUid('A');
      expect(j().boundUid, 'B');
      expect(j().isBound, isTrue);
    });

    test('after a failed bind (open throws): unbound, not the old uid',
        () async {
      await j().bindUid('A');
      w.failOpen.add(activityJournalScopeId('B'));
      expect(await j().bindUid('B'), isFalse);
      expect(j().boundUid, isNull);
      expect(j().isBound, isFalse);
    });

    test('after an empty uid: unbound', () async {
      await j().bindUid('A');
      expect(await j().bindUid(''), isFalse);
      expect(j().boundUid, isNull);
      expect(j().isBound, isFalse);
    });

    test('after close(): unbound', () async {
      await j().bindUid('A');
      await j().close();
      expect(j().boundUid, isNull);
      expect(j().isBound, isFalse);
    });
  });

  group('item 2: a key deletion failure fails the wipe', () {
    test('forget() propagates the delete failure and drops the cached key',
        () async {
      final provider = SecureStorageJournalKeyProvider(
          storage: w.storage, scopeId: 'scopeX');
      await provider.loadOrCreateKey();
      final name = provider.keyNameInUse;
      expect(w.storage.values.containsKey(name), isTrue);

      w.storage.failDeletes = true;
      await expectLater(provider.forget(), throwsA(isA<StateError>()));
      expect(w.storage.values.containsKey(name), isTrue,
          reason: 'the key really is still there');

      // The cache must be gone: a key removed behind its back reads as absent.
      w.storage.values.remove(name);
      expect(await provider.loadKey(), isNull);
    });

    test('forget() of an absent key succeeds (idempotent)', () async {
      final provider = SecureStorageJournalKeyProvider(
          storage: w.storage, scopeId: 'scopeY');
      await provider.forget();
      await provider.forget();
    });

    test('key names: default and scoped are unchanged', () {
      expect(SecureStorageJournalKeyProvider(storage: w.storage).keyNameInUse,
          'activity_journal.key.v1');
      expect(
          SecureStorageJournalKeyProvider(storage: w.storage, scopeId: 'abc')
              .keyNameInUse,
          'activity_journal.key.v1.abc');
    });

    test('wipeForUid(A) of an unbound scope throws; the retry completes and '
        'is idempotent', () async {
      await putFor('A', 1);
      await w.writeSide('A', 'sources/a.json', '{}');
      await j().bindUid(null);
      expect(w.storage.values.containsKey(keyOf('A')), isTrue);

      w.storage.failDeletes = true;
      await expectLater(j().wipeForUid('A'), throwsA(isA<StateError>()));
      expect(w.storage.values.containsKey(keyOf('A')), isTrue,
          reason: 'the key is still there, so the failure must be visible');

      w.storage.failDeletes = false;
      await j().wipeForUid('A');
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
      expect(await w.snapshot('A'), isEmpty);
      await j().wipeForUid('A'); // again: nothing left, still no error
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
    });

    test('wipeForUid(A) of the BOUND scope throws; journal ends unbound; the '
        'retry completes', () async {
      await putFor('A', 1);
      w.storage.failDeletes = true;
      await expectLater(j().wipeForUid('A'), throwsA(isA<StateError>()));
      expect(j().isBound, isFalse, reason: 'unbound even when the wipe failed');

      w.storage.failDeletes = false;
      await j().wipeForUid('A');
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
      expect(await w.snapshot('A'), isEmpty);
    });

    test('wipe() of the bound journal throws when the key cannot be deleted',
        () async {
      await putFor('A', 1);
      w.storage.failDeletes = true;
      await expectLater(j().wipe(), throwsA(isA<StateError>()));
    });

    test('ActivityAwareLocalDataWipe: LocalWipeIncomplete(activity_journal), '
        'the pending marker stays, the next attempt succeeds', () async {
      await putFor('A', 1);
      await j().bindUid(null);
      final marker = InMemoryPendingWipeMarker()..add('A');
      final wipe = ActivityAwareLocalDataWipe(
          inner: RecordingLocalDataWipe(), journal: j());

      w.storage.failDeletes = true;
      await expectLater(
          wipe.wipe('A'),
          throwsA(isA<LocalWipeIncomplete>().having(
              (e) => e.remaining, 'remaining', ['activity_journal'])));
      expect(
          await finishInterruptedWipe(
              marker: marker, wipe: wipe, signedInUid: null),
          isFalse);
      expect(await marker.read(), {'A'}, reason: 'marker kept for the retry');

      w.storage.failDeletes = false;
      expect(
          await finishInterruptedWipe(
              marker: marker, wipe: wipe, signedInUid: null),
          isTrue);
      expect(await marker.read(), isEmpty);
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
      expect(await w.snapshot('A'), isEmpty);
    });

    test('bound A deleted while its key store fails: the result is '
        'incomplete, never success', () async {
      await putFor('A', 1);
      final wipe = ActivityAwareLocalDataWipe(
          inner: RecordingLocalDataWipe(), journal: j());
      w.storage.failDeletes = true;
      await expectLater(wipe.wipe('A'), throwsA(isA<LocalWipeIncomplete>()));
      expect(await j().bindUid('A'), isFalse,
          reason: 'and the account scope cannot be reopened meanwhile');
    });
  });

  group('close paths stay best effort', () {
    test('switching away from a journal whose close throws still binds the '
        'next one', () async {
      late _ThrowingClose first;
      final scoped = UidScopedActivityJournal(factory: (scopeId) async {
        final real = await w.factory(scopeId);
        final wrapped = _ThrowingClose(real);
        if (scopeId == activityJournalScopeId('A')) first = wrapped;
        return wrapped;
      });
      expect(await scoped.bindUid('A'), isTrue);
      expect(await scoped.bindUid('B'), isTrue);
      expect(first.closes, 1);
      expect(scoped.boundUid, 'B');
      await scoped.close(); // must not throw either
      expect(scoped.isBound, isFalse);
    });

    test('bindUid(null) with a throwing close unbinds and returns true',
        () async {
      final scoped = UidScopedActivityJournal(
          factory: (scopeId) async => _ThrowingClose(await w.factory(scopeId)));
      expect(await scoped.bindUid('A'), isTrue);
      expect(await scoped.bindUid(null), isTrue);
      expect(scoped.isBound, isFalse);
    });

    test('the wipe of a bound journal whose close throws still wipes and '
        'unbinds', () async {
      final scoped = UidScopedActivityJournal(
          factory: (scopeId) async => _ThrowingClose(await w.factory(scopeId)));
      expect(await scoped.bindUid('A'), isTrue);
      // The key is created lazily at the first write; create it explicitly.
      await SecureStorageJournalKeyProvider(
              storage: w.storage, scopeId: activityJournalScopeId('A'))
          .loadOrCreateKey();
      expect(w.storage.values.containsKey(keyOf('A')), isTrue);
      await scoped.wipeForUid('A'); // the close error is swallowed
      expect(scoped.isBound, isFalse);
      expect(w.storage.values.containsKey(keyOf('A')), isFalse);
    });
  });
}
