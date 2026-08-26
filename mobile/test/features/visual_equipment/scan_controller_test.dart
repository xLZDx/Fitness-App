import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/machine_card.dart';
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
      expect(result.outcome, ScanOutcome.confident);
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
}
