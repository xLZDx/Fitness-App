import 'auth_user.dart';

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
  Future<AuthUser> signInWithGoogle();

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
