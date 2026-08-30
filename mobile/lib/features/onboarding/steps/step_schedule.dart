import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

/// O5 — when the training happens.
///
/// Three answers, all optional like the rest of the questionnaire: how many
/// sessions a week, how long one session runs, and which days suit.
///
/// ## Why minutes and not the existing buckets
///
/// The app already had [WorkoutDuration] — five buckets — and the motivation
/// screen asked for one. A bucket cannot express "45 minutes": `m30to45` and
/// `m45to60` are both named for it. So the exact number is what gets stored and
/// the bucket is derived (`TrainingSchedule.durationBucket`), which keeps every
/// existing reader of the bucket working without asking the question twice.
///
/// ## Why this is not `FitnessLevel.frequencyPerWeek`
///
/// That field is the answer to "how much do you train now", asked on the goal
/// and level screen. This one is "how much do you intend to". They look
/// interchangeable and are not: the difference between the two is the entire
/// input a plan generator would need to size a ramp.
class StepSchedule extends ConsumerWidget {
  const StepSchedule({super.key});

  /// Two is the floor the design offers, not one: a single session a week is
  /// not a schedule this app can build a programme around, and offering it
  /// would promise something the generator cannot honour.
  static const _daysOptions = [2, 3, 4, 5, 6];

  /// The design's five lengths. 15-minute steps up to an hour, then two longer
  /// options for people who train in blocks.
  static const _minuteOptions = [30, 45, 60, 75, 90];

  static const _weekdays = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(questionnaireDraftProvider).schedule;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnbRefTitle(
          title: l10n.onbScheduleTitle,
          subtitle: l10n.onbScheduleSubtitle,
        ),
        FieldLabel(l10n.onbScheduleDays),
        SingleChoiceChips<int>(
          options: _daysOptions,
          labelOf: (d) => l10n.onbScheduleDaysValue(d),
          value: s.daysPerWeek,
          onChanged: (d) =>
              notifier.updateSchedule((v) => v.copyWith(daysPerWeek: d)),
        ),
        FieldLabel(l10n.onbScheduleLength),
        SingleChoiceChips<int>(
          options: _minuteOptions,
          labelOf: (m) => l10n.onbScheduleMinutesValue(m),
          value: s.sessionMinutes,
          onChanged: (m) =>
              notifier.updateSchedule((v) => v.copyWith(sessionMinutes: m)),
        ),
        FieldLabel(l10n.onbScheduleWeekdays),
        MultiChoiceChips<int>(
          options: _weekdays,
          labelOf: (d) => _weekdayLabel(l10n, d),
          values: s.preferredWeekdays.toSet(),
          onChanged: (next) => notifier.updateSchedule(
            // Stored in week order, not tap order. This list is persisted and
            // compared; a set that serialises differently depending on which
            // chip was pressed first makes two identical answers look
            // different. Same reasoning as the equipment chips in O4.
            (v) => v.copyWith(
              preferredWeekdays: [
                for (final d in _weekdays)
                  if (next.contains(d)) d,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _weekdayLabel(AppLocalizations l, int weekday) => switch (weekday) {
      DateTime.monday => l.weekdayMon,
      DateTime.tuesday => l.weekdayTue,
      DateTime.wednesday => l.weekdayWed,
      DateTime.thursday => l.weekdayThu,
      DateTime.friday => l.weekdayFri,
      DateTime.saturday => l.weekdaySat,
      // `_weekdays` is the only caller and it lists exactly seven values, but
      // the switch still needs a total branch and Sunday is the honest one.
      _ => l.weekdaySun,
    };
