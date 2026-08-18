import 'package:cloud_functions/cloud_functions.dart';

import 'stripe_checkout_service.dart';

/// Why a checkout did not start, in terms the SCREEN can act on.
///
/// ## Why this exists
///
/// The subscription card used to render `error.toString()` into a monospace
/// panel with a stack trace beside it. For a genuinely unexpected fault that is
/// the right design — a screenshot has to carry enough to diagnose from. For a
/// refusal it is the defect this programme keeps meeting: a deliberate,
/// actionable answer displayed as a crash.
///
/// What the user actually saw when they tapped Subscribe on a guest account
/// was `[firebase_functions/failed-precondition] Add a Google account before
/// subscribing…` — an English sentence written for a server log, prefixed with
/// the name of a vendor SDK, shown to every locale.
///
/// ## Why it reads codes and not messages
///
/// Two of the backend's refusals share the gRPC status `failed-precondition`:
/// "you are a guest" and "you already have a subscription". One is fixed by
/// linking an account, the other by opening the billing portal, so the screen
/// has to tell them apart. The only other thing on the wire is that English
/// prose — and a phone deciding a product question with a substring would
/// break the day somebody improved the wording.
///
/// So `createCheckoutSession` states the distinction as data, in
/// `HttpsError`'s details payload, and this reads that. Nothing here ever
/// inspects [FirebaseFunctionsException.message].
enum CheckoutRefusal {
  /// No signed-in account at all.
  signedOut,

  /// The token is valid but the account behind it was deleted — the stale
  /// token window every guarded callable closes.
  accountDeleted,

  /// Signed in as a guest. Paying is refused because a guest account has no
  /// credential to sign back into, so the subscription could be neither
  /// restored nor cancelled. Fixed by linking a real account.
  anonymousAccount,

  /// A live subscription already exists. Fixed in the billing portal.
  alreadySubscribed,

  /// The free trial has been used on this account already. Reachable from the
  /// trial button, which shares this screen's error card.
  trialAlreadyUsed,

  /// The backend could not be reached. Named separately because it is the one
  /// failure that is genuinely worth retrying in a moment, and the one the
  /// 2026-08-08 report proves must not be claimed without evidence.
  unreachable,

  /// Reached the backend, and it refused for a reason it did not name.
  unnamedRefusal,

  /// Anything else. Keeps its detail, because that detail is the only
  /// diagnostic there is.
  unknown,
}

/// A classified checkout failure, carrying the original for diagnosis.
class CheckoutFailure {
  const CheckoutFailure(this.refusal, this.detail);

  final CheckoutRefusal refusal;

  /// The original error's own words. Shown ONLY for [CheckoutRefusal.unknown]
  /// — for everything else the screen has a sentence of its own and this is
  /// for a bug report.
  final String detail;

  /// True when the screen should show the diagnostic panel rather than a
  /// product sentence.
  bool get isUnclassified => refusal == CheckoutRefusal.unknown;

  /// Classifies [error] without reading any human-language text.
  ///
  /// The reason codes come from `CHECKOUT_REFUSAL` in `functions/src/index.ts`
  /// and are asserted identical by `checkout_reason_parity_test.dart`, so a
  /// rename on either side fails a test rather than silently degrading every
  /// refusal to [CheckoutRefusal.unnamedRefusal].
  static CheckoutFailure of(Object error) {
    if (error is FirebaseFunctionsException) {
      final reason = _reasonOf(error.details);
      if (reason != null) {
        final known = _byReason[reason];
        if (known != null) return CheckoutFailure(known, error.message ?? '');
      }
      // No reason, so fall back to what the status code alone supports. These
      // are the two gRPC codes that mean something specific enough to say out
      // loud; the rest are refusals whose grounds the backend did not state.
      final byCode = switch (error.code) {
        'unavailable' || 'deadline-exceeded' => CheckoutRefusal.unreachable,
        'unauthenticated' => CheckoutRefusal.signedOut,
        _ => CheckoutRefusal.unnamedRefusal,
      };
      return CheckoutFailure(byCode, error.message ?? '');
    }
    if (error is StripeCheckoutException) {
      // Raised by the client itself: no URL came back, or the browser would
      // not open. Neither is something the user did, and neither is a network
      // claim this can support.
      return CheckoutFailure(CheckoutRefusal.unnamedRefusal, error.message);
    }
    return CheckoutFailure(CheckoutRefusal.unknown, '$error');
  }

  /// The `reason` field, if the payload is shaped the way the backend sends it.
  ///
  /// Defensive because `details` is `dynamic` across the Firebase SDK boundary
  /// and arrives as whatever JSON decoding produced. A malformed payload must
  /// degrade to "the backend refused and did not say why", never throw inside
  /// an error handler.
  static String? _reasonOf(Object? details) {
    if (details is Map) {
      final reason = details['reason'];
      if (reason is String && reason.isNotEmpty) return reason;
    }
    return null;
  }

  /// Wire value to case. Deliberately NOT `CheckoutRefusal.values.byName` on a
  /// lowercased string: the wire format is the backend's to choose, and tying
  /// it to this enum's Dart spelling would make renaming a local identifier a
  /// breaking protocol change.
  static const _byReason = <String, CheckoutRefusal>{
    'SIGNED_OUT': CheckoutRefusal.signedOut,
    'ACCOUNT_DELETED': CheckoutRefusal.accountDeleted,
    'ANONYMOUS_ACCOUNT': CheckoutRefusal.anonymousAccount,
    'ALREADY_SUBSCRIBED': CheckoutRefusal.alreadySubscribed,
    'TRIAL_ALREADY_USED': CheckoutRefusal.trialAlreadyUsed,
  };

  /// Every reason string this understands, for the parity test.
  static Iterable<String> get knownReasons => _byReason.keys;
}
