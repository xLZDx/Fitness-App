import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/glass.dart';
import 'backup_envelope.dart';
import 'backup_providers.dart';
import 'backup_transfer.dart';
import '../../shared/widgets/app_buttons.dart';

/// H2b — create a transfer backup, or restore one.
///
/// Two halves on one page rather than two routes, because they are one task
/// seen from two devices: the old phone makes the file, the new phone opens
/// it. A user who has just reinstalled looks for "the backup screen", not for
/// "restore", and finding both here means the passphrase warning is read by
/// the person who has to remember it.
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  final _createPass = TextEditingController();
  final _restorePass = TextEditingController();
  final _restoreBody = TextEditingController();
  bool _restoreDone = false;

  Future<void> _restore() async {
    setState(() => _restoreDone = false);
    await ref.read(backupRestoreActionProvider.notifier).restore(
          envelope: _restoreBody.text,
          passphrase: _restorePass.text,
        );
    if (!mounted) return;
    final failed = ref.read(backupRestoreActionProvider).hasError;
    setState(() => _restoreDone = !failed);
  }

  @override
  void dispose() {
    // Passphrases are held only as long as the fields are on screen. A
    // controller left undisposed keeps its text alive in the widget tree for
    // as long as the route object survives.
    _createPass.dispose();
    _restorePass.dispose();
    _restoreBody.dispose();
    super.dispose();
  }

  /// Turns an exception into a sentence the user can act on.
  ///
  /// The three cases are deliberately distinct. Told "wrong passphrase" when
  /// the real problem is the wrong file, a user retypes a correct passphrase
  /// forever; told "damaged file" when they simply mistyped, they give up on a
  /// backup that was fine.
  String _message(AppLocalizations l10n, Object error) {
    if (error is BackupPassphraseException) return l10n.backupWrongPassphrase;
    if (error is BackupFormatException) return l10n.backupNotABackupFile;
    if (error is TransferPayloadException) return l10n.backupNotABackupFile;
    return l10n.backupSomethingWentWrong;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final createState = ref.watch(backupCreateActionProvider);
    final restoreState = ref.watch(backupRestoreActionProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.backupTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.backupWhatItCarriesTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(l10n.backupWhatItCarriesBody,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- create -------------------------------------------------
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.backupCreateTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                // The warning sits ABOVE the field, not under the button and
                // not in a help page: it has to be read before the passphrase
                // is chosen, because after that it is advice about a decision
                // already made.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.key_outlined,
                        size: 18, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.backupPassphraseWarning,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('backup-create-passphrase'),
                  controller: _createPass,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.backupPassphraseLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                AppPrimaryButton(
                  key: const Key('backup-create-button'),
                  // The spinner used to be a bare `CircularProgressIndicator`,
                  // which takes `colorScheme.primary` — the same colour this
                  // button paints its background. Pressing "back up" gave no
                  // visible feedback at all while it worked.
                  loading: createState.isLoading,
                  onPressed: _createPass.text.isEmpty
                      ? null
                      : () => ref
                          .read(backupCreateActionProvider.notifier)
                          .create(_createPass.text),
                  icon: Icons.lock_outline,
                  label: l10n.backupCreateButton,
                ),
                if (createState.hasError) ...[
                  const SizedBox(height: 10),
                  Text(
                    _message(l10n, createState.error!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // --- restore ------------------------------------------------
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.backupRestoreTitle,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(l10n.backupRestoreHint,
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('backup-restore-body'),
                  controller: _restoreBody,
                  maxLines: 5,
                  minLines: 3,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.backupPasteLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('backup-restore-passphrase'),
                  controller: _restorePass,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.backupPassphraseLabel,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                AppPrimaryButton(
                  key: const Key('backup-restore-button'),
                  loading: restoreState.isLoading,
                  onPressed: _restoreBody.text.trim().isEmpty ||
                          _restorePass.text.isEmpty
                      ? null
                      : _restore,
                  icon: Icons.restore,
                  label: l10n.backupRestoreButton,
                ),
                if (restoreState.hasError) ...[
                  const SizedBox(height: 10),
                  Text(
                    _message(l10n, restoreState.error!),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                // An explicit flag, not `restoreState.hasValue`: the notifier
                // starts life as AsyncData(null), so "has a value" is true
                // before anything has been restored and the confirmation would
                // greet a user who has done nothing yet.
                if (_restoreDone && !restoreState.isLoading) ...[
                  const SizedBox(height: 10),
                  Text(l10n.backupRestoreDone,
                      style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
