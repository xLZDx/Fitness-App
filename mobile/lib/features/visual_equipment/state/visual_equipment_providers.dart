import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/debug/g3_step10b_probe.dart';
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
/// 30s is generous for a cloud round trip on gym wifi and still a wait rather
/// than a hang. A provider, not a constant, so a test can prove the timeout
/// fires without spending thirty real seconds doing it.
///
/// MUST stay strictly greater than
/// [GeminiVisualEquipmentService.kSlowInferenceThreshold] with real margin —
/// this wraps the ENTIRE `classifyFile()` call, resize and index-load
/// included, which start before that inner stopwatch does. A prior 20s/20s
/// pairing meant the outer clamp always fired first: `.timeout()` does not
/// cancel the underlying future, so the inner "successful but slow" telemetry
/// call still fired moments later, but the user had already been shown the
/// timeout card for an answer that in fact arrived. Found live on a real S8
/// device during MVP1.G3 Step 10B (`core/DECISION_LOG.md`), which is also
/// where `_recogniseTimeoutInvariantMargin` below is enforced as a test.
final recogniseTimeoutProvider =
    Provider<Duration>((_) => const Duration(seconds: 30));

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
  /// Back to the untouched state -- what the Scan screen's "Scan again" does
  /// (SCAN-G1, core/SCAN_G1_SCOPE.md R4): the match card leaves, the
  /// viewfinder's hint returns to "align", and the next capture starts from
  /// nothing rather than over a stale answer.
  void reset() => state =
      const AsyncValue.data(ScanResult(outcome: ScanOutcome.noEquipment));

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
      // SCAN-G1 review: this used to claim "kept as an AsyncError as well as
      // an outcome", but only ever set `AsyncValue.data` -- the error and
      // stack reached nothing but `debugPrint`, which is not collected in
      // production. An unexpected failure here (not a timeout -- a real bug
      // in the classification pipeline) would look identical to an ordinary
      // transient failure, with zero signal that recognition is broken.
      // Same guard as `scanner_page.dart`'s camera-init reporting and
      // `gemini_equipment_service.dart`'s: telemetry must never break the
      // feature it instruments.
      debugPrint('recognition failed: $e\n$st');
      try {
        if (G3Step10bProbe.kEnabled) {
          unawaited(G3Step10bProbe.recordError(e, st,
              fatal: false, reason: 'scan classification failed'));
        } else {
          unawaited(FirebaseCrashlytics.instance.recordError(e, st,
              fatal: false, reason: 'scan classification failed'));
        }
      } catch (_) {
        // Reporting failure is not itself reportable.
      }
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
    // G-C/F016: `card.uses` is the model's own invention, unchecked against
    // anything real at the point `machine_describer.dart` parsed it.
    // `MachineCardView` re-validates on every render regardless of how a
    // card reached it — that is the ONLY safety boundary for this content,
    // deliberately, and `card` is stored and forwarded here unmodified.
    //
    // An earlier version of this fix also filtered here, before the first
    // save, as claimed defense in depth for data at rest. GPT-PM's round-19
    // review found that unsafe, not merely redundant: `exerciseNameMatcherProvider`
    // fails closed (empty matcher) while the catalogue is still loading, and
    // this was a one-time `ref.read` that PERMANENTLY overwrote `card.uses`
    // with that empty-matcher result before saving -- a real suggestion
    // scanned during a cold start was destroyed with no raw copy left
    // anywhere to recover from, defeating the render-time watcher's own
    // ability to pick it up once the catalogue actually loaded a moment
    // later. Storing the raw card and validating only at render time has no
    // such failure mode: nothing is ever destroyed, so there is nothing to
    // lose during a race. The data-at-rest property (an internal Admin-SDK
    // read over `machine_cards` could see raw invented text) is a real,
    // knowingly deferred gap, not solved by this gate -- closing it needs a
    // way to sanitise storage that cannot itself destroy legitimate content
    // on a slow catalogue load, which is a bigger change than this fix.
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
