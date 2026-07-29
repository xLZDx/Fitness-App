import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;

import 'auth_repository.dart';
import 'auth_user.dart';

/// FirebaseAuth-backed [AuthRepository]. Maps Firebase users into our domain
/// [AuthUser] type so the rest of the app doesn't have to know which backend
/// is in use.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository([
    fb.FirebaseAuth? instance,
    Future<String?> Function()? googleIdTokenLoader,
  ])  : _injectedAuth = instance,
        _googleIdTokenLoader = googleIdTokenLoader;

  final fb.FirebaseAuth? _injectedAuth;

  /// Resolved lazily: touching `FirebaseAuth.instance` in the constructor
  /// throws when no Firebase app is initialised, which would make every
  /// pre-Firebase code path untestable.
  fb.FirebaseAuth get _auth => _injectedAuth ?? fb.FirebaseAuth.instance;

  /// Seam for tests: returns the Google ID token, or null when Google gave
  /// us none. Defaults to the real Credential Manager flow.
  final Future<String?> Function()? _googleIdTokenLoader;

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

  /// The project's **web** OAuth client id (`client_type: 3` in
  /// `android/app/google-services.json`). Android's Credential Manager needs
  /// it as `serverClientId` to mint the ID token Firebase verifies. Not a
  /// secret — it ships in the app bundle either way.
  static const _serverClientId =
      '1007678328591-j034epr1u9hjc99u1f3t649qdf3q57d0.apps.googleusercontent.com';

  bool _googleReady = false;

  Future<gsi.GoogleSignIn> _google() async {
    final signIn = gsi.GoogleSignIn.instance;
    if (!_googleReady) {
      // v7 requires an explicit initialize before any auth call.
      await signIn.initialize(serverClientId: _serverClientId);
      _googleReady = true;
    }
    return signIn;
  }

  Future<String?> _realGoogleIdToken() async {
    final signIn = await _google();
    if (!signIn.supportsAuthenticate()) {
      throw const AuthException(
          'Google sign-in is not supported on this platform.');
    }
    final account = await signIn.authenticate();
    return account.authentication.idToken;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    try {
      final idToken =
          await (_googleIdTokenLoader ?? _realGoogleIdToken).call();
      if (idToken == null) {
        // Almost always a misconfigured serverClientId or an unregistered
        // signing SHA — say so instead of a bare null error.
        throw const AuthException(
            'Google did not return an ID token. Check the SHA fingerprint '
            'registered for this build and the OAuth client id.');
      }
      final cred = fb.GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(cred);
      return _toDomain(result.user)!;
    } on gsi.GoogleSignInException catch (e, st) {
      debugPrintStack(stackTrace: st);
      if (e.code == gsi.GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Sign-in cancelled.');
      }
      throw AuthException(
        'Google sign-in failed (${e.code.name}): ${e.description ?? ''}'.trim(),
        cause: e,
      );
    } on fb.FirebaseAuthException catch (e, st) {
      debugPrintStack(stackTrace: st);
      throw AuthException(e.message ?? 'Google sign-in failed', cause: e);
    }
  }

  @override
  Future<void> signOut() async {
    // Sign out of Google too, otherwise the next sign-in silently reuses the
    // previous account with no chooser.
    if (_googleReady) {
      try {
        await gsi.GoogleSignIn.instance.signOut();
      } catch (e, st) {
        // Never block the Firebase sign-out on this.
        debugPrint('google sign-out failed: $e');
        debugPrintStack(stackTrace: st);
      }
    }
    await _auth.signOut();
  }
}
