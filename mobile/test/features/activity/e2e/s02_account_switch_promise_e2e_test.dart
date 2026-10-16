// S02 remediation E1 (test epic 11a): the user promise from the lessons log
// ("S02 journal wipe on account switch"): signing in as someone else never
// destroys my data. End to end over the REAL FileActivityJournal on a temp
// directory (in-memory key store), once through bindUid directly and once
// through the app's auth-driven binding listener.
import 'dart:async';
import 'dart:convert';

import 'package:fitness_app/core/config/activity_flags.dart';
import 'package:fitness_app/core/wiring/activity_wiring.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_harness.dart';
import '../../../support/scoped_journal_world.dart';

String _fingerprint(ActivitySession s) =>
    '${sessionJson(s)}|${jsonEncode(streamsOf(s))}';

void main() {
  late ScopedJournalWorld w;

  setUp(() async => w = await ScopedJournalWorld.create());
  tearDown(() => w.dispose());

  Future<List<String>> ids() async =>
      [for (final e in await w.journal.list()) e.id]..sort();

  test('A records, A signs out, B signs in and records, B signs out, A signs '
      'in: A\'s session and stream are intact and B\'s are not visible',
      () async {
    final j = w.journal;

    // A signs in and records a session with a GPS and a heart-rate stream.
    expect(await j.bindUid('A'), isTrue);
    final sessionA = journalSession(idFor(1), seed: 1);
    await j.put(sessionA);
    final stored = (await j.read(idFor(1)))!;
    final fingerprintA = _fingerprint(stored.session);
    expect(stored.session.streams.keys,
        containsAll([StreamKind.gps, StreamKind.heartRate]),
        reason: 'precondition: the stream really is stored');
    expect(stored.streamLost, isFalse);

    // A signs out.
    expect(await j.bindUid(null), isTrue);
    expect(await j.list(), isEmpty, reason: 'nobody signed in sees nothing');

    // B signs in: sees nothing of A, records its own.
    expect(await j.bindUid('B'), isTrue);
    expect(await ids(), isEmpty, reason: 'B starts with an empty journal');
    expect(await j.read(idFor(1)), isNull, reason: 'B cannot read A by id');
    await j.put(journalSession(idFor(2), seed: 2));
    expect(await ids(), [idFor(2)]);
    final fingerprintB = _fingerprint((await j.read(idFor(2)))!.session);

    // B signs out.
    expect(await j.bindUid(null), isTrue);

    // A signs in again: everything is exactly as left.
    expect(await j.bindUid('A'), isTrue);
    expect(await ids(), [idFor(1)], reason: 'only A\'s session is visible');
    final back = (await j.read(idFor(1)))!;
    expect(_fingerprint(back.session), fingerprintA,
        reason: 'session and streams are byte-for-byte the same');
    expect(back.streamLost, isFalse, reason: 'the stream key survived');
    expect(back.session.streams[StreamKind.gps]!.lats, isNotEmpty);
    expect(await j.read(idFor(2)), isNull, reason: 'B\'s session is invisible');
    expect(await j.assessSignOut().then((a) => a.entryCount), 1);

    // And B still has its own on the next sign-in.
    expect(await j.bindUid('B'), isTrue);
    expect(_fingerprint((await j.read(idFor(2)))!.session), fingerprintB);
    expect(await j.read(idFor(1)), isNull);
    expect(w.storage.deletes, 0, reason: 'no key was ever deleted');
  });

  test('the same promise through the app\'s auth-driven binding', () async {
    final auth = StreamController<AuthUser?>();
    addTearDown(() => unawaited(auth.close()));
    final c = ProviderContainer(overrides: [
      activityFlagsProvider.overrideWithValue(
          const ActivityFlags(localJournal: true)),
      activityJournalProvider.overrideWithValue(w.journal),
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    addTearDown(c.dispose);
    c.read(activityJournalBindingProvider);

    Future<void> signIn(AuthUser? u, String? expectBound) async {
      auth.add(u);
      for (var i = 0;
          i < 1000 && w.journal.boundUid != expectBound;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(w.journal.boundUid, expectBound);
    }

    AuthUser user(String uid) => AuthUser(
        uid: uid, displayName: uid, provider: AuthProvider.google);

    await signIn(user('A'), 'A');
    await w.journal.put(journalSession(idFor(1), seed: 1));
    final fingerprintA = _fingerprint((await w.journal.read(idFor(1)))!.session);

    await signIn(null, null);
    await signIn(user('B'), 'B');
    expect(await ids(), isEmpty);
    await w.journal.put(journalSession(idFor(2), seed: 2));

    await signIn(null, null);
    await signIn(user('A'), 'A');
    expect(await ids(), [idFor(1)]);
    expect(_fingerprint((await w.journal.read(idFor(1)))!.session),
        fingerprintA);
    expect((await w.journal.read(idFor(1)))!.streamLost, isFalse);
    expect(await w.journal.read(idFor(2)), isNull);
  });
}
