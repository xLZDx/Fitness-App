// S03-16 sign-out warning S-10 (test plan 6.2). The real guard and sheets run
// in a host with one button; the journal is a fake with delete/export spies.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/state/sign_out_guard.dart';

import '../../support/s03_step4_support.dart';

Finder key(String k) => find.byKey(Key(k));

class _Host extends ConsumerWidget {
  const _Host(this.results);
  final List<bool> results;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('host.signOut'),
            onPressed: () async =>
                results.add(await confirmSignOutWithLocalData(context, ref)),
            child: const Text('go'),
          ),
        ),
      );
}

Future<void> settle(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 80));
  }
}

JournalEntry run(String id) => entry(sess(id, start: kNow, dist: 1, time: 1));

Future<List<bool>> pumpHost(WidgetTester t, List<Override> o) async {
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  final results = <bool>[];
  await t.pumpWidget(appHost(_Host(results), overrides: o));
  await settle(t);
  return results;
}

Future<void> trigger(WidgetTester t) async {
  await t.tap(key('host.signOut'));
  await settle(t);
}

void main() {
  group('AC-SO-1 warning with three actions', () {
    testWidgets('AC-SO-1/threeActions', (t) async {
      final j = FakeJournal([run('a'), run('b'), run('c')]);
      final r = await pumpHost(t, dashOverrides(journal: j));
      await trigger(t);
      expect(find.text('You have 3 activities stored only on this device'),
          findsOneWidget);
      expect(key('signOut.exportFirst'), findsOneWidget);
      expect(key('signOut.andDelete'), findsOneWidget);
      expect(key('signOut.cancel'), findsOneWidget);
      expect(r, isEmpty, reason: 'no sign-out decision before a choice');
      expect(j.wipeCalls, 0);
    });
    testWidgets('AC-SO-1/nothingDeletedFirst: needs the second confirmation',
        (t) async {
      final j = FakeJournal([run('a'), run('b'), run('c')]);
      final r = await pumpHost(t, dashOverrides(journal: j));
      await trigger(t);
      await t.tap(key('signOut.andDelete'));
      await settle(t);
      expect(key('signOut.confirmDelete'), findsOneWidget);
      expect(j.wipeCalls, 0, reason: 'first tap deletes nothing');
      await t.tap(key('signOut.confirmDelete'));
      await settle(t);
      expect(j.wipeCalls, 1);
      expect(r, [true]);
    });
  });

  testWidgets('AC-SO-2 empty journal signs out at once', (t) async {
    final r = await pumpHost(t, dashOverrides(journal: FakeJournal()));
    await trigger(t);
    expect(r, [true]);
    expect(find.byType(Dialog), findsNothing);
    expect(key('signOut.cancel'), findsNothing);
  });

  testWidgets('DT-16-1 Cancel stays signed in, deletes nothing', (t) async {
    final j = FakeJournal([run('a')]);
    final r = await pumpHost(t, dashOverrides(journal: j));
    await trigger(t);
    await t.tap(key('signOut.cancel'));
    await settle(t);
    expect(r, [false]);
    expect(j.wipeCalls, 0);
    expect(key('signOut.cancel'), findsNothing);
  });

  testWidgets('DT-16-2 notEnabled: no prompt', (t) async {
    final r = await pumpHost(t, dashOverrides(localJournal: false));
    await trigger(t);
    expect(r, [true]);
    expect(key('signOut.cancel'), findsNothing);
  });

  testWidgets('DT-16-3 account B never sees A after A deleted', (t) async {
    // Needs the real UidScopedActivityJournal on a temp directory; the S02
    // e2e files (s02_account_switch_promise, s02_wipe_and_rebind) own that
    // seam. Not re-implemented here: NOT_RUN by design in this step.
  }, skip: true);

  group('DT-16-4 cannot check', () {
    testWidgets('DT-16-4/failedToOpen: no Try again, no silent sign-out',
        (t) async {
      final r = await pumpHost(t, dashOverrides());
      await trigger(t);
      expect(find.text('We could not check the activity stored on this device'),
          findsOneWidget);
      expect(key('signOut.tryAgain'), findsNothing);
      expect(key('signOut.anyway'), findsOneWidget);
      expect(key('signOut.cancel'), findsOneWidget);
      expect(r, isEmpty);
      await t.tap(key('signOut.anyway'));
      await settle(t);
      expect(r, [true]);
    });
    testWidgets('DT-16-4/binding: Try again offered; Cancel stays signed in',
        (t) async {
      final j = ScopedFakeJournal([run('a')]);
      final r = await pumpHost(
          t, dashOverrides(journal: j, timers: FakeTimers()));
      await trigger(t);
      expect(key('signOut.tryAgain'), findsOneWidget);
      expect(r, isEmpty);
      await t.tap(key('signOut.cancel'));
      await settle(t);
      expect(r, [false]);
    });
    testWidgets('DT-16-4/gaveUp: sheet shown', (t) async {
      final j = ScopedFakeJournal([run('a')]);
      final timers = FakeTimers();
      final r = await pumpHost(t, dashOverrides(journal: j, timers: timers));
      for (var i = 0; i < 5; i++) {
        j.complete(false);
        await settle(t, 2);
        timers.all.last.fire();
        await settle(t, 2);
      }
      j.complete(false);
      await settle(t);
      await trigger(t);
      expect(key('signOut.tryAgain'), findsOneWidget);
      expect(key('signOut.anyway'), findsOneWidget);
      expect(r, isEmpty);
    });
  });

  testWidgets('DT-16-5 a failing wipe keeps the user signed in with Retry',
      (t) async {
    final j = FakeJournal([run('a')])..wipeError = StateError('disk');
    final r = await pumpHost(t, dashOverrides(journal: j));
    await trigger(t);
    await t.tap(key('signOut.andDelete'));
    await settle(t);
    await t.tap(key('signOut.confirmDelete'));
    await settle(t);
    expect(key('signOut.retry'), findsOneWidget);
    expect(find.text('Activity deleted from this device.'), findsNothing);
    await t.tap(key('signOut.cancel'));
    await settle(t);
    expect(r, [false]);
  });

  testWidgets('DT-16-6 a failing export does not sign out', (t) async {
    // FakeJournal.read is unimplemented, so the real export path throws.
    final j = FakeJournal([run('a')]);
    final r = await pumpHost(t, dashOverrides(journal: j));
    await trigger(t);
    await t.tap(key('signOut.exportFirst'));
    await settle(t, 10);
    expect(key('signOut.retry'), findsOneWidget);
    expect(r, isEmpty, reason: 'no sign-out while the error sheet is open');
    await t.tap(key('signOut.cancel'));
    await settle(t);
    // Back on the warning sheet, still signed in; nothing deleted.
    expect(key('signOut.exportFirst'), findsOneWidget);
    expect(r, isEmpty);
    await t.tap(key('signOut.cancel'));
    await settle(t);
    expect(r, [false]);
    expect(j.wipeCalls, 0);
  });

  testWidgets('DT-16-7 deleted text only after the wipe returned', (t) async {
    final j = FakeJournal([run('a')])..wipeGate = Completer<void>();
    final r = await pumpHost(t, dashOverrides(journal: j));
    await trigger(t);
    await t.tap(key('signOut.andDelete'));
    await settle(t);
    await t.tap(key('signOut.confirmDelete'));
    await settle(t);
    expect(j.wipeCalls, 1);
    expect(find.text('Activity deleted from this device.'), findsNothing);
    expect(r, isEmpty, reason: 'sign-out waits for the wipe');
    j.wipeGate!.complete();
    await settle(t);
    expect(find.text('Activity deleted from this device.'), findsOneWidget);
    expect(r, [true]);
  });

  testWidgets('DT-16-8 export temp location', (t) async {
    // Needs path_provider and share_plus platform fakes plus a backup layout;
    // not implemented in this step (NOT_RUN, see the findings).
  }, skip: true);

  test('DT-16-9 every user sign-out call site goes through the guard', () {
    final allowed = <String, String>{
      // Not a user-initiated sign-out: runs after a completed account deletion
      // (the local data was wiped by the deletion flow itself).
      'features/account_deletion/state/account_deletion_providers.dart':
          'post-deletion',
    };
    final callSites = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = f.readAsStringSync();
      if (!RegExp(r'authActionProvider\.notifier\)\s*\.signOut\(\)')
          .hasMatch(text)) {
        continue;
      }
      final rel = f.path.replaceAll('\\', '/').replaceFirst('lib/', '');
      callSites.add(rel);
      if (allowed.containsKey(rel)) continue;
      expect(text.contains('confirmSignOutWithLocalData'), isTrue,
          reason: '$rel signs out without the guard');
    }
    expect(callSites, contains('features/profile/profile_page.dart'));
    expect(callSites.toSet().difference(allowed.keys.toSet()).toList(),
        ['features/profile/profile_page.dart']);
  });
}
