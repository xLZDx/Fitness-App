import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/exercise_name_matcher.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/visual_equipment/data/gemini_equipment_service.dart'
    show GeminiVisualEquipmentService;
import 'package:fitness_app/features/visual_equipment/data/machine_card.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_card_repository.dart';
import 'package:fitness_app/features/visual_equipment/data/machine_describer.dart';
import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_match.dart';
import 'package:fitness_app/features/visual_equipment/data/visual_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/machine_card_providers.dart';
import 'package:fitness_app/features/visual_equipment/state/visual_equipment_providers.dart';

/// Never answers. Models the failure the timeout exists for: not a call that
/// throws, a call that simply does not come back.
class _HangingService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) =>
      Completer<List<VisualMatch>>().future;
}

/// Genuinely finds nothing.
///
/// `MockVisualEquipmentService(fixedResults: const [])` does NOT do this — an
/// empty `fixedResults` falls through to its deterministic seed branch and
/// returns squat_rack/barbell, which is a catalogue HIT and the opposite of
/// what these tests are about.
class _EmptyService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      const [];
}

class _ThrowingService implements VisualEquipmentService {
  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async =>
      throw const VisualEquipmentException('model missing');
}

/// Answers, but not immediately -- stands in for a real
/// `GeminiVisualEquipmentService` call that took long enough to cross its own
/// `kSlowInferenceThreshold` and still succeeded. See the regression test
/// below: MVP1.G3 Step 10B found this exact shape live, on a real device --
/// `recogniseTimeoutProvider` and `GeminiVisualEquipmentService.
/// kSlowInferenceThreshold` were both 20s, and since this controller's
/// `.timeout()` wraps resize/index-load work that starts before that
/// service-internal stopwatch does, the outer clamp always fired first. The
/// user was shown a timeout card for an answer that, moments later, arrived.
class _DelayedService implements VisualEquipmentService {
  _DelayedService(this.delay, this.matches);

  final Duration delay;
  final List<VisualMatch> matches;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) =>
      Future.delayed(delay, () => matches);
}

/// Describes nothing, slowly enough to outlive the timeout.
class _HangingDescriber implements MachineDescriber {
  @override
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) =>
      Completer<MachineCard?>().future;
}

/// Answers, but not immediately -- the shape of the race this file's
/// `describeTimeoutProvider` amendment exists to close. See the test using
/// this below.
class _DelayedDescriber implements MachineDescriber {
  _DelayedDescriber(this.delay, this.card);

  final Duration delay;
  final MachineCard? card;

  @override
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) =>
      Future.delayed(delay, () => card);
}

class _ThrowingDescriber implements MachineDescriber {
  @override
  Future<MachineCard?> describe({
    required String path,
    String languageCode = 'ru',
    String? recognisedAs,
    double? confidence,
    DateTime? now,
  }) async =>
      throw Exception('describer outage');
}

MachineCard _card() => MachineCard(
      id: 'unknown_1',
      name: 'Some machine',
      summary: 'A machine the catalogue does not have yet.',
      uses: const ['general'],
      firstSeenAt: DateTime(2026, 1, 1),
    );

void main() {
  ProviderContainer containerWith(List<Override> overrides) {
    final c = ProviderContainer(overrides: [
      // Short enough that proving the timeout fires costs milliseconds, not
      // the twenty/thirty-five real seconds production waits. Kept in the
      // same relative order as production (recognise < describe) even though
      // nothing in this file depends on that ordering directly -- a test
      // relying on the wrong one being larger would itself be the kind of
      // silent drift this pair of providers exists to prevent.
      recogniseTimeoutProvider
          .overrideWithValue(const Duration(milliseconds: 40)),
      describeTimeoutProvider
          .overrideWithValue(const Duration(milliseconds: 80)),
      ...overrides,
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('VisualEquipmentController outcomes', () {
    test('a catalogue hit is an answer, and the describer is never asked',
        () async {
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(
          MockVisualEquipmentService(fixedResults: const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          ]),
        ),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');

      final result = c.read(visualEquipmentControllerProvider).requireValue;
      // FITAPP-EQUIP-ACC-2026-09-17: a cloud match, even alone, is no longer
      // "confident" -- it settles as alternatives until a real end-to-end
      // accuracy measurement exists. The describer is still skipped: the
      // catalogue matched something, which is the actual condition this test
      // name describes.
      expect(result.outcome, ScanOutcome.alternatives);
      expect(result.matches.single.equipmentId, 'leg_press');
    });

    test('nothing in the catalogue but nameable is UNKNOWN', () async {
      // "Not in our catalogue yet" — the machine card is the honest answer.
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_EmptyService()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: _card())),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/abcd.jpg');

      expect(c.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.unknown);
      expect(c.read(lastMachineCardProvider), isNotNull);
    });

    test(
        'G-C/F016: the saved/last-scan card keeps the model\'s RAW uses[] — '
        'validation is a render-time concern, not a write-time one', () async {
      // GPT-PM's round-19 review caught why write-time filtering was unsafe:
      // a one-time `ref.read` of the matcher, done while the catalogue could
      // still be loading (an empty, fail-closed matcher), would PERMANENTLY
      // destroy a legitimate suggestion before `MachineCardView` ever got a
      // chance to validate it against the real, later-loaded catalogue. So
      // `_describeInstead` must store exactly what the describer returned,
      // unfiltered, with no path where a matcher's state at describe-time can
      // ever lose data. `MachineCardView`'s own tests (machine_card_flow_test
      // .dart) prove the actual filtering; this proves this layer does NOT
      // do it, which is equally load-bearing given the round-19 finding.
      final rawCard = MachineCard(
        id: 'unknown_1',
        name: 'Some machine',
        summary: 'A machine the catalogue does not have yet.',
        uses: const ['Leg Press for quads', 'Invented Machine Twist'],
        firstSeenAt: DateTime(2026, 1, 1),
      );
      final repo = MockMachineCardRepository();
      addTearDown(repo.dispose);
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_EmptyService()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: rawCard)),
        machineCardRepositoryProvider.overrideWithValue(repo),
        // Deliberately an empty matcher (as if the catalogue were still
        // loading) — if `_describeInstead` filtered against this, both
        // lines would vanish. They must not: this provider is never read
        // for the write path any more.
        exerciseNameMatcherProvider
            .overrideWithValue(ExerciseNameMatcher(const [])),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/abcd.jpg');

      final saved = c.read(lastMachineCardProvider);
      expect(saved, isNotNull);
      expect(saved!.uses, rawCard.uses);
      final stored = await repo.list();
      expect(stored.single.uses, rawCard.uses);
    });

    test('nothing in the catalogue and unnameable is NO EQUIPMENT', () async {
      // Distinct from unknown on purpose: telling someone pointing at a wall
      // that their machine is missing from our catalogue is a lie about our
      // own data.
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_EmptyService()),
        machineDescriberProvider
            .overrideWithValue(MockMachineDescriber(card: null)),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/abcd.jpg');

      expect(c.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.noEquipment);
    });

    test('a describer outage does not become "not in the catalogue"',
        () async {
      // An outage is not evidence that the user photographed a machine.
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_EmptyService()),
        machineDescriberProvider.overrideWithValue(_ThrowingDescriber()),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/abcd.jpg');

      final state = c.read(visualEquipmentControllerProvider);
      expect(state.hasError, isFalse,
          reason: 'the additive second question must not fail the scan');
      expect(state.requireValue.outcome, ScanOutcome.noEquipment);
    });

    test('a recognition that never returns times out instead of spinning',
        () async {
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_HangingService()),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/hangs.jpg');

      expect(c.read(visualEquipmentControllerProvider).requireValue.outcome,
          ScanOutcome.timeout);
      expect(c.read(visualEquipmentControllerProvider).isLoading, isFalse,
          reason: 'the whole point: no infinite spinner');
    });

    test('a hanging describer also lands on a settled state', () async {
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_EmptyService()),
        machineDescriberProvider.overrideWithValue(_HangingDescriber()),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/abcd.jpg');

      final state = c.read(visualEquipmentControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.requireValue.outcome, ScanOutcome.noEquipment);
    });

    test(
        'a description answering after the recognition-timeout-equivalent '
        'window still survives, because it has its own longer budget',
        () async {
      // The exact regression GPT-PM's GO review on the machine-description
      // slice caught before this code existed: reusing recogniseTimeoutProvider
      // (here, 40ms) for the describer call would have discarded this 60ms
      // answer as a timeout. With describeTimeoutProvider (80ms) wired to only
      // this call site, it survives instead.
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_EmptyService()),
        machineDescriberProvider.overrideWithValue(
          _DelayedDescriber(const Duration(milliseconds: 60), _card()),
        ),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/abcd.jpg');

      final state = c.read(visualEquipmentControllerProvider);
      expect(state.requireValue.outcome, ScanOutcome.unknown,
          reason: 'a 60ms answer must survive a 40ms recognise timeout when '
              'describeTimeoutProvider (80ms) is what actually gates it');
      expect(c.read(lastMachineCardProvider), isNotNull);
    });

    test(
        'a recognition answering after the slow-inference-equivalent window '
        'still survives, because the outer timeout has real margin over it',
        () async {
      // MVP1.G3 Step 10B regression. Real production values were
      // recogniseTimeoutProvider=20s and
      // GeminiVisualEquipmentService.kSlowInferenceThreshold=20s -- equal,
      // and since this controller's own `.timeout()` starts counting before
      // the service's internal stopwatch does (it wraps resize/index-load
      // too), the outer clamp always won that race. Scaled down 1000x here
      // (60ms outer / 45ms answer) to prove the SAME shape without spending
      // real seconds: a slow-but-successful answer must render as a real
      // result, never as ScanOutcome.timeout, whenever the outer timeout
      // genuinely has margin over how long the answer took.
      final c = containerWith([
        recogniseTimeoutProvider
            .overrideWithValue(const Duration(milliseconds: 60)),
        visualEquipmentServiceProvider.overrideWithValue(
          _DelayedService(const Duration(milliseconds: 45), const [
            VisualMatch(equipmentId: 'leg_press', confidence: 0.9),
          ]),
        ),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/slow-but-real.jpg');

      final state = c.read(visualEquipmentControllerProvider);
      expect(state.requireValue.outcome, isNot(ScanOutcome.timeout),
          reason: 'a 45ms answer must survive a 60ms outer timeout -- if '
              'this becomes ScanOutcome.timeout, recogniseTimeoutProvider '
              'has lost its margin over a slow-but-successful call again');
      expect(state.requireValue.matches, isNotEmpty);
    });

    test('a thrown recognition error is a rendered outcome, not a raw error',
        () async {
      final c = containerWith([
        visualEquipmentServiceProvider.overrideWithValue(_ThrowingService()),
      ]);

      await c
          .read(visualEquipmentControllerProvider.notifier)
          .classifyFilePath('/tmp/a.jpg');

      final state = c.read(visualEquipmentControllerProvider);
      expect(state.hasError, isFalse,
          reason: 'the screen renders an outcome; the exception goes to logs');
      expect(state.requireValue.outcome, ScanOutcome.failed);
      expect(state.requireValue.isRetryable, isTrue);
    });
  });

  group('recogniseTimeoutProvider / kSlowInferenceThreshold invariant', () {
    test(
        'the outer recognise timeout has real margin over the slow-inference '
        'threshold it wraps', () {
      // MVP1.G3 Step 10B: the two were found live, on a real device, exactly
      // equal (both 20s) -- structurally impossible for a real slow-but-
      // successful answer to ever reach the user, because this provider's
      // `.timeout()` wraps GeminiVisualEquipmentService.classifyFile()
      // entirely (resize/index-load included), so it starts counting before
      // that service's own stopwatch does and therefore always fires first
      // or at the same instant. A minimum 5s margin, not just >, per GPT-PM's
      // review of the fix: "not merely 20.001s."
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final outer = container.read(recogniseTimeoutProvider);
      const inner = GeminiVisualEquipmentService.kSlowInferenceThreshold;
      expect(
        outer - inner,
        greaterThanOrEqualTo(const Duration(seconds: 5)),
        reason: 'recogniseTimeoutProvider ($outer) must stay at least 5s '
            'above GeminiVisualEquipmentService.kSlowInferenceThreshold '
            '($inner), or a successful-but-slow answer is shown to the user '
            'as a timeout again -- see the regression test above and '
            'core/DECISION_LOG.md, MVP1.G3 Step 10B',
      );
    });
  });
}
