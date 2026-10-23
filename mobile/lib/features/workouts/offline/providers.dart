/// Riverpod providers of the offline command module. Nothing in the app
/// watches them yet and nothing overrides the store provider in `main.dart`;
/// the module is inert until a later slice wires it.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'command_queue_store.dart';
import 'file_command_queue_store.dart';
import 'sqlite_command_queue_store.dart';
import 'status.dart';

/// The uid-scoped queue store. Throws until overridden (same pattern as the
/// recorder ports): a store must be opened for the signed-in uid by the code
/// that owns the account binding.
final offlineCommandQueueStoreProvider = Provider<CommandQueueStore>((ref) {
  throw UnimplementedError(
      'offlineCommandQueueStoreProvider must be overridden with a store for the signed-in uid');
});

/// `<app support>/offline_command_queue`, the parent of every uid scope of the
/// legacy file store (kept for the file implementation and its tests).
Future<String> offlineCommandQueueRoot() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/offline_command_queue';
}

/// Directory (under the app support directory) holding the SQLite databases.
/// Android excludes the whole directory from backup and device transfer
/// (backup_rules.xml, data_extraction_rules.xml); keep the name in step.
const String kOfflineQueueDbDirName = 'offline_command_queue_db';

/// `<app support>/offline_command_queue_db/workout_command_queue_<scope>.db`
/// (plus `-wal` and `-shm`); the directory is created here.
Future<String> offlineCommandQueueDatabasePath(String uid) async {
  final dir = await getApplicationSupportDirectory();
  final dbDir = Directory('${dir.path}/$kOfflineQueueDbDirName');
  await dbDir.create(recursive: true);
  return '${dbDir.path}/${sqliteQueueFileName(uid)}';
}

/// Opens the durable SQLite store of [uid] in the default location. The caller
/// owns the result (dispose it on sign-out).
Future<SqliteCommandQueueStore> openOfflineCommandQueueStore(String uid) async =>
    SqliteCommandQueueStore.open(
        uid: uid, path: await offlineCommandQueueDatabasePath(uid));

/// What the file store found when it opened (unreadable record files, repaired
/// counter or marker files, recovered SENDING records). Null for stores that
/// have no open report (the in-memory fake).
final offlineCommandQueueOpenReportProvider = Provider<QueueOpenReport?>((ref) {
  final store = ref.watch(offlineCommandQueueStoreProvider);
  if (store is SqliteCommandQueueStore) return store.openReport;
  return store is FileCommandQueueStore ? store.openReport : null;
});

final offlineCommandSyncStatusSourceProvider =
    Provider<CommandSyncStatusSource>((ref) =>
        StoreSyncStatusSource(ref.watch(offlineCommandQueueStoreProvider)));

/// Pending/synced counts for all sessions of the bound uid.
final offlineCommandSyncStatusProvider =
    StreamProvider<SyncStatusSnapshot>((ref) =>
        ref.watch(offlineCommandSyncStatusSourceProvider).watch());

/// Counts for one session; `pending == 0` here means nothing is waiting.
final offlineSessionSyncStatusProvider =
    Provider.family<AsyncValue<SessionSyncStatus>, String>((ref, sessionId) =>
        ref.watch(offlineCommandSyncStatusProvider).whenData(
            (snap) => snap.forSession(sessionId)));
