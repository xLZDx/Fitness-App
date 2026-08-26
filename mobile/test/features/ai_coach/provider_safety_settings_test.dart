import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F026's structural guard, now permanent rather than an allowlist.
///
/// G1's four slices moved every direct client-side Gemini call
/// (`ai_coach_service.dart`, `gemini_equipment_service.dart`,
/// `machine_describer.dart`, `ai_exercise_generator.dart`) behind its own
/// Cloud Function. `provider_safety_settings.dart` -- the client-side
/// `kProviderSafetySettings` this suite used to test the VALUES of -- is
/// deleted along with the last call site that used it: with zero direct
/// mobile call sites, there is nothing left client-side to configure a
/// provider content filter for. Those settings' values (four harm
/// categories, `medium` threshold, nothing switched off) now live and are
/// tested server-side, in `functions/src/ai_gateway.ts`'s own
/// `SAFETY_SETTINGS` and `ai_gateway.test.ts`'s "always sends the four
/// safety categories at the medium threshold" -- ported deliberately rather
/// than re-derived, see that file's own doc comment.
///
/// What stays permanently useful client-side is the boundary itself: a
/// second direct call site added later, with or without safety settings, is
/// invisible to any behavioural test because it only shows up in a network
/// request. This file's only remaining job is to keep proving that boundary
/// holds -- zero direct Gemini SDK usage anywhere under `lib/`.
void main() {
  test('mobile/lib makes zero direct Gemini SDK calls', () {
    final foundGenerativeModel = <String>[];
    final foundFirebaseAiImport = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      final path = f.path.replaceAll(r'\', '/');
      // `generativeModel(` alone, not `FirebaseAI.googleAI()`: every migrated
      // file's own doc comment now narrates "...rather than calling
      // `FirebaseAI.googleAI()` directly", so that string legitimately
      // appears in source text describing what is NOT done any more.
      // `generativeModel(` -- the actual instantiation call, with its
      // parenthesis -- does not have the same false-positive problem: it
      // never appears in prose form in any of these files.
      if (src.contains('generativeModel(')) {
        foundGenerativeModel.add(path);
      }
      if (src.contains("import 'package:firebase_ai")) {
        foundFirebaseAiImport.add(path);
      }
    }
    expect(foundGenerativeModel, isEmpty,
        reason: 'a Gemini call site appeared or moved. It needs the same '
            'question asked of it that F016 asked of MachineDescriber: can '
            'its output become an actionable exercise? A call site that '
            'moves server-side needs the equivalent question asked of '
            'ai_gateway.ts instead, and this list should stay empty.');
    expect(foundFirebaseAiImport, isEmpty,
        reason: 'package:firebase_ai should have no remaining importer once '
            'all four G1 AI surfaces are server-owned; an import with no '
            'generativeModel( call is still a live dependency edge worth '
            'catching here rather than only at pubspec-cleanup time.');
  });

  test('ai_coach_service.dart calls the aiCoachAdvice callable', () {
    final src =
        File('lib/features/ai_coach/ai_coach_service.dart').readAsStringSync();
    expect(src, isNot(contains('generativeModel(')));
    expect(src, contains("httpsCallable('aiCoachAdvice')"));
  });

  test('gemini_equipment_service.dart calls the aiEquipmentRecognition callable', () {
    final src = File('lib/features/visual_equipment/data/gemini_equipment_service.dart')
        .readAsStringSync();
    expect(src, isNot(contains('generativeModel(')));
    expect(src, contains("httpsCallable(kEquipmentRecognitionFunctionName)"));
  });

  test('machine_describer.dart calls the aiMachineDescription callable', () {
    final src = File('lib/features/visual_equipment/data/machine_describer.dart')
        .readAsStringSync();
    expect(src, isNot(contains('generativeModel(')));
    expect(src, contains("httpsCallable(kMachineDescriptionFunctionName)"));
  });

  test('ai_exercise_generator.dart calls the aiExerciseGeneration callable', () {
    final src = File('lib/features/ai_coach/ai_exercise_generator.dart')
        .readAsStringSync();
    expect(src, isNot(contains('generativeModel(')));
    expect(src, contains("httpsCallable(kExerciseGenerationFunctionName)"));
  });
}
