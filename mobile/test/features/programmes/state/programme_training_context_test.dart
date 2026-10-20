import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// Programmes honour the chosen training context with the same filter rules the
/// planner and home feed use (training_context.dart); a skipped or unanswered
/// context behaves exactly as before.

ExerciseItem _ex(String id, String title, String? label,
        {String? group, bool stretch = false}) =>
    ExerciseItem(
      id: id,
      title: title,
      equipmentId: null,
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

// Titles, not ids, are what movementRoleOf reads.
const _titles = {
  'sq': 'Bodyweight Squat',
  'sq2': 'Goblet Squat',
  'hi': 'Romanian Deadlift',
  'hi2': 'Glute Bridge',
  'hp': 'Push Up',
  'hp2': 'Bench Press',
  'vp': 'Overhead Press',
  'vp2': 'Push Press',
  'hl': 'Bent Over Row',
  'hl2': 'Seated Row',
  'vl': 'Pull Up',
  'vl2': 'Lat Pulldown',
  'sl': 'Walking Lunge',
  'sl2': 'Bulgarian Split Squat',
  'ce': 'Front Plank',
  'ce2': 'Hollow Hold',
  'cr': 'Russian Twist',
  'cr2': 'Cable Woodchop',
};

/// Every strength role filled twice with the given equipment label, ids
/// prefixed so two kits can sit in one catalogue.
List<ExerciseItem> _strength(String prefix, String label) => [
      for (final e in _titles.entries) _ex('$prefix${e.key}', e.value, label),
    ];

final _yoga = [
  for (var i = 0; i < 12; i++)
    _ex('yoga$i', 'Flow Pose $i', 'Yoga Mat', group: 'Yoga', stretch: true),
];
final _bodyweight = _strength('bw_', 'None (Bodyweight)');
final _barbell = _strength('bb_', 'Barbell');

class _FakeContext extends TrainingContextNotifier {
  _FakeContext(this.initial);
  final TrainingContextAnswer initial;
  @override
  Future<TrainingContextAnswer> build() async => initial;
}

/// Enrols in the first template; returns (scheduled exercise ids, error).
Future<(Set<String>, Object?)> _enroll({
  required List<ExerciseItem> catalogue,
  required TrainingContextAnswer answer,
  EquipmentAccess? profileEquipment,
}) async {
  final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
  addTearDown(programmeRepo.dispose);
  final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
  addTearDown(sessionRepo.dispose);
  final c = ProviderContainer(overrides: [
    programmeRepositoryProvider.overrideWithValue(programmeRepo),
    scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
    authUserProvider.overrideWith(
        (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
    safeCatalogProvider.overrideWith((ref) async => catalogue),
    safetyContextProvider.overrideWith((ref) async => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
          equipment: profileEquipment,
        )),
    trainingContextProvider.overrideWith(() => _FakeContext(answer)),
  ]);
  addTearDown(c.dispose);
  await c.read(authUserProvider.future);
  await c.read(trainingContextProvider.future);
  await c
      .read(programmeActionProvider.notifier)
      .enroll(programmeTemplates.first);
  final st = c.read(programmeActionProvider);
  return ({for (final r in sessionRepo.cached('u1')) r.exerciseId}, st.error);
}

const _homeBodyweight = EquipmentAccess(
    location: TrainingLocation.home, available: [EquipmentKind.bodyweight]);

void main() {
  final mixed = [..._bodyweight, ..._barbell, ..._yoga];

  test('gymMachines: barbell work allowed even if the profile says bodyweight',
      () async {
    final (ids, err) = await _enroll(
      catalogue: [..._barbell, ..._yoga],
      answer: const TrainingContextAnswer.chosen(TrainingContext.gymMachines),
      profileEquipment: _homeBodyweight,
    );
    expect(err, isNull);
    expect(ids, isNotEmpty);
    expect(ids.every((i) => i.startsWith('bb_')), isTrue, reason: '$ids');
  });

  test('outdoorMinimal: only bodyweight/portable kit, never the barbell',
      () async {
    final (ids, err) = await _enroll(
      catalogue: mixed,
      answer:
          const TrainingContextAnswer.chosen(TrainingContext.outdoorMinimal),
    );
    expect(err, isNull);
    expect(ids, isNotEmpty);
    expect(ids.every((i) => i.startsWith('bw_')), isTrue, reason: '$ids');
  });

  test('outdoorMinimal with only barbell work refuses, writes nothing',
      () async {
    final (ids, err) = await _enroll(
      catalogue: _barbell,
      answer:
          const TrainingContextAnswer.chosen(TrainingContext.outdoorMinimal),
    );
    expect(ids, isEmpty);
    expect(err, isA<ProgrammeNotViable>());
  });

  test('home: the profile kit only, no gym carry-over', () async {
    final (ids, err) = await _enroll(
      catalogue: mixed,
      answer: const TrainingContextAnswer.chosen(TrainingContext.home),
      profileEquipment: const EquipmentAccess(
          location: TrainingLocation.gym,
          available: [EquipmentKind.fullGym, EquipmentKind.bodyweight]),
    );
    expect(err, isNull);
    expect(ids.every((i) => i.startsWith('bw_')), isTrue, reason: '$ids');
  });

  test('yoga: every scheduled exercise is yoga/mobility, no strength work',
      () async {
    final (ids, err) = await _enroll(
      catalogue: mixed,
      answer: const TrainingContextAnswer.chosen(TrainingContext.yoga),
      profileEquipment: _homeBodyweight,
    );
    expect(err, isNull, reason: 'yoga has its own structure, not a refusal');
    expect(ids, isNotEmpty);
    expect(ids.every((i) => i.startsWith('yoga')), isTrue, reason: '$ids');
  });

  test('skipped and unanswered behave identically and as before', () async {
    final unanswered = await _enroll(
        catalogue: mixed,
        answer: TrainingContextAnswer.unanswered,
        profileEquipment: _homeBodyweight);
    final skipped = await _enroll(
        catalogue: mixed,
        answer: TrainingContextAnswer.skipped,
        profileEquipment: _homeBodyweight);
    expect(unanswered.$2, isNull);
    expect(skipped.$2, isNull);
    expect(skipped.$1, unanswered.$1);
    // As before: the profile bodyweight answer decides, so no barbell.
    expect(unanswered.$1.any((i) => i.startsWith('bb_')), isFalse);
    expect(unanswered.$1.any((i) => i.startsWith('bw_')), isTrue);
  });
}
