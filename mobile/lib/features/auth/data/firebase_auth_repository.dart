import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi;

import 'auth_repository.dart';
import 'auth_user.dart';
import 'sign_in_outcome.dart';

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
      // `_auth.userChanges()`, not `_auth.authStateChanges()`. Verified
      // against the pinned firebase_auth 6.4.0 source: authStateChanges()'s
      // own doc comment says only "sign-in or sign-out", while userChanges()
      // says "a superset of authStateChanges() ... such as when credentials
      // are linked". Every reactive surface in the app -- the router, the
      // profile, `authUserProvider` itself -- is built on THIS stream, so
      // with the plain authStateChanges() a guest who successfully linked to
      // Google (L0d) kept seeing themselves as the stale pre-link anonymous
      // user for the rest of the session, until an unrelated sign-in/out
      // happened to refresh it. userChanges() is documented as a strict
      // superset, so this changes nothing about the existing sign-in/sign-out
      // behaviour -- it only adds the events that were missing.
      _auth.userChanges().map(_toDomain);

  @override
  // MVP-3 (`splash_page.dart`): the splash screen waits for
  // `authUserProvider`'s (built on `userChanges()`) first emission before
  // ever leaving `/splash`, on the premise that by the time that stream
  // fires, this synchronous getter already reflects the same user -- so the
  // router's redirect (which reads this getter, not the stream) sees a
  // consistent value right after. Verified against the pinned
  // firebase_auth_platform_interface 8.1.9 method-channel source
  // (`method_channel_firebase_auth.dart:179-193`): `instance.currentUser` is
  // always assigned before the corresponding event is pushed onto the
  // `userChanges()`/`idTokenChanges()` stream controller, for both the
  // signed-in and signed-out branches -- never the other way around.
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
  ///
  /// It must belong to the SAME project as the `google-services.json` the APK
  /// was built against. It did not: this constant used to read
  /// `1007678328591-j034epr…`, whose project number is `1007678328591`, while
  /// the shipped config is project `988522745882` (`fitness-app-korostelev`).
  /// Credential Manager was being asked for a token whose audience belongs to
  /// a project this app is not part of, and answered
  /// `[28444] Developer console is not set up correctly` — the same message it
  /// gives for an unregistered signing SHA, which is what made this look for
  /// two builds like a missing fingerprint. Registering the release SHA-1 was
  /// necessary and did not help, because no fingerprint in the right project
  /// can satisfy a request pointed at the wrong one.
  ///
  /// `firebase_auth_repository_test.dart` now reads the real
  /// `google-services.json` and fails if these two ever disagree again, so the
  /// next project swap breaks a test instead of the sign-in button.
  static const serverClientId =
      '988522745882-05gql4s6t59f7l6qjftveh5jj5kado4e.apps.googleusercontent.com';

  bool _googleReady = false;

  Future<gsi.GoogleSignIn> _google() async {
    final signIn = gsi.GoogleSignIn.instance;
    if (!_googleReady) {
      // v7 requires an explicit initialize before any auth call.
      await signIn.initialize(serverClientId: serverClientId);
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
  Future<SignInResult> signInWithGoogle() async {
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

      // Link, not sign in, when the current session is a guest (L0d).
      //
      // `signInWithCredential` unconditionally mints a NEW Firebase user, so
      // a guest tapping "Continue with Google" got a fresh uid every time —
      // the anonymous account, and every Firestore document under it
      // (profile, injuries, workout history, schedule), was silently
      // orphaned. Nothing deletes an anonymous Firebase user on its own;
      // that data was not lost so much as unreachable forever, because an
      // anonymous account has no credential to sign back into.
      //
      // `linkWithCredential` on the anonymous user keeps the SAME uid and
      // attaches the Google identity to it, so every already-written
      // Firestore document is still that uid's data with no migration of any
      // kind — this is the one gate in the round that gets to avoid S1b's
      // whole problem by construction rather than by writing a migration.
      final anonymous = _auth.currentUser;
      final wasGuest = anonymous != null && anonymous.isAnonymous;
      if (wasGuest) {
        try {
          final result = await anonymous.linkWithCredential(cred);
          return SignInResult(_toDomain(result.user)!, GuestUpgrade.linked);
        } on fb.FirebaseAuthException catch (e) {
          // 'credential-already-in-use': the Google account is already the
          // real identity behind a DIFFERENT Firebase user -- most often
          // this device's guest data is not the user's first time signing in
          // with this Google account. Firebase's own doc for this code
          // (user.dart:147-158 in the pinned firebase_auth 6.4.0 source)
          // names `signInWithCredential(credential)` as the direct recovery,
          // which is exactly the fallback below.
          //
          // 'email-already-in-use' is handled the same way here, but the
          // package's own doc for THAT code (user.dart:160-167) describes a
          // different, two-step recovery: sign into the email's existing
          // provider first, then link the Google credential to that session
          // -- not a same-credential retry. It fires when the Google
          // credential's email is already claimed by a DIFFERENT provider on
          // this project, which this app cannot produce today: the only
          // providers wired up anywhere in `lib/` are anonymous and Google
          // (grepped for signInWithEmailAndPassword / EmailAuthProvider --
          // zero results), so there is no second real-identity provider for
          // an email to collide with. Reusing the same fallback here is an
          // accepted, currently-unreachable gap rather than a verified
          // correct recovery -- building the actual two-step flow would mean
          // adding an email/password provider this app does not otherwise
          // have any use for, which is a materially bigger feature than this
          // gate.
          //
          // Either way, both codes are the same shape of failure for the
          // user: linking did not succeed, sign-in falls back to their real
          // account, and this device's guest data stays orphaned but intact
          // -- not silently lost, just unreachable by this flow.
          if (e.code != 'credential-already-in-use' &&
              e.code != 'email-already-in-use') {
            rethrow;
          }
        }
      }

      // Reached either because there was no guest session at all, or
      // because linking one was refused. Those are not the same event and
      // must not return the same value: in the second case the person is
      // signed in and everything they did on this device just became
      // unreachable. Saying so is the caller's job, and it cannot do that job
      // with a value that does not carry the distinction.
      final result = await _auth.signInWithCredential(cred);
      return SignInResult(
        _toDomain(result.user)!,
        wasGuest ? GuestUpgrade.orphaned : GuestUpgrade.notAGuest,
      );
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
