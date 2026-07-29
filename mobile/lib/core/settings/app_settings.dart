import 'package:flutter/material.dart' show ThemeMode;

/// Which theme the user picked. Stored as its own enum rather than Flutter's
/// [ThemeMode] so the persisted name never depends on a framework type.
enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  ThemeMode get material => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

/// The languages the app ships translations for. `system` follows the device.
enum AppLanguage { system, ru, en }

extension AppLanguageX on AppLanguage {
  /// `null` means "let Flutter resolve from the device locale".
  String? get localeCode => switch (this) {
        AppLanguage.system => null,
        AppLanguage.ru => 'ru',
        AppLanguage.en => 'en',
      };
}

/// User-controlled app preferences, persisted locally.
///
/// Defaults deliberately match the shipped behaviour before settings existed:
/// system theme, Russian pinned (the launch market is RU/CIS), reminders on.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.language = AppLanguage.ru,
    this.notificationsEnabled = true,
  });

  final AppThemeMode themeMode;
  final AppLanguage language;

  /// When false, session reminders are not scheduled at all. This gates the
  /// real call site — it is not a decorative switch.
  final bool notificationsEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppLanguage? language,
    bool? notificationsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.language == language &&
      other.notificationsEnabled == notificationsEnabled;

  @override
  int get hashCode => Object.hash(themeMode, language, notificationsEnabled);

  @override
  String toString() => 'AppSettings(theme: ${themeMode.name}, '
      'language: ${language.name}, notifications: $notificationsEnabled)';
}
