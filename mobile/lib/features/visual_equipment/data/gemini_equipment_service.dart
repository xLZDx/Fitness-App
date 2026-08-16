import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart'
    show compute, debugPrint, visibleForTesting;
import 'package:image/image.dart' as img;

import '../../equipment/data/equipment_alias_index.dart';
import 'visual_equipment_match.dart';
import 'visual_equipment_service.dart';
import '../../ai_coach/provider_safety_settings.dart';

/// Signature of "send an image + prompt to the cloud model, get text back".
/// Injectable so every piece of this service is testable without Firebase.
typedef CloudAsk = Future<String?> Function(Uint8List imageBytes, String prompt);

/// Verified live 2026-07-30: gemini-2.5-flash returns 404 'no longer available
/// to new users' on this project; 3-flash-preview answered the operator's
/// power-cage photo with {"machine":"squat rack", 0.9}.
const String kVisionModel = 'gemini-3-flash-preview';

/// The Firebase AI caller every vision path in the app shares.
///
/// JSON only, temperature 0, and thinking switched OFF: with the model's
/// default thinking a single photo took 25-31s, without it 2-5s (verified live
/// 2026-07-30). Two callers now send a photo — the classifier and the machine
/// describer — and a second copy of this configuration is a second place for
/// that 25-second regression to come back.
///
/// The model is built on first use and kept, so the second question about the
/// same photo does not pay the setup again. No deadline is applied here; the
/// caller owns its own timeout so there is exactly one.
CloudAsk firebaseCloudAsk({String modelName = kVisionModel}) {
  GenerativeModel? model;
  return (Uint8List bytes, String prompt) {
    model ??= FirebaseAI.googleAI().generativeModel(
      model: modelName,
      // F026 — provider moderation, not domain safety.
      safetySettings: kProviderSafetySettings,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0,
        thinkingConfig: ThinkingConfig(thinkingBudget: 0),
      ),
    );
    return model!.generateContent([
      Content.multi([
        InlineDataPart('image/jpeg', bytes),
        TextPart(prompt),
      ]),
    ]).then((r) => r.text);
  };
}

/// Cloud recogniser: Gemini through Firebase AI Logic.
///
/// Why this exists: the on-device model is 10 catalogue-trained classes and
/// on a real gym floor it misfired badly enough to call two flat benches a
/// treadmill. Gemini sees the actual machine. The API key lives server-side
/// in Firebase — nothing is embedded in the app.
///
/// The prompt pins the answer to the registry's canonical names, and the
/// reply is resolved through [EquipmentAliasIndex], so the model cannot
/// invent a machine we have no page for: an unresolvable answer degrades to
/// "no match", never to a guess.
class GeminiVisualEquipmentService implements VisualEquipmentService {
  GeminiVisualEquipmentService({
    Future<EquipmentAliasIndex>? index,
    CloudAsk? ask,
    this.modelName = kVisionModel,
    this.timeout = const Duration(seconds: 20),
  })  : _index = index ?? EquipmentAliasIndex.load(),
        _ask = ask;

  final String modelName;
  final Future<EquipmentAliasIndex> _index;
  final CloudAsk? _ask;

  /// Verified live 2026-07-30: with the model's default "thinking" a single
  /// photo took 25-31s; with thinking disabled, 2-5s typically (occasional
  /// preview-model queueing still hit 15-18s). The operator's report — long
  /// waits, then nothing after several tries — is this combined with a
  /// classifyFile call that had NO deadline: a genuinely stalled request just
  /// spun the spinner forever and never reached the on-device fallback below.
  final Duration timeout;

  late final CloudAsk _cloud = _ask ?? firebaseCloudAsk(modelName: modelName);

  Future<String?> _askCloud(Uint8List bytes, String prompt) =>
      _cloud(bytes, prompt).timeout(timeout);

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    final index = await _index;
    // Resized off the UI isolate: a camera still can run several MB, and on
    // gym wifi/LTE the upload itself was a real chunk of the reported delay.
    // 1024px keeps the model's answer quality (verified live) while cutting
    // the payload roughly 3-4x versus a full-resolution JPEG.
    final bytes = await compute(resizeForCloud, path);
    final String? text;
    try {
      text = await _askCloud(bytes, buildPrompt());
    } catch (e) {
      throw VisualEquipmentException('cloud recognition failed: $e');
    }
    if (text == null || text.trim().isEmpty) {
      throw VisualEquipmentException('cloud recognition returned no answer');
    }
    return parseResponse(text, index, topK: topK);
  }

  /// The machine list is embedded so the model answers in OUR vocabulary.
  /// "unknown" is explicitly offered — a model told it must pick something
  /// picks something, which is exactly the failure mode this app is curing.
  @visibleForTesting
  static String buildPrompt() => '''
You identify gym equipment. Look ONLY at the machine closest to the center of
the photo; ignore machines at the edges — gyms are crowded and the user aimed
the center of the frame at the one they mean.

Answer with JSON only:
{"machine": "<name from the list below, or unknown>", "confidence": <0.0-1.0>,
 "alternatives": [{"machine": "<name>", "confidence": <0.0-1.0>}]}

"confidence" is YOUR honest certainty; use low values when unsure. Give up to
2 alternatives only when they are genuinely plausible. Machine list:
${kCanonicalMachines.join(', ')}''';

  /// Canonical EN names the prompt offers. Kept in one place and asserted
  /// against the alias index by the test suite, so a registry rename cannot
  /// silently break the prompt.
  ///
  /// 2026-08-03: 4 machines (`stability ball` .. `parallettes`) had been in
  /// `equipment.json` for a while without ever being added here -- the camera
  /// could not recognise them even though their pages already existed. Found
  /// while re-syncing this list for the batch below; fixed in the same pass.
  @visibleForTesting
  static const List<String> kCanonicalMachines = [
    'treadmill', 'rowing machine', 'squat rack', 'bench press station',
    'cable machine', 'leg press', 'lat pulldown', 'barbell', 'dumbbells',
    'kettlebell', 'elliptical trainer', 'exercise bike', 'recumbent bike',
    'stair climber', 'air bike', 'ski erg', 'smith machine',
    'hack squat machine', 'leg extension machine', 'leg curl machine',
    'hip abductor machine', 'glute kickback machine', 'calf raise machine',
    'chest press machine', 'pec deck', 'shoulder press machine',
    'seated row machine', 't-bar row', 'assisted pull-up machine',
    'pull-up bar', 'dip station', 'preacher curl bench',
    'biceps curl machine', 'triceps extension machine', 'ab crunch machine',
    'rotary torso machine', 'back extension bench', "captain's chair",
    'flat bench', 'ez curl bar', 'weight plates', 'resistance bands',
    'suspension trainer', 'medicine ball', 'battle ropes', 'plyo box',
    'punching bag', 'foam roller',
    // previously missing (2026-08-03 drift fix)
    'stability ball', 'skipping rope', 'ab wheel', 'parallettes',
    // new, 2026-08-03: real equipment found in the vendor pack's own clips
    // (core/EQUIPMENT_GAP_ITEMS_2026-08-03.csv), not external stock names
    'seated dip machine', 'multi hip machine', 'lateral raise machine',
    'sissy squat machine', 'agility ladder', 'mini trampoline',
    'balance board', 'yoga blocks', 'weighted sled', 'ab mat', 'bosu ball',
    'sliding discs', 'sandbag', 'gymnastic rings', 'tyre',
    // new, 2026-08-04: the last 2 of the 4 groups left open in batch 3
    'vertical pole', 'outdoor air walker',
    // alias-only: these two resolve to parallettes / plyo box respectively
    // (see build_registry.py) rather than owning a separate id, but the
    // model still needs the words offered to recognise them by sight
    'push-up blocks', 'aerobic step',
  ];

  /// Parses the model's JSON (tolerating ```json fences) and resolves every
  /// named machine through the alias index. Unresolvable names are dropped
  /// with a log — never guessed at.
  @visibleForTesting
  static List<VisualMatch> parseResponse(
    String text,
    EquipmentAliasIndex index, {
    int topK = 3,
  }) {
    final cleaned = text
        .replaceAll(RegExp(r'^\s*```(?:json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e) {
      throw VisualEquipmentException('cloud answer was not JSON: $e');
    }
    if (decoded is! Map) {
      throw VisualEquipmentException('cloud answer had no object');
    }

    final raw = <VisualMatch>[];
    void addCandidate(Object? name, Object? confidence) {
      if (name is! String) return;
      if (name.trim().toLowerCase() == 'unknown') return;
      final id = index.resolve(name);
      if (id == null) {
        debugPrint('cloud named "$name" but the registry has no such machine');
        return;
      }
      final c = confidence is num ? confidence.toDouble().clamp(0.0, 1.0) : 0.5;
      raw.add(VisualMatch(equipmentId: id, confidence: c, labelHint: name));
    }

    addCandidate(decoded['machine'], decoded['confidence']);
    final alts = decoded['alternatives'];
    if (alts is List) {
      for (final a in alts) {
        if (a is Map) addCandidate(a['machine'], a['confidence']);
      }
    }

    // One machine may arrive twice (main + alternative); keep the best.
    final best = <String, VisualMatch>{};
    for (final m in raw) {
      final prev = best[m.equipmentId];
      if (prev == null || m.confidence > prev.confidence) {
        best[m.equipmentId] = m;
      }
    }
    return rankTopK(best.values, minConfidence: 0.01, limit: topK);
  }
}

/// Runs on a background isolate via [compute]: decodes the photo, downsizes
/// to at most 1024px on the long edge, and re-encodes as JPEG. A resize
/// failure (corrupt file, unsupported format) falls back to the original
/// bytes rather than throwing — a slightly larger upload beats no upload.
///
/// Shared with the machine describer: when a photo is not in the catalog it is
/// sent twice, and the second question must not re-do the resize differently.
Uint8List resizeForCloud(String path) {
  final bytes = File(path).readAsBytesSync();
  try {
    var decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    decoded = img.bakeOrientation(decoded);
    if (decoded.width <= 1024 && decoded.height <= 1024) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: 88));
    }
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: 1024)
        : img.copyResize(decoded, height: 1024);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
  } catch (e) {
    debugPrint('cloud photo resize failed, sending original: $e');
    return bytes;
  }
}

/// Cloud first, on-device fallback.
///
/// The cloud path needs network + the Firebase AI API enabled; the on-device
/// model needs neither. Any cloud failure falls back silently-but-logged, so
/// the user in a basement gym still gets an answer — the weaker one, honestly
/// scored. Only when BOTH fail does the user see an error.
class HybridVisualEquipmentService
    implements VisualEquipmentService, FallbackReportingRecogniser {
  HybridVisualEquipmentService({required this.cloud, required this.local});

  final VisualEquipmentService cloud;
  final VisualEquipmentService local;

  bool _lastAnsweredOffline = false;

  /// R2.2 state 12. The fallback used to be invisible: "silently-but-logged"
  /// meant the user got the weaker answer, honestly scored, but was never told
  /// it came from the weaker model — so a low-confidence result in a basement
  /// gym looked like the app being bad at its job rather than the network
  /// being absent.
  @override
  bool get lastAnsweredOffline => _lastAnsweredOffline;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    Object? cloudError;
    try {
      final answer = await cloud.classifyFile(path: path, topK: topK);
      _lastAnsweredOffline = false;
      return answer;
    } catch (e) {
      cloudError = e;
      debugPrint('cloud recognition unavailable, falling back on-device: $e');
    }
    try {
      final answer = await local.classifyFile(path: path, topK: topK);
      _lastAnsweredOffline = true;
      return answer;
    } catch (e) {
      // Both failed: there is no answer, so there is nothing to label as
      // having come from the fallback.
      _lastAnsweredOffline = false;
      throw VisualEquipmentException(
          'recognition failed (cloud: $cloudError; on-device: $e)');
    }
  }
}
