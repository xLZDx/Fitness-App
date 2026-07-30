import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/state/settings_providers.dart';
import 'ai_coach_service.dart';

/// Bottom sheet with one round of machine-specific coaching advice.
///
/// This is the visible "AI" the operator asked for: a button on every machine
/// page, an answer generated for that machine in the interface language. The
/// provider is autoDispose+family, so reopening the sheet for the same
/// machine within a session reuses the cached answer instead of re-billing
/// the free-tier quota.
class AiCoachSheet extends ConsumerWidget {
  const AiCoachSheet({super.key, required this.machineName});

  final String machineName;

  static Future<void> show(BuildContext context, {required String machineName}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AiCoachSheet(machineName: machineName),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final language = ref.watch(effectiveLanguageCodeProvider);
    final advice = ref
        .watch(aiCoachAdviceProvider((machine: machineName, language: language)));

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
                      AppLocalizations.of(context).aiCoachTitle(machineName),
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
                      TextButton(
                        onPressed: () => ref.invalidate(aiCoachAdviceProvider(
                            (machine: machineName, language: language))),
                        child:
                            Text(AppLocalizations.of(context).aiCoachRetry),
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
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
