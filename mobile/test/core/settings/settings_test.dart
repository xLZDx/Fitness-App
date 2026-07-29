import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/settings_repository.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings', () {
    test('defaults match the behaviour shipped before settings existed', () {
      const s = AppSettings();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.language, AppLanguage.ru,
          reason: 'Russian was pinned as the product default');
      expect(s.notificationsEnabled, isTrue);
    });

    test('system language resolves to a null locale code', () {
      expect(AppLanguage.system.localeCode, isNull);
      expect(AppLanguage.ru.localeCode, 'ru');
      expect(AppLanguage.en.localeCode, 'en');
    });

    test('copyWith leaves untouched fields alone', () {
      const s = AppSettings();
      final next = s.copyWith(themeMode: AppThemeMode.dark);
      expect(next.themeMode, AppThemeMode.dark);
      expect(next.language, s.language);
      expect(next.notificationsEnabled, s.notificationsEnabled);
    });

    test('equality is by value so no-op writes can be skipped', () {
      expect(const AppSettings(), const AppSettings());
      expect(const AppSettings(),
          isNot(const AppSettings(themeMode: AppThemeMode.dark)));
    });
  });

  group('PrefsSettingsRepository', () {
    test('round-trips every field', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await PrefsSettingsRepository.open();

      const saved = AppSettings(
        themeMode: AppThemeMode.dark,
        language: AppLanguage.en,
        notificationsEnabled: false,
      );
      await repo.save(saved);

      // Re-open so the read goes through the store, not through memory.
      final reopened = await PrefsSettingsRepository.open();
      expect(await reopened.load(), saved);
    });

    test('an empty store yields the defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await PrefsSettingsRepository.open();
      expect(await repo.load(), const AppSettings());
    });

    // A value written by a newer build, or a corrupted string, must not wedge
    // the app on launch — settings are read before the first frame.
    test('an unrecognised stored value falls back to the default', () async {
      SharedPreferences.setMockInitialValues({
        'settings.theme_mode': 'solarized',
        'settings.language': 'kl',
      });
      final repo = await PrefsSettingsRepository.open();
      final loaded = await repo.load();
      expect(loaded.themeMode, AppThemeMode.system);
      expect(loaded.language, AppLanguage.ru);
    });
  });

  group('SettingsController', () {
    ProviderContainer build({
      InMemorySettingsRepository? repo,
      MockNotificationService? notifications,
    }) {
      return ProviderContainer(overrides: [
        if (repo != null) settingsRepositoryProvider.overrideWithValue(repo),
        if (notifications != null)
          notificationServiceProvider.overrideWithValue(notifications),
      ]);
    }

    test('a theme change is published and persisted', () async {
      final repo = InMemorySettingsRepository();
      final c = build(repo: repo);
      addTearDown(c.dispose);

      await c
          .read(settingsControllerProvider.notifier)
          .setThemeMode(AppThemeMode.dark);

      expect(c.read(settingsControllerProvider).themeMode, AppThemeMode.dark);
      expect((await repo.load()).themeMode, AppThemeMode.dark);
    });

    test('a language change is published and persisted', () async {
      final repo = InMemorySettingsRepository();
      final c = build(repo: repo);
      addTearDown(c.dispose);

      await c
          .read(settingsControllerProvider.notifier)
          .setLanguage(AppLanguage.en);

      expect(c.read(settingsControllerProvider).language, AppLanguage.en);
      expect((await repo.load()).language, AppLanguage.en);
    });

    test('writing the value it already holds does not hit the store', () async {
      final repo = InMemorySettingsRepository();
      final c = build(repo: repo);
      addTearDown(c.dispose);

      await c
          .read(settingsControllerProvider.notifier)
          .setThemeMode(AppThemeMode.system);

      expect(repo.saveCount, 0);
    });

    // Turning reminders off has to silence what is already queued. Otherwise
    // "off" would only apply to sessions scheduled after the switch and the
    // user keeps getting alerts they just disabled.
    test('turning reminders off cancels the ones already queued', () async {
      final notifications = MockNotificationService();
      await notifications.scheduleReminder(
        ScheduledSession(
          id: 'already-queued',
          exerciseId: 'pushup',
          exerciseTitle: 'Push-ups',
          scheduledFor: DateTime.now().add(const Duration(days: 1)),
          durationMinutes: 10,
          status: ScheduledSessionStatus.pending,
        ),
      );
      expect(notifications.scheduled, hasLength(1));

      final c = build(
        repo: InMemorySettingsRepository(),
        notifications: notifications,
      );
      addTearDown(c.dispose);

      await c
          .read(settingsControllerProvider.notifier)
          .setNotificationsEnabled(false);

      expect(notifications.scheduled, isEmpty);
    });

    test('turning reminders on does not cancel anything', () async {
      final notifications = MockNotificationService();
      final c = build(
        repo: InMemorySettingsRepository(
          const AppSettings(notificationsEnabled: false),
        ),
        notifications: notifications,
      );
      addTearDown(c.dispose);

      await c
          .read(settingsControllerProvider.notifier)
          .setNotificationsEnabled(true);

      expect(c.read(settingsControllerProvider).notificationsEnabled, isTrue);
    });
  });

  group('the reminder switch gates real scheduling', () {
    ProviderContainer build({
      required MockNotificationService notifications,
      required bool remindersOn,
    }) {
      return ProviderContainer(overrides: [
        scheduledSessionRepositoryProvider
            .overrideWithValue(MockScheduledSessionRepository()),
        authUserProvider.overrideWith(
          (_) => Stream.value(
            const AuthUser(uid: 'u1', email: 'a@b.c', displayName: 'A'),
          ),
        ),
        notificationServiceProvider.overrideWithValue(notifications),
        initialSettingsProvider
            .overrideWithValue(AppSettings(notificationsEnabled: remindersOn)),
      ]);
    }

    ScheduledSession session() => ScheduledSession(
          id: 's1',
          exerciseId: 'pushup',
          exerciseTitle: 'Push-ups',
          scheduledFor: DateTime.now().add(const Duration(days: 2)),
          durationMinutes: 10,
          status: ScheduledSessionStatus.pending,
        );

    test('reminders on: scheduling a session queues a notification', () async {
      final notifications = MockNotificationService();
      final c = build(notifications: notifications, remindersOn: true);
      addTearDown(c.dispose);
      // Let the auth stream deliver before the action reads it.
      await c.read(authUserProvider.future);

      await c
          .read(scheduleSessionActionProvider.notifier)
          .schedule(session());

      expect(notifications.scheduled.map((r) => r.sessionId), ['s1']);
    });

    test('reminders off: the session is saved but stays silent', () async {
      final notifications = MockNotificationService();
      final c = build(notifications: notifications, remindersOn: false);
      addTearDown(c.dispose);
      await c.read(authUserProvider.future);

      await c
          .read(scheduleSessionActionProvider.notifier)
          .schedule(session());

      expect(c.read(scheduleSessionActionProvider).hasError, isFalse,
          reason: 'the save itself must still succeed');
      expect(notifications.scheduled, isEmpty);
    });
  });
}
