import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/firebase/functions_region.dart';
import '../equipment/data/equipment_models.dart';

/// Signature of "ask for exercises on this machine, in this language, get raw
/// JSON text back" -- injectable for tests, so the suite never needs a real
/// `FirebaseFunctions`.
///
/// Two args, not the old signature's (equipmentId, machineName, languageCode)
/// plus a client-built prompt: unlike before G1's migration of this class,
/// there is no client-supplied `machineName` any more -- the
/// `aiExerciseGeneration` Cloud Function resolves the canonical machine name
/// server-side from `equipmentId` itself
/// (`functions/src/ai_exercise_generation.ts`), never trusting caller text.
typedef CloudGenerateAsk = Future<String?> Function(
    String equipmentId, String languageCode);

/// The Cloud Function name this surface calls. Named once so
/// [cloudFunctionsGenerateAsk] and its test cannot drift apart on a typo.
const String kExerciseGenerationFunctionName = 'aiExerciseGeneration';

/// Builds the request body sent to [kExerciseGenerationFunctionName].
@visibleForTesting
Map<String, dynamic> buildExerciseGenerationRequest(
        String equipmentId, String languageCode) =>
    {'equipmentId': equipmentId, 'languageCode': languageCode};

/// Extracts the answer text from [kExerciseGenerationFunctionName]'s reply.
@visibleForTesting
String? extractExerciseGenerationText(Map<String, dynamic> data) =>
    data['text'] as String?;

/// The default [CloudGenerateAsk]: routes through the `aiExerciseGeneration`
/// Cloud Function rather than calling `FirebaseAI.googleAI()` directly.
///
/// G1: the fourth and last of the four mobile call sites migrated off a
/// direct client-side Gemini call.
CloudGenerateAsk cloudFunctionsGenerateAsk({FirebaseFunctions? functions}) {
  final fns = functions ?? functionsForRegion;
  return (String equipmentId, String languageCode) async {
    final result = await fns
        .httpsCallable(kExerciseGenerationFunctionName)
        .call<Map<String, dynamic>>(
            buildExerciseGenerationRequest(equipmentId, languageCode));
    return extractExerciseGenerationText(result.data);
  };
}

/// Fills a machine's exercise card when the vendored catalog has nothing for
/// it — round 4 (S0) closed 21 of 32 empty machines with real, curated
/// upstream exercises; a handful stay genuinely empty (elliptical, exercise
/// bike, stair climber, ...) because no public-domain source covers them.
/// This is the fallback for those, and only those: [ExerciseGeneratedRepository]
/// callers must try the real catalog FIRST.
///
/// Muscle names are constrained to our vocabulary in the prompt itself, and
/// still re-validated on the way back — an unrecognised muscle name is
/// dropped rather than passed through, the same discipline the recognition
/// prompt applies to machine names.
class AiExerciseGenerator {
  AiExerciseGenerator({
    CloudGenerateAsk? ask,
    FirebaseFunctions? functions,
    this.timeout = const Duration(seconds: 35),
  })  : _ask = ask,
        _injected = functions;

  /// 35s, not the server's 25s: mirrors `GeminiMachineDescriber.timeout`'s
  /// own already-reviewed fix (`machine_describer.dart`) for the identical
  /// client/server timeout-race GPT-PM's G1 review caught on that slice
  /// first. `aiExerciseGeneration` bounds the MODEL call itself at 25s
  /// (`functions/src/ai_exercise_generation.ts`), but that budget only
  /// starts after auth, request validation, and the quota-ledger transaction
  /// have already run server-side — none of which this client-side clock
  /// accounts for. 35s gives real margin over the server's own 25s model
  /// budget rather than racing it.
  final Duration timeout;

  final CloudGenerateAsk? _ask;
  final FirebaseFunctions? _injected;

  late final CloudGenerateAsk _cloud =
      _ask ?? cloudFunctionsGenerateAsk(functions: _injected);

  static const List<String> kMuscleVocab = [
    'adductors', 'back', 'biceps', 'calves', 'chest', 'core', 'forearms',
    'glutes', 'hamstrings', 'lats', 'lower_back', 'quads', 'shoulders',
    'traps', 'triceps',
  ];

  /// Generates 3-4 exercises for [equipmentId], titled/worded in
  /// [languageCode]. Every item gets id `ai_<equipmentId>_<n>` so it is
  /// recognisable in the UI without a dedicated schema field.
  Future<List<ExerciseItem>> generate({
    required String equipmentId,
    required String languageCode,
  }) async {
    final text = await _cloud(equipmentId, languageCode).timeout(timeout);
    if (text == null || text.trim().isEmpty) {
      throw Exception('AI exercise generation returned no answer');
    }
    return parseResponse(text, equipmentId: equipmentId);
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
