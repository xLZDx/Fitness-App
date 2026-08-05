/// What must never be written to the server, as a value rather than as logic
/// spread across a repository.
///
/// ## Why this exists
///
/// The profile used to be saved whole to `users/{uid}/profile/main`, which put
/// medications, surgeries and reported injuries in Firestore. Nothing on the
/// server ever read them — no Cloud Function touches the profile at all — so
/// they were held without being used, which is the worst trade available: full
/// GDPR Article 9 exposure and a Play "Health info" declaration, bought for
/// nothing.
///
/// ## What counts, and why these fields
///
/// [HealthHistory] entire, plus smoking and alcohol out of [Lifestyle].
///
/// The lifestyle pair is the non-obvious part. Play's taxonomy files it under
/// lifestyle rather than health, but GDPR's "data concerning health" is read
/// broadly enough to cover habits that reveal health status, and these two do.
/// They travel with the health block rather than being argued about later.
///
/// Height and weight deliberately stay on the server. They are Play "Fitness
/// info", not "Health info", so moving them does not remove a single row from
/// the Data safety form — it would be churn that buys nothing, and the profile
/// summary would lose device-to-device sync for no gain.
library;

import 'profile_models.dart';

/// The parts of a profile that live on the device only.
class SensitiveProfile {
  const SensitiveProfile({
    this.health = HealthHistory.empty,
    this.smoking,
    this.alcohol,
  });

  final HealthHistory health;
  final SmokingHabit? smoking;
  final AlcoholHabit? alcohol;

  static const empty = SensitiveProfile();

  /// True when the user has answered none of it. The merge treats this as
  /// "nothing stored locally" rather than as "stored, and empty" — which is
  /// what lets a profile written before this split still resolve from the
  /// server until the migration has run.
  bool get isEmpty => health.isEmpty && smoking == null && alcohol == null;

  Map<String, dynamic> toJson() => {
        'health': health.toJson(),
        'smoking': smoking?.name,
        'alcohol': alcohol?.name,
      };

  static SensitiveProfile fromJson(Map<String, dynamic> j) => SensitiveProfile(
        health: HealthHistory.fromJson(
          Map<String, dynamic>.from((j['health'] as Map?) ?? const {}),
        ),
        smoking: _byName(SmokingHabit.values, j['smoking']),
        alcohol: _byName(AlcoholHabit.values, j['alcohol']),
      );

  static T? _byName<T extends Enum>(List<T> values, dynamic name) {
    if (name is! String) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Pulls the device-only parts out of a whole profile.
SensitiveProfile extractSensitive(UserProfile p) => SensitiveProfile(
      health: p.health,
      smoking: p.lifestyle.smoking,
      alcohol: p.lifestyle.alcohol,
    );

/// The same profile with those parts blanked — what the server is allowed to
/// see.
///
/// [Lifestyle] is rebuilt field by field rather than through `copyWith`,
/// because `copyWith` cannot set a nullable field back to null: `smoking ??
/// this.smoking` would keep the value it was asked to remove. A stripper that
/// silently fails to strip is worse than no stripper, since everything
/// downstream would then be reporting success.
UserProfile stripSensitive(UserProfile p) => p.copyWith(
      health: HealthHistory.empty,
      lifestyle: Lifestyle(
        diet: p.lifestyle.diet,
        sleepHoursPerNight: p.lifestyle.sleepHoursPerNight,
        stressLevel: p.lifestyle.stressLevel,
        occupation: p.lifestyle.occupation,
      ),
    );

/// Puts the device-only parts back on top of a server profile.
///
/// An empty [s] leaves [p] untouched, which is what makes this safe to run
/// before the migration: a user whose health block is still in Firestore keeps
/// reading it until the migration moves it down and deletes it up there.
UserProfile mergeSensitive(UserProfile p, SensitiveProfile s) {
  if (s.isEmpty) return p;
  return p.copyWith(
    health: s.health.isEmpty ? p.health : s.health,
    lifestyle: Lifestyle(
      diet: p.lifestyle.diet,
      smoking: s.smoking ?? p.lifestyle.smoking,
      alcohol: s.alcohol ?? p.lifestyle.alcohol,
      sleepHoursPerNight: p.lifestyle.sleepHoursPerNight,
      stressLevel: p.lifestyle.stressLevel,
      occupation: p.lifestyle.occupation,
    ),
  );
}
