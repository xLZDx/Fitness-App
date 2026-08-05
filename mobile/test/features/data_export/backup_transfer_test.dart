import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/backup_envelope.dart';
import 'package:fitness_app/features/data_export/backup_providers.dart';
import 'package:fitness_app/features/data_export/backup_transfer.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';

/// H2b — what travels, and that restoring it lands where the profile reads.
const _sensitive = SensitiveProfile(
  health: HealthHistory(
    conditions: ['hypertension'],
    medications: ['ramipril'],
    injuries: [Injury(bodyPart: 'knee', type: 'ligament')],
    bloodPressure: BloodPressure.high,
  ),
  smoking: SmokingHabit.regular,
  alcohol: AlcoholHabit.moderate,
);

void main() {
  group('transfer payload', () {
    test('round-trips every field', () {
      final back = readTransferPayload(buildTransferPayload(_sensitive));
      expect(back.health.conditions, ['hypertension']);
      expect(back.health.medications, ['ramipril']);
      expect(back.health.injuries.single.bodyPart, 'knee');
      expect(back.health.bloodPressure, BloodPressure.high);
      expect(back.smoking, SmokingHabit.regular);
      expect(back.alcohol, AlcoholHabit.moderate);
    });

    /// By the time this parses, the GCM tag has already proved the passphrase.
    /// Anything wrong here is a content problem and must not be reported as a
    /// passphrase one, or the user retypes a correct passphrase forever.
    test('a decrypted-but-foreign payload is a content error', () {
      expect(
        () => readTransferPayload('{"kind":"something-else","version":1}'),
        throwsA(isA<TransferPayloadException>()),
      );
      expect(
        () => readTransferPayload('not json'),
        throwsA(isA<TransferPayloadException>()),
      );
    });

    test('a newer payload version says so', () {
      expect(
        () => readTransferPayload(
            '{"kind":"$kTransferKind","version":2,"data":{}}'),
        throwsA(isA<TransferPayloadException>()),
      );
    });

    /// The end-to-end shape a user actually performs: seal on the old phone,
    /// open on the new one.
    test('survives the full seal-and-open chain', () {
      final sealed = encryptBackup(
        plaintext: buildTransferPayload(_sensitive),
        passphrase: 'a phrase i will remember',
        iterations: 8,
      );
      // The thing being protected is not in the file.
      expect(sealed, isNot(contains('ramipril')));
      expect(sealed, isNot(contains('hypertension')));

      final back = readTransferPayload(decryptBackup(
        envelopeJson: sealed,
        passphrase: 'a phrase i will remember',
      ));
      expect(back.health.medications, ['ramipril']);
    });
  });

  group('BackupRestoreAction', () {
    /// The reason `localSensitiveStoreProvider` exists at all. If restore
    /// wrote to its own store instance instead of the one
    /// `DeviceHealthProfileRepository` reads, the import would report success
    /// and change nothing -- the worst kind of failure, because the user only
    /// finds out later, on the phone they migrated to.
    test('writes into the store the profile reads from', () async {
      final store = InMemorySensitiveStore();
      final container = ProviderContainer(overrides: [
        localSensitiveStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
        ),
      ]);
      addTearDown(container.dispose);

      final sealed = encryptBackup(
        plaintext: buildTransferPayload(_sensitive),
        passphrase: 'phrase',
      );

      await container
          .read(backupRestoreActionProvider.notifier)
          .restore(envelope: sealed, passphrase: 'phrase');

      expect(container.read(backupRestoreActionProvider).hasError, isFalse);
      final stored = await store.read('u1');
      expect(stored.health.medications, ['ramipril']);
      expect(stored.smoking, SmokingHabit.regular);
    });

    test('a wrong passphrase leaves the store untouched', () async {
      final store = InMemorySensitiveStore();
      final container = ProviderContainer(overrides: [
        localSensitiveStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
        ),
      ]);
      addTearDown(container.dispose);

      final sealed = encryptBackup(
        plaintext: buildTransferPayload(_sensitive),
        passphrase: 'phrase',
      );

      await container
          .read(backupRestoreActionProvider.notifier)
          .restore(envelope: sealed, passphrase: 'not the phrase');

      expect(container.read(backupRestoreActionProvider).hasError, isTrue);
      expect((await store.read('u1')).isEmpty, isTrue);
    });
  });
}
