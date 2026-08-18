import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/prefetch_outcome.dart';
import 'package:fitness_app/features/workouts/workouts_page.dart';

/// The sentence under the download card, which is the entire user-facing
/// contract of the offline feature.
///
/// It used to be `l10n.workoutsOfflineFailed('${action.error}')` — an English
/// sentence composed inside a Riverpod notifier, formatted by `toString()`,
/// and shown to every locale. And it had two states, so the case that actually
/// happens (some of the week is on the device) had no wording at all.
///
/// The distinction these cases exist to hold is between the last two:
///
///   * **"the rest could not be prepared"** — a fault. Nothing the user can do.
///   * **"daily limit reached"** — not a fault. Nothing failed, and it ends by
///     itself at the next UTC midnight.
///
/// Saying the second as the first sends someone looking for a problem that
/// does not exist. Saying the first as the second promises a reset that will
/// not fix anything.
void main() {
  late AppLocalizations en;
  late AppLocalizations ru;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  String lineFor(PrefetchOutcome o, [AppLocalizations? l]) =>
      prefetchLine(l ?? en, AsyncValue.data(o));

  String lineForRefusal(PrefetchRefusal r, [AppLocalizations? l]) =>
      prefetchLine(l ?? en, AsyncValue.error(PrefetchRefused(r), StackTrace.empty));

  group('what the card says', () {
    test('a complete week reports the counts, not a verb', () {
      final s = lineFor(const PrefetchOutcome(requested: 84, ready: 84));
      expect(s, contains('84'));
      expect(s.toLowerCase(), isNot(contains('limit')));
      expect(s.toLowerCase(), isNot(contains('could not')));
    });

    test('quota partway through names the limit AND what landed', () {
      final s = lineFor(const PrefetchOutcome(
          requested: 84, ready: 38, quotaExhausted: true));
      expect(s, contains('38'));
      expect(s, contains('84'),
          reason: 'the user needs to know how much of the week is covered');
      expect(s.toLowerCase(), contains('limit'));
      expect(s.toLowerCase(), contains('tomorrow'),
          reason: 'the one video failure with an action the user can take is '
              'waiting, so the line has to say that it ends');
    });

    test('an ordinary partial failure does NOT borrow the limit message', () {
      // The control. Without it, a line that always said "daily limit
      // reached" would satisfy the case above and be wrong every other time.
      final s = lineFor(const PrefetchOutcome(requested: 84, ready: 38));
      expect(s, contains('38'));
      expect(s.toLowerCase(), isNot(contains('limit')));
      expect(s.toLowerCase(), isNot(contains('tomorrow')));
    });

    test('zero delivered on quota says the limit, without a 0-of-N count', () {
      final s = lineFor(const PrefetchOutcome(
          requested: 84, ready: 0, quotaExhausted: true));
      // Exact, not `contains('limit')`. Substrings let this branch be swapped
      // for the PARTIAL quota key: "0 of 84 ready, more tomorrow" contains
      // every word the loose version looked for, and it is a count where the
      // user needs a statement.
      expect(s, en.workoutsOfflineLimitReached);
      expect(s, isNot(contains('0')),
          reason: 'a 0-of-N count in the one line that is not about a count');
    });

    test('zero delivered without quota is the plain failure line', () {
      final s = lineFor(const PrefetchOutcome(requested: 84, ready: 0));
      // Exact for the same reason, and this branch was the weaker of the two:
      // its only assertion was "does not contain limit", which every unrelated
      // string in the file also satisfies -- `workoutsOfflineNothingScheduled`
      // included, so a total failure could have read "nothing was scheduled".
      expect(s, en.workoutsOfflineNoneFailed);
      expect(s, isNot(contains('84')),
          reason: 'nothing was prepared; "0 of 84" is a statistic, not news');
    });

    test('an empty week is not reported as a failure or a success', () {
      final s = lineFor(const PrefetchOutcome(requested: 0, ready: 0));
      expect(s.toLowerCase(), isNot(contains('limit')));
      expect(s.toLowerCase(), isNot(contains('could not')));
      expect(s, isNot(contains('0 of 0')));
    });

    test('every outcome state produces its own distinct line', () {
      // The strongest form of the guard: if any two states share wording,
      // the type is distinguishing something the user cannot see.
      final lines = <String>{
        lineFor(const PrefetchOutcome(requested: 0, ready: 0)),
        lineFor(const PrefetchOutcome(requested: 84, ready: 84)),
        lineFor(const PrefetchOutcome(
            requested: 84, ready: 38, quotaExhausted: true)),
        lineFor(const PrefetchOutcome(requested: 84, ready: 38)),
        lineFor(const PrefetchOutcome(
            requested: 84, ready: 0, quotaExhausted: true)),
        lineFor(const PrefetchOutcome(requested: 84, ready: 0)),
      };
      expect(lines, hasLength(PrefetchState.values.length),
          reason: 'two prefetch states render as the same sentence');
    });
  });

  group('the pair of integers has to mean something', () {
    // `requested` is a count of distinct video FILES, not of exercises: the
    // prefetch queues both the girl and the men demonstration of every
    // scheduled exercise, so twelve exercises can be eighty-four videos
    // (`offline_video_providers.dart`). Unlabelled, "38 of 84" invited the
    // reader to reconcile 84 with a plan that has nothing like 84 of anything
    // in it -- accurate, and uninterpretable, which the programme rule about
    // naming only what is known is no defence against.
    test('every counted line names the unit it is counting', () {
      for (final o in const [
        PrefetchOutcome(requested: 84, ready: 84),
        PrefetchOutcome(requested: 84, ready: 38, quotaExhausted: true),
        PrefetchOutcome(requested: 84, ready: 38),
      ]) {
        expect(lineFor(o), contains('video'), reason: '${o.state} is unlabelled');
        expect(lineFor(o, ru), contains('видео'),
            reason: '${o.state} is unlabelled in Russian');
      }
    });

    test('one video is not "1 videos"', () {
      expect(lineFor(const PrefetchOutcome(requested: 1, ready: 1)),
          contains('1 video '));
      expect(lineFor(const PrefetchOutcome(requested: 1, ready: 1)),
          isNot(contains('videos')));
    });
  });

  group('what survives the truncation', () {
    // The subtitle is `maxLines: 2, overflow: ellipsis` in a column narrowed
    // by a 40dp icon on one side and a status icon on the other
    // (`workouts_page.dart`). The quota line is the longest of the nine, so
    // it is the one that gets cut -- and it used to be built as
    // "<count> ready — daily limit reached, the rest can be fetched
    // tomorrow", which puts the entire reason this is NOT a fault after the
    // cut. A user on a narrow phone read "38 of 84 ready — daily limit reac…"
    // at best, and the whole point of this gate is that a deliberate,
    // self-resolving refusal must not read as an outage.
    //
    // Asserted by ORDER rather than by a character budget: a budget would be
    // a number invented here to bound a rendering this test cannot measure.
    // Order is the actual requirement -- the exculpating clause is not last.
    test('the quota line leads with the limit, not with the count', () {
      for (final l in [en, ru]) {
        final s = lineFor(
            const PrefetchOutcome(requested: 84, ready: 38, quotaExhausted: true),
            l);
        final limit = s.toLowerCase().indexOf(l == en ? 'limit' : 'лимит');
        expect(limit, isNonNegative);
        expect(limit, lessThan(s.indexOf('38')),
            reason: 'the clause that stops this reading as a fault is behind '
                'the count, where the ellipsis eats it');
      }
    });
  });

  group('refusals', () {
    test('each reason has its own localized line, and none is a toString', () {
      final lines = <String>{};
      for (final reason in PrefetchRefusal.values) {
        final s = prefetchLine(
            en, AsyncValue.error(PrefetchRefused(reason), StackTrace.empty));
        expect(s, isNot(contains('PrefetchRefused')),
            reason: 'the exception leaked into the UI, which is the defect '
                'this replaced');
        expect(s, isNotEmpty);
        lines.add(s);
      }
      expect(lines, hasLength(PrefetchRefusal.values.length));
    });

    test('a free user is told what the feature costs, not what threw', () {
      expect(lineForRefusal(PrefetchRefusal.notSubscribed),
          contains('Supporter'));
    });

    test('each reason is wired to ITS OWN line, not merely to some line', () {
      // Distinct-and-non-empty is not enough: swapping two branches keeps all
      // three strings distinct and non-empty, and a user whose plan had not
      // finished loading would be told to sign in -- while an actually
      // signed-out user was told their plan could not be checked. Both
      // sentences are true of somebody, which is what makes the swap survive.
      expect(lineForRefusal(PrefetchRefusal.planUnknown),
          en.workoutsOfflineRefusedPlanUnknown);
      expect(lineForRefusal(PrefetchRefusal.signedOut),
          en.workoutsOfflineRefusedSignedOut);
      expect(lineForRefusal(PrefetchRefusal.notSubscribed),
          en.workoutsOfflineRefusedNotSubscribed);
    });

    test('an unnamed failure still shows its detail', () {
      // The player keeps its detail line for the failure it could not
      // classify, and so does this: a screenshot has to carry enough to
      // diagnose from.
      final s = prefetchLine(
          en, AsyncValue.error(Exception('signBlob denied'), StackTrace.empty));
      expect(s, contains('signBlob denied'));
    });
  });

  group('localization', () {
    test('the quota line is translated, not English in both locales', () {
      const o =
          PrefetchOutcome(requested: 84, ready: 38, quotaExhausted: true);
      final e = lineFor(o, en);
      final r = lineFor(o, ru);
      expect(r, isNot(e),
          reason: 'a Russian user was reading an English sentence composed '
              'in a state layer; that is the whole reason the text moved');
      expect(r, contains('38'));
      expect(r, contains('84'));
    });

    test('every refusal reason is translated too', () {
      for (final reason in PrefetchRefusal.values) {
        final e = prefetchLine(
            en, AsyncValue.error(PrefetchRefused(reason), StackTrace.empty));
        final r = prefetchLine(
            ru, AsyncValue.error(PrefetchRefused(reason), StackTrace.empty));
        expect(r, isNot(e), reason: '$reason is the same string in both');
      }
    });
  });

  test('loading says loading, whatever it is carrying', () {
    expect(prefetchLine(en, const AsyncValue.loading()),
        en.workoutsOfflineDownloading);
  });

  test('an untouched card shows the hint, not a fabricated result', () {
    expect(prefetchLine(en, const AsyncValue.data(null)),
        en.workoutsOfflineHint);
  });
}
