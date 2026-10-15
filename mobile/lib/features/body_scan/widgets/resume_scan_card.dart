/// "Finish your scan" card for a non-terminal scan record, and the terminal
/// failure variant with Retry / Keep on this device / Delete (D-78): an app kill
/// never leaves an invisible job and a failure is never a dead end.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';

class ResumeScanCard extends StatelessWidget {
  /// Non-terminal record: Resume / Cancel.
  const ResumeScanCard.pending({
    super.key,
    required VoidCallback this.onResume,
    required VoidCallback this.onCancel,
  })  : failed = false,
        onRetry = null,
        onKeep = null,
        onDelete = null;

  /// Terminal failure (after the retries): Retry / Keep on device / Delete.
  const ResumeScanCard.failed({
    super.key,
    required VoidCallback this.onRetry,
    required VoidCallback this.onKeep,
    required VoidCallback this.onDelete,
  })  : failed = true,
        onResume = null,
        onCancel = null;

  final bool failed;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onKeep;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    ButtonStyle s() => TextButton.styleFrom(minimumSize: const Size(48, 48));
    return GlassCard(
      key: Key(failed ? 'bodyScan.failedCard' : 'bodyScan.resumeCard'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(failed ? Icons.error_outline : Icons.pending_actions,
                  color: failed ? context.colors.danger : hud.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                      failed
                          ? l10n.bodyScanFailedTitle
                          : l10n.bodyScanResumeTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: hud.textPrimary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(failed ? l10n.bodyScanFailedBody : l10n.bodyScanResumeBody,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: hud.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: failed
                ? [
                    FilledButton(
                      key: const Key('bodyScan.failed.retry'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48)),
                      onPressed: onRetry,
                      child: Text(l10n.bodyScanFailedRetry),
                    ),
                    TextButton(
                      key: const Key('bodyScan.failed.keep'),
                      style: s(),
                      onPressed: onKeep,
                      child: Text(l10n.bodyScanFailedKeep),
                    ),
                    TextButton(
                      key: const Key('bodyScan.failed.delete'),
                      style: s(),
                      onPressed: onDelete,
                      child: Text(l10n.bodyScanFailedDelete),
                    ),
                  ]
                : [
                    FilledButton(
                      key: const Key('bodyScan.resume.resume'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48)),
                      onPressed: onResume,
                      child: Text(l10n.bodyScanResumeAction),
                    ),
                    TextButton(
                      key: const Key('bodyScan.resume.cancel'),
                      style: s(),
                      onPressed: onCancel,
                      child: Text(l10n.bodyScanCancel),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}
