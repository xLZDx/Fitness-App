import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/localized_tts_voice_coach.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

import 'squat_body_relative_signal_test.dart' show squatBody, squatRep;

/// Operator, real phone, 2026-10-14: "the squat coach writes a cue as text but
/// does not speak it".
///
/// This drives the REAL pipeline -- `RepSessionController`, the shipped
/// `CueGate`, `TtsVoiceCoach` with the production wiring
/// (`buildLocalizedTtsVoiceCoach`, the Russian resolver) -- over a fake
/// `flutter_tts` platform channel whose `speak` is DEFERRED (it only completes
/// when the test lets it, like an engine that is busy reading the previous
/// cue). The assertion is what the speaker received, in Russian, once per rep.
///
/// Root cause found: the gate's same-cue repeat window (20 s) and minimum gap
/// (3 s) were applied on top of the per-rep pacing the controller already
/// provides, so only the FIRST of several identical rep-end cues was spoken
/// while every rep still showed its text banner. Rep-end cues are now
/// `repScoped` and the gate skips those two stopwatch filters for them.

const _channel = MethodChannel('flutter_tts');

class _FakeEngine {
  final spoken = <String>[];
  final stops = <int>[];
  final _pending = <Completer<Object?>>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case 'isLanguageAvailable':
          return true;
        case 'speak':
          spoken.add(call.arguments as String);
          // Deferred: completes only when released.
          final c = Completer<Object?>();
          _pending.add(c);
          return c.future;
        case 'stop':
          stops.add(1);
          return 1;
        default:
          return 1;
      }
    });
  }

  void releaseAll() {
    for (final c in _pending) {
      if (!c.isCompleted) c.complete(1);
    }
    _pending.clear();
  }

  void uninstall() {
    releaseAll();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

Future<(RepSessionState, _FakeEngine)> _run(List<PoseFrame> frames,
    {bool withTarget = false, bool avatar = false}) async {
  final engine = _FakeEngine()..install();
  addTearDown(engine.uninstall);
  final svc = MockPoseDetectorService(frames);
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWithValue(svc),
    voiceCoachProvider.overrideWith((ref) {
      final coach = buildLocalizedTtsVoiceCoach('ru');
      ref.onDispose(() => coach.dispose());
      return coach;
    }),
    if (!withTarget) poseTargetProvider.overrideWithValue(null),
    avatarModeProvider.overrideWith((_) => avatar),
  ]);
  addTearDown(container.dispose);
  container.read(repSessionControllerProvider);
  // The Russian bundle loads asynchronously, exactly as in production.
  await pumpEventQueue();
  await svc.start();
  await pumpEventQueue();
  final state = container.read(repSessionControllerProvider);
  await svc.dispose();
  return (state, engine);
}

List<PoseFrame> _reps(int n, {required double elev, double lean = 20}) => [
      for (var i = 0; i < n; i++)
        ...squatRep(i * 10000, bottomElev: elev, bottomLean: lean),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations ru;
  setUpAll(() async {
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  test('POSITIVE CONTROL: a clean deep rep speaks nothing, and the pipeline '
      'counts it', () async {
    final (state, engine) = await _run(_reps(2, elev: -5));
    expect(state.repCount, 2);
    expect(engine.spoken, isEmpty);
  });

  test('three shallow reps: the Russian shallow cue is spoken once per rep',
      () async {
    final (state, engine) = await _run(_reps(3, elev: 17));
    expect(state.repCount, 3);
    expect(engine.spoken,
        List.filled(3, ru.formcheckCueSquatDepthShallow),
        reason: 'every rep showed the banner; every rep must be spoken');
  });

  test('three folded-back reps: the Russian back cue is spoken once per rep',
      () async {
    final (state, engine) = await _run(_reps(3, elev: -5, lean: 75));
    expect(state.repCount, 3);
    expect(engine.spoken,
        List.filled(3, ru.formcheckCueSquatBackRounding));
  });

  test('a rep that misses the silhouette speaks the generic cue once per rep, '
      'and a specific squat cue is not replaced by it', () async {
    // Real squat target, camera mode: a deep, upright stick figure that does
    // not match the authored shape is "missed".
    final (state, engine) =
        await _run(_reps(2, elev: -5), withTarget: true);
    expect(state.repCount, 2);
    expect(state.lastRepMissedTarget, isTrue,
        reason: 'precondition: the fixture misses the shape');
    expect(engine.spoken,
        List.filled(2, ru.formcheckCueSilhouetteMissed));

    final (_, engine2) =
        await _run(_reps(2, elev: 17), withTarget: true);
    expect(engine2.spoken,
        List.filled(2, ru.formcheckCueSquatDepthShallow),
        reason: 'the specific diagnosis wins over the generic miss');
  });

  test('avatar mode, no target: a squat rejected as incomplete still speaks '
      'the shallow cue, once', () async {
    // The silhouette target is withdrawn here, so there is no peak match to
    // compare: the rejection reason alone must carry the cue.
    final (state, engine) = await _run(_reps(1, elev: 25), avatar: true);
    expect(state.repCount, 0);
    expect(state.lastReject, RepRejectReason.incomplete);
    expect(engine.spoken, [ru.formcheckCueSquatDepthShallow]);
  });

  test('an abandoned lap is not charged to the lifter as a shallow squat',
      () async {
    final (state, engine) = await _run([
      ..._reps(1, elev: 25).take(18),
      // The lifter stops for a long time half-way down, then leaves.
      for (var i = 0; i < 5; i++)
        squatBody(30000 + i * 10000, elevDeg: 25, leanDeg: 20),
    ], avatar: true);
    expect(state.lastReject, RepRejectReason.abandoned);
    expect(engine.spoken, isEmpty);
  });

  test('a failed Russian bundle falls back to English text, never to an '
      'identifier', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final coach = buildLocalizedTtsVoiceCoach('ru',
        loadLocalizations: (locale) => locale.languageCode == 'ru'
            ? Future.error(StateError('no ru bundle'))
            : AppLocalizations.delegate.load(locale));
    addTearDown(coach.dispose);
    await pumpEventQueue();
    expect(coach.resolveText(FormCueKey.squatDepthShallow),
        en.formcheckCueSquatDepthShallow);
  });

  test('if even English fails the coach is silent, not reading a key aloud',
      () async {
    final coach = buildLocalizedTtsVoiceCoach('ru',
        loadLocalizations: (_) => Future.error(StateError('no bundles')));
    addTearDown(coach.dispose);
    await pumpEventQueue();
    for (final k in FormCueKey.values) {
      expect(coach.resolveText(k), isEmpty, reason: '$k');
    }
  });

  test('the production resolver maps every new cue key to its Russian text',
      () async {
    final coach = buildLocalizedTtsVoiceCoach('ru');
    addTearDown(coach.dispose);
    await pumpEventQueue();
    expect(coach.resolveText(FormCueKey.squatBackRounding),
        ru.formcheckCueSquatBackRounding);
    expect(coach.resolveText(FormCueKey.squatDepthShallow),
        ru.formcheckCueSquatDepthShallow);
    expect(coach.resolveText(FormCueKey.silhouetteMissed),
        ru.formcheckCueSilhouetteMissed);
    expect(coach.languageTag, 'ru-RU');
  });
}
