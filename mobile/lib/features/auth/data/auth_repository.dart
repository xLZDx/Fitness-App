import 'auth_user.dart';
import 'sign_in_outcome.dart';

/// Authentication backend abstraction. Implementations:
///   * [MockAuthRepository] — in-memory, used for development and tests.
///   * (Phase 1B) FirebaseAuthRepository — wraps FirebaseAuth.
abstract class AuthRepository {
  /// A broadcast stream that emits the current user (or null) every time
  /// authentication state changes. Replays the latest value on subscription.
  Stream<AuthUser?> authStateChanges();

  /// The current synchronously-known user, or null if not signed in.
  AuthUser? get currentUser;

  /// Sign in anonymously. Resolves with the created user.
  Future<AuthUser> signInAnonymously();

  /// Sign in with a (mock) Google account.
  /// Returns what became of any guest session, not just who is signed
  /// in. A bare `AuthUser` cannot express the difference between a
  /// linked account and one whose guest history was just orphaned, and
  /// that difference is the whole of what the caller has to tell the
  /// person in front of them.
  Future<SignInResult> signInWithGoogle();

  /// Sign out the current user. No-op when no one is signed in.
  Future<void> signOut();
}

/// Generic auth failure. Wraps the underlying cause for diagnostics.
class AuthException implements Exception {
  const AuthException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AuthException: $message';
}
