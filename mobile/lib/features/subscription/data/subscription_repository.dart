import 'subscription_models.dart';

/// Persistence interface for the user's subscription record. Default is
/// `MockSubscriptionRepository`; production overrides with
/// `FirestoreSubscriptionRepository` writing to
/// `users/{uid}/subscription/main`.
abstract class SubscriptionRepository {
  /// Streams the user's subscription record. Emits null when no record
  /// exists yet (brand-new user).
  Stream<Subscription?> watch(String uid);

  /// Synchronous read of the most recent stream emission.
  Subscription? cached(String uid);

  /// Inserts or replaces the user's subscription record.
  Future<void> save(Subscription sub);

  /// Removes the user's subscription record (debug + GDPR data export).
  Future<void> delete(String uid);
}
