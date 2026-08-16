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

  test('the Firestore rules tests are part of a workflow', () {
    // G-D is proven by the emulator suite in `functions/`. If that job stops
    // running, the gate stops being enforced anywhere but in a decision-log
    // entry.
    expect(workflow('functions.yml').readAsStringSync(), contains('rules'));
  });
}
