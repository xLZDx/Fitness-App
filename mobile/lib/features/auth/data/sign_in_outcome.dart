import 'auth_user.dart';

/// What happened to a guest session when a Google identity was added to it.
///
/// `signInWithGoogle` used to return a bare `AuthUser`, and that type could
/// not tell its caller the one thing the caller needed to know. Linking an
/// anonymous session keeps the same uid, so every Firestore document already
/// written under it stays reachable. Falling back to `signInWithCredential`
/// signs the person into their real account instead, and this device's guest
/// history -- profile, injuries, workout log, schedule -- stays where it is,
/// under a uid that has no credential anyone can ever sign into again.
///
/// Both paths returned an `AuthUser` with a name and an email on it, and the
/// screen showed the same thing either way. The data was not deleted; it
/// became unreachable, silently, at the moment the person did exactly what
/// the app asked them to do.
///
/// This is the same defect shape the quota refusal had -- a refusal that
/// arrives dressed as a success -- and it gets the same remedy the rest of
/// this codebase settled on: a result type that has to be read.
///
/// `core/review/N05_DISPOSITION.md` recorded it as the unfixed half of P2:
/// *"The copy in this branch names the exception; the flow still does not
/// handle it."* This is the flow handling it.
enum GuestUpgrade {
  /// There was no guest session. An ordinary sign-in, nothing at stake.
  notAGuest,

  /// The anonymous session was linked. Same uid, everything still reachable.
  /// This is the path the app is built around and the one that normally runs.
  linked,

  /// The Google account already belonged to a different Firebase user, so
  /// linking was refused and sign-in fell back to that existing account.
  ///
  /// The person is signed in and nothing is broken from the app's point of
  /// view, which is precisely why this has to be said out loud: whatever they
  /// did on this device before tapping is now under the old anonymous uid and
  /// no longer visible to them.
  orphaned,
}

/// The result of a sign-in, carrying what became of any guest session.
class SignInResult {
  const SignInResult(this.user, this.guestUpgrade);

  /// An ordinary sign-in with no anonymous session in play.
  const SignInResult.plain(this.user) : guestUpgrade = GuestUpgrade.notAGuest;

  final AuthUser user;

  /// Deliberately not defaulted. A default would let a future implementation
  /// return a value without deciding what happened, which is how the original
  /// bug read: not a wrong answer, an unasked question.
  final GuestUpgrade guestUpgrade;

  /// True when the person kept nothing from this device.
  bool get lostGuestHistory => guestUpgrade == GuestUpgrade.orphaned;
}
