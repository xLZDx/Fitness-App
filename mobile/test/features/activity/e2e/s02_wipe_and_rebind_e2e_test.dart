// S02 remediation F2 (test epic 12b): adversarial end to end. The user promise
// is "when I delete my account my activity data is erased and nothing brings it
// back; the next person who signs in keeps their own data". Oracles: GPS-PRIV-085
// (design 6.2, 7), S02_DESIGN.md 17 item 22 and the F2 test notes, not the code.
//
// REAL FileActivityJournal on a temp directory, the real binding provider, the
// real ActivityAwareLocalDataWipe, an auth stream that re-emits the deleted uid.
import 'dart:async';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/activity/repository/activity_aware_local_data_wipe.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

AuthUser _user(String uid, [String name = 'n']) =>
    AuthUser(uid: uid, displayName: name, provider: AuthProvider.google);

void main() {
  late ScopedJournalWorld w;
  late StreamController<AuthUser?> auth;

  setUp(() async {
    w = await ScopedJournalWorld.create();
    auth = StreamController<AuthUser?>();
  });

  tearDown(() async {
    unawaited(auth.close());
    await w.dispose();
  });

  String keyOf(String uid) =>
      '${SecureStorageJournalKeyProvider.keyName}.${activityJournalScopeId(uid)}';

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      activityFlagsProvider
          .overrideWithValue(const ActivityFlags(localJournal: true)),
      activityJournalProvider.overrideWithValue(w.journal),
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    addTearDown(c.dispose);
    c.read(activityJournalBindingProvider);
    return c;
  }

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'not reached: $what');
  }

  /// Real disk I/O: give pending work real time for "nothing happens" checks.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 150));

  Future<void> emit(AuthUser? u) async {
    auth.add(u);
    await Future<void>.delayed(Duration.zero);
  }

  Future<List<String>> idsOf() async =>
      [for (final e in await w.journal.list()) e.id]..sort();

  test('delete A, the auth stream re-emits A: no scope or key for A reappears; '
      'B signs in and records; B intact, A gone', () async {
    final c = container();

    // A signs in and records.
    await emit(_user('A'));
    await until(() => w.journal.boundUid == 'A', 'A bound');
    await w.journal.put(journalSession(idFor(1), seed: 1));
    await w.writeSide('A', 'sources/a.json', '{}');
    expect(await idsOf(), [idFor(1)]);
    expect(w.storage.values.containsKey(keyOf('A')), isTrue,
        reason: 'precondition: A has a key');

    // The server confirmed the deletion: the app marks it, then wipes.
    c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
    await ActivityAwareLocalDataWipe(
            inner: RecordingLocalDataWipe(), journal: w.journal)
        .wipe('A');
    expect(w.journal.isBound, isFalse);
    expect(w.storage.values.containsKey(keyOf('A')), isFalse);
    expect(await w.snapshot('A'), isEmpty);
    final opensAfterWipe = w.opened.length;

    // The auth stream re-emits A (before and after the sign-out).
    await emit(_user('A', 'again'));
    await emit(null);
    await emit(_user('A', 'third'));
    await settle();
    expect(w.journal.isBound, isFalse, reason: 'A is never bound again');
    expect(w.opened.length, opensAfterWipe, reason: 'A\'s scope never opened');
    expect(w.storage.values.containsKey(keyOf('A')), isFalse,
        reason: 'no key for A reappeared');
    expect(await w.snapshot('A'), isEmpty, reason: 'no file for A reappeared');

    // B signs in and records.
    await emit(_user('B'));
    await until(() => w.journal.boundUid == 'B', 'B bound');
    expect(await idsOf(), isEmpty, reason: 'B sees nothing of A');
    await w.journal.put(journalSession(idFor(2), seed: 2));
    expect(await idsOf(), [idFor(2)]);

    // Final state: B intact, A gone.
    expect(w.storage.values.containsKey(keyOf('B')), isTrue);
    expect(w.storage.values.containsKey(keyOf('A')), isFalse);
    expect(await w.snapshot('A'), isEmpty);
    expect((await w.snapshot('B')).keys.any((k) => k.contains('journal/')),
        isTrue,
        reason: 'B\'s record is on disk');
    expect(await w.scopeDirs(),
        everyElement(isIn([activityJournalScopeId('A'), activityJournalScopeId('B')])));
  });

  test('journal guard alone (no deleting-uid marker): a same-uid re-emission '
      'after the wipe does not bring A back; B is untouched', () async {
    container();
    await emit(_user('B'));
    await until(() => w.journal.boundUid == 'B', 'B bound');
    await w.journal.put(journalSession(idFor(2), seed: 2));
    final b = await w.snapshot('B');
    // Deleting B: wipe of the bound scope, then the stream re-emits B.
    await ActivityAwareLocalDataWipe(
            inner: RecordingLocalDataWipe(), journal: w.journal)
        .wipe('B');
    final opens = w.opened.length;
    expect(await w.snapshot('B'), isEmpty);
    expect(b, isNotEmpty, reason: 'precondition: B had files');

    await emit(_user('B', 'again'));
    await settle();
    expect(w.journal.isBound, isFalse);
    expect(w.opened.length, opens);
    expect(w.storage.values.containsKey(keyOf('B')), isFalse);
    expect(await w.snapshot('B'), isEmpty);
  });

  test('a failed key deletion keeps the deletion incomplete and the data '
      'recoverable for the retry; the retry then erases everything', () async {
    final c = container();
    await emit(_user('A'));
    await until(() => w.journal.boundUid == 'A', 'A bound');
    await w.journal.put(journalSession(idFor(1), seed: 1));
    c.read(accountBeingDeletedUidProvider.notifier).state = 'A';
    final wipe = ActivityAwareLocalDataWipe(
        inner: RecordingLocalDataWipe(), journal: w.journal);

    w.storage.failDeletes = true;
    await expectLater(wipe.wipe('A'), throwsA(isA<LocalWipeIncomplete>()));
    await emit(_user('A', 'again'));
    await settle();
    expect(w.journal.isBound, isFalse, reason: 'not reopened between attempts');

    w.storage.failDeletes = false;
    await wipe.wipe('A');
    expect(w.storage.values.containsKey(keyOf('A')), isFalse);
    expect(await w.snapshot('A'), isEmpty);
  });
}
