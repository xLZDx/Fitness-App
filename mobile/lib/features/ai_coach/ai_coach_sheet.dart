import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/state/settings_providers.dart';
import '../../shared/widgets/app_buttons.dart';
import 'ai_coach_context.dart';
import 'ai_coach_service.dart';
import '../../core/theme/app_semantic_colors.dart';

/// Bottom sheet with one round of machine-specific coaching advice.
///
/// This is the visible "AI" the operator asked for: a button on every machine
/// page, an answer generated for that machine in the interface language. The
/// provider is autoDispose+family, so reopening the sheet for the same
/// machine within a session reuses the cached answer instead of re-billing
/// the free-tier quota.
class AiCoachSheet extends ConsumerWidget {
  const AiCoachSheet({
    super.key,
    required this.source,
    required this.subjectId,
    required this.subjectName,
  });

  /// Which screen opened it — see [AiCoachContext] for why the prompt needs it.
  final AiCoachSource source;

  /// Stable catalog id. The cache key; a display name used to be, and collided.
  final String subjectId;

  /// What to call it, on screen and in the prompt.
  final String subjectName;

  static Future<void> show(
    BuildContext context, {
    required AiCoachSource source,
    required String subjectId,
    required String subjectName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AiCoachSheet(
        source: source,
        subjectId: subjectId,
        subjectName: subjectName,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Read here rather than passed in: the language is a user setting, not a
    // property of the subject, and a caller that had to supply it would be the
    // caller that gets it stale.
    final request = AiCoachContext(
      source: source,
      subjectId: subjectId,
      subjectName: subjectName,
      languageCode: ref.watch(effectiveLanguageCodeProvider),
    );
    final advice = ref.watch(aiCoachAdviceProvider(request));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).aiCoachTitle(subjectName),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: advice.when(
                  loading: () => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(AppLocalizations.of(context).aiCoachThinking),
                      ],
                    ),
                  ),
                  error: (e, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).aiCoachFailed('$e'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 8),
                      AppTertiaryButton(
                        onPressed: () =>
                            ref.invalidate(aiCoachAdviceProvider(request)),
                        label: AppLocalizations.of(context).aiCoachRetry,
                      ),
                    ],
                  ),
                  data: (text) => SingleChildScrollView(
                    child: Text(text, style: theme.textTheme.bodyMedium),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).aiCoachDisclaimer,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
