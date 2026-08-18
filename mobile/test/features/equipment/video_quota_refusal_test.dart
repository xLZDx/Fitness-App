import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

import 'package:fitness_app/features/equipment/data/clip_url_resolver.dart';
import 'package:fitness_app/features/equipment/data/video_failure.dart';
import 'package:fitness_app/features/equipment/widgets/exercise_reference.dart';

/// A deliberate refusal must not read as a fault.
///
/// `enforceDailyQuota` throws `resource-exhausted` with a sentence already
/// written for a reader — "You have reached today's limit for this action. It
/// resets tomorrow." That sentence died in `ClipUrlResolver.fetch`, which
/// caught every exception alike and returned `{}`; `resolve` mapped the empty
/// map to null; the player stored the `unresolved` sentinel; and the screen
/// said **"The clip link is unavailable"**.
///
/// So every deliberate refusal was indistinguishable from a signing outage, a
/// missing object, or the absent `tokenCreator` grant the backend names as a
/// real failure mode. The already-shipped `ANONYMOUS_QUOTA_DIVISOR = 8` makes
/// that a live case, not a hypothetical one — and `firestore.rules` closes
/// `users/{uid}/usage/{day}` outright, so the callable's error is the only
/// channel that exists.
///
/// This file follows the refusal along the whole path it used to die on:
/// recognise it, keep it typed, and put the right sentence on the screen.
class _Refusal extends FirebaseFunctionsException {
  // Subclassing rather than constructing: the platform interface marks the
  // constructor `@protected`, which a subclass may legitimately call.
  _Refusal({required super.code, required super.message});
}

void main() {
  group('recognising the refusal', () {
    test('resource-exhausted is a quota refusal and keeps its sentence', () {
      final e = FunctionsClipUrlResolver.asQuotaRefusal(_Refusal(
        code: 'resource-exhausted',
        message: "You have reached today's limit for this action. "
            'It resets tomorrow.',
      ));
      expect(e, isNotNull);
      expect(e!.message, contains('resets tomorrow'),
          reason: 'the backend already wrote the useful half of this message; '
              'the app only has to stop throwing it away');
    });

    test('any other Functions error is NOT a quota refusal', () {
      // The codes that actually reach this path: an unauthenticated caller, a
      // missing object, and a signing failure. Reporting any of them as
      // "limit reached" would be the original defect with the sign flipped.
      for (final code in const [
        'unauthenticated',
        'not-found',
        'internal',
        'permission-denied',
        'invalid-argument',
      ]) {
        expect(
          FunctionsClipUrlResolver.asQuotaRefusal(
              _Refusal(code: code, message: 'x')),
          isNull,
          reason: '$code is not a quota refusal',
        );
      }
    });

    test('a non-Firebase failure is not a quota refusal', () {
      expect(FunctionsClipUrlResolver.asQuotaRefusal(Exception('boom')), isNull);
      expect(FunctionsClipUrlResolver.asQuotaRefusal('resource-exhausted'),
          isNull,
          reason: 'the string is not the code; matching on message text is '
              'what this deliberately avoids');
    });

    test('an empty backend message becomes null, not an empty headline', () {
      final e = FunctionsClipUrlResolver.asQuotaRefusal(
          _Refusal(code: 'resource-exhausted', message: '   '));
      expect(e, isNotNull);
      expect(e!.message, isNull);
      expect(e.toString(), isNotEmpty,
          reason: 'there is always something to say, even when the backend '
              'sent nothing');
    });
  });

  group('classifying it', () {
    test('a quota refusal is its own reason, not linkUnavailable', () {
      expect(classifyVideoFailure(const ClipQuotaExhausted('anything')),
          VideoFailureReason.quotaExhausted);
    });

    test('the TYPE decides, not the words in the message', () {
      // The control that makes this different from the string matching the
      // rest of the classifier does. A backend sentence containing a network
      // word must not turn a deliberate refusal into "no connection" -- that
      // is precisely the 2026-08-08 defect this file's neighbour exists for.
      expect(
        classifyVideoFailure(
            const ClipQuotaExhausted('connection reset while counting')),
        VideoFailureReason.quotaExhausted,
      );
    });

    test('it carries no detail line: the headline is the whole message', () {
      expect(videoFailureDetail(const ClipQuotaExhausted('x')), isNull);
    });

    test('the sentinel still means linkUnavailable', () {
      // Nothing about the existing path moved. If this fails, the new branch
      // widened instead of splitting.
      expect(classifyVideoFailure(kUnresolvedClip),
          VideoFailureReason.linkUnavailable);
    });
  });

  group('the single-clip failure policy', () {
    // fetch() catches inside a real FirebaseFunctions call, so no test can
    // enter that block. The decision it used to hold lives here instead, and
    // these two cases are the whole of it.
    test('a refusal is rethrown', () {
      expect(
        () => FunctionsClipUrlResolver.swallowOrThrow(_Refusal(
            code: 'resource-exhausted', message: 'It resets tomorrow.')),
        throwsA(isA<ClipQuotaExhausted>()),
      );
    });

    test('everything else is swallowed, as before', () {
      expect(FunctionsClipUrlResolver.swallowOrThrow(Exception('boom')),
          isEmpty);
      expect(
          FunctionsClipUrlResolver.swallowOrThrow(
              _Refusal(code: 'not-found', message: 'gone')),
          isEmpty);
    });
  });

  group('propagating it', () {
    test('resolve throws the refusal instead of returning null', () async {
      final r = _RefusingBackend();
      await expectLater(
        r.resolve('exercises/men/Legs/squat.mp4'),
        throwsA(isA<ClipQuotaExhausted>()),
      );
    });

    test('a signing failure still returns null, silently', () async {
      // The contract for everything that is NOT a refusal is unchanged: keep
      // the poster up and say nothing the app cannot support.
      final r = _FailingBackend();
      expect(await r.resolve('exercises/men/Legs/squat.mp4'), isNull);
    });
  });

  group('showing it', () {
    Future<void> pumpNote(WidgetTester tester, Object error) async {
      await tester.pumpWidget(MaterialApp(
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExerciseVideoFailedNote(hasPoster: true, error: error),
        ),
      ));
      await tester.pump();
    }

    testWidgets('a refusal says what happened and when it ends',
        (tester) async {
      await pumpNote(tester, const ClipQuotaExhausted('ignored'));
      expect(find.textContaining('Daily clip limit'), findsOneWidget);
      expect(find.textContaining('resets tomorrow'), findsOneWidget,
          reason: 'the one video failure with an action the user can take is '
              'waiting, so the message has to say that it ends');
      expect(find.text('The clip link is unavailable'), findsNothing);
    });

    testWidgets('an unresolved clip still says the link is unavailable',
        (tester) async {
      await pumpNote(tester, kUnresolvedClip);
      expect(find.text('The clip link is unavailable'), findsOneWidget);
      expect(find.textContaining('Daily clip limit'), findsNothing);
    });
  });
}

/// A resolver whose backend refuses on the daily budget.
class _RefusingBackend extends FunctionsClipUrlResolver {
  _RefusingBackend() : super(now: DateTime.now);

  @override
  Future<Map<String, String>> fetch(List<String> objects) async =>
      throw const ClipQuotaExhausted("It resets tomorrow.");
}

/// A resolver whose backend simply could not sign.
class _FailingBackend extends FunctionsClipUrlResolver {
  _FailingBackend() : super(now: DateTime.now);

  @override
  Future<Map<String, String>> fetch(List<String> objects) async => {};
}
