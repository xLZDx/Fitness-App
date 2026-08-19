import 'package:flutter_gen/gen_l10n/app_localizations_en.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/equipment_type_history.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

/// Gate D2 — deterministic matching-rule proofs for
/// `summarizeEquipmentTypeHistory`, including the mandatory adversarial
/// wrong-equipment-leakage case: this function must never attribute one
/// equipment type's history to another, even when exercise ids look similar.
WorkoutLogEntry _log(
  String id,
  String exerciseId,
  DateTime at, {
  double? weightKg,
  int? repsCompleted,
  String? sessionId,
}) =>
    WorkoutLogEntry(
      id: id,
      sessionId: sessionId ?? id,
      exerciseId: exerciseId,
      exerciseTitle: exerciseId,
      completedAt: at,
      durationMinutes: 20,
      weightKg: weightKg,
      repsCompleted: repsCompleted,
    );

void main() {
  final base = DateTime(2026, 8, 19, 9);

  group('summarizeEquipmentTypeHistory', () {
    test('no logs at all -> confirmed no history, not a truncated miss', () {
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: const [],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 0,
      );
      expect(result.hasHistory, isFalse);
      expect(result.isConfirmedNoHistory, isTrue);
      expect(result.completeness, EquipmentHistoryCompleteness.completeHistory);
    });

    test('picks the most recent matching entry, not the first in the list', () {
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: [
          _log('old', 'leg_press_machine', base.subtract(const Duration(days: 10)),
              weightKg: 40, repsCompleted: 10),
          _log('new', 'leg_press_machine', base, weightKg: 45, repsCompleted: 10),
          _log('mid', 'leg_press_machine', base.subtract(const Duration(days: 3)),
              weightKg: 42, repsCompleted: 10),
        ],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 3,
      );
      expect(result.lastEntry?.id, 'new');
      expect(result.lastEntry?.weightKg, 45);
    });

    test(
        'ADVERSARIAL: never attributes another equipment type\'s history to this one',
        () {
      // Same day, same-looking ids, deliberately NOT in the queried set —
      // proves membership is exact-id, not substring/prefix/fuzzy.
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: [
          _log('a', 'leg_press_alt_machine', base, weightKg: 99, repsCompleted: 5),
          _log('b', 'seated_leg_press', base, weightKg: 99, repsCompleted: 5),
          _log('c', 'leg_extension', base, weightKg: 99, repsCompleted: 5),
        ],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 3,
      );
      expect(result.hasHistory, isFalse,
          reason: 'none of the logged exerciseIds are in the equipment-type set');
      expect(result.isConfirmedNoHistory, isTrue);
    });

    test('empty exercise set for an equipment type never matches anything', () {
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'unmapped_type',
        windowedHistory: [_log('a', 'bench_press_barbell', base)],
        exerciseIdsForEquipment: const {},
        allTimeTotal: 1,
      );
      expect(result.hasHistory, isFalse);
    });

    test('a match found survives a truncated window (still trustworthy)', () {
      // Window shorter than all-time total, but the match IS inside the
      // window -- since the window is "the newest N logs of any exercise",
      // nothing outside it can be newer.
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: [_log('recent', 'leg_press_machine', base)],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 250, // far more logs exist than the window shows
      );
      expect(result.hasHistory, isTrue);
      expect(result.completeness, EquipmentHistoryCompleteness.completeHistory);
    });

    test('a truncated window with no match is NOT reported as confirmed no-history', () {
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: [_log('unrelated', 'barbell_row', base)],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 250, // window (1) is far short of the real total
      );
      expect(result.hasHistory, isFalse);
      expect(result.completeness, EquipmentHistoryCompleteness.recentWindowOnly);
      expect(result.isConfirmedNoHistory, isFalse,
          reason: 'a false "no history" claim is the exact bug D3 forbids');
    });

    test('a complete (non-truncated) window with no match IS confirmed no-history', () {
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: [_log('unrelated', 'barbell_row', base)],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 1, // window already covers the user's whole history
      );
      expect(result.isConfirmedNoHistory, isTrue);
    });

    test(
        'REGRESSION (Gate D7 review): row count vs. session count -- a '
        'multi-exercise window must not read as complete just because it has '
        'as many ROWS as the all-time SESSION total', () {
      // Two sessions, three exercises each -> 6 rows from 2 sessions. If the
      // truncation check compared raw row count to allTimeTotal (a SESSION
      // count), 6 >= 5 would wrongly read as "window covers everything",
      // masking that 3 of the user's 5 real sessions are missing from it.
      final windowedHistory = [
        for (final sid in ['s1', 's2'])
          for (final ex in ['a', 'b', 'c'])
            _log('${sid}_$ex', ex, base, sessionId: sid),
      ];
      expect(windowedHistory, hasLength(6), reason: 'sanity: 6 rows');

      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: windowedHistory,
        exerciseIdsForEquipment: const {'leg_press_machine'}, // no match
        allTimeTotal: 5, // 5 SESSIONS total, only 2 are in the window
      );
      expect(result.hasHistory, isFalse);
      expect(result.completeness, EquipmentHistoryCompleteness.recentWindowOnly,
          reason: '2 sessions in window < 5 sessions total -- must be truncated, '
              'even though 6 rows >= 5');
      expect(result.isConfirmedNoHistory, isFalse);
    });

    test(
        'REGRESSION (Gate D7 review): distinct session count, not row count, '
        'correctly reports complete history when the window really is complete',
        () {
      final windowedHistory = [
        for (final sid in ['s1', 's2'])
          for (final ex in ['a', 'b', 'c'])
            _log('${sid}_$ex', ex, base, sessionId: sid),
      ];
      final result = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: windowedHistory,
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 2, // exactly the 2 sessions actually in the window
      );
      expect(result.completeness, EquipmentHistoryCompleteness.completeHistory);
      expect(result.isConfirmedNoHistory, isTrue);
    });

    test('multiple equipment types mixed in one window only match their own', () {
      final legPress = summarizeEquipmentTypeHistory(
        equipmentId: 'leg_press',
        windowedHistory: [
          _log('lp1', 'leg_press_machine', base.subtract(const Duration(days: 1)),
              weightKg: 60, repsCompleted: 8),
          _log('bp1', 'bench_press_barbell', base, weightKg: 80, repsCompleted: 5),
        ],
        exerciseIdsForEquipment: const {'leg_press_machine'},
        allTimeTotal: 2,
      );
      expect(legPress.lastEntry?.id, 'lp1');
      expect(legPress.lastEntry?.weightKg, 60);
    });
  });

  group('formatLastSessionMetric', () {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();

    test('weight and reps both logged -> combined string, both locales', () {
      expect(
        formatLastSessionMetric(en, weightKg: 45, repsCompleted: 10),
        '45 kg × 10 reps',
      );
      expect(
        formatLastSessionMetric(ru, weightKg: 45, repsCompleted: 10),
        '45 кг × 10 повт.',
      );
    });

    test('a fractional weight keeps one decimal, a whole one drops it', () {
      expect(formatLastSessionMetric(en, weightKg: 42.5, repsCompleted: 8),
          '42.5 kg × 8 reps');
      expect(formatLastSessionMetric(en, weightKg: 40.0, repsCompleted: 8),
          '40 kg × 8 reps');
    });

    test('weight only (reps not logged) -> weight alone, no fabricated reps', () {
      expect(formatLastSessionMetric(en, weightKg: 45, repsCompleted: null),
          '45 kg');
    });

    test('reps only (bodyweight / no weight logged) -> reps alone', () {
      expect(formatLastSessionMetric(en, weightKg: null, repsCompleted: 12),
          '12 reps');
    });

    test('neither logged -> null, never a fabricated "0 kg x 0"', () {
      expect(
        formatLastSessionMetric(en, weightKg: null, repsCompleted: null),
        isNull,
      );
    });
  });
}
