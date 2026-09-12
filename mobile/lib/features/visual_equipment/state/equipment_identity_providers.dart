import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cloud_equipment_identity_service.dart';
import '../data/equipment_identity.dart';
import '../data/equipment_identity_outcome_sink.dart';
import '../data/identity_text_parser.dart';
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
final equipmentIdentityProvider =
    FutureProvider.autoDispose.family<EquipmentIdentity?, String>((ref, scanId) async {
  if (!ref.watch(equipmentIdentityEnrichmentEnabledProvider)) return null;

  final imagePath = ref.read(scanIdImagePathProvider)[scanId];
  if (imagePath == null) return null;

  final recogniser = ref.read(machineTextRecogniserProvider);
  if (recogniser is! StructuredTextRecogniser) return null;

  try {
    final evidence = await recogniser.readStructured(imagePath);
    final parsed =
        parseIdentityText(evidence, lexicon: ref.read(identityLexiconProvider));
    final ask = ref.read(equipmentIdentityAskProvider);
    final identity = await ask(scanId: scanId, evidence: parsed);
    // The lossless-handoff seam (Step 8): recorded only on a genuine
    // terminal answer from the server, never on the fail-open-to-null paths
    // above/below -- there is no decision to hand off from those.
    ref
        .read(equipmentIdentityOutcomeSinkProvider)
        .recordTerminal(scanId, EquipmentIdentityOutcome.fromIdentity(identity));
    return identity;
  } catch (e) {
    // Progressive enrichment only -- see this provider's own doc comment.
    // Same guard as `visual_equipment_providers.dart`'s own recognition
    // failure paths: telemetry-worthy, never user-facing.
    debugPrint('equipment identity enrichment failed: $e');
    return null;
  }
});
