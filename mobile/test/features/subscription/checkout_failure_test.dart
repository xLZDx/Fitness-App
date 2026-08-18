import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/subscription/data/checkout_failure.dart';
import 'package:fitness_app/features/subscription/data/stripe_checkout_service.dart';
import 'package:fitness_app/features/subscription/subscription_page.dart';

/// The sentence the subscription card shows when a checkout does not start.
///
/// It used to be `error.toString()` in a monospace panel with a stack trace.
/// A guest tapping Subscribe read
/// `[firebase_functions/failed-precondition] Add a Google account before
/// subscribing…` — an English sentence written for a server log, prefixed with
/// a vendor SDK's name, shown to every locale.
///
/// The distinction these tests hold is between a refusal the backend NAMED —
/// which has an action attached and belongs in the user's language — and a
/// failure nobody classified, which keeps its detail because that detail is
/// the only diagnostic there is.
FirebaseFunctionsException _fn(String code, {Object? details, String? message}) =>
    FirebaseFunctionsException(
      code: code,
      message: message ?? 'a message written for a server log',
      details: details,
    );

void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  group('classification reads codes, never prose', () {
    test('each backend reason maps to its own case', () {
      expect(
        CheckoutFailure.of(_fn('failed-precondition',
                details: {'reason': 'ANONYMOUS_ACCOUNT'}))
            .refusal,
        CheckoutRefusal.anonymousAccount,
      );
      expect(
        CheckoutFailure.of(_fn('failed-precondition',
                details: {'reason': 'ALREADY_SUBSCRIBED'}))
            .refusal,
        CheckoutRefusal.alreadySubscribed,
      );
      expect(
        CheckoutFailure.of(
                _fn('unauthenticated', details: {'reason': 'ACCOUNT_DELETED'}))
            .refusal,
        CheckoutRefusal.accountDeleted,
      );
      expect(
        CheckoutFailure.of(
                _fn('unauthenticated', details: {'reason': 'SIGNED_OUT'}))
            .refusal,
        CheckoutRefusal.signedOut,
      );
    });

    test('two refusals sharing one status code stay apart', () {
      // The reason the reason exists. Both are `failed-precondition`; one is
      // fixed by linking an account and the other in the billing portal.
      final a = CheckoutFailure.of(
          _fn('failed-precondition', details: {'reason': 'ANONYMOUS_ACCOUNT'}));
      final b = CheckoutFailure.of(_fn('failed-precondition',
          details: {'reason': 'ALREADY_SUBSCRIBED'}));
      expect(a.refusal, isNot(b.refusal));
      expect(checkoutLine(en, _fn('failed-precondition',
              details: {'reason': 'ANONYMOUS_ACCOUNT'})),
          isNot(checkoutLine(en, _fn('failed-precondition',
              details: {'reason': 'ALREADY_SUBSCRIBED'}))));
    });

    test('the message is never consulted', () {
      // The guard against the fix that would have been easiest to write. A
      // message carrying every trigger word, with NO reason attached, must
      // still classify as an unnamed refusal.
      final e = _fn('failed-precondition',
          message: 'Add a Google account before subscribing. A guest account '
              'cannot be signed back into. You already have an active '
              'subscription.');
      expect(CheckoutFailure.of(e).refusal, CheckoutRefusal.unnamedRefusal);
    });

    test('an unreachable backend is named, and only by its status code', () {
      expect(CheckoutFailure.of(_fn('unavailable')).refusal,
          CheckoutRefusal.unreachable);
      expect(CheckoutFailure.of(_fn('deadline-exceeded')).refusal,
          CheckoutRefusal.unreachable);
    });

    test('a refusal with no reason is unnamed, not invented', () {
      expect(CheckoutFailure.of(_fn('internal')).refusal,
          CheckoutRefusal.unnamedRefusal);
      expect(CheckoutFailure.of(_fn('permission-denied')).refusal,
          CheckoutRefusal.unnamedRefusal);
    });

    test('a malformed details payload degrades, it does not throw', () {
      // `details` crosses a dynamic SDK boundary. Throwing inside an error
      // handler would replace a refusal with a crash.
      for (final bad in <Object?>[
        null,
        'ANONYMOUS_ACCOUNT',
        <String, Object?>{'reason': 42},
        <String, Object?>{'reason': ''},
        <String, Object?>{'other': 'ANONYMOUS_ACCOUNT'},
        <Object?>['ANONYMOUS_ACCOUNT'],
      ]) {
        expect(
          () => CheckoutFailure.of(_fn('failed-precondition', details: bad)),
          returnsNormally,
        );
        expect(
          CheckoutFailure.of(_fn('failed-precondition', details: bad)).refusal,
          CheckoutRefusal.unnamedRefusal,
          reason: 'a payload of $bad named a reason it does not carry',
        );
      }
    });

    test('a client-side failure is unnamed, not a network claim', () {
      // No URL came back, or the browser would not open. Neither is something
      // the user did, and neither supports a claim about the network — the
      // 2026-08-08 report was a player blaming the network on a 1 Gb link.
      final f = CheckoutFailure.of(
          StripeCheckoutException('Backend returned no checkout URL.'));
      expect(f.refusal, CheckoutRefusal.unnamedRefusal);
      expect(f.refusal, isNot(CheckoutRefusal.unreachable));
    });

    test('something that is not an exception at all keeps its detail', () {
      final f = CheckoutFailure.of('a bare string thrown from somewhere');
      expect(f.refusal, CheckoutRefusal.unknown);
      expect(f.isUnclassified, isTrue);
      expect(f.detail, contains('a bare string'));
    });
  });

  group('what the card says', () {
    test('no classified refusal leaks an implementation term', () {
      for (final reason in CheckoutFailure.knownReasons) {
        for (final l in [en, ru]) {
          final s = checkoutLine(
              l, _fn('failed-precondition', details: {'reason': reason}));
          for (final leak in const [
            'firebase',
            'Firebase',
            'Exception',
            'failed-precondition',
            'null',
            'Stripe',
          ]) {
            expect(s, isNot(contains(leak)),
                reason: '$reason leaked "$leak" into user copy');
          }
          expect(s, isNotEmpty);
        }
      }
    });

    test('the guest refusal states the action, not the fault', () {
      final s = checkoutLine(
          en, _fn('failed-precondition', details: {'reason': 'ANONYMOUS_ACCOUNT'}));
      expect(s.toLowerCase(), contains('link'));
      expect(s.toLowerCase(), contains('google'));
    });

    test('every case has its own sentence', () {
      final lines = <String>{
        for (final r in CheckoutFailure.knownReasons)
          checkoutLine(en, _fn('failed-precondition', details: {'reason': r})),
        checkoutLine(en, _fn('unavailable')),
        checkoutLine(en, _fn('internal')),
      };
      // Six distinct: four named reasons, unreachable, and unnamed.
      expect(lines, hasLength(6),
          reason: 'two checkout outcomes render as the same sentence');
    });

    test('the unreachable line does not blame the network', () {
      final s = checkoutLine(en, _fn('unavailable')).toLowerCase();
      expect(s, isNot(contains('network')));
      expect(s, isNot(contains('internet')));
      expect(s, isNot(contains('offline')));
    });

    test('every line is translated, not English in both locales', () {
      for (final r in CheckoutFailure.knownReasons) {
        final e = checkoutLine(en, _fn('failed-precondition', details: {'reason': r}));
        final u = checkoutLine(ru, _fn('failed-precondition', details: {'reason': r}));
        expect(u, isNot(e), reason: '$r is the same string in both locales');
      }
      expect(checkoutLine(ru, _fn('unavailable')),
          isNot(checkoutLine(en, _fn('unavailable'))));
    });
  });

  _wiring();

  group('the wire format is one contract, held on both sides', () {
    test('every reason the client knows is one the backend sends', () {
      // A rename on either side must fail a test rather than silently
      // degrading every refusal to "the backend did not say why" -- which is
      // a failure mode that looks exactly like working software.
      final ts = File('../functions/src/index.ts').readAsStringSync();
      final block = RegExp(
              r'export const CHECKOUT_REFUSAL = \{(.*?)\} as const;',
              dotAll: true)
          .firstMatch(ts);
      expect(block, isNotNull,
          reason: 'CHECKOUT_REFUSAL is gone from functions/src/index.ts');

      final declared = RegExp('"([A-Z_]+)"')
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(declared, isNotEmpty);
      expect(CheckoutFailure.knownReasons.toSet().difference(declared), isEmpty,
          reason: 'the client understands a reason the backend never sends');
      expect(declared.difference(CheckoutFailure.knownReasons.toSet()), isEmpty,
          reason: 'the backend sends a reason the client silently ignores');
    });

    test('the backend actually attaches each reason to a throw', () {
      // The constant existing is not the contract. Each value has to reach a
      // caller, and a `details` payload is the only way it does.
      final ts = File('../functions/src/index.ts').readAsStringSync();
      for (final r in CheckoutFailure.knownReasons) {
        expect(ts, contains('CHECKOUT_REFUSAL.$r'),
            reason: '$r is declared but never sent, so the client branch for '
                'it is unreachable');
      }
    });
  });
}

/// The seam has to be WIRED, not merely present.
///
/// Every test above calls `checkoutLine` directly, and a mutation that put
/// `error.toString()` back as the card's line left all of them green — the
/// function was still correct, and the widget had simply stopped calling it.
/// An extracted seam nothing is required to use is not a guard.
///
/// This page cannot be pumped: its own test file records that
/// AuroraBackground + GoRouter never settle under `flutter test` and hit a
/// ten-minute isolate timeout. So the wiring is asserted structurally, the
/// same way the clinical handoff and the reason-parity guards read their
/// sources. It matches identifiers and their ORDER, never prose.
void _wiring() {
  group('the card is wired to the classifier', () {
    late String card;

    setUpAll(() {
      final src =
          File('lib/features/subscription/subscription_page.dart').readAsStringSync();
      final start = src.indexOf('class _ErrorCard');
      expect(start, isNonNegative, reason: '_ErrorCard is gone');
      // From `build` onward, NOT the whole class. `_composePayload` also
      // stringifies the error, and it is right to: that is the text the Copy
      // button puts on the clipboard for a bug report, and its own comment
      // says it is deliberately English and deliberately not localized. A
      // guard that could not tell the two apart failed on correct code the
      // first time it ran.
      final build = src.indexOf('Widget build(BuildContext context)', start);
      expect(build, isNonNegative, reason: '_ErrorCard has no build method');
      card = src.substring(build);
    });

    test('the error card renders the classified line', () {
      expect(card, contains('checkoutLine(AppLocalizations.of(context), error)'),
          reason: 'the card stopped calling the classifier, so every refusal '
              'renders as whatever the exception says');
    });

    test('the raw exception appears only behind the unclassified guard', () {
      final raw = card.indexOf('error.toString()');
      if (raw < 0) return; // no diagnostic at all is also acceptable
      final guard = card.indexOf('CheckoutFailure.of(error).isUnclassified');
      expect(guard, isNonNegative,
          reason: 'error.toString() is rendered with nothing gating it');
      expect(guard, lessThan(raw),
          reason: 'the raw exception is rendered before the guard that is '
              'supposed to restrict it to unclassified failures');
    });
  });
}
