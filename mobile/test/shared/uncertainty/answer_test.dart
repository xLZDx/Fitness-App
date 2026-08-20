import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/shared/uncertainty/answer.dart';

/// Gate E — proofs for the shared `Answer<T, R>` contract: exhaustiveness,
/// the never-fabricate-a-value invariant, and the bestGuess/value
/// separation that makes a tentative reading structurally impossible to
/// mistake for a real one.
///
/// A realistic domain-shaped reason enum, mirroring the real
/// `VideoFailureReason` (`features/equipment/data/video_failure.dart`) --
/// proves the contract fits a real existing shape without touching any
/// production call site (Gate E's own D0 note explains why no existing
/// system is retrofitted onto this in this gate).
enum _ClipFailureReason { linkUnavailable, quotaExhausted, offline, playbackFailed }

void main() {
  group('Answer.confident', () {
    test('carries the value and reports isConfident', () {
      const answer = Answer<int, _ClipFailureReason>.confident(42);
      expect(answer.isConfident, isTrue);
      expect(answer.valueOrNull, 42);
      expect(answer.reasonOrNull, isNull);
    });

    test('equality and hashCode are value-based', () {
      const a = Answer<int, _ClipFailureReason>.confident(7);
      const b = Answer<int, _ClipFailureReason>.confident(7);
      const c = Answer<int, _ClipFailureReason>.confident(8);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString is legible for debugging/logging', () {
      const answer = Answer<int, _ClipFailureReason>.confident(42);
      expect(answer.toString(), 'Answer.confident(42)');
    });

    test(
        'REGRESSION-SHAPE: equality is symmetric across a covariant generic '
        'instantiation (codex review, 2026-08-20, before this port landed on '
        "master) -- `other is ConfidentAnswer<T, R>` alone let int/num "
        'disagree on direction', () {
      const asInt = Answer<int, _ClipFailureReason>.confident(1);
      const Answer<num, _ClipFailureReason> asNum =
          Answer<num, _ClipFailureReason>.confident(1);
      expect(asInt == asNum, asNum == asInt,
          reason: 'equality must agree regardless of comparison direction');
    });
  });

  group('Answer.uncertain', () {
    test('carries the reason and reports NOT confident', () {
      const answer =
          Answer<int, _ClipFailureReason>.uncertain(_ClipFailureReason.offline);
      expect(answer.isConfident, isFalse);
      expect(answer.reasonOrNull, _ClipFailureReason.offline);
    });

    test(
        'REGRESSION-SHAPE: valueOrNull is null even when a bestGuess is present -- '
        'a tentative reading must never be readable through the confident accessor',
        () {
      const answer = Answer<int, _ClipFailureReason>.uncertain(
        _ClipFailureReason.playbackFailed,
        bestGuess: 999,
      );
      expect(answer.valueOrNull, isNull,
          reason: 'valueOrNull must only ever surface a REAL confident '
              'value, never a labeled guess -- a caller that reads it '
              'blind must never receive an uncertain answer disguised as '
              'a certain one');
      expect(answer.isConfident, isFalse);
    });

    test('bestGuess is reachable only through the UncertainAnswer arm, explicitly',
        () {
      const answer = Answer<int, _ClipFailureReason>.uncertain(
        _ClipFailureReason.offline,
        bestGuess: 5,
      );
      final guess = switch (answer) {
        ConfidentAnswer<int, _ClipFailureReason>() => null,
        UncertainAnswer<int, _ClipFailureReason>(:final bestGuess) => bestGuess,
      };
      expect(guess, 5);
    });

    test('equality distinguishes reason and bestGuess independently', () {
      const a = Answer<int, _ClipFailureReason>.uncertain(
          _ClipFailureReason.offline,
          bestGuess: 1);
      const b = Answer<int, _ClipFailureReason>.uncertain(
          _ClipFailureReason.offline,
          bestGuess: 1);
      const differentReason = Answer<int, _ClipFailureReason>.uncertain(
          _ClipFailureReason.linkUnavailable,
          bestGuess: 1);
      const differentGuess = Answer<int, _ClipFailureReason>.uncertain(
          _ClipFailureReason.offline,
          bestGuess: 2);
      const noGuess =
          Answer<int, _ClipFailureReason>.uncertain(_ClipFailureReason.offline);

      expect(a, equals(b));
      expect(a, isNot(equals(differentReason)));
      expect(a, isNot(equals(differentGuess)));
      expect(a, isNot(equals(noGuess)));
    });

    test('toString includes both the reason and the bestGuess', () {
      const answer = Answer<int, _ClipFailureReason>.uncertain(
        _ClipFailureReason.linkUnavailable,
        bestGuess: 3,
      );
      expect(answer.toString(),
          'Answer.uncertain(_ClipFailureReason.linkUnavailable, bestGuess: 3)');
    });
  });

  group('exhaustiveness', () {
    // The point of `sealed` is that this switch is a COMPILE error if a
    // third subtype is ever added without being handled here -- this test
    // exercises the real Dart pattern-matching path both branches use, not
    // just the extension helpers.
    String describe(Answer<String, _ClipFailureReason> answer) => switch (answer) {
          ConfidentAnswer<String, _ClipFailureReason>(:final value) =>
            'confident: $value',
          UncertainAnswer<String, _ClipFailureReason>(:final reason) =>
            'uncertain: $reason',
        };

    test('confident arm', () {
      expect(describe(const Answer.confident('leg press')),
          'confident: leg press');
    });

    test('uncertain arm', () {
      expect(
        describe(
            const Answer.uncertain(_ClipFailureReason.playbackFailed)),
        'uncertain: _ClipFailureReason.playbackFailed',
      );
    });
  });

  group('a realistic domain fit (mirrors VideoFailureReason, no production code touched)', () {
    Answer<String, _ClipFailureReason> classify({
      required bool linkOk,
      bool quotaExhausted = false,
      String? platformDetail,
    }) {
      if (!linkOk) {
        return const Answer.uncertain(_ClipFailureReason.linkUnavailable);
      }
      if (quotaExhausted) {
        return const Answer.uncertain(_ClipFailureReason.quotaExhausted);
      }
      if (platformDetail == null) {
        return const Answer.confident('clip.mp4');
      }
      final lower = platformDetail.toLowerCase();
      if (lower.contains('connection reset')) {
        return Answer.uncertain(_ClipFailureReason.offline,
            bestGuess: null);
      }
      // "When in doubt ... blames nothing" -- VideoFailureReason's own
      // documented default, reproduced here structurally: an unrecognised
      // detail degrades to the honest catch-all reason, never a guessed
      // specific one.
      return const Answer.uncertain(_ClipFailureReason.playbackFailed);
    }

    test('a resolvable link with no platform error is confident', () {
      final result = classify(linkOk: true);
      expect(result.isConfident, isTrue);
      expect(result.valueOrNull, 'clip.mp4');
    });

    test('an unresolvable link is uncertain for the right, specific reason', () {
      final result = classify(linkOk: false);
      expect(result.reasonOrNull, _ClipFailureReason.linkUnavailable);
    });

    // Real `VideoFailureReason` (`video_failure.dart`) has a fourth case,
    // `quotaExhausted`, split out of `linkUnavailable` specifically because
    // the two need opposite messages -- codex review, 2026-08-20, caught
    // this fixture drifting to only three of the four real cases.
    test('a quota-exhausted link is uncertain for its own reason, distinct '
        'from a merely unavailable one', () {
      final result = classify(linkOk: true, quotaExhausted: true);
      expect(result.reasonOrNull, _ClipFailureReason.quotaExhausted);
      expect(result.reasonOrNull, isNot(_ClipFailureReason.linkUnavailable),
          reason: 'the two need opposite messages and must not collapse '
              'into one reason');
    });

    test('a positively-matched network error reason is not guessed', () {
      final result =
          classify(linkOk: true, platformDetail: 'Connection reset by peer');
      expect(result.reasonOrNull, _ClipFailureReason.offline);
    });

    test('an unrecognised platform error degrades to the honest catch-all, '
        'never a fabricated specific reason', () {
      final result =
          classify(linkOk: true, platformDetail: 'PlatformException(-11800)');
      expect(result.reasonOrNull, _ClipFailureReason.playbackFailed,
          reason: 'must never guess "offline" or "linkUnavailable" for an '
              'error it does not actually recognise');
    });
  });
}
