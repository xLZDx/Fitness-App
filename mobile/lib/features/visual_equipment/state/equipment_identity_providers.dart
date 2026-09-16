import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_equipment_identity_service.dart';
import '../data/cloud_equipment_identity_telemetry_service.dart';
import '../data/equipment_identity.dart';
import '../data/equipment_identity_outcome_sink.dart';
import '../data/equipment_identity_telemetry_outbox.dart';
import '../data/equipment_identity_telemetry_report.dart';
import '../data/identity_text_parser.dart';
import '../data/machine_text_evidence.dart';
import '../data/mlkit_text_recogniser.dart';
import '../data/parsed_identity_text.dart';
import 'visual_equipment_providers.dart' show machineTextRecogniserProvider;

/// Master switch for the whole P2.G4 progressive-identity surface -- OFF by
/// default. Checked FIRST inside [equipmentIdentityProvider] itself (not
/// only at whatever call site watches it): a caller that watches the family
/// unconditionally must still get zero OCR and zero network calls while
/// this reads false, rather than relying on every future call site to
/// remember to gate the watch.
final equipmentIdentityEnrichmentEnabledProvider = Provider<bool>((_) => false);

/// scanId -> the image path that scan captured.
///
/// Entries are added when a scan starts and removed ONLY by an explicit
/// logical event -- `_scanAgain()` (`scanner_page.dart`) clearing its own
/// scanId's entry -- never by [equipmentIdentityProvider]'s own dispose
/// lifecycle. GPT-PM round-3 correction (`core/DECISION_LOG.md`,
/// 2026-09-11): `autoDispose` can tear down and recreate the SAME family
/// instance on ordinary transient unwatch/rewatch churn (a brief navigation
/// flicker, for instance), which is not the same event as the scan itself
/// ending -- tying cleanup to the family's own disposal would silently
/// break re-resolution after that kind of churn (the map entry would already
/// be gone by the time the recreated instance looked for it).
final scanIdImagePathProvider = StateProvider<Map<String, String>>((_) => const {});

/// [IdentityLexicon] for [parseIdentityText]. Brand/product-line sets are
/// deliberately empty: no canonical brand/product-line list exists anywhere
/// in this repository yet (`identity_text_parser.dart`'s own scope note,
/// reconfirmed for this gate -- building one is explicitly out of scope, see
/// the Rosetta plan's own NOT-IN-SCOPE list). This does not silently weaken
/// the signal that actually drives `EXACT_MODEL`: `modelCodeCandidates`/
/// `conflicts` come from pattern heuristics inside the parser and never
/// depend on this lexicon at all.
final identityLexiconProvider =
    Provider<IdentityLexicon>((_) => const IdentityLexicon());

final equipmentIdentityServiceProvider = Provider<CloudEquipmentIdentityService>(
  (_) => CloudEquipmentIdentityService(),
);

/// The resolver [equipmentIdentityProvider] calls -- overridden in tests so
/// they never construct a real [CloudEquipmentIdentityService]/Firebase.
final equipmentIdentityAskProvider = Provider<EquipmentIdentityAsk>((ref) {
  final service = ref.watch(equipmentIdentityServiceProvider);
  return service.resolveFromText;
});

/// App-lifetime (not `autoDispose`): the whole point is that a terminal
/// outcome survives the family instance that produced it, for a later gate
/// to read. See `equipment_identity_outcome_sink.dart`'s own doc comment.
final equipmentIdentityOutcomeSinkProvider =
    Provider<EquipmentIdentityOutcomeSink>((_) => InMemoryEquipmentIdentityOutcomeSink());

final equipmentIdentityTelemetryServiceProvider = Provider<CloudEquipmentIdentityTelemetryService>(
  (_) => CloudEquipmentIdentityTelemetryService(),
);

/// The sender [equipmentIdentityProvider] fires telemetry reports through --
/// overridden in tests, mirroring [equipmentIdentityAskProvider] one
/// declaration above.
final equipmentIdentityTelemetrySendProvider = Provider<EquipmentIdentityTelemetrySend>((ref) {
  final service = ref.watch(equipmentIdentityTelemetryServiceProvider);
  return service.send;
});

/// P2.G5-readiness step 3b: durable retry-on-failure delivery. Defaults to
/// the in-memory fake so a test/host that never overrides this still runs
/// (same posture as [equipmentIdentityOutcomeSinkProvider]'s own default) --
/// the real app overrides this with `FileEquipmentIdentityTelemetryOutbox`,
/// opened in `main()` before `runApp`, same pattern as `PrefsMomentRepository`.
final equipmentIdentityTelemetryOutboxProvider =
    Provider<EquipmentIdentityTelemetryOutbox>((_) => InMemoryEquipmentIdentityTelemetryOutbox());

/// Fires one telemetry report body through the durable outbox: never awaited
/// by the caller (a telemetry round-trip must not add latency to the scan's
/// own result) and never able to surface as an uncaught async error
/// (P2.G5-readiness step 3a, design doc §6/§7) -- the outbox's own
/// `sendOrEnqueue` never rethrows, so there is nothing for `unawaited` to
/// hand an error to here even without a `.catchError`.
///
/// Step 3a's version dropped a failed send permanently, the moment it
/// failed. Step 3b's only change is durability: a failed attempt is now
/// persisted and retried on the next app-resume drain
/// (`main.dart`'s `_FitnessAppState.didChangeAppLifecycleState`), instead of
/// silently vanishing.
void _sendTelemetryReport(EquipmentIdentityTelemetrySend send,
    EquipmentIdentityTelemetryOutbox outbox, Map<String, dynamic> body) {
  unawaited(outbox.sendOrEnqueue(send, body));
}

/// Resolves one scan's on-device OCR evidence into a server-verified
/// [EquipmentIdentity] -- or `null`, on ANY failure (enrichment disabled, no
/// image path recorded for this scanId, no structured recogniser configured,
/// OCR/parse/service throwing, a malformed reply). This is a progressive
/// enrichment, never the scan's primary answer: a failure here must never
/// surface to the user as an error, so every path that is not a clean
/// success returns `null` rather than propagating.
///
/// Keyed by scanId ONLY (not imagePath) -- see [scanIdImagePathProvider]'s
/// own doc comment for why cleanup is external to this family's lifecycle.
///
/// P2.G5-readiness step 3a (design doc §4.2/§4.2a/§5.4/§6): the single
/// try/catch this provider used to wrap OCR+parse+network in is now
/// stage-separated, so each failure maps to the correct
/// `LOCAL_FAILURE`/`REQUEST_FAILURE` reason and is reported through exactly
/// ONE self-contained fragment (state + reason + `scanStartedAt` +
/// `scanEndedAt`, all known at the same settle instant). `scanStartedAt` is
/// parsed from `scanId` itself (`equipment_identity_telemetry_report.dart`'s
/// `parseScanStartedAt`) -- no new mobile state. `enrichmentDisabled` and
/// `missingImagePath`/`missingStructuredRecognizer` early-return BEFORE
/// `scanStartedAt` can be meaningfully read as "the pipeline actually
/// started", but the enrichment-disabled branch above already returns
/// before this point and is DELIBERATELY never reported over the network
/// (design doc §4.2b) -- everything below this comment always has a real
/// scanId to parse a start instant from.
final equipmentIdentityProvider =
    FutureProvider.autoDispose.family<EquipmentIdentity?, String>((ref, scanId) async {
  if (!ref.watch(equipmentIdentityEnrichmentEnabledProvider)) return null;

  final send = ref.read(equipmentIdentityTelemetrySendProvider);
  final outbox = ref.read(equipmentIdentityTelemetryOutboxProvider);
  // Falls back to "now" only for the near-impossible case of a scanId this
  // app itself did not mint in the expected shape -- never fabricates a
  // start instant earlier than it can prove.
  final scanStartedAt = parseScanStartedAt(scanId) ?? nowUtcIso();

  void reportLocalFailure(LocalFailureReason reason) {
    _sendTelemetryReport(
      send,
      outbox,
      buildLocalFailureReportBody(
        scanId: scanId,
        reason: reason,
        scanStartedAt: scanStartedAt,
        scanEndedAt: nowUtcIso(),
      ),
    );
  }

  final imagePath = ref.read(scanIdImagePathProvider)[scanId];
  if (imagePath == null) {
    reportLocalFailure(LocalFailureReason.missingImagePath);
    return null;
  }

  final recogniser = ref.read(machineTextRecogniserProvider);
  if (recogniser is! StructuredTextRecogniser) {
    reportLocalFailure(LocalFailureReason.missingStructuredRecognizer);
    return null;
  }

  final MachineTextEvidence evidence;
  try {
    evidence = await recogniser.readStructured(imagePath);
  } catch (e) {
    debugPrint('equipment identity OCR failed: $e');
    reportLocalFailure(LocalFailureReason.ocrException);
    return null;
  }

  // NOTE, correcting design doc §4.2's own claim (recon finding, not yet
  // reflected in that frozen text): `identity_text_parser.dart`'s own doc
  // comment states `parseIdentityText` is "Pure ... never throws, always
  // returns a ParsedIdentityText" -- confirmed by reading it (zero `throw`
  // statements in that file). `parserException` is therefore currently
  // UNREACHABLE in production, the same "reserved but never occurs" posture
  // §4's own table already accepts for `NOT_ATTEMPTED`
  // ("an unused enum value is not a defect; a missing one that later occurs
  // uncategorized would be"). This catch stays as defense-in-depth against
  // a future change to the parser's own no-throw contract, not because it
  // fires today.
  final ParsedIdentityText parsed;
  try {
    parsed = parseIdentityText(evidence, lexicon: ref.read(identityLexiconProvider));
  } catch (e) {
    debugPrint('equipment identity parse failed: $e');
    reportLocalFailure(LocalFailureReason.parserException);
    return null;
  }

  try {
    final ask = ref.read(equipmentIdentityAskProvider);
    final identity = await ask(scanId: scanId, evidence: parsed);
    // The lossless-handoff seam (Step 8): recorded only on a genuine
    // terminal answer from the server, never on the fail-open-to-null paths
    // above/below -- there is no decision to hand off from those.
    ref
        .read(equipmentIdentityOutcomeSinkProvider)
        .recordTerminal(scanId, EquipmentIdentityOutcome.fromIdentity(identity));
    // Design doc §6 rule 5b: the server has already committed
    // SERVER_TERMINAL by the time this reply exists, so this always lands
    // as an enrichment fragment, never a state-defining write.
    _sendTelemetryReport(
      send,
      outbox,
      buildScanTimingReportBody(scanId: scanId, scanStartedAt: scanStartedAt, scanEndedAt: nowUtcIso()),
    );
    return identity;
  } catch (e) {
    // Progressive enrichment only -- see this provider's own doc comment.
    // Same guard as `visual_equipment_providers.dart`'s own recognition
    // failure paths: telemetry-worthy, never user-facing.
    debugPrint('equipment identity enrichment failed: $e');
    _sendTelemetryReport(
      send,
      outbox,
      buildRequestFailureReportBody(
        scanId: scanId,
        reason: classifyRequestFailureReason(e),
        scanStartedAt: scanStartedAt,
        scanEndedAt: nowUtcIso(),
      ),
    );
    return null;
  }
});

/// Retries every currently-queued equipment-identity telemetry report.
///
/// Called from `main.dart`'s `_FitnessAppState.didChangeAppLifecycleState`
/// on `AppLifecycleState.resumed` -- the drain trigger this app has to use
/// in place of a real connectivity event, since no `connectivity_plus`
/// dependency exists here (confirmed: not in `mobile/pubspec.yaml`). Resume
/// is not a perfect proxy for "network is back" (the app can resume while
/// still offline, in which case this drain itself fails and the reports
/// stay queued for the NEXT resume), but it is the cheapest real signal
/// this app already observes for every other lifecycle-driven refresh, and
/// a failed drain attempt costs nothing beyond one extra doomed network
/// call -- the outbox's own `drainPending` never throws.
Future<void> drainEquipmentIdentityTelemetryOutbox(WidgetRef ref) {
  final send = ref.read(equipmentIdentityTelemetrySendProvider);
  final outbox = ref.read(equipmentIdentityTelemetryOutboxProvider);
  return outbox.drainPending(send);
}
