import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/notification_providers.dart';
import '../app_settings.dart';
import '../settings_repository.dart';

/// Where settings are persisted. `main.dart` overrides this with the
/// SharedPreferences implementation; tests and widget previews get the
/// in-memory one.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (_) => InMemorySettingsRepository(),
);

/// Settings as loaded at launch.
///
/// Read synchronously on purpose: theme and locale are needed on the very
/// first frame, and resolving them through an async provider would flash the
/// wrong theme (and the wrong language) before settling. `main.dart` awaits
/// the load once and overrides this.
final initialSettingsProvider = Provider<AppSettings>(
  (_) => const AppSettings(),
);

/// Live settings. Writes go to state first so the UI turns instantly, then
/// persist in the background — a slow disk must not make a switch feel stuck.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> setThemeMode(AppThemeMode mode) =>
      _update(state.copyWith(themeMode: mode));

  Future<void> setLanguage(AppLanguage language) =>
      _update(state.copyWith(language: language));

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _update(state.copyWith(notificationsEnabled: enabled));
    if (enabled) return;
    // Turning reminders off has to silence the ones already queued too —
    // otherwise "off" would only apply to sessions scheduled from now on and
    // the user would keep getting alerts they just switched off.
    try {
      await ref.read(notificationServiceProvider).cancelAll();
    } catch (e) {
      // The preference is saved regardless; log rather than swallow so a
      // platform refusal is diagnosable.
      debugPrint('failed to cancel queued reminders: $e');
    }
  }

  Future<void> _update(AppSettings next) async {
    if (next == state) return;
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
