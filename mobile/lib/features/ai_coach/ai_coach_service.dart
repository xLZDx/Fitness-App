import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/functions_region.dart';
import 'ai_coach_context.dart';

/// Signature of "ask the backend for advice on this context" — injectable
/// for tests, so the suite never needs a real `FirebaseFunctions`.
typedef CoachAsk = Future<String?> Function(AiCoachContext context);

/// One-shot technique advice for a machine, in the user's language.
///
/// G1: routed through the `aiCoachAdvice` Cloud Function rather than calling
/// `FirebaseAI.googleAI()` directly. The prompt this used to build on-device
/// (`buildCoachPrompt`, deleted from `ai_coach_context.dart` — see that
/// file's remaining doc comment for where it went and why) is now built
/// server-side in `functions/src/ai_coach_advice.ts`, from the same structured
/// `{source, subjectName, languageCode}` this class sends rather than from a
/// client-supplied prompt string, so quota (`QUOTAS.aiCoachAdvice` in
/// `abuse_guard.ts`) actually bounds what gets spent per account — nothing
/// did before this gate. Deliberately not a chat: the sheet asks one
/// well-formed question and renders one answer.
class AiCoachService {
  AiCoachService({CoachAsk? ask, FirebaseFunctions? functions})
      : _ask = ask,
        _injected = functions;

  final CoachAsk? _ask;
  final FirebaseFunctions? _injected;

  FirebaseFunctions get _functions => _injected ?? functionsForRegion;

  Future<String?> _askCloud(AiCoachContext context) async {
    final custom = _ask;
    if (custom != null) return custom(context);
    final result = await _functions
        .httpsCallable('aiCoachAdvice')
        .call<Map<String, dynamic>>({
      'source': context.source.name,
      'subjectName': context.subjectName,
      'languageCode': context.languageCode,
    });
    return result.data['advice'] as String?;
  }

  /// Returns advice text, or throws with the underlying reason.
  ///
  /// A `FirebaseFunctionsException` with code `resource-exhausted` is the
  /// backend's own daily-limit refusal (`enforceDailyQuota` in
  /// `abuse_guard.ts`) surfacing unchanged — `ai_coach_sheet.dart` already
  /// renders any thrown error's message generically, matching how it handled
  /// a `firebase_ai` failure before this gate, so no new error-shape handling
  /// was needed here.
  Future<String> advise(AiCoachContext context) async {
    final text = await _askCloud(context);
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
