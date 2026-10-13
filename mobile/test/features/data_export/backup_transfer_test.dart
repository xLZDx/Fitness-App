import 'dart:async';
import 'dart:convert';

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

  group('owner tag', () {
    test('is 16 lowercase hex chars and deterministic', () {
      final tag = ownerTagFor('uid-alpha');
      expect(tag, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(ownerTagFor('uid-alpha'), tag);
    });

    test('differs per uid and never contains the uid', () {
      expect(ownerTagFor('uid-alpha'), isNot(ownerTagFor('uid-beta')));
      expect(ownerTagFor('abcdef0123456789'), isNot(contains('abcdef01')));
      final payload = buildTransferPayload(_sensitive,
          ownerTag: ownerTagFor('uid-alpha'));
      expect(payload, isNot(contains('uid-alpha')));
    });

    test('payload carries owner only when one is given', () {
      expect(readTransferOwner(buildTransferPayload(_sensitive)), isNull);
      expect(
        (jsonDecode(buildTransferPayload(_sensitive)) as Map)
            .containsKey('owner'),
        isFalse,
      );
      final tag = ownerTagFor('u1');
      final withOwner = buildTransferPayload(_sensitive, ownerTag: tag);
      expect(readTransferOwner(withOwner), tag);
      // The tag does not disturb the data.
      expect(readTransferPayload(withOwner).health.medications, ['ramipril']);
    });

    test('readTransferOwner is null for unparseable or non-map payloads', () {
      expect(readTransferOwner('not json'), isNull);
      expect(readTransferOwner('[1,2]'), isNull);
      expect(readTransferOwner('{"owner":42}'), isNull);
    });
  });

  group('BackupRestoreAction account guard and undo', () {
    const other = SensitiveProfile(
      health: HealthHistory(medications: ['metformin']),
      smoking: SmokingHabit.never,
    );

    String seal(SensitiveProfile s, {String? ownerUid}) => encryptBackup(
          plaintext: buildTransferPayload(s,
              ownerTag: ownerUid == null ? null : ownerTagFor(ownerUid)),
          passphrase: 'phrase',
          iterations: 8,
        );

    ({ProviderContainer container, InMemorySensitiveStore store}) setUpFor(
        String uid) {
      final store = InMemorySensitiveStore();
      final container = ProviderContainer(overrides: [
        localSensitiveStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
          (ref) => Stream.value(AuthUser(uid: uid, displayName: 'U')),
        ),
      ]);
      addTearDown(container.dispose);
      return (container: container, store: store);
    }

    test('same-account backup restores', () async {
      final t = setUpFor('u1');
      await t.container
          .read(backupRestoreActionProvider.notifier)
          .restore(envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
      expect(t.container.read(backupRestoreActionProvider).hasError, isFalse);
      expect((await t.store.read('u1')).health.medications, ['ramipril']);
    });

    test('a backup from another account is refused and nothing is written',
        () async {
      final t = setUpFor('u1');
      await t.store.write('u1', other);
      final action = t.container.read(backupRestoreActionProvider.notifier);
      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u2'), passphrase: 'phrase');

      expect(t.container.read(backupRestoreActionProvider).error,
          isA<BackupAccountMismatch>());
      expect((await t.store.read('u1')).health.medications, ['metformin']);
      expect(action.canUndo, isFalse);
    });

    test('acceptOtherAccount restores a backup from another account',
        () async {
      final t = setUpFor('u1');
      final action = t.container.read(backupRestoreActionProvider.notifier);
      await action.restore(
        envelope: seal(_sensitive, ownerUid: 'u2'),
        passphrase: 'phrase',
        acceptOtherAccount: true,
      );
      expect(t.container.read(backupRestoreActionProvider).hasError, isFalse);
      expect((await t.store.read('u1')).health.medications, ['ramipril']);
    });

    test('a backup with no owner (made before tags) restores as before',
        () async {
      final t = setUpFor('u1');
      await t.container
          .read(backupRestoreActionProvider.notifier)
          .restore(envelope: seal(_sensitive), passphrase: 'phrase');
      expect(t.container.read(backupRestoreActionProvider).hasError, isFalse);
      expect((await t.store.read('u1')).health.medications, ['ramipril']);
    });

    test('undo puts back the previous blob', () async {
      final t = setUpFor('u1');
      await t.store.write('u1', other);
      final action = t.container.read(backupRestoreActionProvider.notifier);
      expect(action.canUndo, isFalse);

      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
      expect((await t.store.read('u1')).health.medications, ['ramipril']);
      expect(action.canUndo, isTrue);

      await action.undoLastRestore();
      expect(t.container.read(backupRestoreActionProvider).hasError, isFalse);
      final back = await t.store.read('u1');
      expect(back.health.medications, ['metformin']);
      expect(back.smoking, SmokingHabit.never);
      expect(action.canUndo, isFalse);
    });

    test('undo clears the key when the device held nothing before', () async {
      final t = setUpFor('u1');
      final action = t.container.read(backupRestoreActionProvider.notifier);
      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
      expect(await t.store.readChecked('u1'), isA<SensitiveValid>());

      await action.undoLastRestore();
      expect(t.container.read(backupRestoreActionProvider).hasError, isFalse);
      expect(await t.store.readChecked('u1'), isA<SensitiveMissing>());
      expect(action.canUndo, isFalse);
    });

    test('a failed restore keeps the earlier undo target intact', () async {
      final t = setUpFor('u1');
      await t.store.write('u1', other);
      final action = t.container.read(backupRestoreActionProvider.notifier);
      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
      await action.restore(envelope: 'garbage', passphrase: 'phrase');
      expect(t.container.read(backupRestoreActionProvider).hasError, isTrue);

      await action.undoLastRestore();
      expect((await t.store.read('u1')).health.medications, ['metformin']);
    });

    test('a restore whose WRITE fails offers no undo', () async {
      final store = _FlakyWriteStore()..failWrites = true;
      final container = ProviderContainer(overrides: [
        localSensitiveStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
        ),
      ]);
      addTearDown(container.dispose);
      final action = container.read(backupRestoreActionProvider.notifier);

      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');

      expect(container.read(backupRestoreActionProvider).hasError, isTrue);
      expect(action.canUndo, isFalse,
          reason: 'nothing changed on the device, so there is nothing to undo');
    });

    test('a restore whose WRITE fails keeps the earlier undo target',
        () async {
      final store = _FlakyWriteStore();
      final container = ProviderContainer(overrides: [
        localSensitiveStoreProvider.overrideWithValue(store),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
        ),
      ]);
      addTearDown(container.dispose);
      await store.write('u1', other);
      final action = container.read(backupRestoreActionProvider.notifier);
      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
      expect(action.canUndo, isTrue);

      store.failWrites = true;
      await action.restore(
          envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
      expect(container.read(backupRestoreActionProvider).hasError, isTrue);
      expect(action.canUndo, isTrue,
          reason: 'the failed second restore must not discard the first undo');

      store.failWrites = false;
      await action.undoLastRestore();
      expect(container.read(backupRestoreActionProvider).hasError, isFalse);
      expect((await store.read('u1')).health.medications, ['metformin']);
    });

    group('undo is tied to the signed-in account', () {
      late StreamController<AuthUser?> auth;
      late ProviderContainer container;
      late BackupRestoreAction action;

      Future<void> signedInAndRestored() async {
        auth = StreamController<AuthUser?>();
        addTearDown(auth.close);
        final store = InMemorySensitiveStore();
        container = ProviderContainer(overrides: [
          localSensitiveStoreProvider.overrideWithValue(store),
          authUserProvider.overrideWith((ref) => auth.stream),
          // The real one re-reads auth after an await and trips riverpod's
          // "dependency changed" assertion when the test swaps the account.
          currentProfileProvider
              .overrideWith((ref) => Stream<UserProfile?>.value(null)),
        ]);
        addTearDown(container.dispose);
        action = container.read(backupRestoreActionProvider.notifier);
        auth.add(const AuthUser(uid: 'u1', displayName: 'U'));
        await action.restore(
            envelope: seal(_sensitive, ownerUid: 'u1'), passphrase: 'phrase');
        expect(action.canUndo, isTrue);
      }

      Future<void> deliver() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      test('the same account re-emitting keeps the undo', () async {
        await signedInAndRestored();
        auth.add(const AuthUser(uid: 'u1', displayName: 'Renamed'));
        await deliver();
        expect(action.canUndo, isTrue);
      });

      test('switching to another account clears it', () async {
        await signedInAndRestored();
        auth.add(const AuthUser(uid: 'u2', displayName: 'Other'));
        await deliver();
        expect(action.canUndo, isFalse);
      });

      test('signing out clears it', () async {
        await signedInAndRestored();
        auth.add(null);
        await deliver();
        expect(action.canUndo, isFalse);
      });
    });
  });
}

/// An in-memory store whose writes can be made to fail on demand.
class _FlakyWriteStore extends InMemorySensitiveStore {
  bool failWrites = false;

  @override
  Future<void> write(String uid, SensitiveProfile value) async {
    if (failWrites) throw StateError('disk full');
    await super.write(uid, value);
  }
}
