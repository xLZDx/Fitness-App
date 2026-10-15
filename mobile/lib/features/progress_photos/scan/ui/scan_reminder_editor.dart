/// Weekly check-in reminder editor (design s19, D-21, D-74, D-77): an on/off
/// switch, weekday chips, a time picker and the "pause tracking" switch.
/// Weekday and time are formatted through `intl` with the active locale
/// ("Sunday 08:00" / "воскресенье 08:00").
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/notifications/notification_service.dart'
    show ReminderOutcome;
import '../../../body_scan/data/scan_plan_context.dart';
import '../../../body_scan/state/body_scan_providers.dart';
import '../../../body_scan/state/scan_plan_context_provider.dart';
import '../scan_reminder.dart';

/// 2024-01-01 is a Monday, so `DateTime(2024, 1, weekday)` has that weekday.
DateTime _dayOf(int weekday) => DateTime(2024, 1, weekday);

/// "Sunday 08:00" in [locale]. Pure, so it can be tested without a widget.
String formatReminderWhen(String locale, int weekday, int minutes) {
  final day = DateFormat.EEEE(locale).format(_dayOf(weekday));
  final time = DateFormat.Hm(locale)
      .format(DateTime(2024, 1, 1, minutes ~/ 60, minutes % 60));
  return '$day $time';
}

class ScanReminderEditor extends ConsumerWidget {
  const ScanReminderEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final on = ref.watch(scanReminderEnabledProvider);
    final schedule = ref.watch(scanReminderScheduleProvider);
    final paused =
        ref.watch(bodyScanSettingsProvider).valueOrNull?.paused ?? false;
    final measurementOnly = ref.watch(scanPlanContextValueProvider).surfaceMode ==
        ScanSurfaceMode.measurementOnly;
    final notifier = ref.read(scanReminderEnabledProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('scan.entry.reminder'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.scanReminderWeeklyLabel),
          subtitle: on
              ? Text(l10n.scanReminderSummary(
                  formatReminderWhen(locale, schedule.weekday, schedule.minutes)))
              : (measurementOnly
                  ? Text(l10n.scanReminderMeasurementOnlyOff)
                  : null),
          value: on,
          onChanged: (v) async {
            final messenger = ScaffoldMessenger.of(context);
            final outcome = await notifier.setEnabled(v);
            // The notifier already flipped the toggle back to off; say why.
            if (v && outcome == ReminderOutcome.denied) {
              messenger.showSnackBar(SnackBar(
                  key: const Key('scan.entry.reminderDenied'),
                  content: Text(l10n.scanReminderDenied)));
            }
            if (v && outcome == ReminderOutcome.failed) {
              messenger.showSnackBar(SnackBar(
                  key: const Key('scan.entry.reminderFailed'),
                  content: Text(l10n.commonSomethingWentWrong)));
            }
          },
        ),
        if (on) ...[
          Semantics(
            container: true,
            label: l10n.scanReminderDayGroup,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    key: Key('scan.reminder.day.$d'),
                    label: Text(DateFormat.E(locale).format(_dayOf(d))),
                    tooltip: DateFormat.EEEE(locale).format(_dayOf(d)),
                    selected: schedule.weekday == d,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onSelected: (_) => notifier.setSchedule(weekday: d),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            key: const Key('scan.reminder.time'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.schedule),
            label: Text(
              '${l10n.scanReminderChangeTime}: '
              '${DateFormat.Hm(locale).format(DateTime(2024, 1, 1, schedule.minutes ~/ 60, schedule.minutes % 60))}',
            ),
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                    hour: schedule.minutes ~/ 60,
                    minute: schedule.minutes % 60),
              );
              if (picked != null) {
                await notifier.setSchedule(
                    minutes: picked.hour * 60 + picked.minute);
              }
            },
          ),
        ],
        SwitchListTile(
          key: const Key('scan.reminder.paused'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.scanReminderPausedLabel),
          subtitle: Text(l10n.scanReminderPausedHint),
          value: paused,
          // The notifier re-syncs when the settings stream reports the change.
          onChanged: (v) =>
              ref.read(bodyScanSettingsStoreProvider).setPaused(v),
        ),
      ],
    );
  }
}
