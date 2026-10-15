// C17 weekly reminder editor (design s19, D-21, D-74, D-77): weekday chips, the
// time picker, the pause switch, locale-aware weekday/time text and 48 dp
// targets. Real notifier and in-memory settings store; only the platform
// notification service is the mock.
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/body_scan/data/scan_plan_context.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_providers.dart';
import 'package:fitness_app/features/body_scan/state/body_scan_settings.dart';
import 'package:fitness_app/features/body_scan/state/scan_plan_context_provider.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_reminder_editor.dart';

class _MemRepo implements ScanRepository {
  _MemRepo(this.items);
  final List<ScanRecord> items;
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async => items.removeWhere((r) => r.id == id);
}

class _Source extends ScanPlanContextSource {
  const _Source(this.mode);
  final ScanSurfaceMode mode;
  @override
  ScanPlanContext current() => ScanPlanContext(surfaceMode: mode);
}

class _ThrowingScheduler extends MockNotificationService {
  @override
  Future<ReminderOutcome> scheduleAt(String id,
          {required DateTime fireAt,
          required String title,
          required String body}) async =>
      throw StateError('plugin');
}

ScanRecord _scan() => ScanRecord(
      id: 's1',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      shots: const {},
    );

class _Rig {
  _Rig(this.notes, this.store);
  final MockNotificationService notes;
  final InMemoryBodyScanSettingsStore store;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  String locale = 'en',
  BodyScanSettings settings = const BodyScanSettings(
      reminder: ScanReminderPrefs(enabled: true)),
  ScanSurfaceMode mode = ScanSurfaceMode.full,
  MockNotificationService? service,
  bool withScan = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final notes = service ?? MockNotificationService();
  final store = InMemoryBodyScanSettingsStore(settings);
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      notificationServiceProvider.overrideWithValue(notes),
      scanPlanContextProvider.overrideWithValue(_Source(mode)),
      scanRepositoryProvider
          .overrideWithValue(_MemRepo([if (withScan) _scan()])),
      bodyScanSettingsStoreProvider.overrideWithValue(store),
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'x'))),
      initialSettingsProvider.overrideWithValue(AppSettings(
          language: locale == 'ru' ? AppLanguage.ru : AppLanguage.en)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: const Scaffold(body: SingleChildScrollView(child: ScanReminderEditor())),
    ),
  ));
  await tester.pumpAndSettle();
  return _Rig(notes, store);
}

Finder _chip(int d) => find.byKey(Key('scan.reminder.day.$d'));

ChoiceChip _chipWidget(WidgetTester t, int d) => t.widget<ChoiceChip>(_chip(d));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ru');
  });

  group('formatReminderWhen (pure)', () {
    test('EN: weekday name and 24 h time for every weekday', () {
      const names = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      for (var d = 1; d <= 7; d++) {
        expect(formatReminderWhen('en', d, 18 * 60 + 30), '${names[d - 1]} 18:30');
      }
    });

    test('RU: localised weekday names, not English', () {
      expect(formatReminderWhen('ru', 7, 480), 'воскресенье 08:00');
      expect(formatReminderWhen('ru', 1, 480), 'понедельник 08:00');
      expect(formatReminderWhen('ru', 3, 1110), 'среда 18:30');
    });

    test('time extremes are zero padded', () {
      expect(formatReminderWhen('en', 7, 0), 'Sunday 00:00');
      expect(formatReminderWhen('en', 7, 1439), 'Sunday 23:59');
      expect(formatReminderWhen('en', 7, 65), 'Sunday 01:05');
    });
  });

  group('state of the switch', () {
    testWidgets('off: no chips, no time button, no hint on a full surface',
        (tester) async {
      await _pump(tester,
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false)));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.entry.reminder'))).value,
          isFalse);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const Key('scan.reminder.time')), findsNothing);
      expect(find.text('Weekly reminder'), findsOneWidget);
      expect(find.textContaining('off by default'), findsNothing);
    });

    testWidgets('off in measurement-only mode explains the default (D-74)',
        (tester) async {
      await _pump(tester,
          settings: const BodyScanSettings(),
          mode: ScanSurfaceMode.measurementOnly);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.entry.reminder'))).value,
          isFalse);
      expect(find.text('The reminder is off by default. You can turn it on.'),
          findsOneWidget);
    });

    testWidgets('on: seven chips, Sunday selected by default, summary line',
        (tester) async {
      await _pump(tester);
      expect(find.byType(ChoiceChip), findsNWidgets(7));
      for (var d = 1; d <= 7; d++) {
        expect(_chipWidget(tester, d).selected, d == 7, reason: 'chip $d');
      }
      expect(find.text('Every Sunday 08:00'), findsOneWidget);
      expect(find.text('Change time: 08:00'), findsOneWidget);
    });

    testWidgets('chip labels are the short EN weekday names Monday first',
        (tester) async {
      await _pump(tester);
      final labels = [
        for (var d = 1; d <= 7; d++)
          ((_chipWidget(tester, d).label) as Text).data
      ];
      expect(labels, ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
      expect(_chipWidget(tester, 3).tooltip, 'Wednesday');
    });

    testWidgets('the stored weekday and time are reflected', (tester) async {
      await _pump(tester,
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: true, weekday: 3, minutes: 1110)));
      expect(_chipWidget(tester, 3).selected, isTrue);
      expect(_chipWidget(tester, 7).selected, isFalse);
      expect(find.text('Every Wednesday 18:30'), findsOneWidget);
      expect(find.text('Change time: 18:30'), findsOneWidget);
    });
  });

  group('localisation', () {
    testWidgets('RU: copy, weekday chips and summary come from the ru locale',
        (tester) async {
      await _pump(tester, locale: 'ru');
      expect(find.text('Еженедельное напоминание'), findsOneWidget);
      expect(find.text('Каждый раз: воскресенье 08:00'), findsOneWidget);
      expect(find.text('Изменить время: 08:00'), findsOneWidget);
      expect(find.text('Приостановить отслеживание'), findsOneWidget);
      final first = (_chipWidget(tester, 1).label as Text).data!;
      final last = (_chipWidget(tester, 7).label as Text).data!;
      expect(first.toLowerCase(), 'пн');
      expect(last.toLowerCase(), 'вс');
      expect(_chipWidget(tester, 7).tooltip, 'воскресенье');
      expect(find.text('Weekly reminder'), findsNothing);
    });

    testWidgets('the day group has a localised semantics label', (tester) async {
      await _pump(tester);
      expect(find.bySemanticsLabel('Reminder day'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, locale: 'ru');
      expect(find.bySemanticsLabel('День напоминания'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('switching on schedules the next slot and shows the chips',
        (tester) async {
      final rig = await _pump(tester,
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false)));
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(7));
      expect(rig.notes.scheduled, hasLength(1));
      expect(rig.notes.scheduled.single.fireAt.weekday, DateTime.sunday);
      expect((await rig.store.watch().first).reminder?.enabled, isTrue);
    });

    testWidgets('switching off cancels the pending reminder and hides chips',
        (tester) async {
      final rig = await _pump(tester,
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false)));
      // Turn it on through the UI first so something is pending.
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      expect(rig.notes.scheduled, hasLength(1));
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      expect(rig.notes.scheduled, isEmpty);
      expect(find.byType(ChoiceChip), findsNothing);
      expect((await rig.store.watch().first).reminder?.enabled, isFalse);
    });

    testWidgets('tapping a weekday chip stores it, moves the slot, updates text',
        (tester) async {
      final rig = await _pump(tester);
      await tester.tap(find.byKey(const Key('scan.entry.reminder'))); // off
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.entry.reminder'))); // on
      await tester.pumpAndSettle();
      await tester.tap(_chip(3));
      await tester.pumpAndSettle();
      expect(_chipWidget(tester, 3).selected, isTrue);
      expect(_chipWidget(tester, 7).selected, isFalse);
      expect(find.text('Every Wednesday 08:00'), findsOneWidget);
      final stored = (await rig.store.watch().first).reminder!;
      expect((stored.weekday, stored.minutes, stored.enabled), (3, 480, true));
      expect(rig.notes.scheduled, hasLength(1));
      expect(rig.notes.scheduled.single.fireAt.weekday, DateTime.wednesday);
    });

    testWidgets('time picker: confirming an entered time stores and reschedules',
        (tester) async {
      final rig = await _pump(tester);
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scan.reminder.time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      // Switch the dial to keyboard entry and type 18:30.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '18');
      await tester.enterText(fields.at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('Change time: 18:30'), findsOneWidget);
      expect(find.text('Every Sunday 18:30'), findsOneWidget);
      final stored = (await rig.store.watch().first).reminder!;
      expect((stored.weekday, stored.minutes), (7, 18 * 60 + 30));
      final fire = rig.notes.scheduled.single.fireAt;
      expect((fire.hour, fire.minute), (18, 30));
    });

    testWidgets('time picker: cancelling changes nothing', (tester) async {
      final rig = await _pump(tester);
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.reminder.time')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Change time: 08:00'), findsOneWidget);
      final fire = rig.notes.scheduled.single.fireAt;
      expect((fire.hour, fire.minute), (8, 0));
    });

    testWidgets('permission denied: toggle falls back to off with a snackbar',
        (tester) async {
      final svc = MockNotificationService()..initResult = false;
      final rig = await _pump(tester,
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false)),
          service: svc);
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan.entry.reminderDenied')), findsOneWidget);
      expect(find.textContaining('Notifications are off for this app'),
          findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.entry.reminder'))).value,
          isFalse);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(rig.notes.scheduled, isEmpty);
    });

    testWidgets('platform failure: toggle falls back to off with a snackbar',
        (tester) async {
      final rig = await _pump(tester,
          settings: const BodyScanSettings(
              reminder: ScanReminderPrefs(enabled: false)),
          service: _ThrowingScheduler());
      await tester.tap(find.byKey(const Key('scan.entry.reminder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan.entry.reminderFailed')), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.entry.reminder'))).value,
          isFalse);
      expect(rig.notes.scheduled, isEmpty);
    });
  });

  group('pause tracking (D-77)', () {
    testWidgets('shows label, hint and the current value', (tester) async {
      await _pump(tester);
      expect(find.text('Pause tracking'), findsOneWidget);
      expect(find.text('Hides check-in nudges and cancels the reminder.'),
          findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.reminder.paused'))).value,
          isFalse);
    });

    testWidgets('reflects a stored paused flag', (tester) async {
      await _pump(tester,
          settings: const BodyScanSettings(
              paused: true, reminder: ScanReminderPrefs(enabled: true)));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.reminder.paused'))).value,
          isTrue);
    });

    testWidgets('toggling stores paused and cancels / restores the reminder',
        (tester) async {
      final rig = await _pump(tester);
      await tester.tap(find.byKey(const Key('scan.entry.reminder'))); // off
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.entry.reminder'))); // on
      await tester.pumpAndSettle();
      expect(rig.notes.scheduled, hasLength(1));

      await tester.tap(find.byKey(const Key('scan.reminder.paused')));
      await tester.pumpAndSettle();
      expect((await rig.store.watch().first).paused, isTrue);
      expect(rig.notes.scheduled, isEmpty);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('scan.reminder.paused'))).value,
          isTrue);

      await tester.tap(find.byKey(const Key('scan.reminder.paused')));
      await tester.pumpAndSettle();
      expect((await rig.store.watch().first).paused, isFalse);
      expect(rig.notes.scheduled, hasLength(1));
    });
  });

  group('accessibility targets (48 dp)', () {
    testWidgets('time button, both switches and every day chip are >= 48 dp',
        (tester) async {
      await _pump(tester);
      final time = tester.getSize(find.byKey(const Key('scan.reminder.time')));
      expect(time.width, greaterThanOrEqualTo(48));
      expect(time.height, greaterThanOrEqualTo(48));
      for (final k in const ['scan.entry.reminder', 'scan.reminder.paused']) {
        final s = tester.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(48), reason: k);
        expect(s.width, greaterThanOrEqualTo(48), reason: k);
      }
      for (var d = 1; d <= 7; d++) {
        final s = tester.getSize(_chip(d));
        expect(s.height, greaterThanOrEqualTo(48), reason: 'chip $d');
        expect(s.width, greaterThanOrEqualTo(48), reason: 'chip $d');
        expect(_chipWidget(tester, d).materialTapTargetSize,
            MaterialTapTargetSize.padded);
      }
    });

    testWidgets('targets stay >= 48 dp at 200% text scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester);
      for (var d = 1; d <= 7; d++) {
        final s = tester.getSize(_chip(d));
        expect(s.height, greaterThanOrEqualTo(48), reason: 'chip $d');
      }
      expect(tester.getSize(find.byKey(const Key('scan.reminder.time'))).height,
          greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });
}
