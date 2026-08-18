// The outcome a successful sign-in can carry, and the screen that has to say
// it.
//
// `core/review/N05_DISPOSITION.md` recorded this as the unfixed half of P2:
// "The copy in this branch names the exception; the flow still does not handle
// it." Linking an anonymous session keeps its uid and everything under it;
// falling back to `signInWithCredential` signs the person into their real
// account and leaves this device's history under a uid nobody can ever sign
// into again. Both returned an `AuthUser`, so the screen showed the same thing
// either way.
import 'dart:io';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/mock_auth_repository.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what a sign-in reports about the guest session', () {
    test('a guest who links keeps the uid, and the outcome says so', () async {
      final repo = MockAuthRepository(latency: Duration.zero);
      final guest = await repo.signInAnonymously();

      final result = await repo.signInWithGoogle();

      expect(result.guestUpgrade, GuestUpgrade.linked);
      expect(result.lostGuestHistory, isFalse);
      // The outcome must agree with what actually happened, not merely be a
      // plausible label: same uid means the data is still reachable.
      expect(result.user.uid, guest.uid);
      repo.dispose();
    });

    test('a collision reports orphaned, and the uid really did change',
        () async {
      final repo = MockAuthRepository(
        latency: Duration.zero,
        simulateGoogleAccountCollision: true,
      );
      final guest = await repo.signInAnonymously();

      final result = await repo.signInWithGoogle();

      expect(result.guestUpgrade, GuestUpgrade.orphaned);
      expect(result.lostGuestHistory, isTrue);
      expect(result.user.uid, isNot(guest.uid),
          reason: 'orphaned must mean the guest uid was left behind');
      repo.dispose();
    });

    test('no guest session at all is notAGuest, not orphaned', () async {
      final repo = MockAuthRepository(latency: Duration.zero);

      final result = await repo.signInWithGoogle();

      // The distinction that matters: nothing was lost, because there was
      // nothing on this device to lose. Reporting `orphaned` here would train
      // people to ignore the warning.
      expect(result.guestUpgrade, GuestUpgrade.notAGuest);
      expect(result.lostGuestHistory, isFalse);
      repo.dispose();
    });
  });

  group('the state the screen watches', () {
    ProviderContainer containerWith(MockAuthRepository repo) {
      final c = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('carries the outcome through to the screen', () async {
      final repo = MockAuthRepository(
        latency: Duration.zero,
        simulateGoogleAccountCollision: true,
      );
      addTearDown(repo.dispose);
      final c = containerWith(repo);

      await c.read(authActionProvider.notifier).signInAnonymously();
      await c.read(authActionProvider.notifier).signInWithGoogle();

      expect(c.read(authActionProvider).value, GuestUpgrade.orphaned);
    });

    test('an ordinary link leaves nothing for the screen to warn about',
        () async {
      final repo = MockAuthRepository(latency: Duration.zero);
      addTearDown(repo.dispose);
      final c = containerWith(repo);

      await c.read(authActionProvider.notifier).signInAnonymously();
      await c.read(authActionProvider.notifier).signInWithGoogle();

      expect(c.read(authActionProvider).value, GuestUpgrade.linked);
    });

    test('a failure is still an error, not a quiet outcome', () async {
      final repo = _FailingAuth();
      addTearDown(repo.dispose);
      final c = containerWith(repo);

      await c.read(authActionProvider.notifier).signInWithGoogle();

      expect(c.read(authActionProvider).hasError, isTrue);
      // Not `.value`, which throws on an AsyncError in Riverpod. The point is
      // that a thrown sign-in stays an error rather than degrading into a
      // quiet outcome the screen would render as an ordinary result.
      expect(c.read(authActionProvider).hasValue, isFalse);
    });
  });

  group('the screen actually reads it', () {
    // `login_page.dart` is not pumped here. The rest of this repository's
    // login widget tests do pump it, but a structural guard is what catches
    // the specific regression this gate exists to prevent: someone keeping
    // the outcome type and quietly dropping the branch that renders it, which
    // restores the silent success without touching a single assertion above.
    late String code;

    setUpAll(() {
      // Comments stripped first: this file explains the defect by naming the
      // symbols involved, and a guard that reads prose would find the
      // explanation and mistake it for the implementation.
      code = File('lib/features/auth/login_page.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('the orphaned outcome reaches a widget', () {
      expect(code, contains('GuestUpgrade.orphaned'),
          reason: 'nothing on the screen distinguishes the outcome any more');
      expect(code, contains('_GuestHistoryNotice'));
    });

    test('the notice is localized, not an English literal', () {
      expect(code, contains('authGuestHistoryOrphaned'));
    });

    test('the warning is not a SnackBar', () {
      // Deliberate: a person who has just lost sight of their training history
      // should not have the only explanation disappear on a timer.
      final notice = code.substring(code.indexOf('_GuestHistoryNotice'));
      expect(notice, isNot(contains('SnackBar')));
    });
  });

  _realRepositoryGuards();

  group('the copy says what happened', () {
    late Map<String, String> en;

    setUpAll(() {
      final raw = File('lib/l10n/app_en.arb').readAsStringSync();
      en = {
        for (final m in RegExp(r'"(\w+)"\s*:\s*"((?:[^"\\]|\\.)*)"')
            .allMatches(raw))
          m.group(1)!: m.group(2)!,
      };
    });

    test('it does not call a successful sign-in an error', () {
      final s = en['authGuestHistoryOrphaned']!.toLowerCase();
      expect(s, isNot(contains('error')));
      expect(s, isNot(contains('failed')));
      expect(s, isNot(contains('went wrong')));
    });

    test('it does not claim anything was deleted, because nothing was', () {
      final s = en['authGuestHistoryOrphaned']!.toLowerCase();
      for (final word in ['deleted', 'erased', 'lost', 'removed']) {
        expect(s, isNot(contains(word)),
            reason: 'the guest data still exists; it is unreachable. Saying '
                '"$word" would be false, and false in the direction that '
                'makes people stop looking for it');
      }
    });

    test('both locales carry it', () {
      final ru = File('lib/l10n/app_ru.arb').readAsStringSync();
      expect(ru, contains('authGuestHistoryOrphaned'));
      expect(en['authGuestHistoryOrphaned'], isNotEmpty);
    });
  });
}

class _FailingAuth extends MockAuthRepository {
  _FailingAuth() : super(latency: Duration.zero);

  @override
  Future<SignInResult> signInWithGoogle() async =>
      throw StateError('google refused');
}

// Referenced so the analyzer keeps the import that documents the shape the
// outcome wraps.
// ignore: unused_element
AuthUser? _shape;

// ---------------------------------------------------------------------------
// The class that actually ships.
//
// Found by mutation, not by review: replacing the real repository's
// `wasGuest ? orphaned : notAGuest` with a flat `notAGuest` -- which is the
// original defect, exactly -- left all twelve tests above green, because every
// one of them runs against `MockAuthRepository`. `FirebaseAuthRepository`
// cannot be constructed here (it needs a live FirebaseAuth), and the rest of
// this repository already tests that file by reading it, so this does too.
void _realRepositoryGuards() {
  group('the shipping repository, read as source', () {
    late String code;

    setUpAll(() {
      code = File('lib/features/auth/data/firebase_auth_repository.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('the fallback decides on whether there WAS a guest', () {
      expect(code, contains('final wasGuest ='),
          reason: 'nothing records that a guest session existed');
      expect(
        code,
        contains('wasGuest ? GuestUpgrade.orphaned : GuestUpgrade.notAGuest'),
        reason: 'the fallback no longer distinguishes a lost guest session '
            'from an ordinary sign-in -- which is the original defect, and it '
            'is invisible to every test that goes through the mock',
      );
    });

    test('the linking path reports linked, not a bare user', () {
      expect(code, contains('GuestUpgrade.linked'));
      // The bug was that both paths returned the same shape. If either one
      // stops naming its outcome, they are indistinguishable again.
      expect(code, contains('GuestUpgrade.orphaned'));
    });
  });
}
