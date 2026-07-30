import 'package:flutter/material.dart' show Locale, ThemeMode;

/// The locales the app actually ships translations for.
///
/// Order is load-bearing: this list is passed to `MaterialApp.supportedLocales`
/// verbatim, and Flutter falls back to the FIRST entry for any device locale it
/// cannot match. So the first entry is also what [AppLanguage.system] resolves
/// to on an unsupported device.
const List<String> kSupportedLocaleCodes = <String>['ru', 'en'];

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

  /// The language the user will actually SEE, resolved the same way Flutter
  /// resolves it — so UI chrome and bundled content can never disagree.
  ///
  /// Testing `language == AppLanguage.ru` instead of calling this is the bug
  /// this method exists to prevent: [AppLanguage.system] has no code of its
  /// own, so on a device set to, say, French, Flutter resolves the interface to
  /// `ru` (first in [kSupportedLocaleCodes]) while that equality check answers
  /// "not Russian" and leaves bundled text in English. The result is a screen
  /// that is half translated, with no error and nothing in the logs.
  String resolvedLocaleCode(Iterable<Locale> deviceLocales) {
    final own = localeCode;
    if (own != null) return own;
    for (final locale in deviceLocales) {
      if (kSupportedLocaleCodes.contains(locale.languageCode)) {
        return locale.languageCode;
      }
    }
    return kSupportedLocaleCodes.first;
  }
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
