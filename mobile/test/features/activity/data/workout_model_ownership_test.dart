// S02-01 U31: design 3.6 ownership of the workout models. The pinned table is a
// literal of docs/phase2/s02/S02_01_SPORT_MODEL_NOTE.md, so an unreviewed edit
// of the production constant fails here.
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/data/workout_model_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

const _literal = <String, ActivityStoreModel>{
  'running': ActivityStoreModel.activitySession,
  'trailRunning': ActivityStoreModel.activitySession,
  'walking': ActivityStoreModel.activitySession,
  'hiking': ActivityStoreModel.activitySession,
  'cycling': ActivityStoreModel.activitySession,
  'indoorCycling': ActivityStoreModel.activitySession,
  'mountainBiking': ActivityStoreModel.activitySession,
  'swimmingPool': ActivityStoreModel.activitySession,
  'swimmingOpenWater': ActivityStoreModel.activitySession,
  'rowing': ActivityStoreModel.activitySession,
  'strength': ActivityStoreModel.workoutSession,
  'other': ActivityStoreModel.activitySession,
};

void main() {
  test('the table is total over all 12 SportType values and has no extra key', () {
    expect(SportType.values, hasLength(12));
    expect(kSportModel.keys.toSet(), SportType.values.toSet());
    expect(kSportModel.length, 12);
  });

  test('the pinned table equals the one in the S02-01 note', () {
    expect({for (final e in kSportModel.entries) e.key.name: e.value}, _literal);
  });

  test('each sport has exactly one owner and the two owner sets are disjoint '
      'and cover everything', () {
    final session = {for (final e in kSportModel.entries) if (e.value == ActivityStoreModel.activitySession) e.key};
    final workout = {for (final e in kSportModel.entries) if (e.value == ActivityStoreModel.workoutSession) e.key};
    expect(session.intersection(workout), isEmpty);
    expect(session.union(workout), SportType.values.toSet());
    expect(workout, {SportType.strength});
    expect(ActivityStoreModel.values, hasLength(2));
  });

  test('modelForSport agrees with the table for every name', () {
    for (final t in SportType.values) {
      expect(modelForSport(t.name), _literal[t.name], reason: t.name);
    }
  });

  test('unknown or malformed sport values fall back like other', () {
    for (final v in <Object?>['futureSport7', '', 'Strength', null, 42, 'kiteSurfing']) {
      expect(modelForSport(v), ActivityStoreModel.activitySession, reason: '$v');
    }
    expect(modelForSport('other'), kSportModel[SportType.other]);
  });
}
