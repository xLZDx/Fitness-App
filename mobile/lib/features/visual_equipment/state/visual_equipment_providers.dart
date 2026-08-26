import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/state/settings_providers.dart';
import '../../equipment/state/equipment_providers.dart';
import '../data/machine_card.dart';
import '../data/machine_text_anchor.dart';
import '../data/mlkit_text_recogniser.dart';
import '../data/scan_outcome.dart';
import '../data/visual_equipment_match.dart';
import '../data/visual_equipment_service.dart';
import 'machine_card_providers.dart';

final visualEquipmentServiceProvider =
    Provider<VisualEquipmentService>((_) {
  return MockVisualEquipmentService();
});

/// B5b. Reads the machine's own printed name. Overridden in `main.dart` with
/// the ML Kit implementation; null here so the default (and every test that
/// does not care) runs the classifier path alone.
final machineTextRecogniserProvider =
    Provider<MachineTextRecogniser?>((_) => null);

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

/// How long the SECOND question -- "what is this, if it's not in our
/// catalogue" -- may run before the user is told it did not answer.
///
/// Deliberately its OWN provider, not a reuse of [recogniseTimeoutProvider].
/// GPT-PM's G1 GO review of the `machine_describer.dart` migration caught
/// that reusing the 20s recognition budget here would have silently defeated
/// `GeminiMachineDescriber.timeout`'s own 30s fix for the client/server
/// timeout race (see that class's own doc comment): this call site wraps the
/// WHOLE `describe()` call, timeout included, in a further `.timeout()` of
/// its own, so a 20s outer clamp fires before the describer's internal 30s
/// deadline ever gets a chance to. 35s keeps the invariant this app now
/// relies on across three layers:
///
///   server model deadline (20s, `ai_machine_description.ts`)
/// < describer/service deadline (30s, `GeminiMachineDescriber.timeout`)
/// < this controller deadline (35s)
///
/// A test can still prove the timeout fires without spending 35 real seconds
/// doing it, exactly like [recogniseTimeoutProvider] — see
/// `scan_controller_test.dart`.
final describeTimeoutProvider =
    Provider<Duration>((_) => const Duration(seconds: 35));

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

      // B5b — the text anchor runs FIRST, because when it fires it is the
      // better signal by a wide margin.
      //
      // Measured on the operator's 30 gym photos (2026-08-07): 18 carry the
      // machine's name legibly on its own shroud, and the v2 classifier scored
      // 5 of those same 18 on top-3. Reading what Nautilus already printed
      // beats inferring it from shape.
      //
      // It answers rarely and is silent otherwise — the opposite failure mode
      // to a softmax that always returns something. Only a SINGLE unambiguous
      // reading short-circuits: `matchMachineText` hands back several
      // candidates when the text names several machines, and those go on to
      // the classifier rather than being resolved by picking one.
      final anchored = await _anchorOnPrintedText(path, timeout);
      if (anchored != null) {
        state = AsyncValue.data(anchored);
        return;
      }

      final service = ref.read(visualEquipmentServiceProvider);
      final matches =
          await service.classifyFile(path: path).timeout(timeout);
      // Read straight after the awaited call, which is what the flag
      // describes. Only one scan runs at a time, so there is no second call
      // to have overwritten it in between. Services without a fallback do not
      // implement the capability and simply have nothing to report.
      final result = ScanResult.fromMatches(
        matches,
        answeredOffline: service is FallbackReportingRecogniser &&
            service.lastAnsweredOffline,
      );
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
      final named =
          await _describeInstead(path, ref.read(describeTimeoutProvider));
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

  /// B5b — try to identify the machine from text printed ON it.
  ///
  /// Returns a settled result ONLY when the reading is unambiguous; null in
  /// every other case, including "no recogniser configured", "no text in the
  /// frame", "the text named nothing we know" and "the text named more than
  /// one machine". Each of those hands the photo on to the classifier, which
  /// is the point: this anchor adds answers, it never removes them.
  ///
  /// A failure here is swallowed on purpose and logged. OCR is an addition to
  /// a path that already worked; a text-recognition fault must not turn a scan
  /// that the classifier could have answered into an error.
  Future<ScanResult?> _anchorOnPrintedText(
      String path, Duration timeout) async {
    final recogniser = ref.read(machineTextRecogniserProvider);
    if (recogniser == null) return null;
    final String text;
    try {
      text = await recogniser.readText(path).timeout(timeout);
    } catch (e) {
      debugPrint('text anchor: could not read text: $e');
      return null;
    }
    if (text.trim().isEmpty) return null;

    // The catalogue the rest of the app uses, so the anchor cannot name a
    // machine that has no page. Already loaded by the time a scan runs; if it
    // is not, skip rather than block the scan on it.
    final catalogue = ref.read(equipmentListProvider).valueOrNull;
    if (catalogue == null) return null;

    final hits = matchMachineText(
      text,
      catalogue: {for (final e in catalogue) e.id: e.name},
    );
    // Exactly one, or nothing. Several candidates means the text could not
    // decide, and resolving that by taking the first is the defect this
    // returns null to avoid.
    if (hits.length != 1) return null;

    final hit = hits.single;
    debugPrint('text anchor: "${hit.matchedPhrase}" -> ${hit.equipmentId}');
    return ScanResult.confident([
      VisualMatch(
        equipmentId: hit.equipmentId,
        confidence: hit.confidence,
        labelHint: hit.matchedPhrase,
        // The only place this is set. It is what licenses the Scan tab to
        // print "read on the machine: ..." next to the answer.
        source: MatchSource.printedText,
      ),
    ]);
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
