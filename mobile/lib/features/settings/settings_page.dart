import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/state/settings_providers.dart';
import '../../shared/widgets/glass.dart';
import '../data_export/data_export_providers.dart';
import '../../core/theme/app_semantic_colors.dart';

/// Device preferences. Every control here changes real behaviour:
/// theme drives `MaterialApp.themeMode`, language drives its `locale`, and the
/// reminder switch gates the actual `scheduleReminder` call. Nothing on this
/// page is decorative — a settings screen full of inert switches is worse than
/// no settings screen.
///
/// Units are deliberately absent: the app stores and shows metric everywhere
/// and nothing reads a unit preference, so a toggle would do nothing.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final exportState = ref.watch(dataExportActionProvider);

    ref.listen<AsyncValue<void>>(dataExportActionProvider, (prev, next) {
      next.whenOrNull(error: (e, _) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).catalogError(e))),
        );
      });
    });

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).profileSettings),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          _Section(
            key: const Key('settings-section-appearance'),
            title: AppLocalizations.of(context).settingsAppearance,
            child: Column(
              children: [
                for (final mode in AppThemeMode.values)
                  RadioListTile<AppThemeMode>(
                    key: Key('settings-theme-${mode.name}'),
                    value: mode,
                    groupValue: settings.themeMode,
                    onChanged: (v) {
                      if (v != null) controller.setThemeMode(v);
                    },
                    title: Text(_themeLabel(context, mode)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            key: const Key('settings-section-language'),
            title: AppLocalizations.of(context).settingsLanguage,
            child: Column(
              children: [
                for (final lang in AppLanguage.values)
                  RadioListTile<AppLanguage>(
                    key: Key('settings-language-${lang.name}'),
                    value: lang,
                    groupValue: settings.language,
                    onChanged: (v) {
                      if (v != null) controller.setLanguage(v);
                    },
                    title: Text(_languageLabel(context, lang)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            key: const Key('settings-section-reminders'),
            title: AppLocalizations.of(context).settingsReminders,
            child: SwitchListTile(
              key: const Key('settings-notifications'),
              value: settings.notificationsEnabled,
              onChanged: controller.setNotificationsEnabled,
              title:
                  Text(AppLocalizations.of(context).settingsSessionReminders),
              subtitle: Text(
                settings.notificationsEnabled
                    ? AppLocalizations.of(context).settingsRemindersOnBody
                    : AppLocalizations.of(context).settingsRemindersOffBody,
                style: theme.textTheme.bodySmall,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),
          // Unlocks the paid surfaces on this device only. Nothing is written
          // to Firestore and no Stripe object is invented — it changes what
          // this phone believes about itself and nothing else. It exists
          // because there was no way to open a premium screen at all: Stripe
          // is in sandbox, sandbox rejects made-up card numbers, and the
          // reasonable conclusion from a declined card is "the app is broken".
          _Section(
            key: const Key('settings-section-tier'),
            title: AppLocalizations.of(context).settingsTestAccess,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    AppLocalizations.of(context).settingsTestAccessBody,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colors.textSecondary,
                    ),
                  ),
                ),
                for (final o in TierOverride.values)
                  RadioListTile<TierOverride>(
                    key: Key('settings-tier-${o.name}'),
                    value: o,
                    groupValue: settings.tierOverride,
                    onChanged: (v) {
                      if (v != null) controller.setTierOverride(v);
                    },
                    title: Text(_tierLabel(context, o)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            key: const Key('settings-about'),
            onTap: () => context.push('/about'),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(AppLocalizations.of(context).settingsAboutThisApp,
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            key: const Key('settings-terms'),
            onTap: () => context.push('/terms'),
            child: Row(
              children: [
                Icon(Icons.gavel_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(AppLocalizations.of(context).legalTermsOfService,
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            key: const Key('settings-privacy'),
            onTap: () => context.push('/privacy'),
            child: Row(
              children: [
                Icon(Icons.privacy_tip_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(AppLocalizations.of(context).legalPrivacyPolicy,
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // L0c. Structured, textual data only -- profile (incl. injuries),
          // full workout + schedule history, progress-photo metadata. NOT
          // the photos themselves, because there are none: the only bound
          // repository is the in-memory mock, so there are no bytes to
          // package and no key to reason about. When R7 lands a real store,
          // whether to decrypt into a shareable file becomes a genuine
          // question; today it is not one.
          GlassCard(
            key: const Key('settings-export-data'),
            onTap: exportState.isLoading
                ? null
                : () => ref.read(dataExportActionProvider.notifier).export(),
            child: Row(
              children: [
                if (exportState.isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else
                  Icon(Icons.download_outlined,
                      color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(AppLocalizations.of(context).settingsExportData,
                      style: theme.textTheme.titleMedium),
                ),
                if (!exportState.isLoading) const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // H2b. Separate from the export above, and deliberately so: that one
          // is the GDPR copy -- everything, plain, readable, no secret needed.
          // This one is the transfer, and carries only the health block,
          // because that is the only half a reinstall cannot bring back.
          // Encrypting the export instead would have made a data-portability
          // file unreadable without a passphrase, which is the opposite of
          // portable.
          GlassCard(
            key: const Key('settings-backup-transfer'),
            onTap: () => GoRouter.of(context).push('/backup'),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                      AppLocalizations.of(context).settingsBackupTransfer,
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Not optional decoration: the bundled content ships under licences
          // that require visible attribution. See core/licences/.
          GlassCard(
            key: const Key('settings-licences'),
            onTap: () => context.push('/licences'),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                      AppLocalizations.of(context).settingsLicencesAndCredits,
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // The moderation console. Routed, translated, finished — and linked
          // from nowhere, so the only person who could approve a community
          // submission had no way to open the queue.
          //
          // In Settings rather than on the profile because it is an operator
          // console, not a feature. It is not hidden behind a client-side
          // moderator check because there is no such check to hide it behind:
          // the Firestore rules enforce the moderator claim, and a client flag
          // would be decoration over the real gate. A curious user who taps it
          // sees an empty queue, which is the truth.
          GlassCard(
            key: const Key('settings-moderation'),
            onTap: () => context.push('/moderate'),
            child: Row(
              children: [
                Icon(Icons.rule_folder_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                      AppLocalizations.of(context).catalogModerationQueue,
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // L0b. Visually separated from every tile above it -- error colour
          // throughout, not just the icon -- because this is the one action
          // on this page that is not reversible by tapping it again.
          GlassCard(
            key: const Key('settings-delete-account'),
            onTap: () => context.push('/delete-account'),
            child: Row(
              children: [
                Icon(Icons.delete_forever_outlined,
                    color: theme.colorScheme.error),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context).settingsDeleteAccount,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)
                            .settingsDeleteAccountSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.error),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(BuildContext context, AppThemeMode mode) {
    final l = AppLocalizations.of(context);
    return switch (mode) {
      AppThemeMode.system => l.settingsFollowTheSystem,
      AppThemeMode.light => l.settingsThemeLight,
      AppThemeMode.dark => l.settingsThemeDark,
    };
  }

  String _languageLabel(BuildContext context, AppLanguage lang) =>
      switch (lang) {
        AppLanguage.system =>
          AppLocalizations.of(context).settingsFollowTheSystem,
        // Endonyms, not English names, and never translated: a user looking for
        // their own language scans for the word they actually call it.
        AppLanguage.ru => 'Русский',
        AppLanguage.en => 'English',
      };

  String _tierLabel(BuildContext context, TierOverride o) => switch (o) {
        TierOverride.off => AppLocalizations.of(context).settingsTierOff,
        TierOverride.standard =>
          AppLocalizations.of(context).settingsTierStandard,
        TierOverride.celebrity =>
          AppLocalizations.of(context).settingsTierCelebrity,
      };
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
