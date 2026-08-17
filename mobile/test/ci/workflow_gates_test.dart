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

  group('F008: the branch the work happens on is covered', () {
    for (final name in const ['flutter.yml', 'functions.yml']) {
      test('$name runs on a push to any branch', () {
        final src = workflow(name).readAsStringSync();
        expect(src, contains("branches: ['**']"),
            reason: 'a working branch got no push-triggered run at all, so a '
                'regression sat until someone opened a pull request');
        expect(src, isNot(contains('branches: [master, main]')));
        expect(src, isNot(contains('branches: [master]')));
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
      final src = workflow('flutter.yml').readAsStringSync();
      expect(src, contains('flutter analyze'));
      expect(src, contains('flutter test'));
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

  /// The YAML with comment lines removed.
  ///
  /// Not fastidiousness: these workflows carry more explanation than
  /// configuration, and every trigger name below also appears in prose
  /// nearby. A raw `contains` matches the commented-out form just as happily
  /// as the live one — which is exactly how a disabled nightly would keep a
  /// test green. Found by mutating this file rather than by foresight.
  String live(String name) => workflow(name)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('#'))
      .join('\n');

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
    expect(workflow('functions.yml').readAsStringSync(), contains('rules'));
  });
}
