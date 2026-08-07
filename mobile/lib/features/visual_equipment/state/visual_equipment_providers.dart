import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../data/machine_card.dart';
import '../data/scan_outcome.dart';
import '../data/visual_equipment_service.dart';
import 'machine_card_providers.dart';

final visualEquipmentServiceProvider =
    Provider<VisualEquipmentService>((_) {
  return MockVisualEquipmentService();
});

/// How long recognition may run before the user is told it did not answer.
///
/// The call used to be awaited unbounded: a request that never returned — not
/// one that failed, one that simply hung — left the spinner up for good, with
/// no retry and no way out but leaving the screen. That is the "no infinite
/// spinner" rule, and it had no representation in the state at all.
///
/// 20s is generous for a cloud round trip on gym wifi and still a wait rather
/// than a hang. A provider, not a constant, so a test can prove the timeout
/// fires without spending twenty real seconds doing it.
final recogniseTimeoutProvider =
    Provider<Duration>((_) => const Duration(seconds: 20));

class VisualEquipmentController extends Notifier<AsyncValue<ScanResult>> {
  @override
  AsyncValue<ScanResult> build() =>
      const AsyncValue.data(ScanResult(outcome: ScanOutcome.noEquipment));

  /// The file route decodes JPEG + EXIF rotation correctly
  /// (see VisualEquipmentService — the raw-bytes route is gone).
  Future<void> classifyFilePath(String path) async {
    final timeout = ref.read(recogniseTimeoutProvider);
    state = const AsyncValue.loading();
    try {
      // Inside the try. Every statement between "state = loading" and the
      // catch has to be covered by it, or the one that throws leaves the
      // spinner up permanently — the exact failure this gate exists to
      // remove, reintroduced by a line that looks like bookkeeping.
      ref.read(lastMachineCardProvider.notifier).clear();
      final matches = await ref
          .read(visualEquipmentServiceProvider)
          .classifyFile(path: path)
          .timeout(timeout);
      final result = ScanResult.fromMatches(matches);
      // In the catalog → the catalog answers, and it answers immediately.
      // Operator: *"если есть в каталоге то показывать из каталога сразу"*.
      if (result.outcome != ScanOutcome.noEquipment) {
        state = AsyncValue.data(result);
        return;
      }
      // Nothing in the catalogue matched. Whether that is "not in our
      // catalogue" or "there is no machine in this photo" is the describer's
      // answer to give, not ours to assume — so the state is only settled
      // after asking.
      final named = await _describeInstead(path, timeout);
      state = AsyncValue.data(
          named ? const ScanResult.unknown() : const ScanResult.noEquipment());
    } on TimeoutException {
      state = const AsyncValue.data(ScanResult.timeout());
    } catch (e, st) {
      // Kept as an AsyncError as well as an outcome: the error and stack are
      // what a bug report needs, while the outcome is what the screen renders.
      debugPrint('recognition failed: $e\n$st');
      state = const AsyncValue.data(ScanResult.failed());
    }
  }

  /// Not in the catalog. Ask the model what the thing actually is, show the
  /// user that, and keep the card so the missing clip has a name and a photo
  /// attached to it.
  ///
  /// Returns whether it could name anything — the signal that separates
  /// "not in our catalogue" (state 8) from "no machine in this frame"
  /// (state 10). A describer failure counts as "could not name it": an
  /// outage is not evidence that the user photographed a machine.
  Future<bool> _describeInstead(String path, Duration timeout) async {
    final MachineCard? card;
    try {
      card = await ref
          .read(machineDescriberProvider)
          .describe(
            path: path,
            languageCode: ref.read(effectiveLanguageCodeProvider),
          )
          .timeout(timeout);
    } catch (e) {
      // Additive question, already past the point where recognition itself
      // answered — a failure here must not turn a finished scan into an error.
      debugPrint('could not describe the machine: $e');
      return false;
    }
    if (card == null) return false;
    ref.read(lastMachineCardProvider.notifier).set(card);
    try {
      await ref.read(machineCardRepositoryProvider).save(card);
    } catch (e) {
      // The user is looking at the card either way; only the record failed.
      // Losing one row of "what people photograph" is not worth taking the
      // answer off their screen.
      debugPrint('could not save the machine card: $e');
    }
    return true;
  }
}

final visualEquipmentControllerProvider =
    NotifierProvider<VisualEquipmentController, AsyncValue<ScanResult>>(
  VisualEquipmentController.new,
);
