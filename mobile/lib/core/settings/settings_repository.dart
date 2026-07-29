import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// Persistence boundary for [AppSettings].
abstract class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// SharedPreferences-backed store. Local-only by design: these are device
/// preferences, not account data, so they should not follow a sign-in.
class PrefsSettingsRepository implements SettingsRepository {
  PrefsSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _themeKey = 'settings.theme_mode';
  static const _languageKey = 'settings.language';
  static const _notificationsKey = 'settings.notifications_enabled';

  static Future<PrefsSettingsRepository> open() async {
    return PrefsSettingsRepository(await SharedPreferences.getInstance());
  }

  /// Resolves a stored enum name, falling back to [fallback] for anything
  /// unrecognised. A value written by a newer build must not crash an older
  /// one, and a corrupt string must not wedge the app at launch.
  static T _readEnum<T extends Enum>(
    String? raw,
    List<T> values,
    T fallback,
  ) {
    if (raw == null) return fallback;
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  @override
  Future<AppSettings> load() async {
    const defaults = AppSettings();
    return AppSettings(
      themeMode: _readEnum(
        _prefs.getString(_themeKey),
        AppThemeMode.values,
        defaults.themeMode,
      ),
      language: _readEnum(
        _prefs.getString(_languageKey),
        AppLanguage.values,
        defaults.language,
      ),
      notificationsEnabled: _prefs.getBool(_notificationsKey) ??
          defaults.notificationsEnabled,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_themeKey, settings.themeMode.name);
    await _prefs.setString(_languageKey, settings.language.name);
    await _prefs.setBool(_notificationsKey, settings.notificationsEnabled);
  }
}

/// Test/demo store. Keeps the last saved value in memory.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this._current = const AppSettings()]);

  AppSettings _current;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    _current = settings;
    saveCount += 1;
  }
}
