import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/debug/coach_recorder.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

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

Widget _app(List<Override> overrides, {Widget? child}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
          home: Scaffold(body: child ?? const CoachRecorderPanel())),
    );

void main() {
  testWidgets('release is simulated through the injectable flag: nothing is built',
      (t) async {
    await t.pumpWidget(
        _app([coachHarnessEnabledProvider.overrideWithValue(false)]));
    expect(find.byKey(const Key('coach.recorder')), findsNothing);
    expect(find.byKey(const Key('coach.recorder.toggle')), findsNothing);
  });

  testWidgets('debug/profile: the panel is built', (t) async {
    await t.pumpWidget(
        _app([coachHarnessEnabledProvider.overrideWithValue(true)]));
    expect(find.byKey(const Key('coach.recorder')), findsOneWidget);
  });

  test('default flag follows kDebugMode/kProfileMode (tests run in debug)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(coachHarnessEnabledProvider), isTrue);
  });

  test('the recording holds angles and timestamps only', () {
    final rec = CoachRecording(exercise: 'curl');
    rec.add(_frame(1000), repPhase: 'top', reps: 0, rule: 'curl.x', severity: 0);
    rec.add(_frame(1100), repPhase: 'ascending', reps: 1);
    final json = jsonEncode(rec.toJson());
    final m = jsonDecode(json) as Map<String, dynamic>;
    expect(m['schema'], 'coach_recording/v1');
    final frames = m['frames'] as List;
    expect(frames[0]['t'], 0);
    expect(frames[1]['t'], 100);
    expect((frames[0]['angles'] as Map)['leftElbow'], 90.0);
    // No coordinates, landmarks, images or identity leak into the file.
    for (final banned in ['landmarks', '"x"', '"y"', 'image', 'video', 'uid']) {
      expect(json.contains(banned), isFalse, reason: banned);
    }
  });

  test('recording is capped', () {
    final rec = CoachRecording(exercise: 'curl');
    for (var i = 0; i < kCoachRecordingMaxFrames + 5; i++) {
      rec.add(_frame(i));
    }
    expect(rec.frames.length, kCoachRecordingMaxFrames);
  });

  testWidgets('panel records frames, saves under the uid dir, offers export',
      (t) async {
    final docs = Directory.systemTemp.createTempSync('rec_test');
    addTearDown(() => docs.deleteSync(recursive: true));
    final svc = _Service();
    await t.pumpWidget(_app([
      coachHarnessEnabledProvider.overrideWithValue(true),
      poseDetectorServiceProvider.overrideWithValue(svc),
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'x'))),
    ], child: CoachRecorderPanel(store: CoachRecordingStore(documents: docs))));
    // The auth stream is app-lifetime in production; subscribe it here.
    ProviderScope.containerOf(t.element(find.byKey(const Key('coach.recorder'))))
        .listen(authUserProvider, (_, __) {});
    await t.pump();
    await t.pump();

    await t.tap(find.byKey(const Key('coach.recorder.toggle')));
    await t.pump();
    svc.frames$.add(_frame(10));
    svc.frames$.add(_frame(50));
    await t.pump();
    expect(find.byKey(const Key('coach.recorder.export')), findsNothing);
    await t.tap(find.byKey(const Key('coach.recorder.toggle')));
    // Real file IO: alternate real time (IO completes) and pumps (the fake
    // zone's microtasks resume the save) until the export button shows.
    for (var i = 0; i < 100; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      if (find.byKey(const Key('coach.recorder.export')).evaluate().isNotEmpty) {
        break;
      }
    }

    final dir = Directory('${docs.path}/$kCoachRecordingsDir/u1');
    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final m = jsonDecode(files.single.readAsStringSync()) as Map;
    expect((m['frames'] as List), hasLength(2));
    expect(find.byKey(const Key('coach.recorder.export')), findsOneWidget);
  });

  test('the account-deletion wipe erases that uid\'s recordings only',
      () async {
    final docs = Directory.systemTemp.createTempSync('rec_wipe');
    addTearDown(() => docs.deleteSync(recursive: true));
    final store = CoachRecordingStore(documents: docs);
    await store.save('u1', CoachRecording(exercise: 'curl'));
    await store.save('u2', CoachRecording(exercise: 'curl'));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('u1');

    expect(Directory('${docs.path}/$kCoachRecordingsDir/u1').existsSync(),
        isFalse);
    expect(Directory('${docs.path}/$kCoachRecordingsDir/u2').existsSync(),
        isTrue);
  });
}
