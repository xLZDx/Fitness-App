import 'dart:math' as math;

import 'package:fitness_app/features/form_check/data/coach_registry.dart';
import 'package:fitness_app/features/form_check/data/coach_signal.dart';
import 'package:fitness_app/features/form_check/data/coach_spec.dart';
import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/generic_rule_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/data/registry_cue_text.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Content tests for the eight authored registry exercises (WS7 P3). Frames are
// synthesised from joint angles; every row is authored + beta + advisory, so a
// faulty frame must yield the expected cue id at severity 0 (advisory).

typedef Pt = (double, double);

Pt at(Pt o, double deg, double len) {
  final r = deg * math.pi / 180;
  return (o.$1 + len * math.cos(r), o.$2 + len * math.sin(r));
}

/// A point `c` at distance [len] from [b] such that the angle a-b-c is [theta]
/// degrees. [lower] picks the candidate with the larger screen y.
Pt third(Pt b, Pt a, double theta, double len, {required bool lower}) {
  final d = math.atan2(a.$2 - b.$2, a.$1 - b.$1) * 180 / math.pi;
  final c1 = at(b, d + theta, len);
  final c2 = at(b, d - theta, len);
  return (c1.$2 > c2.$2) == lower ? c1 : c2;
}

PoseFrame frame(Map<LandmarkType, Pt> pts, int ts) => PoseFrame(
      timestampMs: ts,
      landmarks: {
        for (final e in pts.entries)
          e.key: PoseLandmark(
              type: e.key, x: e.value.$1, y: e.value.$2, likelihood: 0.95),
      },
    );

const _ls = LandmarkType.leftShoulder;
const _le = LandmarkType.leftElbow;
const _lw = LandmarkType.leftWrist;
const _lh = LandmarkType.leftHip;
const _lk = LandmarkType.leftKnee;
const _la = LandmarkType.leftAnkle;
const _rs = LandmarkType.rightShoulder;
const _re = LandmarkType.rightElbow;
const _rw = LandmarkType.rightWrist;
const _rh = LandmarkType.rightHip;
const _nose = LandmarkType.nose;

// ---- per-exercise frame builders (left side view unless noted) ------------

PoseFrame rowFrame(double elbow, {double hip = 120, int ts = 0}) {
  final h = (0.5, 0.5);
  final k = (0.5, 0.75);
  final s = at(h, 90 + hip, 0.25);
  final e = (s.$1, s.$2 + 0.2);
  final w = third(e, s, elbow, 0.2, lower: true);
  return frame({_ls: s, _le: e, _lw: w, _lh: h, _lk: k}, ts);
}

/// Front view; [alpha] = arm abduction, [elbow] = elbow angle (180 straight).
PoseFrame raiseFrame(double alpha, {double elbow = 180, int ts = 0}) {
  Map<LandmarkType, Pt> side(
      LandmarkType sh, LandmarkType el, LandmarkType wr, LandmarkType hp, double sgn) {
    final s = (0.5 + sgn * 0.1, 0.3);
    final h = (0.5 + sgn * 0.08, 0.55);
    final screenDeg = sgn < 0 ? 90 + alpha : 90 - alpha;
    final e = at(s, screenDeg, 0.15);
    final w = elbow >= 179.9
        ? at(s, screenDeg, 0.3)
        : third(e, s, elbow, 0.15, lower: true);
    return {sh: s, el: e, wr: w, hp: h};
  }

  return frame({
    ...side(_ls, _le, _lw, _lh, -1),
    ...side(_rs, _re, _rw, _rh, 1),
  }, ts);
}

PoseFrame plankFrame(double hipDy, {int ts = 0}) => frame({
      _ls: (0.2, 0.5),
      _lh: (0.5, 0.5 + hipDy),
      _la: (0.8, 0.5),
    }, ts);

/// [hip] = shoulder-hip-knee angle, [knee] = hip-knee-ankle angle.
PoseFrame bridgeFrame(double hip, {double knee = 95, int ts = 0}) {
  final h = (0.5, 0.6);
  final s = (0.2, 0.62);
  final k = third(h, s, hip, 0.25, lower: false);
  final a = third(k, h, knee, 0.25, lower: true);
  return frame({_ls: s, _lh: h, _lk: k, _la: a}, ts);
}

/// [noseBelowWrist] > 0 means the nose is lower than the wrist (chin not up).
PoseFrame pullFrame(double elbow, {double noseBelowWrist = -0.05, int ts = 0}) {
  final s = (0.5, 0.5);
  final h = (0.5, 0.75);
  final e = (0.56, 0.3);
  final w = third(e, s, elbow, 0.2, lower: false);
  return frame({
    _nose: (0.5, w.$2 + noseBelowWrist),
    _ls: s,
    _le: e,
    _lw: w,
    _lh: h,
  }, ts);
}

/// [knee] = working-knee angle; [lean] = trunk off vertical, degrees.
PoseFrame stepFrame(double knee, {double lean = 8, int ts = 0}) {
  final h = (0.5, 0.5);
  final k = (0.58, 0.7);
  final a = third(k, h, knee, 0.25, lower: true);
  final s = at(h, -90 - lean, 0.25);
  return frame({_ls: s, _lh: h, _lk: k, _la: a}, ts);
}

PoseFrame dipFrame(double elbow, {int ts = 0}) {
  final s = (0.5, 0.4);
  final h = (0.5, 0.65);
  final e = (0.45, 0.55);
  final w = third(e, s, elbow, 0.18, lower: true);
  return frame({_ls: s, _le: e, _lw: w, _lh: h}, ts);
}

PoseFrame morningFrame(double hip, {double knee = 172, int ts = 0}) {
  final h = (0.5, 0.4);
  final s = at(h, 90 + hip, 0.2);
  final k = (0.5, 0.6);
  final a = third(k, h, knee, 0.2, lower: true);
  return frame({_ls: s, _lh: h, _lk: k, _la: a}, ts);
}

/// rest -> active -> rest, 100 ms per frame, [build] maps the key value.
List<PoseFrame> cycle(PoseFrame Function(double v, int ts) build, double rest,
    double active,
    {int startMs = 0}) {
  final out = <PoseFrame>[];
  var t = startMs;
  void add(double v) {
    out.add(build(v, t));
    t += 100;
  }

  for (var i = 0; i < 6; i++) {
    add(rest);
  }
  for (var i = 1; i <= 10; i++) {
    add(rest + (active - rest) * i / 10);
  }
  for (var i = 0; i < 5; i++) {
    add(active);
  }
  for (var i = 1; i <= 10; i++) {
    add(active + (rest - active) * i / 10);
  }
  for (var i = 0; i < 6; i++) {
    add(rest);
  }
  return out;
}

int countReps(CoachSpec spec, List<PoseFrame> frames) {
  final (signal, config) = coachRepSignal(spec)!;
  final c = RepCounter(config: config, signal: signal);
  for (final f in frames) {
    c.update(f);
  }
  return c.repCount;
}

/// Every synthetic frame must pass the pose gate: otherwise "no feedback"
/// would be vacuous (the classifier returns null for unscorable frames too).
void expectScorable(CoachSpec spec, List<PoseFrame> frames) {
  final need = coachRequiredLandmarks(spec);
  for (final f in frames) {
    final v = gatePose(coachFrameFor(spec, f), need);
    expect(v.isScorable, isTrue,
        reason: '${spec.id} frame @${f.timestampMs} gated: $v');
  }
}

/// Feedback emitted over a whole sequence (null frames skipped).
List<FormFeedback> run(CoachSpec spec, List<PoseFrame> frames) {
  expectScorable(spec, frames);
  final c = GenericRuleClassifier(spec);
  return [
    for (final f in frames)
      if (c.evaluate(f) case final fb?) fb,
  ];
}

FormFeedback? last(CoachSpec spec, List<PoseFrame> frames) {
  expectScorable(spec, frames);
  final c = GenericRuleClassifier(spec);
  FormFeedback? out;
  for (final f in frames) {
    out = c.evaluate(f);
  }
  return out;
}

void expectAdvisoryCue(FormFeedback? fb, String cueId) {
  expect(fb, isNotNull, reason: 'expected cue $cueId');
  expect(fb!.cueId, cueId);
  expect(fb.cueKey, FormCueKey.registry);
  expect(fb.severity, 0, reason: 'authored rows are advisory');
  expect(fb.advisory, isTrue);
}

const _newIds = [
  'bentOverRow',
  'lateralRaise',
  'plank',
  'gluteBridge',
  'pullUp',
  'stepUp',
  'tricepDip',
  'goodMorning',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoachRegistry registry;
  CoachSpec spec(String id) => registry.byId(id)!;

  setUpAll(() async {
    registry = await CoachRegistry.load();
  });

  group('shipped registry', () {
    test('all eight exercises parse; authored, beta, advisory; no calf raise', () {
      expect(registry.exercises.map((e) => e.id).toSet(), _newIds.toSet());
      expect(registry.byId('calfRaise'), isNull);
      expect(registry.lookup('calf_raise'), isNull);
      for (final e in registry.exercises) {
        expect(e.provenance.kind, CoachProvenanceKind.authored, reason: e.id);
        expect(e.provenance.status, CoachProvenanceStatus.beta, reason: e.id);
        expect(e.rules, isNotEmpty, reason: e.id);
        for (final r in e.rules) {
          expect(r.advisory, isTrue, reason: '${e.id}.${r.id}');
          expect(r.cueId, '${e.id}.${r.id}');
        }
        expect(GenericRuleClassifier(e).canFault, isFalse, reason: e.id);
      }
    });

    test('every rule metric is supported by the engine', () {
      for (final e in registry.exercises) {
        expect(unsupportedCoachMetrics(e), isEmpty, reason: e.id);
      }
    });

    test('hold exercises are plank and glute bridge only; safety wording flags',
        () {
      for (final e in registry.exercises) {
        final hold = e.id == 'plank' || e.id == 'gluteBridge';
        expect(e.counting.mode,
            hold ? CoachCountingMode.hold : CoachCountingMode.reps,
            reason: e.id);
        expect(e.counting.minHoldMs != null, hold, reason: e.id);
        expect(e.safetyWording, e.id == 'tricepDip' || e.id == 'goodMorning',
            reason: e.id);
      }
    });

    test('registry-only exercises are taught once the registry is present', () {
      for (final fe in kRegistryOnlyExercises) {
        expect(formCoachTeaches(fe), isFalse, reason: fe.name);
        expect(formCoachTeaches(fe, registry: registry), isTrue, reason: fe.name);
        expect(showRepCountFor(fe, spec: coachSpecFor(registry, fe)), isFalse,
            reason: '${fe.name}: authored beta rows never show a count');
      }
    });
  });

  group('cue text', () {
    test('validateCueIds accepts the shipped registry', () {
      validateCueIds(registry, registryCueIds);
    });

    test('no unused registry cue keys', () {
      final used = {
        for (final e in registry.exercises)
          for (final r in e.rules) r.cueId,
      };
      expect(registryCueIds, used);
    });

    for (final locale in const ['en', 'ru']) {
      test('every cue has real $locale text, none shared', () async {
        final l10n = await AppLocalizations.delegate.load(Locale(locale));
        final seen = <String, String>{};
        for (final id in registryCueIds) {
          final text = registryCueText(l10n, id);
          expect(text, isNotNull, reason: id);
          expect(text!.trim(), isNotEmpty, reason: id);
          expect(text, isNot(id));
          expect(seen[text], isNull, reason: '$id duplicates ${seen[text]}');
          seen[text] = id;
        }
        expect(registryCueText(l10n, 'nope.unknown'), isNull);
      });
    }

    test('wording stays neutral: no injury or back claims', () async {
      const banned = [
        'injur', 'pain', 'hurt', 'back', 'spine', 'damage', 'risk',
        'трав', 'бол', 'спин', 'вред', 'риск',
      ];
      for (final locale in const ['en', 'ru']) {
        final l10n = await AppLocalizations.delegate.load(Locale(locale));
        for (final id in registryCueIds) {
          final text = registryCueText(l10n, id)!.toLowerCase();
          for (final b in banned) {
            expect(text.contains(b), isFalse, reason: '$locale $id has "$b"');
          }
        }
      }
    });
  });

  group('bentOverRow', () {
    test('good cycle counts a rep with no cue; hinge and drift faults', () {
      final s = spec('bentOverRow');
      final good = cycle((v, t) => rowFrame(v, ts: t), 165, 90);
      expect(countReps(s, [...good, ...cycle((v, t) => rowFrame(v, ts: t), 165, 90, startMs: 5000)]), 2);
      expect(run(s, good), isEmpty);
      expectAdvisoryCue(last(s, [rowFrame(165), rowFrame(165, hip: 170)]),
          'bentOverRow.hinge');
      expectAdvisoryCue(last(s, [rowFrame(165), rowFrame(165, hip: 145)]),
          'bentOverRow.drift');
    });
  });

  group('lateralRaise', () {
    test('good cycle counts a rep; too high, arms bent', () {
      final s = spec('lateralRaise');
      final good = cycle((v, t) => raiseFrame(v, ts: t), 15, 85);
      expect(countReps(s, good), 1);
      expect(run(s, good), isEmpty);
      expectAdvisoryCue(last(s, [raiseFrame(15), raiseFrame(120)]),
          'lateralRaise.too_high');
      expectAdvisoryCue(
          last(s, [raiseFrame(15), raiseFrame(110, elbow: 100)]),
          'lateralRaise.arms_bent');
    });
  });

  group('tricepDip / goodMorning / stepUp / pullUp', () {
    test('tricepDip: good depth counts, too deep cues', () {
      final s = spec('tricepDip');
      final good = cycle((v, t) => dipFrame(v, ts: t), 170, 90);
      expect(countReps(s, good), 1);
      expect(run(s, good), isEmpty);
      expectAdvisoryCue(last(s, [dipFrame(170), dipFrame(40)]),
          'tricepDip.too_deep');
    });

    test('goodMorning: hinge counts, squatting and over-depth cue', () {
      final s = spec('goodMorning');
      final good = cycle((v, t) => morningFrame(v, ts: t), 175, 105);
      expect(countReps(s, good), 1);
      expect(run(s, good), isEmpty);
      expectAdvisoryCue(
          last(s, [morningFrame(175), morningFrame(105, knee: 110)]),
          'goodMorning.knees');
      expectAdvisoryCue(last(s, [morningFrame(175), morningFrame(60)]),
          'goodMorning.too_deep');
    });

    test('stepUp: rep counts, lean cues', () {
      final s = spec('stepUp');
      final good = cycle((v, t) => stepFrame(v, ts: t), 170, 95);
      expect(countReps(s, good), 1);
      expect(run(s, good), isEmpty);
      expectAdvisoryCue(
          last(s, [stepFrame(170), stepFrame(100, lean: 55)]), 'stepUp.lean');
    });

    test('pullUp: rep counts, partial rep cues, hang is quiet', () {
      final s = spec('pullUp');
      final good = cycle((v, t) => pullFrame(v, ts: t), 170, 60);
      expect(countReps(s, good), 1);
      expect(run(s, good), isEmpty);
      expectAdvisoryCue(
          last(s, [pullFrame(170), pullFrame(60, noseBelowWrist: 0.12)]),
          'pullUp.partial_rep');
      expect(
          last(s, [pullFrame(170, noseBelowWrist: 0.2)]), isNull,
          reason: 'hanging with the nose below the wrist is normal');
    });
  });

  group('holds', () {
    test('plank: line in band is quiet, sag and pike cue', () {
      final s = spec('plank');
      expect(run(s, [plankFrame(0.0), plankFrame(0.015)]), isEmpty);
      expectAdvisoryCue(last(s, [plankFrame(0.0), plankFrame(0.06)]), 'plank.sag');
      expectAdvisoryCue(last(s, [plankFrame(0.0), plankFrame(-0.06)]), 'plank.pike');
    });

    test('gluteBridge: bridge band is quiet, low hips and odd knees cue', () {
      final s = spec('gluteBridge');
      expect(last(s, [bridgeFrame(172)]), isNull);
      expectAdvisoryCue(last(s, [bridgeFrame(135)]), 'gluteBridge.lift_hips');
      expectAdvisoryCue(
          last(s, [bridgeFrame(160, knee: 150)]), 'gluteBridge.knee_setup');
    });

    for (final t in const [
      ('plank', FormExercise.plank),
      ('gluteBridge', FormExercise.gluteBridge),
    ]) {
      test('${t.$1}: hold timer runs in band, pauses out, never counts reps',
          () async {
        PoseFrame good(int ts) => t.$1 == 'plank'
            ? plankFrame(0.0, ts: ts)
            : bridgeFrame(172, ts: ts);
        PoseFrame bad(int ts) => t.$1 == 'plank'
            ? plankFrame(0.12, ts: ts)
            : bridgeFrame(120, ts: ts);
        final frames = <PoseFrame>[
          for (var ms = 0; ms <= 3000; ms += 100) good(ms),
          for (var ms = 3100; ms <= 4000; ms += 100) bad(ms),
        ];
        final svc = MockPoseDetectorService(frames);
        final container = ProviderContainer(overrides: [
          poseDetectorServiceProvider.overrideWithValue(svc),
          voiceCoachProvider.overrideWithValue(MockVoiceCoach()),
          coachRegistrySnapshotProvider.overrideWithValue(registry),
          selectedExerciseProvider.overrideWith((_) => t.$2),
        ]);
        addTearDown(container.dispose);
        container.read(repSessionControllerProvider);
        await svc.start();
        await pumpEventQueue();
        final s = container.read(repSessionControllerProvider);
        expect(s.repCount, 0);
        expect(s.holdMs, inInclusiveRange(2500, 3100));
        await svc.dispose();
      });
    }
  });
}
