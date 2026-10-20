// Test-only world for the account-scoped journal (S02 remediation E1, test
// epic 11a): a temp directory, the REAL FileActivityJournal on real files, a
// fake secure store (one key per scope) and a factory that records every open.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fitness_app/features/activity/repository/activity_journal.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/uid_scoped_activity_journal.dart';

import 'journal_harness.dart';

class ScopedJournalWorld {
  ScopedJournalWorld(this.tmp);

  static Future<ScopedJournalWorld> create() async => ScopedJournalWorld(
      await Directory.systemTemp.createTemp('s02_scoped_journal_'));

  final Directory tmp;
  final FakeJournalSecureStorage storage = FakeJournalSecureStorage();

  /// Scope ids the factory was asked to open, in order.
  final List<String> opened = [];

  /// Scope ids whose open throws.
  final Set<String> failOpen = {};

  /// When set, the next open waits for it (a slow bind).
  Completer<void>? gate;

  late final UidScopedActivityJournal journal =
      UidScopedActivityJournal(
        factory: factory,
        // S04 gate 1 M-06: an unreadable wipe marker now fails closed, so the
        // fixture gives the journal a real scopes root instead of the
        // path_provider default (which is unavailable in a unit test).
        scopesRoot: () async => '$base/activity_journal',
      );

  String get base => tmp.path.replaceAll('\\', '/');

  String rootOfScope(String scopeId) => '$base/activity_journal/$scopeId';

  String rootOf(String uid) => rootOfScope(activityJournalScopeId(uid));

  Future<ActivityJournal> factory(String scopeId) async {
    opened.add(scopeId);
    final g = gate;
    if (g != null) {
      gate = null;
      await g.future;
    }
    if (failOpen.contains(scopeId)) throw StateError('open failed');
    return FileActivityJournal(
      rootPath: rootOfScope(scopeId),
      keyProvider:
          SecureStorageJournalKeyProvider(storage: storage, scopeId: scopeId),
    );
  }

  Future<void> writeSide(String uid, String rel, String text) async {
    final f = File('${rootOf(uid)}/$rel');
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
  }

  /// Relative path -> sha256 of every file under the scope directory of [uid].
  Future<Map<String, String>> snapshot(String uid) async {
    final root = Directory(rootOf(uid));
    final out = <String, String>{};
    if (!await root.exists()) return out;
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final rel = e.path.replaceAll('\\', '/').substring(rootOf(uid).length);
        out[rel] = sha256.convert(await e.readAsBytes()).toString();
      }
    }
    return out;
  }

  /// Names of the account directories under `activity_journal/`.
  Future<List<String>> scopeDirs() async {
    final d = Directory('$base/activity_journal');
    if (!await d.exists()) return const [];
    return [
      await for (final e in d.list())
        e.path.replaceAll('\\', '/').split('/').last
    ]..sort();
  }

  Future<void> dispose() async {
    try {
      await journal.close();
    } catch (_) {}
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}
