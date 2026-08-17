import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What CI is actually allowed to let through.
///
/// F007 and F008 are both claims about the workflow files, and neither could
/// be checked by anything in the repository — so a change to a trigger or a
/// flag silently changed what the branch is protected by. The workflows are
/// data; this reads them.
///
/// Deliberately string assertions over the YAML rather than a parsed model:
/// the properties worth pinning are single lines, and a YAML dependency for
/// four checks would be the larger change.
void main() {
  File workflow(String name) {
    // The suite runs with `mobile/` as its working directory; the workflows
    // sit at the repository root above it.
    final f = File('../.github/workflows/$name');
    expect(f.existsSync(), isTrue, reason: 'missing workflow: ${f.path}');
    return f;
  }

  /// The YAML with comment lines removed.
  ///
  /// Not fastidiousness: these workflows carry more explanation than
  /// configuration, and every trigger name below also appears in prose
  /// nearby. A raw `contains` matches the commented-out form just as happily
  /// as the live one — which is exactly how a disabled nightly would keep a
  /// test green. Found by mutating this file rather than by foresight.
  ///
  /// Declared here rather than halfway down: the groups above it were still
  /// reading the raw source, and the reason was proximity rather than intent.
  String live(String name) => workflow(name)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

  group('F008: the branch the work happens on is covered', () {
    for (final name in const ['flutter.yml', 'functions.yml']) {
      test('$name runs on a push to any branch', () {
        // `live`, not the raw source. This group used the raw source while the
        // group below it had already been fixed to strip comments -- so
        // commenting out the wildcard and adding `branches: [main]` beside it
        // left this green, which is the same defect one file over.
        final src = live(name);
        expect(src, contains("branches: ['**']"),
            reason: 'a working branch got no push-triggered run at all, so a '
                'regression sat until someone opened a pull request');
        // And no OTHER branch filter, whatever it names. The previous version
        // listed two literal spellings to reject, so `branches: [main]` -- the
        // most likely regression of all -- passed both guards.
        final filters = src
            .split('\n')
            .where((l) => l.contains('branches:'))
            .where((l) => !l.contains("['**']"))
            .toList();
        expect(filters, isEmpty,
            reason: 'a branch filter other than the wildcard narrows what CI '
                'sees: $filters');
      });
    }
  });

  group('F007: no step is allowed to fail quietly', () {
    for (final name in const ['flutter.yml', 'functions.yml']) {
      test('$name has no continue-on-error', () {
        final src = workflow(name).readAsStringSync();
        // A commented mention is the `functions.yml` header explaining the
        // rule, so match the YAML key rather than the word.
        final live = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('#'))
            .where((l) => l.contains('continue-on-error'))
            .toList();
        expect(live, isEmpty,
            reason: 'a step that is allowed to fail is a step that reports '
                'nothing: $live');
      });
    }

    test('flutter.yml still runs analyze and the whole test suite', () {
      final src = live('flutter.yml');
      expect(src, contains('flutter analyze'));
      // `flutter test --no-pub`, not `flutter test`. The bare form is also how
      // the integration job invokes ONE file -- `flutter test
      // integration_test/app_test.dart` -- so deleting the whole-suite step
      // left this assertion satisfied by a job that runs a single test and is
      // itself skipped on push. It claimed to check the suite and checked
      // nothing.
      expect(src, contains('flutter test --no-pub'),
          reason: 'the step that runs the entire suite is gone; a bare '
              '"flutter test" match is satisfied by the integration job');
    });

    test('the analyze flags suppress warnings only, never errors', () {
      // F007 was recorded as "flutter analyze cannot fail CI". Measured, that
      // is not so: `--no-fatal-warnings --no-fatal-infos` still exits 1 on a
      // genuine error, which was verified directly by analysing a file with a
      // return-type error and reading the exit code.
      //
      // What this pins is the narrower true statement — that the suppression
      // stays limited to warnings and infos. `--no-fatal-errors` would be the
      // flag that makes the finding's claim true, and it must not appear.
      final src = workflow('flutter.yml').readAsStringSync();
      expect(src, isNot(contains('--no-fatal-errors')));
    });
  });

  group('CI-F1: the check that can go stale on its own runs on its own', () {
    // A dependency audit is the only job in this repository whose verdict
    // changes with no commit behind it. Running it only on push means the one
    // check designed to report what happened while nobody was looking is the
    // one check that needs somebody to be looking.
    for (final name in const ['flutter.yml', 'functions.yml']) {
      test('$name has a nightly schedule', () {
        final src = live(name);
        expect(src, contains('schedule:'),
            reason: 'a workflow with no schedule can only ever tell you about '
                'your own commits');
        expect(src, contains('cron:'));
      });

      test('$name can be started by hand', () {
        // When an advisory lands, the alternative to this is pushing an empty
        // commit to ask a question.
        expect(live(name), contains('workflow_dispatch'));
      });
    }

    test('the audit job is still in the workflow the schedule triggers', () {
      // The schedule above is worth exactly the jobs it reaches. If `audit`
      // moves to another file, the cron stays green while auditing nothing.
      final src = live('functions.yml');
      expect(src, contains('npm audit'));
      expect(src, contains('--audit-level=high'));
      expect(src, contains('--package-lock-only'),
          reason: 'without it npm audits the INSTALLED tree, which still '
              'contains the dev packages --omit=dev was meant to exclude');
    });
  });

  test('the Firestore rules tests are part of a workflow', () {
    // G-D is proven by the emulator suite in `functions/`. If that job stops
    // running, the gate stops being enforced anywhere but in a decision-log
    // entry.
    //
    // This asserted `contains('rules')` against the whole file, comments
    // included. The word appears five times in prose -- the header comment
    // alone says "the Firestore rules" -- so deleting the entire `rules:` job
    // left the test green. It could not fail. Match the command instead.
    expect(live('functions.yml'), contains('npm run test:rules'),
        reason: 'the emulator suite is the only thing that proves G-D against '
            'a real Firestore; a mention of the word "rules" in a comment is '
            'not evidence that it runs');
  });
}
