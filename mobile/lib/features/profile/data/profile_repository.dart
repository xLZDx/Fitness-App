import 'profile_models.dart';

/// Profile/onboarding storage abstraction. Implementations:
///   * [MockProfileRepository] — in-memory, used for development and tests.
///   * (Phase 1B) FirestoreProfileRepository — backed by Firestore.
abstract class ProfileRepository {
  /// Stream of the current user's profile (or null if not yet created).
  /// Replays the latest known value to new subscribers.
  Stream<UserProfile?> watch(String uid);

  /// Synchronous accessor for the latest known profile, when available.
  UserProfile? cached(String uid);

  /// Loads the profile if it exists. Returns null when one has not been
  /// created yet for [uid].
  Future<UserProfile?> load(String uid);

  /// Persist [profile]. Always overwrites — callers are expected to merge
  /// before save by using [UserProfile.copyWith].
  Future<void> save(UserProfile profile);

  /// Delete the profile for [uid] (used on sign-out / account delete tests).
  Future<void> delete(String uid);
}
