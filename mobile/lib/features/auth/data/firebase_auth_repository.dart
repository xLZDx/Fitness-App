// This file is deliberately not imported by the running app yet — it
// is wired up during Phase 1B once the user has run `flutterfire configure`
// and a `firebase_options.dart` exists. See `core/PHASE_1B_FIREBASE_SETUP.md`.

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'auth_user.dart';

/// FirebaseAuth-backed [AuthRepository]. Maps Firebase users into our domain
/// [AuthUser] type so the rest of the app doesn't have to know which backend
/// is in use.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository([fb.FirebaseAuth? instance])
      : _auth = instance ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  AuthUser? _toDomain(fb.User? u) {
    if (u == null) return null;
    return AuthUser(
      uid: u.uid,
      displayName: u.displayName ?? (u.isAnonymous ? 'Guest' : 'Athlete'),
      email: u.email,
      photoUrl: u.photoURL,
      provider: u.isAnonymous
          ? AuthProvider.anonymous
          : (u.providerData.any((p) => p.providerId == 'google.com')
              ? AuthProvider.google
              : AuthProvider.email),
    );
  }

  @override
  Stream<AuthUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toDomain);

  @override
  AuthUser? get currentUser => _toDomain(_auth.currentUser);

  @override
  Future<AuthUser> signInAnonymously() async {
    try {
      final cred = await _auth.signInAnonymously();
      return _toDomain(cred.user)!;
    } on fb.FirebaseAuthException catch (e, st) {
      debugPrintStack(stackTrace: st);
      throw AuthException(e.message ?? 'anonymous sign-in failed', cause: e);
    }
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    // Real Google sign-in requires the `google_sign_in` plugin and Android
    // SHA fingerprint registered with Firebase. Wire that up in Phase 1B.
    throw const AuthException(
        'Google sign-in is not yet wired up — finish Phase 1B setup.');
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
