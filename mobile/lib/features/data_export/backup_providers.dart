import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/state/auth_providers.dart';
import '../profile/data/profile_models.dart';
import '../profile/data/sensitive_profile.dart';
import '../profile/state/profile_providers.dart';
import 'backup_envelope.dart';
import 'backup_transfer.dart';
import 'data_export_sink.dart';

/// H2b — create and restore the encrypted transfer backup.
///
/// Both actions push the key derivation onto a background isolate. PBKDF2 at
/// [kDefaultIterations] is about a second of pure-Dart work on a mid-range
/// phone, and a second of frozen UI on a button press reads as a crash, not as
/// security.

({String envelope, String filename}) _seal(
  ({String payload, String passphrase, String filename}) args,
) =>
    (
      envelope: encryptBackup(
        plaintext: args.payload,
        passphrase: args.passphrase,
      ),
      filename: args.filename,
    );

String _open(({String envelope, String passphrase}) args) => decryptBackup(
      envelopeJson: args.envelope,
      passphrase: args.passphrase,
    );

/// Builds the backup and hands it to the same sink the GDPR export uses.
class BackupCreateAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> create(String passphrase) async {
    state = const AsyncValue.loading();
    try {
      // `await ... .future`, not a bare read: on a container where nothing has
      // warmed auth up yet the first synchronous read is AsyncLoading, and
      // "not resolved yet" would read as "signed out" -- the same collapse
      // DataExportAction documents.
      final user = await ref.read(authUserProvider.future);
      if (user == null) {
        throw StateError('Cannot back up while signed out');
      }
      final profile = await ref.read(currentProfileProvider.future) ??
          await ref.read(profileRepositoryProvider).load(user.uid) ??
          UserProfile.empty(user.uid);

      final sensitive = extractSensitive(profile);
      if (sensitive.isEmpty) {
        // Nothing to carry. Refused rather than delivered, because a file that
        // restores nothing is worse than no file: the user keeps it, trusts
        // it, and finds out on the new phone.
        throw StateError('Nothing to back up yet');
      }

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final sealed = await compute(
        _seal,
        (
          payload: buildTransferPayload(sensitive),
          passphrase: passphrase,
          filename: 'fitness-app-backup-$stamp.json',
        ),
      );
      await ref.read(dataExportSinkProvider).deliver(
            filename: sealed.filename,
            contents: sealed.envelope,
          );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final backupCreateActionProvider =
    NotifierProvider<BackupCreateAction, AsyncValue<void>>(
        BackupCreateAction.new);

/// Decrypts a pasted backup and writes it into the store the profile reads.
class BackupRestoreAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> restore({
    required String envelope,
    required String passphrase,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = await ref.read(authUserProvider.future);
      if (user == null) {
        throw StateError('Cannot restore while signed out');
      }

      final payload = await compute(
        _open,
        (envelope: envelope.trim(), passphrase: passphrase),
      );
      final sensitive = readTransferPayload(payload);
      if (sensitive.isEmpty) {
        throw const TransferPayloadException('this backup is empty');
      }

      // Straight into the store, then a re-read. Saving through the repository
      // would round-trip the whole profile to Firestore for a change that only
      // concerns the device -- and would push a restored profile's non-health
      // half over whatever the server already holds, which is newer.
      await ref.read(localSensitiveStoreProvider).write(user.uid, sensitive);
      ref.invalidate(currentProfileProvider);

      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final backupRestoreActionProvider =
    NotifierProvider<BackupRestoreAction, AsyncValue<void>>(
        BackupRestoreAction.new);
