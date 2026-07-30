import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../../equipment/data/equipment_alias_index.dart';
import 'visual_equipment_match.dart';
import 'visual_equipment_service.dart';

/// Signature of "send an image + prompt to the cloud model, get text back".
/// Injectable so every piece of this service is testable without Firebase.
typedef CloudAsk = Future<String?> Function(Uint8List imageBytes, String prompt);

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
    // Verified live 2026-07-30: gemini-2.5-flash returns 404 'no longer
    // available to new users' on this project; 3-flash-preview answered the
    // operator's power-cage photo with {"machine":"squat rack", 0.9}.
    this.modelName = 'gemini-3-flash-preview',
  })  : _index = index ?? EquipmentAliasIndex.load(),
        _ask = ask;

  final String modelName;
  final Future<EquipmentAliasIndex> _index;
  final CloudAsk? _ask;

  GenerativeModel? _model;

  Future<String?> _askCloud(Uint8List bytes, String prompt) async {
    final custom = _ask;
    if (custom != null) return custom(bytes, prompt);
    _model ??= FirebaseAI.googleAI().generativeModel(
      model: modelName,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0,
      ),
    );
    final response = await _model!.generateContent([
      Content.multi([
        InlineDataPart('image/jpeg', bytes),
        TextPart(prompt),
      ]),
    ]);
    return response.text;
  }

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    final index = await _index;
    final bytes = await File(path).readAsBytes();
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

/// Cloud first, on-device fallback.
///
/// The cloud path needs network + the Firebase AI API enabled; the on-device
/// model needs neither. Any cloud failure falls back silently-but-logged, so
/// the user in a basement gym still gets an answer — the weaker one, honestly
/// scored. Only when BOTH fail does the user see an error.
class HybridVisualEquipmentService implements VisualEquipmentService {
  HybridVisualEquipmentService({required this.cloud, required this.local});

  final VisualEquipmentService cloud;
  final VisualEquipmentService local;

  @override
  Future<List<VisualMatch>> classifyFile({
    required String path,
    int topK = 3,
  }) async {
    Object? cloudError;
    try {
      return await cloud.classifyFile(path: path, topK: topK);
    } catch (e) {
      cloudError = e;
      debugPrint('cloud recognition unavailable, falling back on-device: $e');
    }
    try {
      return await local.classifyFile(path: path, topK: topK);
    } catch (e) {
      throw VisualEquipmentException(
          'recognition failed (cloud: $cloudError; on-device: $e)');
    }
  }
}
