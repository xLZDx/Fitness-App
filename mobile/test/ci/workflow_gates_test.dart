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

    test('the job that runs the suite checks out enough history to verify '
        'provenance', () {
      // R-05. `test/ml/model_registry_test.dart` asks git whether a manifest's
      // recorded `source_commit` names a commit that exists. Under the default
      // shallow checkout it never can — one commit is present — so that check
      // would fail on every CI run for a reason unrelated to what it tests,
      // and the cheapest repair would be to weaken it back to the regex that
      // proved nothing.
      //
      // So the depth is load-bearing, and this is the assertion that says so.
      // Matched against the live YAML, because a `fetch-depth: 0` sitting in a
      // comment is exactly the state this exists to catch.
      final lines = live('flutter.yml').split('\n');
      final analyzeAndTest = lines.indexWhere((l) => l.contains('analyze-and-test:'));
      expect(analyzeAndTest, greaterThanOrEqualTo(0),
          reason: 'the job was renamed; this guard now points at nothing');
      // The first checkout after that job's declaration is the one it uses.
      final checkout = lines.indexWhere(
          (l) => l.contains('actions/checkout@'), analyzeAndTest);
      expect(checkout, greaterThan(analyzeAndTest));
      final block = lines.skip(checkout).take(12).join('\n');
      expect(block, contains('fetch-depth: 0'),
          reason: 'the suite-running job checks out shallowly, so the model '
              'registry cannot verify that a recorded training commit exists. '
              'A provenance check that cannot resolve its pointer is the '
              'ML-F1 shape: a record that reads as verified because something '
              'looked at it');
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

  group('CI-F2: the release build is actually exercised by CI (backlog row 22)', () {
    // Before this gate, no job anywhere invoked the real release path --
    // analyze-and-test only ever calls `flutter test`. A regression in
    // Gradle assembleRelease/bundleRelease, R8/resource processing, or
    // native library packaging was invisible to every job in the file. This
    // group pins that the job exists, uses the project's OWN canonical
    // build path (not a second, independently-drifting `flutter build`
    // invocation), builds both artifact forms, never auto-distributes, and
    // still gates on a live (non-`continue-on-error`) size check -- so a
    // later cleanup pass cannot quietly reopen row 22 while every other test
    // in this suite stays green.
    test('release-build job exists', () {
      expect(live('flutter.yml'), contains('release-build:'),
          reason: 'the job was renamed or removed; every guard below points '
              'at nothing');
    });

    test('it uses the canonical build_release.ps1 wrapper, not a bare '
        'flutter build', () {
      final lines = live('flutter.yml').split('\n');
      final jobStart = lines.indexWhere((l) => l.contains('release-build:'));
      expect(jobStart, greaterThanOrEqualTo(0));
      final nextJob = lines.indexWhere(
          (l) => RegExp(r'^  [a-zA-Z0-9_-]+:\s*$').hasMatch(l), jobStart + 1);
      final block =
          lines.sublist(jobStart, nextJob == -1 ? lines.length : nextJob)
              .join('\n');
      // The wrapper is what derives GIT_SHA/BUILT_AT/the monotonic build
      // number (see scripts/dev/build_release.ps1's own header) -- a bare
      // `flutter build apk --release` in this job would silently drop all
      // three and build an artifact this project does not otherwise produce
      // anywhere, local or CI.
      expect(block, contains('build_release.ps1'),
          reason: 'the release job must call the same script the operator '
              'uses locally, or CI is proving a different build path exists '
              'to drift from');
      // Every invocation of the script in this job, and what it may pass.
      //
      // A bare `isNot(contains('-Distribute'))` substring check is
      // defeatable: build_release.ps1's only `-D...` parameter is
      // `-Distribute`, and PowerShell binds an unambiguous flag prefix (-D,
      // -Dis, -Dist, ...) to it just as readily as the full spelling -- a
      // future edit that abbreviates the flag (or copy-pastes a local dev
      // command) would silently start auto-publishing every CI build to
      // testers while this substring check stayed green (code-reviewer
      // finding, verified against the param block in build_release.ps1).
      // Allowlist every token on each invocation line instead: only a bare
      // call or one ending in exactly `-Bundle` is permitted.
      // `[ \t]`, not `\s`, as the flag separator: `\s` also matches
      // newlines, so a greedy `(\s+\S+)*` would happily jump the gap across
      // a blank line and swallow the START of the NEXT step as if it were a
      // flag on this invocation -- caught by actually running this test
      // rather than trusting the regex by inspection.
      final invocations = RegExp(r'build_release\.ps1([ \t]+\S+)*[ \t]*$',
              multiLine: true)
          .allMatches(block)
          .map((m) => m.group(0)!.trim())
          .toList();
      expect(invocations, isNotEmpty,
          reason: 'no build_release.ps1 invocation line matched at all -- '
              'the regex itself may have drifted from the YAML shape');
      for (final line in invocations) {
        final flags = line
            .replaceFirst(RegExp(r'^.*build_release\.ps1'), '')
            .trim();
        expect(flags, anyOf(isEmpty, equals('-Bundle')),
            reason: 'unexpected flag(s) "$flags" on a CI release-build '
                'invocation -- only a bare call or exactly "-Bundle" is '
                'allowed; anything else (including any abbreviation of '
                '-Distribute) must not silently pass: $line');
      }
      // Both artifact forms: the default (split APK) and -Bundle (AAB).
      final bundleCalls =
          invocations.where((l) => l.endsWith('-Bundle')).length;
      expect(bundleCalls, greaterThanOrEqualTo(1),
          reason: 'only the split-APK form is exercised; the AAB path (the '
              'one the Play console actually accepts) is unverified');
      final defaultCalls =
          invocations.where((l) => l.endsWith('build_release.ps1')).length;
      expect(defaultCalls, greaterThanOrEqualTo(1),
          reason: 'only the -Bundle form is exercised; the default split-APK '
              'form (what testers actually install) is unverified');
    });

    test('it checks out full history, same as analyze-and-test', () {
      final lines = live('flutter.yml').split('\n');
      final jobStart = lines.indexWhere((l) => l.contains('release-build:'));
      final checkout = lines.indexWhere(
          (l) => l.contains('actions/checkout@'), jobStart);
      final block = lines.skip(checkout).take(6).join('\n');
      expect(block, contains('fetch-depth: 0'),
          reason: 'build_release.ps1 derives the build number from '
              '`git rev-list --count HEAD` and refuses to run under a '
              'shallow clone; a shallow checkout here fails the whole job, '
              'not silently -- but is still worth pinning so the reason is '
              'legible from the test alone');
    });

    test('the size-floor check pins the actual gate, not just its '
        'vocabulary', () {
      // GPT-PM round-2 finding: checking for the strings `apk_floor=`,
      // `aab_floor=`, `set -euo pipefail` proves the WORDS are present, not
      // that the gate still does anything -- a later edit could set both
      // floors to 0 or delete the size comparison/`exit 1` entirely and
      // every one of those three `contains` checks would still pass. Scope
      // to the release-build job block specifically (not the whole file,
      // where `set -euo pipefail` or a stray `exit 1` could appear in an
      // unrelated step) and pin the actual pre-registered numeric floors
      // plus the comparison and failure path that make them mean anything.
      final lines = live('flutter.yml').split('\n');
      final jobStart = lines.indexWhere((l) => l.contains('release-build:'));
      expect(jobStart, greaterThanOrEqualTo(0));
      final nextJob = lines.indexWhere(
          (l) => RegExp(r'^  [a-zA-Z0-9_-]+:\s*$').hasMatch(l), jobStart + 1);
      final block =
          lines.sublist(jobStart, nextJob == -1 ? lines.length : nextJob)
              .join('\n');

      // Exact pre-registered floors (2026-09-16 measurement: 108.9 MB split
      // APK / 130.5 MB AAB on this exact HEAD) -- a change to these values
      // is a real, visible decision that should touch this test too, not a
      // silent `apk_floor=0` slipping past a substring check.
      expect(block, contains('apk_floor=\$((50 * 1024 * 1024))'),
          reason: 'the APK size floor changed or was zeroed out -- if this '
              'is a deliberate re-measurement, update this pin alongside it, '
              'not around it');
      expect(block, contains('aab_floor=\$((60 * 1024 * 1024))'),
          reason: 'the AAB size floor changed or was zeroed out -- same as '
              'the APK floor above');
      // The comparison that actually uses the floor, and the failure path
      // it takes when violated -- not just that the word "floor" appears
      // somewhere near an unrelated `exit 1`.
      expect(block, contains('"\$size" -lt "\$floor"'),
          reason: 'the numeric comparison against the pre-registered floor '
              'is gone -- the floors above would be dead configuration, '
              'checked for existence but never actually compared against '
              'anything');
      final sizeCheckBlock = block.substring(
          block.indexOf('-lt "\$floor"'),
          block.indexOf('-lt "\$floor"') + 200 < block.length
              ? block.indexOf('-lt "\$floor"') + 200
              : block.length);
      expect(sizeCheckBlock, contains('exit 1'),
          reason: 'the size comparison no longer fails the step on '
              'violation -- a near-empty artifact would print an error and '
              'the job would still report success');
      // `exit 1` on its own already fails the step regardless of `set -e`
      // (it is an unconditional shell builtin, not a command whose own
      // non-zero status needs `-e` to propagate) -- so this is a genuinely
      // separate protection, not a restatement of the check above: `-euo
      // pipefail` is what stops an UNCHECKED failure elsewhere in the same
      // script (e.g. `stat -c%s` erroring on a path with an unexpected
      // shape, or a broken pipe) from being silently ignored and leaving
      // `$size` empty/wrong for the comparison that follows it.
      expect(block, contains('set -euo pipefail'),
          reason: 'without this, an unrelated failure earlier in the same '
              'script (not the explicit size check) could be silently '
              'swallowed instead of failing the step');
    });

    test('the APK is uploaded as a workflow artifact', () {
      final src = live('flutter.yml');
      expect(src, contains('actions/upload-artifact@'));
      expect(src, contains('release-apk-arm64'));
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
