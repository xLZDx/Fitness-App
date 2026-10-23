// Account binding, purge, wipe, storage faults, delivered/cleanup state,
// streamed delivery and crash layout of the resumable export.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/data_export.dart';
import 'package:fitness_app/features/data_export/data_export_providers.dart';
import 'package:fitness_app/features/data_export/data_export_sink.dart';
import 'package:fitness_app/features/data_export/export_progress_store.dart';
import 'package:fitness_app/features/data_export/server_export.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log_totals.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

import 'server_export_resume_test.dart'
    show PagedServer, expectExactRows, idsOf;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------


/// PagedServer whose responses can be rewritten per continuation call.
class HookServer extends PagedServer {
  HookServer(super.totals, {super.pageSize, super.uid});

  /// Runs before the page of this (1-based) call is built.
  Future<void> Function(int call)? beforePage;

  /// Rewrites the page of this call.
  Map<String, dynamic>? Function(int call, Map<String, dynamic> page)? rewrite;

  /// Rewrites the first response.
  Map<String, dynamic> Function(Map<String, dynamic> first)? rewriteFirst;

  @override
  Future<Map<String, dynamic>?> fetch() async {
    final r = await super.fetch();
    if (r != null && rewriteFirst != null) return rewriteFirst!(r);
    return r;
  }

  @override
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async {
    await beforePage?.call(pageCalls + 1);
    final page = await super.fetchPage(cursors);
    if (page == null || rewrite == null) return page;
    return rewrite!(pageCalls, page);
  }
}

/// File store with fault injection that survives `forUser` scoping.
class FaultControl {
  int partWrites = 0;
  int baseWrites = 0;
  int manifestWrites = 0;
  int? failPart;
  int? failBase;
  int? failManifest;
  bool failClear = false;
  bool failPurge = false;
}

class FaultyFileStore extends FileExportProgressStore {
  FaultyFileStore(this.ctl, this.dirOf, {String? uid})
      : super(baseDir: dirOf, uid: uid);
  final FaultControl ctl;
  final Future<Directory> Function() dirOf;

  @override
  ExportProgressStore forUser(String uid) => FaultyFileStore(ctl, dirOf, uid: uid);

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) async {
    ctl.partWrites++;
    if (ctl.failPart == ctl.partWrites) {
      throw const FileSystemException('disk full (part)');
    }
    await super.writePart(index, part);
  }

  @override
  Future<void> writeBase(Map<String, dynamic> base) async {
    ctl.baseWrites++;
    if (ctl.failBase == ctl.baseWrites) {
      throw const FileSystemException('disk full (base)');
    }
    await super.writeBase(base);
  }

  @override
  Future<void> writeManifest(Map<String, dynamic> manifest) async {
    // A delivered marker is a manifest write too, but is counted apart.
    if (manifest['delivered'] != true) ctl.manifestWrites++;
    if (manifest['delivered'] != true && ctl.failManifest == ctl.manifestWrites) {
      throw const FileSystemException('disk full (manifest)');
    }
    await super.writeManifest(manifest);
  }

  @override
  Future<void> clear() async {
    if (ctl.failClear) throw const FileSystemException('cannot delete');
    await super.clear();
  }

  @override
  Future<void> purgeStale({String? keepUid, DateTime? now}) async {
    if (ctl.failPurge) throw const FileSystemException('purge failed');
    await super.purgeStale(keepUid: keepUid, now: now);
  }
}

class InMemoryFaultyStore extends InMemoryExportProgressStore {
  bool failClear = false;
  int? failPartWrite;
  int partWrites = 0;
  int? failManifestWrite;
  int manifestWrites = 0;

  @override
  Future<void> clear() async {
    if (failClear) throw const FileSystemException('cannot delete');
    await super.clear();
  }

  @override
  Future<void> writePart(int index, Map<String, dynamic> part) async {
    partWrites++;
    if (failPartWrite == partWrites) throw const FileSystemException('disk full');
    await super.writePart(index, part);
  }

  @override
  Future<void> writeManifest(Map<String, dynamic> m) async {
    if (m['delivered'] != true) manifestWrites++;
    if (m['delivered'] != true && failManifestWrite == manifestWrites) {
      throw const FileSystemException('disk full');
    }
    await super.writeManifest(m);
  }
}

Future<Directory> tempDir(String tag) async {
  final d = await Directory.systemTemp.createTemp(tag);
  addTearDown(() async {
    if (await d.exists()) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });
  return d;
}

String progressDirOf(Directory support, String uid) =>
    '${support.path}/$kExportProgressDirName/${exportProgressUserKey(uid)}';

bool progressExists(Directory support, String uid) =>
    Directory(progressDirOf(support, uid)).existsSync();

String dirText(String path) {
  final b = StringBuffer();
  final d = Directory(path);
  if (!d.existsSync()) return '';
  for (final e in d.listSync(recursive: true)) {
    if (e is File) b.writeln(e.readAsStringSync());
  }
  return b.toString();
}

/// Keeps a file open so that deleting its directory fails on Windows.
Future<RandomAccessFile> lockDir(String dirPath) async {
  final f = File('$dirPath/.lock');
  return f.open(mode: FileMode.write);
}

final bool _windows = Platform.isWindows;
const String _windowsOnly = 'needs the OS to refuse deleting a directory with an open file (Windows)';

// ---------------------------------------------------------------------------
// Controller fakes
// ---------------------------------------------------------------------------

class FileDeliverySink implements DataExportSink {
  FileDeliverySink(this.dir);
  final Directory dir;
  final List<File> files = <File>[];
  void Function()? onFirstChunk;

  @override
  Future<void> deliver({required String filename, required String contents}) async {
    final f = File('${dir.path}/$filename')..writeAsStringSync(contents);
    files.add(f);
  }

  @override
  Future<void> deliverStreamed({
    required String filename,
    required Future<void> Function(ExportTextSink out) write,
  }) async {
    final f = File('${dir.path}/$filename');
    final io = f.openWrite();
    final out = _Hooked(FileExportTextSink(io), () {
      final h = onFirstChunk;
      onFirstChunk = null;
      h?.call();
    });
    try {
      await write(out);
    } catch (_) {
      await out.inner.close();
      if (f.existsSync()) f.deleteSync(); // nothing is delivered
      rethrow;
    }
    await out.inner.close();
    files.add(f);
  }
}

class _Hooked implements ExportTextSink {
  _Hooked(this.inner, this.onWrite);
  final FileExportTextSink inner;
  final void Function() onWrite;
  @override
  Future<void> write(String chunk) {
    onWrite();
    return inner.write(chunk);
  }
}

class Env {
  Env({required this.container, required this.auth});
  final ProviderContainer container;
  final StreamController<AuthUser?> auth;
  DataExportAction get action => container.read(dataExportActionProvider.notifier);
  AsyncValue<void> get state => container.read(dataExportActionProvider);

  Future<void> switchTo(String uid) async {
    auth.add(AuthUser(uid: uid, displayName: uid));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Env makeEnv({
  required ServerExport server,
  required DataExportSink sink,
  required ExportProgressStore store,
  String uid = 'u1',
}) {
  final auth = StreamController<AuthUser?>.broadcast();
  final c = ProviderContainer(overrides: [
    authUserProvider.overrideWith((ref) async* {
      yield AuthUser(uid: uid, displayName: uid);
      yield* auth.stream;
    }),
    profileRepositoryProvider.overrideWithValue(_Repo()),
    workoutSessionRepositoryProvider.overrideWithValue(_Sessions()),
    scheduledSessionRepositoryProvider.overrideWithValue(_Scheduled()),
    serverExportProvider.overrideWithValue(server),
    localSensitiveStoreProvider.overrideWithValue(InMemorySensitiveStore()),
    dataExportSinkProvider.overrideWithValue(sink),
    exportProgressStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(() async {
    c.dispose();
    await auth.close();
  });
  return Env(container: c, auth: auth);
}

Map<String, dynamic> readFile(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

// ---------------------------------------------------------------------------

void main() {
  group('B02 account binding', () {
    test('a continuation page of another account is not stored; the export aborts',
        () async {
      final store = InMemoryExportProgressStore();
      final server = HookServer(<String, int>{'a': 10})
        ..rewrite = (call, page) {
          if (call != 3) return page;
          return <String, dynamic>{
            'uid': 'u2',
            'a': <Object>[<String, Object?>{'id': 'B-secret'}],
            'paging': page['paging'],
          };
        };
      await expectLater(server.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportAccountChangedException>()));
      expect(server.pageCalls, 3, reason: 'aborted at the first foreign page');
      expect(jsonEncode(store.parts.values.toList()), isNot(contains('B-secret')));
      expect(jsonEncode(store.manifest), isNot(contains('B-secret')));
      expect(store.manifest!['parts'], 3);
    });

    test('a page without a uid counts as a mismatch', () async {
      final store = InMemoryExportProgressStore();
      final server = HookServer(<String, int>{'a': 10})
        ..rewrite = (call, page) {
          if (call == 2) return Map<String, dynamic>.of(page)..remove('uid');
          return page;
        };
      await expectLater(server.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportAccountChangedException>()));
    });

    test('a first response of another account or without uid persists nothing',
        () async {
      for (final rewriteFirst in <Map<String, dynamic> Function(Map<String, dynamic>)>[
        (f) => Map<String, dynamic>.of(f)..['uid'] = 'u2',
        (f) => Map<String, dynamic>.of(f)..remove('uid'),
      ]) {
        final store = InMemoryExportProgressStore();
        final server = HookServer(<String, int>{'a': 5})..rewriteFirst = rewriteFirst;
        await expectLater(server.fetchAll(store: store, uid: 'u1'),
            throwsA(isA<ExportAccountChangedException>()));
        expect(store.manifest, isNull);
        expect(store.base, isNull);
        expect(store.parts, isEmpty);
        expect(server.pageCalls, 0);
      }
    });

    test('a resumed run meeting a foreign page merges nothing of it', () async {
      final store = InMemoryExportProgressStore();
      final s1 = HookServer(<String, int>{'a': 10})..throwOnCall = 4;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(anything));
      final s2 = HookServer(<String, int>{'a': 10})
        ..rewrite = (call, page) => <String, dynamic>{
              'uid': 'u2',
              'a': <Object>[<String, Object?>{'id': 'B-secret'}],
              'paging': page['paging'],
            };
      await expectLater(s2.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportAccountChangedException>()));
      expect(jsonEncode(store.parts.values.toList()), isNot(contains('B-secret')));
    });

    test('stale-cursor restart whose fresh first call belongs to another account stores nothing of it',
        () async {
      final support = await tempDir('exp_stale_');
      final store = FileExportProgressStore(baseDir: () async => support);
      final s1 = PagedServer(<String, int>{'a': 10})..throwOnCall = 4;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(anything));
      final s2 = HookServer(<String, int>{'a': 10})
        ..errorOnCall = 1 // stale_cursor on the resumed page
        ..rewriteFirst = (f) => Map<String, dynamic>.of(f)
          ..['uid'] = 'u2'
          ..['a'] = <Object>[<String, Object?>{'id': 'B-secret'}];
      await expectLater(s2.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportAccountChangedException>()));
      expect(dirText('${support.path}/$kExportProgressDirName'),
          isNot(contains('B-secret')));
    });

    test('controller: account switched during pagination -> error, nothing delivered, progress of the first account deleted',
        () async {
      final support = await tempDir('exp_switch_');
      final docs = await tempDir('exp_out_');
      final store = FileExportProgressStore(baseDir: () async => support);
      late Env env;
      final server = HookServer(<String, int>{'a': 12})
        ..beforePage = (call) async {
          if (call == 4) await env.switchTo('u2');
        };
      final sink = FileDeliverySink(docs);
      env = makeEnv(server: server, sink: sink, store: store);
      await env.action.export();

      expect(env.state.error, isA<ExportAccountChangedException>());
      expect(sink.files, isEmpty);
      expect(docs.listSync(), isEmpty);
      expect(progressExists(support, 'u1'), isFalse);
      expect(progressExists(support, 'u2'), isFalse);
    });

    test('controller: account switched while the file is being written -> nothing delivered, progress deleted',
        () async {
      final support = await tempDir('exp_switch2_');
      final docs = await tempDir('exp_out2_');
      final store = FileExportProgressStore(baseDir: () async => support);
      late Env env;
      final sink = FileDeliverySink(docs);
      final server = PagedServer(<String, int>{'a': 6});
      env = makeEnv(server: server, sink: sink, store: store);
      sink.onFirstChunk = () {
        env.auth.add(const AuthUser(uid: 'u2', displayName: 'u2'));
      };
      await env.action.export();
      expect(env.state.error, isA<ExportAccountChangedException>());
      expect(sink.files, isEmpty);
      expect(docs.listSync().where((e) => e is File), isEmpty,
          reason: 'the partial file is removed');
      expect(progressExists(support, 'u1'), isFalse);
    });

    test('the next account\'s export removes the previous account\'s leftover progress',
        () async {
      final support = await tempDir('exp_orphan_');
      final store = FileExportProgressStore(baseDir: () async => support);
      final s1 = PagedServer(<String, int>{'a': 10})..throwOnCall = 4;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(anything));
      expect(progressExists(support, 'u1'), isTrue);

      final s2 = PagedServer(<String, int>{'a': 4}, uid: 'u2');
      final res = await s2.fetchAll(store: store, uid: 'u2');
      expectExactRows(res!, <String, int>{'a': 4});
      expect(progressExists(support, 'u1'), isFalse,
          reason: 'orphan progress must not outlive the account switch');
      expect(dirText('${support.path}/$kExportProgressDirName'), isNot(contains('a-9')));
    });
  });

  group('B01 purge', () {
    Future<void> seedUser(Directory support, String uid,
        {int? ageDays, bool delivered = false, bool noManifest = false}) async {
      final dir = Directory(progressDirOf(support, uid))..createSync(recursive: true);
      File('${dir.path}/base.json').writeAsStringSync('{}');
      File('${dir.path}/part_00000.a.ndjson').writeAsStringSync('{"id":"$uid-row"}\n');
      if (noManifest) return;
      File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode({
        'version': 2,
        'uid': uid,
        'savedAtMs': DateTime.now()
            .subtract(Duration(days: ageDays ?? 0))
            .millisecondsSinceEpoch,
        'parts': 1,
        'pages': 1,
        'paging': {},
        'rowCounts': {},
        'warnings': [],
        if (delivered) 'delivered': true,
      }));
    }

    test('without keepUid: expired, delivered, unreadable and flat leftovers go; fresh progress stays',
        () async {
      final support = await tempDir('exp_purge_');
      final store = FileExportProgressStore(baseDir: () async => support);
      await seedUser(support, 'fresh', ageDays: 1);
      await seedUser(support, 'edge', ageDays: 6);
      await seedUser(support, 'old', ageDays: 8);
      await seedUser(support, 'done', ageDays: 0, delivered: true);
      await seedUser(support, 'nomani', noManifest: true);
      final root = '${support.path}/$kExportProgressDirName';
      File('$root/manifest.json').writeAsStringSync('{"legacy":true}'); // flat layout
      File('$root/part_00000.json').writeAsStringSync('{"x":"legacy rows"}');

      await store.purgeStale();

      expect(progressExists(support, 'fresh'), isTrue);
      expect(progressExists(support, 'edge'), isTrue);
      expect(progressExists(support, 'old'), isFalse);
      expect(progressExists(support, 'done'), isFalse);
      expect(progressExists(support, 'nomani'), isFalse);
      expect(File('$root/manifest.json').existsSync(), isFalse);
      expect(File('$root/part_00000.json').existsSync(), isFalse);
    });

    test('with keepUid: every other account\'s progress goes, the kept one stays',
        () async {
      final support = await tempDir('exp_purge2_');
      final store = FileExportProgressStore(baseDir: () async => support);
      await seedUser(support, 'u1', ageDays: 1);
      await seedUser(support, 'u2', ageDays: 0);
      await seedUser(support, 'u3', ageDays: 0);
      await store.purgeStale(keepUid: 'u1');
      expect(progressExists(support, 'u1'), isTrue);
      expect(progressExists(support, 'u2'), isFalse);
      expect(progressExists(support, 'u3'), isFalse);
    });

    test('a missing progress directory is not an error', () async {
      final support = await tempDir('exp_purge3_');
      await FileExportProgressStore(baseDir: () async => support).purgeStale();
      await FileExportProgressStore(baseDir: () async => support).purgeStale(keepUid: 'u1');
    });

    test('a purge that cannot remove one entry still removes the others, then reports',
        () async {
      final support = await tempDir('exp_purge4_');
      final store = FileExportProgressStore(baseDir: () async => support);
      await seedUser(support, 'a-old', ageDays: 9);
      await seedUser(support, 'b-old', ageDays: 9);
      await seedUser(support, 'c-old', ageDays: 9);
      final lock = await lockDir(progressDirOf(support, 'b-old'));
      try {
        await expectLater(store.purgeStale(), throwsA(isA<FileSystemException>()));
        expect(progressExists(support, 'a-old'), isFalse);
        expect(progressExists(support, 'c-old'), isFalse);
        expect(progressExists(support, 'b-old'), isTrue);
      } finally {
        await lock.close();
      }
    }, skip: _windows ? false : _windowsOnly);

    test('collect() purges other accounts before it starts, and a failing purge does not fail the export',
        () async {
      final support = await tempDir('exp_purge5_');
      final ctl = FaultControl();
      final store = FaultyFileStore(ctl, () async => support);
      await seedUser(support, 'ghost', ageDays: 0);
      final res = await PagedServer(<String, int>{'a': 3}).fetchAll(store: store, uid: 'u1');
      expectExactRows(res!, <String, int>{'a': 3});
      expect(progressExists(support, 'ghost'), isFalse);

      await seedUser(support, 'ghost2', ageDays: 0);
      ctl.failPurge = true;
      final res2 = await PagedServer(<String, int>{'a': 3}).fetchAll(store: store, uid: 'u1');
      expectExactRows(res2!, <String, int>{'a': 3});
    });
  });

  group('wipe and sign-out', () {
    Future<DeviceLocalDataWipe> wipeOf(Directory docs, Directory support) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      return DeviceLocalDataWipe(
        prefs: await SharedPreferences.getInstance(),
        documentsDir: docs,
        supportDir: support,
        forgetPhotoKey: (_) async {},
      );
    }

    test('the account wipe removes an interrupted export\'s sensitive rows, and only that account\'s',
        () async {
      final docs = await tempDir('wipe_docs_');
      final support = await tempDir('wipe_support_');
      final store = FileExportProgressStore(baseDir: () async => support);
      final s1 = PagedServer(<String, int>{'a': 10})..throwOnCall = 5;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(anything));
      // A second account\'s own progress (written without the purge of u1).
      final dir2 = Directory(progressDirOf(support, 'u2'))..createSync(recursive: true);
      File('${dir2.path}/part_00000.a.ndjson').writeAsStringSync('{"id":"u2-row"}\n');
      expect(dirText(progressDirOf(support, 'u1')), contains('a-1'));

      await (await wipeOf(docs, support)).wipe('u1');

      expect(progressExists(support, 'u1'), isFalse);
      expect(dirText('${support.path}/$kExportProgressDirName'), isNot(contains('"id":"a-')));
      expect(progressExists(support, 'u2'), isTrue);
    });

    test('a missing progress directory is not a wipe failure', () async {
      final docs = await tempDir('wipe_docs2_');
      final support = await tempDir('wipe_support2_');
      await (await wipeOf(docs, support)).wipe('u1');
    });

    test('the wipe still defaults to an isolated support folder beside the documents folder',
        () async {
      final docs = await tempDir('wipe_docs3_');
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final wipe = DeviceLocalDataWipe(
        prefs: await SharedPreferences.getInstance(),
        documentsDir: docs,
        forgetPhotoKey: (_) async {},
      );
      final dir = Directory(progressDirOf(Directory('${docs.path}/_support'), 'u1'))
        ..createSync(recursive: true);
      File('${dir.path}/part_00000.a.ndjson').writeAsStringSync('{"id":"x"}\n');
      await wipe.wipe('u1');
      expect(dir.existsSync(), isFalse);
    });

    test('a wipe that cannot delete the export progress reports export_progress',
        () async {
      final docs = await tempDir('wipe_docs4_');
      final support = await tempDir('wipe_support4_');
      final dir = Directory(progressDirOf(support, 'u1'))..createSync(recursive: true);
      File('${dir.path}/part_00000.a.ndjson').writeAsStringSync('{"id":"x"}\n');
      final lock = await lockDir(dir.path);
      try {
        await expectLater(
          (await wipeOf(docs, support)).wipe('u1'),
          throwsA(isA<LocalWipeIncomplete>()
              .having((e) => e.remaining, 'remaining', contains('export_progress'))),
        );
      } finally {
        await lock.close();
      }
    }, skip: _windows ? false : _windowsOnly);

    test('sign-out deletes the signing-out account\'s export progress',
        () async {
      final store = InMemoryExportProgressStore();
      await PagedServer(<String, int>{'a': 4}).fetchAll(
          store: store, uid: 'u1'); // leaves nothing unfinished: use a stop
      final s = PagedServer(<String, int>{'a': 9})..errorFromCall = 3;
      await s.fetchAll(store: store, uid: 'u1');
      expect(store.manifest, isNotNull);

      final repo = MockAuthRepository(latency: Duration.zero);
      await repo.signInAnonymously();
      final uid = repo.currentUser!.uid;
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        exportProgressStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      // Progress of THIS uid is what sign-out removes.
      final s2 = PagedServer(<String, int>{'a': 9}, uid: uid)..errorFromCall = 3;
      await s2.fetchAll(store: store, uid: uid);
      expect(store.manifest, isNotNull);

      await c.read(authActionProvider.notifier).signOut();
      expect(c.read(authActionProvider).hasError, isFalse);
      expect(store.manifest, isNull);
    });

    test('a failing cleanup never blocks the sign-out itself', () async {
      final store = InMemoryFaultyStore();
      final repo = MockAuthRepository(latency: Duration.zero);
      await repo.signInAnonymously();
      final uid = repo.currentUser!.uid;
      await (PagedServer(<String, int>{'a': 9}, uid: uid)..errorFromCall = 3)
          .fetchAll(store: store, uid: uid);
      store.failClear = true;
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        exportProgressStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      await c.read(authActionProvider.notifier).signOut();
      expect(c.read(authActionProvider).hasError, isFalse);
      expect(repo.currentUser, isNull);
    });
  });

  group('M02 storage faults', () {
    test('a failing PART write stops the export before more server quota is used, then a resume is exact',
        () async {
      final support = await tempDir('exp_fault_');
      final ctl = FaultControl()..failPart = 4;
      final store = FaultyFileStore(ctl, () async => support);
      final totals = <String, int>{'a': 10, 'b': 4};
      final s1 = PagedServer(totals);
      await expectLater(s1.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportStorageException>()));
      expect(s1.pageCalls, 3, reason: 'part 4 failed after the 3rd continuation call');

      ctl.failPart = null;
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 0);
      expectExactRows(res!, totals);
    });

    test('a failing BASE write: one first call, no continuation call, storage error',
        () async {
      final support = await tempDir('exp_fault2_');
      final ctl = FaultControl()..failBase = 1;
      final store = FaultyFileStore(ctl, () async => support);
      final s = PagedServer(<String, int>{'a': 5});
      await expectLater(s.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportStorageException>()));
      expect(s.fetchCalls, 1);
      expect(s.pageCalls, 0);
    });

    test('a failing MANIFEST write is a storage error and the previous manifest still describes a consistent state',
        () async {
      final support = await tempDir('exp_fault3_');
      final ctl = FaultControl()..failManifest = 3;
      final store = FaultyFileStore(ctl, () async => support);
      final totals = <String, int>{'a': 8};
      await expectLater(PagedServer(totals).fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportStorageException>()));
      final m = jsonDecode(File('${progressDirOf(support, 'u1')}/manifest.json')
          .readAsStringSync()) as Map<String, dynamic>;
      expect(m['parts'], 2);
      ctl.failManifest = null;
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 0);
      expectExactRows(res!, totals);
    });

    test('storage fault, then a later quota stop, then a restart: nothing lost, nothing duplicated, no false promise',
        () async {
      final support = await tempDir('exp_fault4_');
      final ctl = FaultControl()..failManifest = 3;
      final store = FaultyFileStore(ctl, () async => support);
      final totals = <String, int>{'a': 12, 'b': 5};

      final s1 = PagedServer(totals);
      await expectLater(s1.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportStorageException>()));

      ctl.failManifest = null;
      final s2 = PagedServer(totals)
        ..errorFromCall = 3
        ..errorCode = 'quota';
      final out2 = await s2.collect(store: store, uid: 'u1');
      expect(out2!.persisted, isTrue);
      expect(out2.header['pagingIncomplete'], isTrue);
      expect(out2.header['pagingStopReason'], 'quota');
      expect(s2.fetchCalls, 0);

      final s3 = PagedServer(totals);
      final res = await s3.fetchAll(store: store, uid: 'u1');
      expect(s3.fetchCalls, 0);
      expectExactRows(res!, totals);
      expect(s1.fetchCalls + s2.fetchCalls + s3.fetchCalls, 1,
          reason: 'one first call for the whole story');
    });

    test('notes never claim saved progress unless it was durably written', () {
      Map<String, dynamic> server() => <String, dynamic>{
            'pagingIncomplete': true,
            'pagingStopReason': 'quota',
            'exportManifest': {
              'pagingIncompleteSections': ['a'],
              'incompleteSections': ['a'],
            },
          };
      String notes(bool saved) => (buildExport(
            profile: const UserProfile(uid: 'u1'),
            workoutLogs: const [],
            scheduledSessions: const [],
            programmes: const [],
            progressPhotos: const [],
            server: server(),
            progressSaved: saved,
          )['notes'] as List)
          .join(' ');
      expect(notes(true), contains('Your progress is saved'));
      final unsaved = notes(false);
      expect(unsaved, isNot(contains('Your progress is saved')));
      expect(unsaved, isNot(contains('it will not start over')));
      expect(unsaved, contains('could not be kept'));
      expect(unsaved, contains('start over'));
    });

    test('a collection without a store reports persisted=false, with a store true',
        () async {
      final totals = <String, int>{'a': 5};
      final noStore = await (PagedServer(totals)..errorFromCall = 3).collect();
      expect(noStore!.persisted, isFalse);
      final withStore = await (PagedServer(totals)..errorFromCall = 3)
          .collect(store: InMemoryExportProgressStore(), uid: 'u1');
      expect(withStore!.persisted, isTrue);
    });

    test('controller: a storage fault surfaces as ExportStorageException and nothing is delivered',
        () async {
      final support = await tempDir('exp_fault5_');
      final docs = await tempDir('exp_out5_');
      final ctl = FaultControl()..failPart = 2;
      final sink = FileDeliverySink(docs);
      final env = makeEnv(
          server: PagedServer(<String, int>{'a': 6}),
          sink: sink,
          store: FaultyFileStore(ctl, () async => support));
      await env.action.export();
      expect(env.state.error, isA<ExportStorageException>());
      expect(sink.files, isEmpty);
      expect(env.state.error.toString(), contains('storage'));
    });
  });

  group('M03 delivered state and failed cleanup', () {
    for (final variant in <String>['in-memory', 'file']) {
      test('[$variant] a failed clear after delivery: cleanup flagged, the next export is FRESH (new server data, not the stale snapshot)',
          () async {
        final support = await tempDir('exp_clear_');
        final docs = await tempDir('exp_clear_out_');
        final ctl = FaultControl();
        final memStore = InMemoryFaultyStore();
        final ExportProgressStore store = variant == 'file'
            ? FaultyFileStore(ctl, () async => support)
            : memStore;
        void setFail(bool v) {
          ctl.failClear = v;
          memStore.failClear = v;
        }

        final sink = FileDeliverySink(docs);
        final oldTotals = <String, int>{'a': 6};
        final env1 = makeEnv(server: PagedServer(oldTotals), sink: sink, store: store);
        setFail(true);
        await env1.action.export();
        expect(env1.state.hasError, isFalse);
        expect(env1.action.cleanupIncomplete, isTrue);
        expectExactRows(readFile(sink.files.single)['server'] as Map<String, dynamic>, oldTotals);

        // The server has new data. Same user exports again; clear still fails.
        final newTotals = <String, int>{'a': 9, 'b': 3};
        final server2 = PagedServer(newTotals);
        final env2 = makeEnv(server: server2, sink: sink, store: store);
        await env2.action.export();
        expect(env2.state.hasError, isFalse);
        expect(server2.fetchCalls, 1, reason: 'a delivered snapshot is never reused');
        expect(sink.files, hasLength(2));
        expectExactRows(
            readFile(sink.files[1])['server'] as Map<String, dynamic>, newTotals);
        expect(env2.action.cleanupIncomplete, isTrue);

        // Once deleting works again the flag is clean and progress is gone.
        setFail(false);
        final env3 = makeEnv(server: PagedServer(newTotals), sink: sink, store: store);
        await env3.action.export();
        expect(env3.action.cleanupIncomplete, isFalse);
      });
    }

    test('a manifest marked delivered is treated as no progress', () async {
      final store = InMemoryExportProgressStore();
      await (PagedServer(<String, int>{'a': 9})..errorFromCall = 3)
          .fetchAll(store: store, uid: 'u1');
      expect(await loadExportResume(store, 'u1'), isNotNull);
      await markExportDelivered(store, 'u1');
      expect(store.manifest!['delivered'], isTrue);
      expect(await loadExportResume(store, 'u1'), isNull);
    });

    test('markExportDelivered with no progress is a no-op', () async {
      final store = InMemoryExportProgressStore();
      await markExportDelivered(store, 'u1');
      expect(store.manifest, isNull);
    });

    test('an incomplete delivery is NOT marked delivered and keeps resumable progress',
        () async {
      final docs = await tempDir('exp_inc_out_');
      final store = InMemoryExportProgressStore();
      final env = makeEnv(
          server: PagedServer(<String, int>{'a': 9})
            ..errorFromCall = 3
            ..errorCode = 'quota',
          sink: FileDeliverySink(docs),
          store: store);
      await env.action.export();
      expect(store.manifest, isNotNull);
      expect(store.manifest!['delivered'], isNull);
      expect(env.action.cleanupIncomplete, isFalse);
    });

    test('a delivery failure keeps the (undelivered) progress for a retry without new calls',
        () async {
      final store = InMemoryExportProgressStore();
      final server = PagedServer(<String, int>{'a': 8});
      final failing = _ThrowingSink();
      final env1 = makeEnv(server: server, sink: failing, store: store);
      await env1.action.export();
      expect(env1.state.hasError, isTrue);
      expect(store.manifest, isNotNull);
      expect(store.manifest!['delivered'], isNull);

      final docs = await tempDir('exp_retry_out_');
      final sink = FileDeliverySink(docs);
      final calls = server.fetchCalls + server.pageCalls;
      final env2 = makeEnv(server: server, sink: sink, store: store);
      await env2.action.export();
      expect(server.fetchCalls + server.pageCalls, calls);
      expectExactRows(readFile(sink.files.single)['server'] as Map<String, dynamic>,
          <String, int>{'a': 8});
    });
  });

  group('streamed delivery', () {
    test('the streamed file is valid JSON with every row exactly once and a matching manifest',
        () async {
      final support = await tempDir('exp_stream_');
      final docs = await tempDir('exp_stream_out_');
      final totals = <String, int>{'foodEntries': 130, 'weightEntries': 70, 'workoutCommandOutcomes': 20};
      final sink = FileDeliverySink(docs);
      final env = makeEnv(
          server: PagedServer(totals),
          sink: sink,
          store: FileExportProgressStore(baseDir: () async => support));
      await env.action.export();
      expect(env.state.hasError, isFalse);

      final file = readFile(sink.files.single);
      expect(file.keys.first, 'exportFormatVersion');
      expect(file['profile'], isA<Map>());
      expect(file['serverIncomplete'], isFalse);
      final server = file['server'] as Map<String, dynamic>;
      expectExactRows(server, totals);
      final manifest = server['exportManifest'] as Map;
      expect(manifest['pages'], 130);
      expect(manifest['incompleteSections'], isEmpty);
      for (final e in totals.entries) {
        expect(manifest['sectionRowCounts'][e.key], e.value);
        expect(manifest['sectionRowCounts'][e.key], idsOf(server, e.key).length);
      }
      expect((file['notes'] as List).join(' '), isNot(contains('INCOMPLETE')));
      // Progress on disk is gone after the delivery.
      expect(progressExists(support, 'u1'), isFalse);
    });

    test('an empty paged section is written as an empty list, not dropped', () async {
      final docs = await tempDir('exp_stream2_out_');
      final sink = FileDeliverySink(docs);
      final env = makeEnv(
          server: PagedServer(<String, int>{'a': 0, 'b': 2}),
          sink: sink,
          store: InMemoryExportProgressStore());
      await env.action.export();
      final server = readFile(sink.files.single)['server'] as Map<String, dynamic>;
      expect(server['a'], isEmpty);
      expect(idsOf(server, 'b'), <String>['b-0', 'b-1']);
    });

    test('a streamed file with an interruption in the middle of writing is not delivered',
        () async {
      final docs = await tempDir('exp_stream3_out_');
      final sink = FileDeliverySink(docs)
        ..onFirstChunk = () => throw StateError('disk full while writing');
      final env = makeEnv(
          server: PagedServer(<String, int>{'a': 3}),
          sink: sink,
          store: InMemoryExportProgressStore());
      await env.action.export();
      expect(env.state.hasError, isTrue);
      expect(sink.files, isEmpty);
    });

    test('memory stays bounded: 300 pages of ~1 MB rows (300 MB total) grow the process by far less',
        () async {
      final support = await tempDir('exp_mem_');
      final docs = await tempDir('exp_mem_out_');
      final sink = FileDeliverySink(docs);
      const pages = 300;
      const blob = 1000 * 1000;
      final env = makeEnv(
          server: _BigServer(pages, blob),
          sink: sink,
          store: FileExportProgressStore(baseDir: () async => support));

      final baseline = ProcessInfo.currentRss;
      var peak = baseline;
      final sampler = Timer.periodic(const Duration(milliseconds: 20), (_) {
        final r = ProcessInfo.currentRss;
        if (r > peak) peak = r;
      });
      await env.action.export();
      sampler.cancel();
      final grown = peak - baseline;
      // ignore: avoid_print
      print('RSS growth during the 300 MB export: ${grown ~/ (1024 * 1024)} MB');

      expect(env.state.hasError, isFalse, reason: '${env.state.error}');
      expect(grown, lessThan(150 * 1024 * 1024),
          reason: 'RSS grew by ${grown ~/ (1024 * 1024)} MB; total data is 300 MB');

      // The output is complete: stream it line by line (no full read).
      final out = sink.files.single;
      expect(out.lengthSync(), greaterThan(pages * blob));
      var rows = 0;
      var next = 0;
      await for (final line in out
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final t = line.endsWith(',') ? line.substring(0, line.length - 1) : line;
        if (t.startsWith('{"id":"big-')) {
          expect(t.startsWith('{"id":"big-$next"'), isTrue,
              reason: 'row $next out of order or missing');
          expect(t.length, greaterThan(blob));
          rows++;
          next++;
        }
      }
      expect(rows, pages);
      expect(progressExists(support, 'u1'), isFalse);
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  group('crash layout on disk', () {
    test('crash after the part files but before the manifest: the orphan is replaced, rows exact',
        () async {
      final support = await tempDir('exp_crash_');
      final ctl = FaultControl()..failManifest = 4;
      final store = FaultyFileStore(ctl, () async => support);
      final totals = <String, int>{'a': 10, 'b': 6};
      final s1 = PagedServer(totals);
      await expectLater(s1.fetchAll(store: store, uid: 'u1'),
          throwsA(isA<ExportStorageException>()));
      final dir = progressDirOf(support, 'u1');
      expect(File('$dir/part_00003.a.ndjson').existsSync(), isTrue,
          reason: 'the part of the lost manifest is on disk');
      expect(File('$dir/part_00003.done').existsSync(), isTrue);
      final m = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map;
      expect(m['parts'], 3);

      ctl.failManifest = null;
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 0);
      expect(s2.requested.first, s1.requested[2],
          reason: 'the page whose manifest was lost is fetched again');
      expectExactRows(res!, totals);
    });

    test('part files without a commit record (crash before .done) are ignored and replaced',
        () async {
      final support = await tempDir('exp_crash2_');
      final store = FileExportProgressStore(baseDir: () async => support);
      final totals = <String, int>{'a': 8};
      final s1 = PagedServer(totals)..throwOnCall = 4;
      await expectLater(s1.fetchAll(store: store, uid: 'u1'), throwsA(anything));
      final dir = progressDirOf(support, 'u1');
      File('$dir/part_00003.a.ndjson')
          .writeAsStringSync('{"id":"a-DUPLICATE"}\n{"id":"a-DUPLICATE"}\n');
      final res = await PagedServer(totals).fetchAll(store: store, uid: 'u1');
      expectExactRows(res!, totals);
      expect(jsonEncode(res), isNot(contains('DUPLICATE')));
    });

    test('a listed part whose commit record is gone discards the progress and restarts cleanly',
        () async {
      final support = await tempDir('exp_crash3_');
      final store = FileExportProgressStore(baseDir: () async => support);
      final totals = <String, int>{'a': 8};
      await expectLater((PagedServer(totals)..throwOnCall = 5).fetchAll(store: store, uid: 'u1'),
          throwsA(anything));
      File('${progressDirOf(support, 'u1')}/part_00002.done').deleteSync();
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 1);
      expectExactRows(res!, totals);
    });

    test('a truncated part file (length differs from its commit record) is discarded',
        () async {
      final support = await tempDir('exp_crash4_');
      final store = FileExportProgressStore(baseDir: () async => support);
      final totals = <String, int>{'a': 8};
      await expectLater((PagedServer(totals)..throwOnCall = 5).fetchAll(store: store, uid: 'u1'),
          throwsA(anything));
      File('${progressDirOf(support, 'u1')}/part_00001.a.ndjson')
          .writeAsStringSync('{"id":"a-');
      final s2 = PagedServer(totals);
      final res = await s2.fetchAll(store: store, uid: 'u1');
      expect(s2.fetchCalls, 1);
      expectExactRows(res!, totals);
    });

    test('the progress directory is named by a hash, never the raw uid, and no temp file survives',
        () async {
      final support = await tempDir('exp_layout_');
      final store = FileExportProgressStore(baseDir: () async => support);
      await (PagedServer(<String, int>{'a': 5}, uid: 'someone@example.com')
            ..errorFromCall = 3)
          .fetchAll(store: store, uid: 'someone@example.com');
      final root = Directory('${support.path}/$kExportProgressDirName');
      final names = root.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last);
      expect(names.single, exportProgressUserKey('someone@example.com'));
      expect(names.single, matches(RegExp(r'^u_[0-9a-f]{32}$')));
      expect(names.single, isNot(contains('someone')));
      final all = Directory(progressDirOf(support, 'someone@example.com')).listSync();
      expect(all.any((e) => e.path.endsWith('.tmp')), isFalse);
      final files = all.map((e) => e.uri.pathSegments.last).toSet();
      expect(files, containsAll(<String>['manifest.json', 'base.json', 'part_00000.done']));
      expect(files.any((n) => n.startsWith('part_00000.') && n.endsWith('.ndjson')), isTrue);
    });
  });
}

/// One ~[blob]-byte row per page, [pages] pages of one section.
class _BigServer extends ServerExport {
  _BigServer(this.pages, this.blob) : _text = 'x' * blob;
  final int pages;
  final int blob;
  final String _text;

  Map<String, dynamic> _page(int i) => <String, dynamic>{
        'uid': 'u1',
        'big': <Object>[
          <String, Object?>{'id': 'big-$i', 'blob': _text}
        ],
        'paging': {
          'big': {
            'returned': 1,
            'hasMore': i < pages - 1,
            'nextCursor': i < pages - 1 ? 'c${i + 1}' : null,
          }
        },
      };

  @override
  Future<Map<String, dynamic>?> fetch() async =>
      <String, dynamic>{..._page(0), 'profile': <String, Object?>{'name': 's'}};

  @override
  Future<Map<String, dynamic>?> fetchPage(Map<String, String> cursors) async =>
      _page(int.parse(cursors['big']!.substring(1)));
}

class _ThrowingSink implements DataExportSink {
  @override
  Future<void> deliver({required String filename, required String contents}) async =>
      throw StateError('share sheet failed');
  @override
  Future<void> deliverStreamed({
    required String filename,
    required Future<void> Function(ExportTextSink out) write,
  }) async {
    await write(StringBufferExportTextSink());
    throw StateError('share sheet failed');
  }
}

class _Repo implements ProfileRepository {
  @override
  Stream<UserProfile?> watch(String uid) => Stream.value(null);
  @override
  UserProfile? cached(String uid) => null;
  @override
  Future<UserProfile?> load(String uid) async =>
      UserProfile(uid: uid, personal: const PersonalInfo(age: 40));
  @override
  Future<void> save(UserProfile profile) async {}
  @override
  Future<void> delete(String uid) async {}
}

class _Sessions implements WorkoutSessionRepository {
  @override
  Stream<List<WorkoutSession>> watch(String uid) => Stream.value(const []);
  @override
  List<WorkoutSession> cached(String uid) => const [];
  @override
  Future<WorkoutLogTotals> totals(String uid) async =>
      const WorkoutLogTotals(total: 0, longestStreakDays: 0);
  @override
  Future<void> recordStreak(String uid, int days) async {}
  @override
  Future<void> save(String uid, WorkoutSession session) async {}
  @override
  Future<void> delete(String uid, String sessionId) async {}
  @override
  Future<void> clear(String uid) async {}
  @override
  Future<List<WorkoutSession>> exportAll(String uid) async => const [];
}

class _Scheduled implements ScheduledSessionRepository {
  @override
  Stream<List<ScheduledSession>> watch(String uid) => Stream.value(const []);
  @override
  List<ScheduledSession> cached(String uid) => const [];
  @override
  Future<void> save(String uid, ScheduledSession session) async {}
  @override
  Future<void> delete(String uid, String sessionId) async {}
  @override
  Future<void> clear(String uid) async {}
  @override
  Future<List<ScheduledSession>> exportAll(String uid) async => const [];
}
