import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// N07 — the tripwire that fires the day the team feed gets a real backend.
///
/// `/team/:teamId` is declared at `app_router.dart:349` and nothing in `lib/`
/// navigates to it. It is auth-gated (not in `_publicPaths`) and backed by
/// `MockTeamFeedRepository`, so today there is no server collection, no
/// Firestore rule for one, and nothing to leak. The finding is deferred as a
/// product decision: wiring it ships a Celebrity-tier feature nobody has
/// exercised, and deleting it removes intended work during an audit.
///
/// What is NOT safe to defer is what happens if somebody wires it without
/// noticing the rest. The Celebrity-tier lock in `TeamFeedPage` is
/// **client-side and partial**: `_PostCard(locked: !isPremium)` substitutes a
/// "sustainer only" string for `post.body`, but the author, avatar, timestamp,
/// pin state and TITLE are rendered above that branch, and the whole post
/// document reaches the device either way. Bind a Firestore-backed repository
/// without a server-side membership-and-tier rule and the paywall becomes a UI
/// string that any client can simply decline to draw.
///
/// So this file does not test Teams. It tests the CONDITIONAL:
///
///     wired to a real repository  =>  firestore.rules must authorise it
///
/// The conditional is currently vacuous in this repository, because nothing is
/// wired. A guard that is vacuous against real inputs is the exact defect this
/// programme has hit repeatedly, so the rule is expressed as a pure function
/// and exercised against THREE inputs: the real tree, a synthetic wired tree
/// with no rule (must fail), and a synthetic wired tree with a rule (must
/// pass). Only the first is evidence about today; the other two are what make
/// the guard something rather than decoration.
void main() {
  /// The provider whose override IS the activation event.
  ///
  /// `teamFeedRepositoryProvider` defaults to the mock in its own declaration.
  /// The only way a real backend reaches `TeamFeedPage` is an override at the
  /// composition root — the same shape `main.dart` already uses for the moment
  /// repository and the wear service.
  const provider = 'teamFeedRepositoryProvider';

  /// The collection a real team feed would have to live in.
  ///
  /// Both spellings, because `TeamFeedRepository.watchTeamFeed(teamId)` fixes
  /// no path and a future author may reasonably pick either.
  const collections = ['teams', 'team_feed', 'team_posts', 'community'];

  /// Is a real repository bound anywhere outside the declaration?
  ///
  /// Comment lines are stripped first. This file's own prose names the
  /// provider a dozen times, and so does the declaration's doc comment — a
  /// raw substring scan would report the documentation as the defect. That is
  /// the failure mode the sibling `dormant_traps_test.dart` already had to fix
  /// once.
  bool wiredIn(Map<String, String> sources) {
    for (final entry in sources.entries) {
      if (entry.key.endsWith('team_feed_providers.dart')) continue;
      final live = entry.value
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      if (live.contains(provider) &&
          (live.contains('overrideWith') ||
              live.contains('overrideWithValue'))) {
        return true;
      }
    }
    return false;
  }

  /// Does the rules file authorise a team collection at all?
  ///
  /// Deliberately weak on purpose: it asks whether a `match` block exists for
  /// one of the plausible collections AND mentions `request.auth`. It does not
  /// try to prove the rule is CORRECT — a source scan cannot, and pretending
  /// otherwise would be worse than admitting it. Proving correctness is what
  /// the emulator tests named in the activation gate are for. This only
  /// catches the case that matters most and is easiest to hit: a real backend
  /// wired with no server-side authorisation written at all.
  bool rulesAuthoriseATeamCollection(String rules) {
    final live = rules
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final c in collections) {
      final match = RegExp(r'match\s+/' + c + r'\b');
      if (match.hasMatch(live) && live.contains('request.auth')) return true;
    }
    return false;
  }

  /// The whole rule, as one predicate over a tree.
  ///
  /// Returns null when the tree is acceptable, or the reason it is not.
  String? violation(Map<String, String> sources, String rules) {
    if (!wiredIn(sources)) return null; // dormant: nothing to authorise
    if (rulesAuthoriseATeamCollection(rules)) return null;
    return 'the team feed is now bound to a real repository, and '
        'firestore.rules authorises no team collection. The Celebrity-tier '
        'lock in TeamFeedPage is client-side and partial -- the post title and '
        'every author field render outside the locked branch, and the whole '
        'document reaches the device. Without a server-side membership and '
        'tier rule the paywall is a string the client can decline to draw. '
        'See core/review/N07_TEAM_ACTIVATION_GATE.md before going further.';
  }

  Map<String, String> realSources() {
    final out = <String, String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        out[f.path.replaceAll(r'\', '/')] = f.readAsStringSync();
      }
    }
    return out;
  }

  final realRules = File('../firestore.rules').readAsStringSync();

  group('N07: wiring the team feed requires a server-side rule', () {
    test('today it is dormant, so the conditional does not fire', () {
      expect(violation(realSources(), realRules), isNull);
    });

    test('the dormancy is real, not an artefact of how the scan is written',
        () {
      // The control. If the provider were renamed or the file moved, `wiredIn`
      // would return false for a reason that has nothing to do with dormancy,
      // and the test above would pass while protecting nothing.
      final decl = File('lib/features/community/state/team_feed_providers.dart')
          .readAsStringSync();
      expect(decl, contains('final $provider'));
      expect(decl, contains('MockTeamFeedRepository()'),
          reason: 'the default is no longer the mock, which is itself the '
              'activation event this file exists to catch');
      expect(wiredIn(realSources()), isFalse);
    });

    test('the rules file really does authorise no team collection', () {
      // The other half of the control. If this ever passes, the conditional
      // above becomes satisfiable for the wrong reason.
      expect(rulesAuthoriseATeamCollection(realRules), isFalse,
          reason: 'firestore.rules gained a team collection. That is good, but '
              'the activation gate has six other requirements and this test '
              'checks only one of them.');
    });

    test('wiring it with no rule is refused', () {
      final wired = {
        'lib/main.dart': '''
          final container = ProviderContainer(overrides: [
            $provider.overrideWithValue(FirestoreTeamFeedRepository()),
          ]);
        ''',
      };
      expect(violation(wired, realRules), isNotNull);
      expect(violation(wired, realRules), contains('client-side and partial'));
    });

    test('wiring it WITH a rule is allowed', () {
      // Without this case the guard would be indistinguishable from one that
      // refuses every wired tree, and the activation gate would be
      // unsatisfiable rather than demanding.
      final wired = {
        'lib/main.dart':
            '$provider.overrideWithValue(FirestoreTeamFeedRepository()),',
      };
      const rules = '''
        match /teams/{teamId}/posts/{postId} {
          allow read: if request.auth != null
            && exists(/databases/\$(database)/documents/teams/\$(teamId)/members/\$(request.auth.uid));
        }
      ''';
      expect(violation(wired, rules), isNull);
    });

    test('a commented-out override is not an activation', () {
      final commented = {
        'lib/main.dart': '// $provider.overrideWithValue(Real()),',
      };
      expect(violation(commented, realRules), isNull);
    });

    test('naming the provider without overriding it is not an activation', () {
      // A reader, a test double, or prose. Only a composition-root override
      // binds a real backend.
      final reader = {
        'lib/features/community/team_feed_page.dart':
            'final repo = ref.read($provider);',
      };
      expect(violation(reader, realRules), isNull);
    });

    test('the activation gate document exists and is reachable from here', () {
      // The refusal message points at it. A refusal that names a missing file
      // is a refusal nobody can act on.
      final gate = File('../core/review/N07_TEAM_ACTIVATION_GATE.md');
      expect(gate.existsSync(), isTrue);
      final text = gate.readAsStringSync();
      for (final required in [
        'server-side membership',
        'server-side tier',
        'firestore.rules',
        'cross-user',
        'deep link',
      ]) {
        expect(text.toLowerCase(), contains(required.toLowerCase()));
      }
    });
  });
}
