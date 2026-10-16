/// Which persisted model owns a workout of a given sport (S02 design 3.6).
/// Pure Dart, no Flutter imports.
///
/// Verified against the code at S02-01: `WorkoutSession` (and the legacy
/// `WorkoutLogEntry` it mirrors through `asLogEntries()`) is exercise and set
/// based with no sport, HR, GPS or source field, so it owns set-based gym
/// logging only; `SportType` is used nowhere outside `activity/data`. The
/// pinned table therefore sends `strength` to the workout model and every
/// other sport (including `rowing` and the `other` fallback) to
/// [ActivityStoreModel.activitySession]. No dual write: a sport maps to exactly
/// one model.
library;

import 'sport_type.dart';

enum ActivityStoreModel {
  /// `ActivitySession`: collection `activities` and the local journal.
  activitySession,

  /// `WorkoutSession` (`workout_sessions`) with its legacy mirror
  /// `WorkoutLogEntry` (`workout_logs`).
  workoutSession,
}

/// The pinned table. Total over every [SportType] value; an unreviewed edit
/// shows in the diff and in the ownership test.
const Map<SportType, ActivityStoreModel> kSportModel = {
  SportType.running: ActivityStoreModel.activitySession,
  SportType.trailRunning: ActivityStoreModel.activitySession,
  SportType.walking: ActivityStoreModel.activitySession,
  SportType.hiking: ActivityStoreModel.activitySession,
  SportType.cycling: ActivityStoreModel.activitySession,
  SportType.indoorCycling: ActivityStoreModel.activitySession,
  SportType.mountainBiking: ActivityStoreModel.activitySession,
  SportType.swimmingPool: ActivityStoreModel.activitySession,
  SportType.swimmingOpenWater: ActivityStoreModel.activitySession,
  SportType.rowing: ActivityStoreModel.activitySession,
  SportType.strength: ActivityStoreModel.workoutSession,
  SportType.other: ActivityStoreModel.activitySession,
};

/// The owning model of a raw sport name; an unknown name degrades to `other`
/// exactly as `SportType.parse` does.
ActivityStoreModel modelForSport(Object? sportName) =>
    kSportModel[SportType.parse(sportName)]!;
