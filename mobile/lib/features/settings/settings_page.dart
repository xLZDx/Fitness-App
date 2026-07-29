import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../core/settings/state/settings_providers.dart';
import '../../shared/widgets/glass.dart';

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

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          _Section(
            title: 'Appearance',
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
                    title: Text(_themeLabel(mode)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Language',
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
                    title: Text(_languageLabel(lang)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Reminders',
            child: SwitchListTile(
              key: const Key('settings-notifications'),
              value: settings.notificationsEnabled,
              onChanged: controller.setNotificationsEnabled,
              title: const Text('Session reminders'),
              subtitle: Text(
                settings.notificationsEnabled
                    ? 'A notification before each scheduled session.'
                    : 'Scheduled sessions are saved but stay silent.',
                style: theme.textTheme.bodySmall,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            onTap: () => context.push('/about'),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('About this app',
                      style: theme.textTheme.titleMedium),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => 'Follow the system',
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
      };

  String _languageLabel(AppLanguage lang) => switch (lang) {
        AppLanguage.system => 'Follow the system',
        // Endonyms, not English names: a user looking for their own language
        // scans for the word they actually call it.
        AppLanguage.ru => 'Русский',
        AppLanguage.en => 'English',
      };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

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
