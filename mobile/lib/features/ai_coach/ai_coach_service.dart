import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_coach_context.dart';

/// Signature of "send a prompt, get text back" — injectable for tests.
typedef CoachAsk = Future<String?> Function(String prompt);

/// One-shot technique advice for a machine, in the user's language.
///
/// Gemini through Firebase AI Logic (key lives server-side). Deliberately not
/// a chat: the page asks one well-formed question — technique, mistakes,
/// beginner set/rep guidance for THIS machine — and renders one answer.
class AiCoachService {
  // Same model as recognition — gemini-2.5-flash 404s for this project
  // (verified live 2026-07-30).
  AiCoachService({CoachAsk? ask, this.modelName = 'gemini-3-flash-preview'})
      : _ask = ask;

  final String modelName;
  final CoachAsk? _ask;
  GenerativeModel? _model;

  Future<String?> _askCloud(String prompt) async {
    final custom = _ask;
    if (custom != null) return custom(prompt);
    _model ??= FirebaseAI.googleAI().generativeModel(model: modelName);
    final r = await _model!.generateContent([Content.text(prompt)]);
    return r.text;
  }

  /// Returns advice text, or throws with the underlying reason.
  ///
  /// The prompt itself lives in `ai_coach_context.dart` as a pure function, so
  /// it can be asserted on without a network call. This method is only the
  /// transport plus the empty-answer guard.
  Future<String> advise(AiCoachContext context) async {
    final text = await _askCloud(buildCoachPrompt(context));
    final out = text?.trim() ?? '';
    if (out.isEmpty) {
      throw Exception('the coach returned an empty answer');
    }
    return out;
  }
}

final aiCoachServiceProvider = Provider<AiCoachService>((_) => AiCoachService());

/// Advice for one subject, fetched once per distinct [AiCoachContext].
///
/// Keyed on the context — which carries a stable id — rather than on a display
/// name, so two catalog rows sharing a label no longer share an answer.
final aiCoachAdviceProvider =
    FutureProvider.autoDispose.family<String, AiCoachContext>((ref, context) {
  return ref.watch(aiCoachServiceProvider).advise(context);
});
