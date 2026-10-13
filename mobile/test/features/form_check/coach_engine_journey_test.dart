// J7: the shipped coach registry driven by synthetic landmark sequences, for
// all eight authored exercises. Complements (does not repeat):
//  * coach_registry_content_test.dart: single good/fault checks per exercise,
//    cue-text catalogue, hold timer through the controller (plank, bridge);
//  * generic_coach_engine_test.dart: engine mechanics on a synthetic registry.
// Added here: a faulty FULL cycle yields the expected advisory cue id with real
// ru and en text, never speech, and never fails or removes the rep; and a
// low-visibility sequence yields no verdict at all (no count, no cue).
import 'package:fitness_app/features/form_check/data/coach_registry.dart';
import 'package:fitness_app/features/form_check/data/coach_signal.dart';
import 'package:fitness_app/features/form_check/data/coach_spec.dart';
import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/generic_rule_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_gate.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/registry_cue_text.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'coach_registry_content_test.dart'
    show
        bridgeFrame,
        countReps,
        cycle,
        dipFrame,
        morningFrame,
        plankFrame,
        pullFrame,
        raiseFrame,
        rowFrame,
        stepFrame;

typedef _Build = PoseFrame Function(double v, int ts);

class _Case {
  const _Case(this.id, this.good, this.faulty, this.rest, this.active,
      this.activeFaulty, this.cueId);
  final String id;
  final _Build good;
  final _Build faulty;
  final double rest;
  final double active;
  final double activeFaulty;
  final String cueId;
}

final _repCases = <_Case>[
  _Case('bentOverRow', (v, t) => rowFrame(v, ts: t),
      (v, t) => rowFrame(v, hip: 170, ts: t), 165, 90, 90, 'bentOverRow.hinge'),
  _Case('lateralRaise', (v, t) => raiseFrame(v, ts: t),
      (v, t) => raiseFrame(v, elbow: 100, ts: t), 15, 85, 110,
      'lateralRaise.arms_bent'),
  _Case('tricepDip', (v, t) => dipFrame(v, ts: t), (v, t) => dipFrame(v, ts: t),
      170, 90, 40, 'tricepDip.too_deep'),
  _Case('goodMorning', (v, t) => morningFrame(v, ts: t),
      (v, t) => morningFrame(v, knee: 110, ts: t), 175, 105, 105,
      'goodMorning.knees'),
  _Case('stepUp', (v, t) => stepFrame(v, ts: t),
      (v, t) => stepFrame(v, lean: 55, ts: t), 170, 95, 95, 'stepUp.lean'),
  _Case('pullUp', (v, t) => pullFrame(v, ts: t),
      (v, t) => pullFrame(v, noseBelowWrist: 0.12, ts: t), 170, 60, 60,
      'pullUp.partial_rep'),
];

PoseFrame _dim(PoseFrame f, [double likelihood = 0.2]) => PoseFrame(
      timestampMs: f.timestampMs,
      landmarks: {
        for (final e in f.landmarks.entries)
          e.key: PoseLandmark(
              type: e.key, x: e.value.x, y: e.value.y, likelihood: likelihood),
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoachRegistry registry;
  late AppLocalizations en;
  late AppLocalizations ru;
  CoachSpec spec(String id) => registry.byId(id)!;

  setUpAll(() async {
    registry = await CoachRegistry.load();
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  /// Everything the classifier says over a sequence, plus the voice coach's
  /// output when each feedback is offered to it.
  Future<(List<FormFeedback>, List<String>)> observe(
      CoachSpec s, List<PoseFrame> frames) async {
    final c = GenericRuleClassifier(s);
    final voice = MockVoiceCoach(resolveText: (_) => 'spoken');
    final out = <FormFeedback>[];
    for (final f in frames) {
      final fb = c.evaluate(f);
      if (fb != null) {
        out.add(fb);
        await voice.cue(fb);
      }
    }
    return (out, voice.spoken);
  }

  void expectCueHasBothLanguages(String cueId) {
    for (final l10n in [en, ru]) {
      final text = registryCueText(l10n, cueId);
      expect(text, isNotNull, reason: '$cueId ${l10n.localeName}');
      expect(text!.trim(), isNotEmpty, reason: '$cueId ${l10n.localeName}');
    }
    expect(registryCueText(en, cueId), isNot(registryCueText(ru, cueId)),
        reason: '$cueId: ru and en must be different texts');
  }

  for (final k in _repCases) {
    group(k.id, () {
      test('good cycle: counted, no cue, no speech', () async {
        final s = spec(k.id);
        final frames = cycle(k.good, k.rest, k.active);
        expect(countReps(s, frames), 1);
        final (fb, spoken) = await observe(s, frames);
        expect(fb, isEmpty);
        expect(spoken, isEmpty);
      });

      test('faulty cycle: advisory cue id with ru+en text, never spoken, rep kept',
          () async {
        final s = spec(k.id);
        final frames = cycle(k.faulty, k.rest, k.activeFaulty);
        final (fb, spoken) = await observe(s, frames);
        final mine = fb.where((f) => f.cueId == k.cueId).toList();
        expect(mine, isNotEmpty, reason: 'expected ${k.cueId}, got ${fb.map((f) => f.cueId).toSet()}');
        for (final f in fb) {
          expect(f.cueKey, FormCueKey.registry);
          expect(f.severity, 0, reason: 'authored rows are advisory: no failure');
          expect(f.advisory, isTrue);
        }
        expect(spoken, isEmpty, reason: 'advisory cues are on-screen only');
        expectCueHasBothLanguages(k.cueId);
        expect(countReps(s, frames), 1,
            reason: 'an advisory cue must not remove or fail the rep');
      });

      test('low visibility: no cue, no count, gate does not accept the frames',
          () async {
        final s = spec(k.id);
        // Both the good and the faulty movement, seen at likelihood 0.2.
        for (final frames in [
          cycle(k.good, k.rest, k.active),
          cycle(k.faulty, k.rest, k.activeFaulty),
        ]) {
          final dim = [for (final f in frames) _dim(f)];
          final (fb, spoken) = await observe(s, dim);
          expect(fb, isEmpty);
          expect(spoken, isEmpty);
          expect(countReps(s, dim), 0);
          final need = coachRequiredLandmarks(s);
          for (final f in dim) {
            expect(gatePose(coachFrameFor(s, f), need).isScorable, isFalse,
                reason: '${k.id} @${f.timestampMs}');
          }
        }
      });
    });
  }

  group('plank (hold)', () {
    test('faulty sag and pike: advisory cues with ru+en text, never spoken', () async {
      final s = spec('plank');
      final sag = [for (var t = 0; t < 2000; t += 100) plankFrame(0.06, ts: t)];
      final pike = [for (var t = 0; t < 2000; t += 100) plankFrame(-0.06, ts: t)];
      for (final (frames, cue) in [(sag, 'plank.sag'), (pike, 'plank.pike')]) {
        final (fb, spoken) = await observe(s, frames);
        expect(fb.map((f) => f.cueId).toSet(), {cue});
        expect(fb.every((f) => f.severity == 0 && f.advisory), isTrue);
        expect(spoken, isEmpty);
        expectCueHasBothLanguages(cue);
      }
    });

    test('low visibility: no verdict', () async {
      final s = spec('plank');
      final dim = [for (var t = 0; t < 2000; t += 100) _dim(plankFrame(0.06, ts: t))];
      final (fb, spoken) = await observe(s, dim);
      expect(fb, isEmpty);
      expect(spoken, isEmpty);
      for (final f in dim) {
        expect(gatePose(coachFrameFor(s, f), coachRequiredLandmarks(s)).isScorable,
            isFalse);
      }
    });
  });

  group('gluteBridge (hold)', () {
    test('faulty low hips: advisory cue with ru+en text, never spoken', () async {
      final s = spec('gluteBridge');
      final low = [for (var t = 0; t < 2000; t += 100) bridgeFrame(135, ts: t)];
      final (fb, spoken) = await observe(s, low);
      expect(fb.map((f) => f.cueId).toSet(), {'gluteBridge.lift_hips'});
      expect(fb.every((f) => f.severity == 0 && f.advisory), isTrue);
      expect(spoken, isEmpty);
      expectCueHasBothLanguages('gluteBridge.lift_hips');
    });

    test('low visibility: no verdict', () async {
      final s = spec('gluteBridge');
      final dim = [for (var t = 0; t < 2000; t += 100) _dim(bridgeFrame(135, ts: t))];
      final (fb, _) = await observe(s, dim);
      expect(fb, isEmpty);
      for (final f in dim) {
        expect(gatePose(coachFrameFor(s, f), coachRequiredLandmarks(s)).isScorable,
            isFalse);
      }
    });
  });

  test('every authored rule is advisory under an authored/beta provenance (nothing can fault)',
      () {
    for (final e in registry.exercises) {
      for (final r in e.rules) {
        if (!r.advisory) {
          expect(e.provenance.kind, CoachProvenanceKind.measured, reason: '${e.id}.${r.id}');
        }
      }
      expect(GenericRuleClassifier(e).canFault, isFalse, reason: e.id);
    }
  });

  test('frame support: PoseFrame helpers used here are consistent', () {
    // Positive control for the low-visibility tests: the undimmed frames ARE
    // scorable, so "not scorable" above is caused by the likelihood alone.
    final s = spec('plank');
    final f = plankFrame(0.0, ts: 0);
    expect(gatePose(coachFrameFor(s, f), coachRequiredLandmarks(s)).isScorable, isTrue);
  });
}
