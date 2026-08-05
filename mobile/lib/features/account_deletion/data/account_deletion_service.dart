/// L0b — the boundary that talks to the `deleteAccount` Cloud Function.
///
/// Deliberately not a client-side flow. Two things a client can never do:
/// cancel the Stripe subscription (no secret key on device, ever), and write
/// to `users/{uid}/subscription/main` (`firestore.rules`'s `coll !=
/// 'subscription'` carve-out denies it, on purpose — a client that could
/// delete its own subscription record could also delete evidence that it
/// owes money). Both require the Admin SDK, so the whole flow is one server
/// call, not a client-driven sequence racing a server-driven Stripe step.
abstract class AccountDeletionService {
  /// Deletes the signed-in user's account: cancels any Stripe subscription,
  /// deletes every Firestore document under their uid, then deletes the
  /// Firebase Auth user itself. Irreversible once it succeeds.
  Future<void> deleteAccount();
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Records calls; deletes nothing. Default binding so widget tests never
/// touch `cloud_functions`.
class MockAccountDeletionService implements AccountDeletionService {
  int callCount = 0;

  /// Set by a test to make [deleteAccount] throw.
  Object? failWith;

  @override
  Future<void> deleteAccount() async {
    callCount++;
    if (failWith != null) throw failWith!;
  }
}
