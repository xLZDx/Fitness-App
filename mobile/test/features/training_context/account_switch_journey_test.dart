// Journey J1: one device, two accounts. A answers the training-context
// question and enables the scan reminder; B signs in and must see none of it;
// A signs back in and finds everything intact. Fakes sit only at the platform
// edge (auth stream, notification plugin, scan store, catalogue); the
// providers under test are the real ones.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/home/state/suggestion_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_reminder.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

const _a = AuthUser(uid: 'A', displayName: 'a');
const _b = AuthUser(uid: 'B', displayName: 'b');

ExerciseItem _ex(String id, {String? equipmentId, String? label, String? group, bool stretch = false}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      equipmentLabel: label,
      muscles: const ['quads'],
      primaryMuscles: const ['quads'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
      isStretch: stretch,
      vendorGroup: group,
    );

final _pool = <ExerciseItem>[
  _ex('pushup', label: 'None (Bodyweight)'),
  _ex('leg_press', equipmentId: 'leg_press', label: 'Leg Press Machine'),
  _ex('cobra', label: 'Yoga Mat', group: 'Yoga', stretch: true),
];

SafetyContext _safety() => SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
    );

/// Scan store keyed by uid, like the real per-account directory.
class _PerAccountScans implements ScanRepository {
  _PerAccountScans(this.store, this.uid);
  final Map<String, List<ScanRecord>> store;
  final String? uid;
  List<ScanRecord> get _mine => store[uid] ?? const [];
  @override
  Future<List<ScanRecord>> list() async => [..._mine];
  @override
  Future<void> save(ScanRecord r) async => store.putIfAbsent(uid!, () => []).add(r);
  @override
  Future<void> delete(String id) async => store[uid]?.removeWhere((r) => r.id == id);
}

void main() {
  late StreamController<AuthUser?> auth;
  late MockNotificationService notes;
  late Map<String, List<ScanRecord>> scans;
  late List<TrainingContext?> requested;
  late ProviderContainer c;
  late SharedPreferences prefs;

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await c.read(trainingContextProvider.future);
    await c.read(scanHistoryProvider.future);
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    notes = MockNotificationService();
    requested = [];
    // Only A has a scan; B has none.
    scans = {
      'A': [
        ScanRecord(id: 's1', createdAt: DateTime.now().subtract(const Duration(days: 2)), shots: const {}),
      ],
    };
    auth = StreamController<AuthUser?>();
    c = ProviderContainer(overrides: [
      authUserProvider.overrideWith((_) => auth.stream),
      notificationServiceProvider.overrideWithValue(notes),
      initialSettingsProvider.overrideWithValue(AppSettings(notificationsEnabled: true)),
      scanRepositoryProvider.overrideWith((ref) =>
          _PerAccountScans(scans, ref.watch(authUserProvider).valueOrNull?.uid)),
      // The catalogue edge: records which context each generation asked for and
      // narrows the pool with the real eligibility layer.
      forYouExercisesInContextProvider.overrideWith((ref, ctx) async {
        requested.add(ctx);
        return ctx == null
            ? _pool
            : eligibleForTrainingContext(_pool, _safety(), ctx);
      }),
      currentProfileProvider.overrideWith((ref) => Stream<UserProfile?>.value(null)),
      workoutSessionHistoryProvider.overrideWithValue(const []),
    ]);
    addTearDown(() async {
      c.dispose();
      await auth.close();
    });
    c.listen(scanReminderEnabledProvider, (_, __) {});
    c.listen(activeTrainingContextProvider, (_, __) {});
  });

  test('A -> B -> A: nothing leaks either way, writes land under the signed-in uid, A comes back intact', () async {
    // --- A signs in, answers "home", turns the scan reminder on.
    auth.add(_a);
    await settle();
    expect(c.read(trainingContextProvider).value, TrainingContextAnswer.unanswered);
    await c.read(trainingContextProvider.notifier).choose(TrainingContext.home);
    expect(c.read(activeTrainingContextProvider), TrainingContext.home);
    await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
    expect(c.read(scanReminderEnabledProvider), isTrue);
    expect(notes.scheduled, hasLength(1));
    expect(notes.scheduled.single.sessionId, kScanReminderId);

    final aSuggestions = await c.read(suggestionsProvider.future);
    expect(requested.last, TrainingContext.home);
    expect(aSuggestions, isNotEmpty);
    // Home with no equipment answers: bodyweight and yoga only, no machine row.
    expect(aSuggestions.map((s) => s.exerciseId), isNot(contains('leg_press')));

    // --- B signs in on the same device.
    auth.add(_b);
    await settle();
    expect(c.read(trainingContextProvider).value, TrainingContextAnswer.unanswered,
        reason: 'B must be asked again; A\'s answer is not B\'s');
    expect(c.read(activeTrainingContextProvider), isNull);
    expect(c.read(scanReminderEnabledProvider), isFalse,
        reason: 'B has no scan and no stored choice');
    expect(notes.scheduled, isEmpty, reason: "A's pending reminder must be cancelled");

    requested.clear();
    c.invalidate(suggestionsProvider);
    await c.read(suggestionsProvider.future);
    expect(requested, isNotEmpty);
    expect(requested, everyElement(isNull),
        reason: "B's suggestions must not be generated for A's context");

    // --- B answers: writes go to B's key only.
    await c.read(trainingContextProvider.notifier).choose(TrainingContext.gymMachines);
    expect(prefs.getString(trainingContextKeyFor('B')), 'gymMachines');
    expect(prefs.getString(trainingContextKeyFor('A')), 'home');
    await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
    expect(prefs.getBool(scanReminderPrefKey('B')), isTrue);
    expect(prefs.getBool(scanReminderPrefKey('A')), isTrue);
    expect(notes.scheduled, isEmpty, reason: 'B has no scan, so nothing is scheduled for B');

    // --- A signs back in: everything is intact and B's gym answer is not used.
    auth.add(_a);
    await settle();
    expect(c.read(trainingContextProvider).value,
        const TrainingContextAnswer.chosen(TrainingContext.home));
    expect(c.read(activeTrainingContextProvider), TrainingContext.home);
    expect(c.read(scanReminderEnabledProvider), isTrue);
    expect(prefs.getString(trainingContextKeyFor('B')), 'gymMachines');
  });

  test('sign-out leaves no answer and no pending reminder for the next person', () async {
    auth.add(_a);
    await settle();
    await c.read(trainingContextProvider.notifier).choose(TrainingContext.yoga);
    await c.read(scanReminderEnabledProvider.notifier).setEnabled(true);
    expect(notes.scheduled, hasLength(1));

    auth.add(null);
    await settle();

    expect(c.read(trainingContextProvider).value, TrainingContextAnswer.unanswered);
    expect(c.read(activeTrainingContextProvider), isNull);
    expect(notes.scheduled, isEmpty);
    // A choose while signed out is refused and writes nothing.
    await c.read(trainingContextProvider.notifier).choose(TrainingContext.gymMachines);
    expect(prefs.getKeys().where((k) => k.contains('gymMachines')), isEmpty);
    expect(prefs.getString(trainingContextKeyFor('A')), 'yoga');
  });
}
