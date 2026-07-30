import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Future<String> advise({
    required String machineName,
    required String languageCode,
  }) async {
    final language = languageCode == 'ru' ? 'Russian' : 'English';
    final text = await _askCloud('''
You are a concise, safety-first gym coach. The user is standing at:
"$machineName".

In $language, give:
1. Correct setup and technique (3-5 short bullet points).
2. The 2-3 most common mistakes and how to avoid them.
3. A sensible beginner volume (sets x reps or minutes).

Plain text with simple dashes for bullets — no markdown headers, no tables.
Under 180 words. Do not invent machine features it does not have. End with
one line reminding to stop on sharp pain.''');
    final out = text?.trim() ?? '';
    if (out.isEmpty) {
      throw Exception('the coach returned an empty answer');
    }
    return out;
  }
}

final aiCoachServiceProvider = Provider<AiCoachService>((_) => AiCoachService());

/// Advice for one machine name, fetched once per (machine, language) pair.
final aiCoachAdviceProvider = FutureProvider.autoDispose
    .family<String, ({String machine, String language})>((ref, args) {
  return ref.watch(aiCoachServiceProvider).advise(
        machineName: args.machine,
        languageCode: args.language,
      );
});
