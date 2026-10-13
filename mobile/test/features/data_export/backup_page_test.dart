import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/backup_envelope.dart';
import 'package:fitness_app/features/data_export/backup_page.dart';
import 'package:fitness_app/features/data_export/backup_providers.dart';
import 'package:fitness_app/features/data_export/backup_transfer.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// The restore half of the backup page: the "restore anyway" escape hatch after
/// an account mismatch, and the undo that follows a restore. Drives the real
/// restore action (real isolate, real envelope) against an in-memory store.
const _sensitive = SensitiveProfile(
  health: HealthHistory(medications: ['ramipril']),
  smoking: SmokingHabit.regular,
);

String _seal(String ownerUid) => encryptBackup(
      plaintext: buildTransferPayload(_sensitive,
          ownerTag: ownerTagFor(ownerUid)),
      passphrase: 'phrase',
      iterations: 8,
    );

Future<InMemorySensitiveStore> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final store = InMemorySensitiveStore();
  // Synchronous controller: the restore notifier subscribes to auth while the
  // page builds (inside the fake-async zone), and a `Stream.value` would then
  // deliver its event through a fake-zone microtask that the real-time section
  // of these tests can never flush.
  final auth = StreamController<AuthUser?>(sync: true);
  addTearDown(auth.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      localSensitiveStoreProvider.overrideWithValue(store),
      authUserProvider.overrideWith((ref) => auth.stream),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const BackupPage(),
    ),
  ));
  await tester.pump();
  auth.add(const AuthUser(uid: 'u1', displayName: 'U'));
  await tester.pump();
  return store;
}

/// Waits (real time, bounded) until the restore action has left `loading`.
/// compute() needs a real isolate round-trip whose latency varies by machine
/// load, so a fixed sleep is a race; the action state is the condition.
///
/// The notifier lives in the fake-async zone (it subscribes to auth while the
/// page builds), so the tap stays in that zone and each real-time wait is
/// followed by a pump that flushes the zone's microtasks.
Future<void> _tapAndSettle(WidgetTester tester, Finder target) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(BackupPage)));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  for (var i = 0;
      i < 600 && container.read(backupRestoreActionProvider).isLoading;
      i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  expect(container.read(backupRestoreActionProvider).isLoading, isFalse,
      reason: 'restore action did not finish in 30 s');
  // The page continues (setState) after the action's future resolves; give
  // that continuation a real tick and a frame.
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.pump();
}

Future<void> _fillAndRestore(WidgetTester tester, String envelope) async {
  await tester.enterText(find.byKey(const Key('backup-restore-body')), envelope);
  await tester.enterText(
      find.byKey(const Key('backup-restore-passphrase')), 'phrase');
  await tester.pump();
  await _tapAndSettle(tester, find.byKey(const Key('backup-restore-button')));
}

void main() {
  testWidgets('a mismatch offers "Restore anyway", which restores and offers undo',
      (tester) async {
    final store = await _pump(tester);
    expect(find.byKey(const Key('backup-restore-anyway')), findsNothing);
    expect(find.byKey(const Key('backup-restore-undo')), findsNothing);

    await _fillAndRestore(tester, _seal('someone-else'));

    expect(find.byKey(const Key('backup-restore-anyway')), findsOneWidget);
    expect(find.byKey(const Key('backup-restore-undo')), findsNothing);
    expect((await store.read('u1')).isEmpty, isTrue);

    final anyway = find.byKey(const Key('backup-restore-anyway'));
    await _tapAndSettle(tester, anyway);

    expect((await store.read('u1')).health.medications, ['ramipril']);
    expect(find.byKey(const Key('backup-restore-anyway')), findsNothing);
    expect(find.byKey(const Key('backup-restore-undo')), findsOneWidget);
  });

  testWidgets('undo after a restore puts the device back and hides itself',
      (tester) async {
    final store = await _pump(tester);
    await _fillAndRestore(tester, _seal('u1'));

    // Same account: no mismatch button, straight to a restored state.
    expect(find.byKey(const Key('backup-restore-anyway')), findsNothing);
    expect((await store.read('u1')).health.medications, ['ramipril']);
    final undo = find.byKey(const Key('backup-restore-undo'));
    expect(undo, findsOneWidget);

    await _tapAndSettle(tester, undo);

    // Nothing was on the device before, so undo clears it.
    expect(await store.readChecked('u1'), isA<SensitiveMissing>());
    expect(find.byKey(const Key('backup-restore-undo')), findsNothing);
    expect(
        find.text(
            'Undone. This phone is back to how it was before the restore.',
            skipOffstage: false),
        findsOneWidget);
  });
}
