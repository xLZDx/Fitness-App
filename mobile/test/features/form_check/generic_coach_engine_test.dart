import 'dart:convert';

import 'package:fitness_app/features/form_check/data/coach_registry.dart';
import 'package:fitness_app/features/form_check/data/coach_signal.dart';
import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/generic_rule_classifier.dart';
import 'package:fitness_app/features/form_check/data/hold_counter.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_registry_fixture.dart';

PoseLandmark p(LandmarkType t, double x, double y, [double l = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: l);

/// Left side view. [kneeAngleDeg] is ~180 (standing) or ~53 (bottom);
/// [shoulderX] moves the shoulder to change the hip angle.
PoseFrame sideFrame({
  required bool bottom,
  double shoulderX = 0.5,
  double likelihood = 0.95,
  bool rightSide = false,
  int ts = 0,
}) {
  final knee = bottom ? (0.7, 0.6) : (0.5, 0.7);
  final ankle = bottom ? (0.5, 0.7) : (0.5, 0.9);
  final m = <LandmarkType, PoseLandmark>{};
  void put(LandmarkType l, LandmarkType r, double x, double y) {
    final t = rightSide ? r : l;
    m[t] = p(t, x, y, likelihood);
  }

  put(LandmarkType.leftShoulder, LandmarkType.rightShoulder, shoulderX, 0.3);
  put(LandmarkType.leftHip, LandmarkType.rightHip, 0.5, 0.5);
  put(LandmarkType.leftKnee, LandmarkType.rightKnee, knee.$1, knee.$2);
  put(LandmarkType.leftAnkle, LandmarkType.rightAnkle, ankle.$1, ankle.$2);
  return PoseFrame(timestampMs: ts, landmarks: m);
}

/// Registry with one rep exercise. [entitled] = measured+stable+non-advisory.
CoachRegistry repRegistry({required bool entitled, String metric = 'hip_angle'}) {
  final doc = exampleForTests();
  final e = firstExercise(doc);
  e['id'] = 'squat_x';
  e['aliases'] = ['squat_x_alias'];
  e['tracked'] = ['hip', 'knee', 'ankle', 'shoulder'];
  e['rules'] = [
    {
      'id': 'hip_open',
      'metric': metric,
      'min': 100,
      'max': 145,
      'tolerance': 5,
      'phase': 'bottom',
      'severity': 'major',
      'cueId': 'cue.x.hip',
      'advisory': !entitled,
    },
  ];
  e['provenance'] = entitled
      ? {'kind': 'measured', 'source': 'test', 'status': 'stable'}
      : {'kind': 'authored', 'source': 'test', 'status': 'beta'};
  return CoachRegistry.fromJson(jsonDecode(jsonEncode(doc)));
}

CoachRegistry plankRegistry() {
  final doc = exampleForTests();
  final e = firstExercise(doc);
  e['id'] = 'plank';
  e['aliases'] = <String>[];
  e['tracked'] = ['shoulder', 'hip', 'ankle'];
  e['phases'] = [
    {'name': 'hold', 'entry': 'body in line'},
  ];
  e['signal'] = {
    'kind': 'lineDeviation',
    'joints': ['shoulder', 'hip', 'ankle'],
    'normalizeBy': 'torso',
    'direction': 'falling',
    'enter': 0.08,
    'exit': 0.12,
  };
  e['counting'] = {'mode': 'hold', 'minHoldMs': 1000};
  e['rules'] = [
    {
      'id': 'sag',
      'metric': 'signal',
      'min': -0.08,
      'max': 0.08,
      'tolerance': 0.0,
      'phase': 'hold',
      'severity': 'minor',
      'cueId': 'cue.x.sag',
      'advisory': true,
    },
  ];
  return CoachRegistry.fromJson(jsonDecode(jsonEncode(doc)));
}

PoseFrame plankFrame(int ts, double hipDy, {double likelihood = 0.95}) =>
    PoseFrame(timestampMs: ts, landmarks: {
      LandmarkType.leftShoulder:
          p(LandmarkType.leftShoulder, 0.2, 0.5, likelihood),
      LandmarkType.leftHip: p(LandmarkType.leftHip, 0.5, 0.5 + hipDy, likelihood),
      LandmarkType.leftAnkle: p(LandmarkType.leftAnkle, 0.8, 0.5, likelihood),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('GenericRuleClassifier', () {
    test('entitled rule: quiet at top, quiet in band, faults out of band', () {
      final c = GenericRuleClassifier(repRegistry(entitled: true).byId('squat_x')!);
      expect(c.canFault, isTrue);
      expect(c.evaluate(sideFrame(bottom: false)), isNull,
          reason: 'bottom-phase rule must not apply at the top');
      expect(c.evaluate(sideFrame(bottom: true)), isNull,
          reason: 'hip angle ~117 is inside 100..145');
      final f = c.evaluate(sideFrame(bottom: true, shoulderX: 0.35));
      expect(f, isNotNull, reason: 'hip angle ~153 > 145 + 5');
      expect(f!.severity, 2);
      expect(f.cueKey, FormCueKey.registry);
      expect(f.cueId, 'cue.x.hip');
      expect(f.advisory, isFalse);
      expect(f.rule, 'squat_x');
      expect(f.metric, closeTo(153.4, 0.5));
    });

    test('tolerance: just outside min/max but inside tolerance is quiet', () {
      final c = GenericRuleClassifier(repRegistry(entitled: true).byId('squat_x')!);
      // shoulderX 0.38 -> hip angle ~147: outside 145, inside 145 + 5.
      expect(c.evaluate(sideFrame(bottom: true, shoulderX: 0.38)), isNull);
    });

    test('advisory/beta row: same violation is severity 0, advisory, canFault false',
        () {
      final c = GenericRuleClassifier(repRegistry(entitled: false).byId('squat_x')!);
      expect(c.canFault, isFalse);
      final f = c.evaluate(sideFrame(bottom: true, shoulderX: 0.35));
      expect(f, isNotNull);
      expect(f!.severity, 0);
      expect(f.advisory, isTrue);
      expect(f.cueId, 'cue.x.hip');
    });

    test('a measured+beta row with advisory=false still cannot fault', () {
      final doc = exampleForTests();
      final e = firstExercise(doc);
      e['provenance'] = {'kind': 'measured', 'source': 't', 'status': 'beta'};
      (e['rules'] as List).first['advisory'] = false;
      final spec = CoachRegistry.fromJson(doc).exercises.first;
      expect(GenericRuleClassifier(spec).canFault, isFalse);
    });

    test('unreadable joint (low likelihood) yields nothing, gate says so', () {
      final c = GenericRuleClassifier(repRegistry(entitled: true).byId('squat_x')!);
      final frame = sideFrame(bottom: true, shoulderX: 0.35, likelihood: 0.2);
      expect(c.evaluate(frame), isNull);
      expect(evaluateGated([c], frame).verdict, PoseGateVerdict.lowConfidence);
    });

    test('right side visible only: judged via side selection', () {
      final c = GenericRuleClassifier(repRegistry(entitled: true).byId('squat_x')!);
      final frame =
          sideFrame(bottom: true, shoulderX: 0.35, rightSide: true);
      final r = evaluateGated([c], frame);
      expect(r.verdict, PoseGateVerdict.ok);
      expect(r.worst?.severity, 2);
    });

    test('unknown metric is inert and reported', () {
      final reg = repRegistry(entitled: true, metric: 'bogus_metric');
      final spec = reg.byId('squat_x')!;
      expect(unsupportedCoachMetrics(spec), ['squat_x.hip_open']);
      final c = GenericRuleClassifier(spec);
      expect(c.evaluate(sideFrame(bottom: true, shoulderX: 0.35)), isNull);
      expect(unsupportedCoachMetrics(repRegistry(entitled: true).byId('squat_x')!),
          isEmpty);
    });

    test('lineDeviation: sagging hip is positive and flagged, level is quiet', () {
      final c = GenericRuleClassifier(plankRegistry().byId('plank')!);
      expect(c.evaluate(plankFrame(0, 0.0)), isNull);
      final sag = c.evaluate(plankFrame(0, 0.06));
      expect(sag, isNotNull);
      expect(sag!.metric, greaterThan(0.08));
      expect(sag.severity, 0);
      final pike = c.evaluate(plankFrame(0, -0.06));
      expect(pike!.metric, lessThan(-0.08));
    });
  });

  group('HoldCounter', () {
    test('credits only after minHoldMs, pauses out of band, resumes', () {
      var now = 0;
      final h = HoldCounter(minHoldMs: 1000, clock: () => now);
      void tick(int ms, bool inBand) {
        now += ms;
        h.update(inBand);
      }

      h.update(true); // t=0 streak starts
      tick(500, true);
      expect(h.heldMs, 0, reason: 'streak shorter than minHoldMs');
      expect(h.running, isFalse);
      tick(500, true);
      expect(h.heldMs, 1000);
      expect(h.running, isTrue);
      tick(1000, true);
      expect(h.heldMs, 2000);
      tick(100, false);
      tick(100, false);
      expect(h.heldMs, 2000, reason: 'paused out of band, banked kept');
      expect(h.running, isFalse);
      tick(500, true);
      expect(h.heldMs, 2000, reason: 'resume needs a fresh minHoldMs streak');
      tick(500, true);
      tick(500, true);
      expect(h.heldMs, 3000);
    });

    test('a long gap without updates breaks the streak', () {
      var now = 0;
      final h = HoldCounter(minHoldMs: 500, maxGapMs: 1000, clock: () => now);
      h.update(true);
      now = 600;
      h.update(true);
      expect(h.heldMs, 600);
      now = 10000;
      h.update(true);
      expect(h.heldMs, 600, reason: 'gap time is not credited');
    });

    test('controller shows a hold timer, not reps, and pauses out of band',
        () async {
      final frames = <PoseFrame>[
        for (var t = 0; t <= 3000; t += 100) plankFrame(t, 0.0),
        for (var t = 3100; t <= 4000; t += 100) plankFrame(t, 0.4), // collapsed
      ];
      final svc = MockPoseDetectorService(frames);
      final container = ProviderContainer(overrides: [
        poseDetectorServiceProvider.overrideWithValue(svc),
        voiceCoachProvider.overrideWithValue(MockVoiceCoach()),
        coachRegistrySnapshotProvider.overrideWithValue(plankRegistry()),
        selectedExerciseProvider.overrideWith((_) => FormExercise.plank),
      ]);
      addTearDown(container.dispose);
      container.read(repSessionControllerProvider);
      await svc.start();
      await pumpEventQueue();
      final s = container.read(repSessionControllerProvider);
      expect(s.repCount, 0);
      expect(s.holdMs, inInclusiveRange(2500, 3000),
          reason: 'about 3 s in band, then paused');
      await svc.dispose();
    });
  });

  group('registry wiring', () {
    test('load failure: logged, null registry, legacy behaviour intact', () async {
      final container = ProviderContainer(overrides: [
        coachRegistryLoaderProvider
            .overrideWithValue(() async => throw StateError('boom')),
      ]);
      addTearDown(container.dispose);
      expect(await container.read(coachRegistryProvider.future), isNull);
      expect(container.read(coachRegistrySnapshotProvider), isNull);
      expect(container.read(activeClassifiersProvider).first,
          isA<SquatDepthClassifier>());
      container.read(selectedExerciseProvider.notifier).state =
          FormExercise.plank;
      expect(container.read(activeClassifiersProvider), isEmpty);
      expect(formCoachTeaches(FormExercise.plank), isFalse);
    });

    test('shipped (empty) asset parses and changes nothing', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final reg = await container.read(coachRegistryProvider.future);
      expect(reg, isNotNull);
      expect(container.read(activeClassifiersProvider).first,
          isA<SquatDepthClassifier>());
    });

    test('legacy parity: squat/pushup/deadlift keep legacy classifiers even if '
        'the registry has a matching alias', () {
      final doc = exampleForTests();
      firstExercise(doc)['aliases'] = ['squat'];
      final reg = CoachRegistry.fromJson(doc);
      final container = ProviderContainer(overrides: [
        coachRegistrySnapshotProvider.overrideWithValue(reg),
      ]);
      addTearDown(container.dispose);
      final n = container.read(selectedExerciseProvider.notifier);
      n.state = FormExercise.squat;
      expect(container.read(activeClassifiersProvider).first,
          isA<SquatDepthClassifier>());
      n.state = FormExercise.pushup;
      expect(container.read(activeClassifiersProvider).single,
          isA<PushupAlignmentClassifier>());
      n.state = FormExercise.deadlift;
      expect(container.read(activeClassifiersProvider).single,
          isA<DeadliftHipHingeClassifier>());
    });

    test('registry-only exercise is taught, classified generically, no count',
        () {
      final reg = plankRegistry();
      expect(formCoachTeaches(FormExercise.plank), isFalse);
      expect(formCoachTeaches(FormExercise.plank, registry: reg), isTrue);
      expect(formCoachTeaches(FormExercise.pullUp, registry: reg), isFalse);
      final container = ProviderContainer(overrides: [
        coachRegistrySnapshotProvider.overrideWithValue(reg),
        selectedExerciseProvider.overrideWith((_) => FormExercise.plank),
      ]);
      addTearDown(container.dispose);
      expect(container.read(activeClassifiersProvider).single,
          isA<GenericRuleClassifier>());
      expect(showRepCountFor(FormExercise.plank, spec: reg.byId('plank')),
          isFalse);
    });

    test('advisory feedback is never spoken, even forged at severity 2', () async {
      final coach = MockVoiceCoach(resolveText: (_) => 'text');
      await coach.cue(const FormFeedback(
        rule: 'x',
        severity: 2,
        cueKey: FormCueKey.registry,
        cueId: 'cue.x',
        advisory: true,
      ));
      expect(coach.spoken, isEmpty);
      await coach.cue(const FormFeedback(
        rule: 'x',
        severity: 2,
        cueKey: FormCueKey.registry,
        cueId: 'cue.x',
      ));
      expect(coach.spoken, ['text'], reason: 'positive control');
    });
  });
}
