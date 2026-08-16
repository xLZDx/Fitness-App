import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../equipment/data/equipment_models.dart';
import 'provider_safety_settings.dart';

/// Signature of "send a prompt, get text back" — injectable for tests.
typedef GeneratorAsk = Future<String?> Function(String prompt);

/// Fills a machine's exercise card when the vendored catalog has nothing for
/// it — round 4 (S0) closed 21 of 32 empty machines with real, curated
/// upstream exercises; 11 stay genuinely empty (elliptical, exercise bike,
/// stair climber, ...) because no public-domain source covers them. This is
/// the fallback for those, and only those: [ExerciseGeneratedRepository]
/// callers must try the real catalog FIRST.
///
/// Muscle names are constrained to our vocabulary in the prompt itself, and
/// still re-validated on the way back — an unrecognised muscle name is
/// dropped rather than passed through, the same discipline the recognition
/// prompt applies to machine names.
class AiExerciseGenerator {
  AiExerciseGenerator({GeneratorAsk? ask, this.modelName = 'gemini-3-flash-preview'})
      : _ask = ask;

  final String modelName;
  final GeneratorAsk? _ask;
  GenerativeModel? _model;

  Future<String?> _askCloud(String prompt) async {
    final custom = _ask;
    if (custom != null) return custom(prompt);
    _model ??= FirebaseAI.googleAI().generativeModel(
      model: modelName,
      // F026 — provider moderation, not domain safety.
      safetySettings: kProviderSafetySettings,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        temperature: 0.4,
        thinkingConfig: ThinkingConfig(thinkingBudget: 0),
      ),
    );
    final r = await _model!
        .generateContent([Content.text(prompt)]).timeout(const Duration(seconds: 25));
    return r.text;
  }

  /// Generates 3-4 exercises for [machineName], titled/worded in
  /// [languageCode]. Every item gets id `ai_<equipmentId>_<n>` so it is
  /// recognisable in the UI without a dedicated schema field.
  Future<List<ExerciseItem>> generate({
    required String equipmentId,
    required String machineName,
    required String languageCode,
  }) async {
    final text = await _askCloud(_buildPrompt(machineName, languageCode));
    if (text == null || text.trim().isEmpty) {
      throw Exception('AI exercise generation returned no answer');
    }
    return parseResponse(text, equipmentId: equipmentId);
  }

  static const List<String> kMuscleVocab = [
    'adductors', 'back', 'biceps', 'calves', 'chest', 'core', 'forearms',
    'glutes', 'hamstrings', 'lats', 'lower_back', 'quads', 'shoulders',
    'traps', 'triceps',
  ];

  @visibleForTesting
  static String buildPromptForTest(String machineName, String languageCode) =>
      _buildPrompt(machineName, languageCode);

  static String _buildPrompt(String machineName, String languageCode) {
    final language = languageCode == 'ru' ? 'Russian' : 'English';
    return '''
Generate 3 to 4 distinct exercises performed on: "$machineName".
Write all text (title, steps) in $language.

Answer with a JSON array only, each item shaped exactly like:
{"title": "...", "steps": ["step 1", "step 2", "step 3"],
 "muscles": ["<from vocabulary>"], "primaryMuscles": ["<from vocabulary>"],
 "difficulty": "beginner|intermediate|advanced", "durationMinutes": <int>}

Muscle vocabulary (use ONLY these, lowercase, exactly as spelled):
${kMuscleVocab.join(', ')}

Steps must be concrete and safe (setup, execution, breathing where it
matters). Do not invent a feature this machine does not have. 3-5 steps per
exercise. durationMinutes between 5 and 12.''';
  }

  /// Parses the model's JSON array, tolerating ```json fences, and drops any
  /// muscle name outside [kMuscleVocab] rather than passing it through.
  @visibleForTesting
  static List<ExerciseItem> parseResponse(
    String text, {
    required String equipmentId,
  }) {
    final cleaned = text
        .replaceAll(RegExp(r'^\s*```(?:json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (e) {
      throw Exception('AI exercise answer was not JSON: $e');
    }
    if (decoded is! List) {
      throw Exception('AI exercise answer was not a JSON array');
    }

    final vocab = kMuscleVocab.toSet();
    List<String> muscles(Object? raw) => (raw is List)
        ? raw
            .whereType<String>()
            .map((m) => m.trim().toLowerCase())
            .where(vocab.contains)
            .toList()
        : const [];

    final out = <ExerciseItem>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map) continue;
      final title = item['title'];
      final steps = item['steps'];
      if (title is! String || title.trim().isEmpty) continue;
      if (steps is! List || steps.isEmpty) continue;
      final stepList = steps.whereType<String>().toList();
      if (stepList.isEmpty) continue;
      final difficulty = ExerciseDifficulty.values.firstWhere(
        (d) => d.name == item['difficulty'],
        orElse: () => ExerciseDifficulty.beginner,
      );
      final duration = item['durationMinutes'];
      out.add(ExerciseItem(
        // '::' rather than '_': equipmentId itself contains underscores
        // (e.g. "hip_abductor_adductor"), so a caller that needs to recover
        // the equipmentId from the id (WorkoutPlayerPage's lookup) needs an
        // unambiguous delimiter, not a split on '_'.
        id: 'ai::$equipmentId::$i',
        title: title.trim(),
        equipmentId: equipmentId,
        muscles: muscles(item['muscles']),
        primaryMuscles: muscles(item['primaryMuscles']),
        difficulty: difficulty,
        durationMinutes: duration is num ? duration.round().clamp(5, 20) : 8,
        summary: stepList.first,
        steps: stepList,
      ));
    }
    if (out.isEmpty) {
      throw Exception('AI generated no usable exercises');
    }
    return out;
  }
}
