import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/debug/coach_recorder.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

// MAJOR-04: a coach recording is bound to the uid that started it. These
// tests pin the file system outcome (what exists under coach_recordings/**)
// and the visible panel state when the signed-in account changes mid-capture.
//
// Not reachable from the UI: the second guard inside `_stop()` (uid re-read at
// stop time). The auth listener discards first, so by the time the user can
// tap Stop the toggle already reads 'Record'. That guard is defence in depth
// and is not exercised here.

const _discardError = 'recording-discarded:auth-changed';

class _Service with NoCameraControls implements PoseDetectorService {
  final frames$ = StreamController<PoseFrame>.broadcast();
  @override
  Stream<PoseFrame> frames() => frames$.stream;
  @override
  Future<void> ensurePermission() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async => frames$.close();
}

PoseFrame _frame(int ts) => PoseFrame(
      timestampMs: ts,
      landmarks: {
        LandmarkType.leftShoulder: const PoseLandmark(
            type: LandmarkType.leftShoulder, x: 0, y: 0, likelihood: 1),
        LandmarkType.leftElbow: const PoseLandmark(
            type: LandmarkType.leftElbow, x: 0, y: 1, likelihood: 1),
        LandmarkType.leftWrist: const PoseLandmark(
            type: LandmarkType.leftWrist, x: 1, y: 1, likelihood: 1),
      },
    );

AuthUser _user(String uid) => AuthUser(uid: uid, displayName: 'x');

class _Rig {
  _Rig(this.docs, this.svc, this.auth, this.container);
  final Directory docs;
  final _Service svc;
  final StreamController<AuthUser?> auth;
  final ProviderContainer container;

  /// Every file under `<docs>/coach_recordings`, relative with '/' separators.
  List<String> files() {
    final root = Directory('${docs.path}/$kCoachRecordingsDir');
    if (!root.existsSync()) return [];
    return root
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path
            .substring(root.path.length + 1)
            .replaceAll(r'\', '/'))
        .toList()
      ..sort();
  }

  List<File> filesUnder(String uid) {
    final d = Directory('${docs.path}/$kCoachRecordingsDir/$uid');
    return d.existsSync() ? d.listSync().whereType<File>().toList() : [];
  }
}

Future<_Rig> _pump(WidgetTester t,
    {String? firstUid = 'A', CoachRecordingStore? store}) async {
  final docs = Directory.systemTemp.createTempSync('rec_acct');
  addTearDown(() => docs.deleteSync(recursive: true));
  final svc = _Service();
  final auth = StreamController<AuthUser?>.broadcast();
  addTearDown(auth.close);
  await t.pumpWidget(ProviderScope(
    overrides: [
      coachHarnessEnabledProvider.overrideWithValue(true),
      poseDetectorServiceProvider.overrideWithValue(svc),
      authUserProvider.overrideWith((_) => auth.stream),
    ],
    child: MaterialApp(
      home: Scaffold(
          body: CoachRecorderPanel(
              store: store ?? CoachRecordingStore(documents: docs))),
    ),
  ));
  final container =
      ProviderScope.containerOf(t.element(find.byKey(const Key('coach.recorder'))));
  container.listen(authUserProvider, (_, __) {});
  if (firstUid != null) auth.add(_user(firstUid));
  await t.pump();
  await t.pump();
  return _Rig(docs, svc, auth, container);
}

Future<void> _emit(WidgetTester t, _Rig r, AuthUser? u) async {
  r.auth.add(u);
  await t.pump();
  await t.pump();
}

/// Lets real file IO finish, pumping so fake-zone microtasks resume.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
  }
}

Finder get _toggle => find.byKey(const Key('coach.recorder.toggle'));

void _expectToggle(String label) {
  expect(find.descendant(of: _toggle, matching: find.text(label)),
      findsOneWidget);
}

/// A store whose `save` parks until [release], then writes for real.
class _GatedStore extends CoachRecordingStore {
  _GatedStore(Directory docs) : super(documents: docs);
  final entered = Completer<void>();
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<File> save(String uid, CoachRecording rec) async {
    entered.complete();
    await _gate.future;
    return super.save(uid, rec);
  }
}

/// Records with A, presses Stop and waits until the save is parked.
Future<_GatedStore> _stopWithPausedSave(WidgetTester t, _Rig r, _GatedStore s) async {
  await t.tap(_toggle);
  await t.pump();
  r.svc.frames$.add(_frame(10));
  r.svc.frames$.add(_frame(50));
  await t.pump();
  await t.tap(_toggle);
  for (var i = 0; i < 40 && !s.entered.isCompleted; i++) {
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
  expect(s.entered.isCompleted, isTrue, reason: 'save must be in flight');
  return s;
}

Directory _dirOf(_Rig r, String uid) =>
    Directory('${r.docs.path}/$kCoachRecordingsDir/$uid');

void main() {
  testWidgets(
      '(g) save in flight, account deleted and real wipe ran: nothing is left',
      (t) async {
    final docs = Directory.systemTemp.createTempSync('rec_acct_g');
    addTearDown(() => docs.deleteSync(recursive: true));
    final store = _GatedStore(docs);
    final r = await _pump(t, store: store);
    // _pump created its own docs; the gated store writes under [docs].
    await _stopWithPausedSave(t, r, store);

    r.container.read(accountBeingDeletedUidProvider.notifier).state = 'A';
    SharedPreferences.setMockInitialValues({});
    await t.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      await DeviceLocalDataWipe(
        prefs: prefs,
        documentsDir: docs,
        forgetPhotoKey: (_) async {},
      ).wipe('A');
    });

    store.release();
    await _settle(t);

    final root = Directory('${docs.path}/$kCoachRecordingsDir');
    expect(Directory('${root.path}/A').existsSync(), isFalse);
    expect(Directory('${root.path}/B').existsSync(), isFalse);
    expect(
        root.existsSync()
            ? root.listSync(recursive: true).whereType<File>()
            : <File>[],
        isEmpty);
    expect(find.byKey(const Key('coach.recorder.export')), findsNothing);
    expect(find.textContaining('save-failed'), findsNothing);
    expect(find.textContaining('recording-discarded'), findsNothing);
    _expectToggle('Record');
  });

  testWidgets('(h) save in flight, auth switches A -> B: A file removed, none under B',
      (t) async {
    final docs = Directory.systemTemp.createTempSync('rec_acct_h');
    addTearDown(() => docs.deleteSync(recursive: true));
    final store = _GatedStore(docs);
    final r = await _pump(t, store: store);
    await _stopWithPausedSave(t, r, store);

    await _emit(t, r, _user('B'));
    store.release();
    await _settle(t);

    final root = Directory('${docs.path}/$kCoachRecordingsDir');
    expect(Directory('${root.path}/A').existsSync(), isFalse);
    expect(Directory('${root.path}/B').existsSync(), isFalse);
    expect(
        root.existsSync()
            ? root.listSync(recursive: true).whereType<File>()
            : <File>[],
        isEmpty);
    expect(find.byKey(const Key('coach.recorder.export')), findsNothing);
    expect(find.textContaining('save-failed'), findsNothing);
    _expectToggle('Record');
  });

  testWidgets('(i) control: gated save with no account change keeps the file',
      (t) async {
    final docs = Directory.systemTemp.createTempSync('rec_acct_i');
    addTearDown(() => docs.deleteSync(recursive: true));
    final store = _GatedStore(docs);
    final r = await _pump(t, store: store);
    await _stopWithPausedSave(t, r, store);

    store.release();
    await _settle(t);

    final files = Directory('${docs.path}/$kCoachRecordingsDir/A')
        .listSync()
        .whereType<File>()
        .toList();
    expect(files, hasLength(1));
    expect(find.byKey(const Key('coach.recorder.export')), findsOneWidget);
    expect(find.textContaining('recording-discarded'), findsNothing);
    _expectToggle('Record');
  });

  group('CoachRecordingStore.discard', () {
    late Directory docs;
    setUp(() => docs = Directory.systemTemp.createTempSync('rec_discard'));
    tearDown(() => docs.deleteSync(recursive: true));

    test('removes the file and the now-empty uid folder', () async {
      final store = CoachRecordingStore(documents: docs);
      final f = await store.save('A', CoachRecording(exercise: 'curl'));
      expect(f.existsSync(), isTrue);
      await store.discard('A', f);
      expect(f.existsSync(), isFalse);
      expect(Directory('${docs.path}/$kCoachRecordingsDir/A').existsSync(),
          isFalse);
    });

    test('keeps the folder when another file is in it', () async {
      final store = CoachRecordingStore(documents: docs);
      final f = await store.save('A', CoachRecording(exercise: 'curl'));
      final other = File('${f.parent.path}/other.json')..writeAsStringSync('{}');
      await store.discard('A', f);
      expect(f.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
      expect(f.parent.existsSync(), isTrue);
    });

    test('never throws and creates nothing when the folder is missing', () async {
      final store = CoachRecordingStore(documents: docs);
      final ghost = File('${docs.path}/$kCoachRecordingsDir/A/x.json');
      await expectLater(store.discard('A', ghost), completes);
      expect(Directory('${docs.path}/$kCoachRecordingsDir').existsSync(),
          isFalse);
    });
  });

  testWidgets('(a) A records, account switches to B: discarded, nothing saved',
      (t) async {
    final r = await _pump(t);
    await t.tap(_toggle);
    await t.pump();
    _expectToggle('Stop');
    r.svc.frames$.add(_frame(10));
    r.svc.frames$.add(_frame(50));
    await t.pump();

    await _emit(t, r, _user('B'));
    _expectToggle('Record');
    expect(find.text(_discardError), findsOneWidget);
    expect(find.byKey(const Key('coach.recorder.export')), findsNothing);

    await _settle(t);
    expect(r.filesUnder('B'), isEmpty);
    expect(r.filesUnder('A'), isEmpty);
    expect(r.files(), isEmpty);
  });

  testWidgets('(b) A records, sign-out (null): discarded, nothing saved',
      (t) async {
    final r = await _pump(t);
    await t.tap(_toggle);
    await t.pump();
    r.svc.frames$.add(_frame(10));
    await t.pump();

    await _emit(t, r, null);
    _expectToggle('Record');
    expect(find.text(_discardError), findsOneWidget);

    await _settle(t);
    expect(r.files(), isEmpty);
  });

  testWidgets('(c) A -> B -> A: the recording does not resume for returning A',
      (t) async {
    final r = await _pump(t);
    await t.tap(_toggle);
    await t.pump();
    r.svc.frames$.add(_frame(10));
    await t.pump();

    await _emit(t, r, _user('B'));
    await _emit(t, r, _user('A'));
    _expectToggle('Record');
    expect(find.text(_discardError), findsOneWidget);

    // Frames after A returned must not be captured by a dead recording.
    r.svc.frames$.add(_frame(90));
    await t.pump();
    await _settle(t);
    expect(r.files(), isEmpty);
  });

  testWidgets('(d) frames after the switch are not appended to B\'s recording',
      (t) async {
    final r = await _pump(t);
    await t.tap(_toggle);
    await t.pump();
    r.svc.frames$.add(_frame(10));
    r.svc.frames$.add(_frame(20));
    r.svc.frames$.add(_frame(30));
    await t.pump();

    await _emit(t, r, _user('B'));
    // Stray frames between the switch and B's own start.
    r.svc.frames$.add(_frame(40));
    r.svc.frames$.add(_frame(50));
    await t.pump();

    await t.tap(_toggle); // starts B's recording
    await t.pump();
    _expectToggle('Stop');
    expect(find.text(_discardError), findsNothing);
    r.svc.frames$.add(_frame(500));
    r.svc.frames$.add(_frame(540));
    await t.pump();
    await t.tap(_toggle); // stop
    for (var i = 0; i < 100; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      if (find.byKey(const Key('coach.recorder.export')).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(r.filesUnder('A'), isEmpty);
    final bFiles = r.filesUnder('B');
    expect(bFiles, hasLength(1));
    final m = jsonDecode(bFiles.single.readAsStringSync()) as Map;
    final frames = m['frames'] as List;
    // Exactly B's two frames; time origin is B's first frame (500), so A's
    // earlier timestamps (10..50) cannot be present.
    expect(frames, hasLength(2));
    expect([for (final f in frames) (f as Map)['t']], [0, 40]);
    expect(r.files(), hasLength(1));
  });

  testWidgets('(e) control: A records and stops, one file under A', (t) async {
    final r = await _pump(t);
    await t.tap(_toggle);
    await t.pump();
    r.svc.frames$.add(_frame(10));
    r.svc.frames$.add(_frame(50));
    r.svc.frames$.add(_frame(90));
    await t.pump();
    await t.tap(_toggle);
    for (var i = 0; i < 100; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      if (find.byKey(const Key('coach.recorder.export')).evaluate().isNotEmpty) {
        break;
      }
    }

    final files = r.filesUnder('A');
    expect(files, hasLength(1));
    expect(r.files(), hasLength(1));
    final m = jsonDecode(files.single.readAsStringSync()) as Map;
    expect(m['schema'], 'coach_recording/v1');
    expect(m['frames'], hasLength(3));
    expect(find.byKey(const Key('coach.recorder.export')), findsOneWidget);
    expect(find.text(_discardError), findsNothing);
    _expectToggle('Record');
  });

  testWidgets(
      '(f) a transient auth reload keeps the previous value: no discard',
      (t) async {
    // First build returns the controller stream; after invalidate the provider
    // rebuilds from a second stream, so it is AsyncLoading carrying A until
    // that stream emits.
    final docs = Directory.systemTemp.createTempSync('rec_acct_f');
    addTearDown(() => docs.deleteSync(recursive: true));
    final svc = _Service();
    final first = StreamController<AuthUser?>.broadcast();
    final second = StreamController<AuthUser?>.broadcast();
    addTearDown(first.close);
    addTearDown(second.close);
    var builds = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        coachHarnessEnabledProvider.overrideWithValue(true),
        poseDetectorServiceProvider.overrideWithValue(svc),
        authUserProvider
            .overrideWith((_) => (builds++ == 0 ? first : second).stream),
      ],
      child: MaterialApp(
        home: Scaffold(
            body:
                CoachRecorderPanel(store: CoachRecordingStore(documents: docs))),
      ),
    ));
    final container = ProviderScope.containerOf(
        t.element(find.byKey(const Key('coach.recorder'))));
    container.listen(authUserProvider, (_, __) {});
    first.add(_user('A'));
    await t.pump();
    await t.pump();

    await t.tap(_toggle);
    await t.pump();
    svc.frames$.add(_frame(10));
    svc.frames$.add(_frame(50));
    await t.pump();

    container.invalidate(authUserProvider);
    await t.pump();
    final loading = container.read(authUserProvider);
    expect(loading.isLoading, isTrue, reason: 'harness must produce a reload');
    expect(loading.valueOrNull?.uid, 'A',
        reason: 'reload must carry the previous value for this scenario');
    _expectToggle('Stop');
    expect(find.text(_discardError), findsNothing);

    second.add(_user('A'));
    await t.pump();
    await t.pump();
    _expectToggle('Stop');
    expect(find.text(_discardError), findsNothing);

    await t.tap(_toggle);
    for (var i = 0; i < 100; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      if (find.byKey(const Key('coach.recorder.export')).evaluate().isNotEmpty) {
        break;
      }
    }
    final dir = Directory('${docs.path}/$kCoachRecordingsDir/A');
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final m = jsonDecode(files.single.readAsStringSync()) as Map;
    expect(m['frames'], hasLength(2));
  });
}
