/// Photo privacy settings (C16): retention choice, "apply to existing photos",
/// delete all cloud photos or scans, withdraw cloud consent and pause tracking
/// (design s9, s17, D-62, D-77). The copy is honest about timing: photos are
/// deleted WITHIN 48 hours of the chosen time (a daily purge, F12), and photos
/// kept on this phone are never touched from here.
///
/// The cloud sections appear only when the build offers cloud analysis
/// (`BODY_SCAN_CLOUD`); with it off no photo ever left the phone and no
/// callable is called (SD-12).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/body_scan_flags.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';
import '../state/body_scan_manage_api.dart';
import '../state/body_scan_providers.dart';
import '../state/body_scan_settings.dart';

class RetentionSettingsView extends ConsumerStatefulWidget {
  const RetentionSettingsView({super.key});

  @override
  ConsumerState<RetentionSettingsView> createState() =>
      _RetentionSettingsViewState();
}

enum _Bulk { applyRetention, deletePhotos, deleteScans }

class _RetentionSettingsViewState extends ConsumerState<RetentionSettingsView> {
  bool _busy = false;

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(String title, String body, String confirm) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('bodyScan.privacy.confirmDialog'),
        title: Semantics(header: true, focusable: true, child: Text(title)),
        content: Text(body),
        actions: [
          TextButton(
            key: const Key('bodyScan.privacy.confirmCancel'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.bodyScanCancel),
          ),
          FilledButton(
            key: const Key('bodyScan.privacy.confirmOk'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _bulk(_Bulk kind, BodyScanSettings settings) async {
    final l10n = AppLocalizations.of(context);
    final api = ref.read(bodyScanManageApiProvider);
    final String done;
    switch (kind) {
      case _Bulk.applyRetention:
        done = l10n.bodyScanPrivacyApplyDone;
      case _Bulk.deletePhotos:
        if (!await _confirm(l10n.bodyScanPrivacyDeletePhotosTitle,
            l10n.bodyScanPrivacyDeletePhotosBody,
            l10n.bodyScanPrivacyDeletePhotosConfirm)) {
          return;
        }
        done = l10n.bodyScanPrivacyDeleteDone;
      case _Bulk.deleteScans:
        if (!await _confirm(l10n.bodyScanPrivacyDeleteScansTitle,
            l10n.bodyScanPrivacyDeleteScansBody,
            l10n.bodyScanPrivacyDeleteScansConfirm)) {
          return;
        }
        done = l10n.bodyScanPrivacyDeleteDone;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      switch (kind) {
        case _Bulk.applyRetention:
          await api.applyRetention(settings.retentionDays);
        case _Bulk.deletePhotos:
          await api.deleteAllPhotos();
        case _Bulk.deleteScans:
          await api.deleteAllScans();
      }
      _say(done);
    } catch (_) {
      _say(l10n.bodyScanPrivacyFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _guarded(Future<void> Function() write) async {
    final l10n = AppLocalizations.of(context);
    try {
      await write();
    } catch (_) {
      _say(l10n.bodyScanPrivacyFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final cloud = ref.watch(bodyScanFlagsProvider).cloudPhotos;
    final settings = ref.watch(bodyScanSettingsProvider).valueOrNull ??
        const BodyScanSettings();
    final store = ref.read(bodyScanSettingsStoreProvider);

    String choiceLabel(int d) =>
        d == 0 ? l10n.bodyScanRetention0 : l10n.bodyScanRetentionDays(d);

    return ListView(
      padding: const EdgeInsets.all(HudTokens.screenGutter),
      children: [
        Text(
          cloud ? l10n.bodyScanPrivacyIntroCloud : l10n.bodyScanPrivacyIntroLocal,
          key: const Key('bodyScan.privacy.intro'),
          style: theme.textTheme.bodyMedium?.copyWith(color: hud.textSecondary),
        ),
        const SizedBox(height: 12),
        if (cloud) ...[
          GlassCard(
            key: const Key('bodyScan.privacy.retentionCard'),
            child: Semantics(
              container: true,
              label: l10n.bodyScanPrivacyRetentionTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(l10n.bodyScanPrivacyRetentionTitle,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: hud.textPrimary)),
                  ),
                  const SizedBox(height: 4),
                  for (final d in kRetentionChoices)
                    Semantics(
                      inMutuallyExclusiveGroup: true,
                      selected: settings.retentionDays == d,
                      button: true,
                      child: ListTile(
                        key: Key('bodyScan.privacy.retention.$d'),
                        minVerticalPadding: 12,
                        title: Text(choiceLabel(d)),
                        trailing: settings.retentionDays == d
                            ? const Icon(Icons.check)
                            : null,
                        onTap: _busy
                            ? null
                            : () => _guarded(() => store.setRetentionDays(d)),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(l10n.bodyScanRetentionHonest,
                      key: const Key('bodyScan.privacy.honest'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: hud.textSecondary)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('bodyScan.privacy.apply'),
                    style:
                        OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _busy
                        ? null
                        : () => _bulk(_Bulk.applyRetention, settings),
                    child: Text(l10n.bodyScanPrivacyApply),
                  ),
                  Text(l10n.bodyScanPrivacyApplyHelp,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: hud.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            key: const Key('bodyScan.privacy.consentCard'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.hasCurrentConsent
                      ? l10n.bodyScanPrivacyConsentOn
                      : l10n.bodyScanPrivacyConsentOff,
                  key: const Key('bodyScan.privacy.consentText'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: hud.textPrimary),
                ),
                if (settings.cloudConsentVersion != null)
                  TextButton(
                    key: const Key('bodyScan.privacy.withdraw'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _busy
                        ? null
                        : () => _guarded(store.withdrawCloudConsent),
                    child: Text(l10n.bodyScanPrivacyWithdraw),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            key: const Key('bodyScan.privacy.deleteCard'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(l10n.bodyScanPrivacyDeleteTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: hud.textPrimary)),
                ),
                const SizedBox(height: 4),
                Text(l10n.bodyScanPrivacyDeleteHelp,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: hud.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton(
                      key: const Key('bodyScan.privacy.deletePhotos'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48)),
                      onPressed: _busy
                          ? null
                          : () => _bulk(_Bulk.deletePhotos, settings),
                      child: Text(l10n.bodyScanPrivacyDeletePhotos),
                    ),
                    OutlinedButton(
                      key: const Key('bodyScan.privacy.deleteScans'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48)),
                      onPressed: _busy
                          ? null
                          : () => _bulk(_Bulk.deleteScans, settings),
                      child: Text(l10n.bodyScanPrivacyDeleteScans),
                    ),
                  ],
                ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      label: l10n.bodyScanPrivacyWorking,
                      // Reduced motion: a static text instead of the
                      // indeterminate bar (design s24, D-81).
                      child: context.reduceMotion
                          ? Text(l10n.bodyScanPrivacyWorking)
                          : const LinearProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        GlassCard(
          key: const Key('bodyScan.privacy.pauseCard'),
          child: SwitchListTile(
            key: const Key('bodyScan.privacy.pause'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.bodyScanPrivacyPause),
            subtitle: Text(l10n.bodyScanPrivacyPauseHelp),
            value: settings.paused,
            onChanged: (v) => _guarded(() => store.setPaused(v)),
          ),
        ),
      ],
    );
  }
}
