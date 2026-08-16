import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tripwires over code that is currently harmless BECAUSE nothing reads it.
///
/// Two findings in this audit have the same shape: the defect is real, the
/// reachability is zero, and "fix it" would mean either repairing an artefact
/// nobody uses or deleting work somebody intended. Neither is honest on its
/// own. What is honest is to make the moment of reachability loud, so the
/// question gets asked when it starts to matter rather than after it has
/// shipped.
///
/// These are source scans, and source scans are weak evidence for behaviour.
/// They are not being used as behaviour proofs here — they assert
/// REACHABILITY, which is exactly the thing a source scan can see and a
/// behavioural test cannot, because there is no behaviour yet.
void main() {
  Iterable<File> dartSources(String root) sync* {
    for (final f in Directory(root).listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) yield f;
    }
  }

  group('F025: the celebrity plans carry nine ids that resolve to nothing', () {
    // `MockCelebrityPlanRepository` seeds two sample plans whose
    // `dailyWorkouts` name exercises as 'squat', 'plank', 'birddog' and so on.
    // The shipped catalogue uses vendor ids (`ea_*`), so not one of them
    // resolves. Both plans are marked `isSample: true`.
    //
    // Currently harmless: `dailyWorkouts` has NO reader in `lib/`. Repairing
    // the ids now would be repairing an artefact nobody can reach, which is
    // closure-count work rather than safety work.
    //
    // What makes it worth a tripwire is what a first reader would most
    // naturally do: render the day's exercises. That path would hand a user a
    // list built from a hand-written map, bypassing the eligibility layer that
    // every other exercise surface goes through — the F020 shape exactly.
    test('nothing reads dailyWorkouts, so the dangling ids stay unreachable',
        () {
      final readers = <String>[];
      for (final f in dartSources('lib')) {
        final path = f.path.replaceAll(r'\', '/');
        if (path.endsWith('celebrity_plan.dart') ||
            path.endsWith('celebrity_plan_repository.dart')) {
          continue; // the declaration and its seed data
        }
        if (f.readAsStringSync().contains('dailyWorkouts')) {
          readers.add(path);
        }
      }
      expect(readers, isEmpty,
          reason: 'a reader appeared for dailyWorkouts. Before it ships, two '
              'things have to happen: the nine ids must be canonicalised '
              'against the real catalogue, and the rendered list must go '
              'through eligibleExercises like every other exercise surface. '
              'Readers found: $readers');
    });

    test('the ids really are dangling, so the tripwire is about something', () {
      // Without this the test above could pass forever over a field whose ids
      // were fine all along, and nobody would know which.
      final seed = File(
        'lib/features/celebrity_plans/data/celebrity_plan_repository.dart',
      ).readAsStringSync();
      for (final id in const [
        'squat',
        'bench_press',
        'plank',
        'deadlift',
        'row_barbell',
        'overhead_press',
        'glute_bridge',
        'birddog',
        'kb_deadlift',
      ]) {
        expect(seed, contains("'$id'"),
            reason: 'the seed changed; re-measure before trusting this row');
      }
      // The shipped catalogue's ids are vendor-prefixed. A bare word is not
      // one of them.
      final catalogue =
          File('assets/data/exercises_vendor.json').readAsStringSync();
      expect(catalogue, contains('"ea_'),
          reason: 'catalogue id shape changed; the claim below depends on it');
      expect(catalogue, isNot(contains('"id": "squat"')));
      expect(catalogue, isNot(contains('"id": "plank"')));
    });
  });

  group('N08: one safety authority, not several', () {
    // `safety_providers.dart` held `safetyVerdictProvider` and
    // `draftSafetyVerdictProvider`. Both answered "is this person screened?"
    // and both returned the `SafetyVerdict` ALONE — the screening half,
    // without the injuries, flags and equipment every caller also needs.
    // Neither had a consumer, and both were deleted rather than wired up: the
    // saved-profile question is `safetyContextProvider`'s and the draft
    // question is `safetyContextFor`'s, each carrying strictly more.
    //
    // The risk was never that they returned a wrong answer. It was that they
    // sat there looking authoritative, so a future surface could screen a user
    // with the verdict and no injuries and believe it had asked.
    test('the superseded verdict providers have not come back', () {
      // Comment lines are skipped, and that is not a loophole: the deletion is
      // EXPLAINED in `eligibility_providers.dart`, by name, which is where a
      // reader looking for the missing provider will land. A scan that could
      // not tell an explanation from a use would force the explanation to be
      // deleted too, and then nobody would know why the file is one provider
      // shorter. A real usage is never on a comment line.
      final offenders = <String>[];
      for (final f in dartSources('lib')) {
        final live = f
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (live.contains('safetyVerdictProvider') ||
            live.contains('draftSafetyVerdictProvider')) {
          offenders.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(offenders, isEmpty,
          reason: 'a second safety authority reappeared. If a surface needs '
              'the verdict alone, take it from SafetyContext.screening rather '
              'than adding a provider that answers with less: $offenders');
    });

    test('the authority everything else uses is still there', () {
      // The control. A scan for absence passes just as happily when the thing
      // it was protecting has itself been deleted.
      final src = File('lib/features/safety/state/eligibility_providers.dart')
          .readAsStringSync();
      expect(src, contains('final safetyContextProvider'));
      expect(src, contains('SafetyContext safetyContextFor('));
    });
  });
}
