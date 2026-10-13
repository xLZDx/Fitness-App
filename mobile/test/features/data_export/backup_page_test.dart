import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/backup_envelope.dart';
import 'package:fitness_app/features/data_export/backup_page.dart';
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
  await tester.pumpWidget(ProviderScope(
    overrides: [
      localSensitiveStoreProvider.overrideWithValue(store),
      authUserProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
      ),
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
  return store;
}

Future<void> _fillAndRestore(WidgetTester tester, String envelope) async {
  await tester.enterText(find.byKey(const Key('backup-restore-body')), envelope);
  await tester.enterText(
      find.byKey(const Key('backup-restore-passphrase')), 'phrase');
  await tester.pump();
  final button = find.byKey(const Key('backup-restore-button'));
  await tester.ensureVisible(button);
  await tester.runAsync(() async {
    await tester.tap(button);
    // compute() needs a real isolate round-trip; give it real time.
    await Future<void>.delayed(const Duration(seconds: 2));
  });
  await tester.pump();
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
    await tester.ensureVisible(anyway);
    await tester.runAsync(() async {
      await tester.tap(anyway);
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();

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

    await tester.ensureVisible(undo);
    await tester.runAsync(() async {
      await tester.tap(undo);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Nothing was on the device before, so undo clears it.
    expect(await store.readChecked('u1'), isA<SensitiveMissing>());
    expect(find.byKey(const Key('backup-restore-undo')), findsNothing);
  });
}
