import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fence that makes `core/ml/MODEL_REGISTRY.json` load-bearing.
///
/// ## Why a registry needs a test at all
///
/// ML-F1 was not a coding error. It was a document saying one model shipped
/// while a different one actually did, for months, with nobody able to notice
/// — because no artefact in the repository could be checked against reality.
/// A registry that nothing verifies is the same document with better
/// formatting, and would fail in exactly the same way.
///
/// So this asserts the registry against the tree it describes: the bundled
/// artefact exists, its bytes hash to the recorded digest, the code loads the
/// path the registry says is bundled, and no model claims to be bundled that
/// is not. Deployment truth cannot drift from recorded truth without this
/// going red.
///
/// ## What it deliberately does NOT assert
///
/// Nothing about whether a model is any good. Accuracy is an evaluation
/// question and lives in the registry's `evaluations`; the fence's job is
/// provenance and deployment, which are the two things that were wrong.
void main() {
  final registryFile = File('../core/ml/MODEL_REGISTRY.json');

  late Map<String, dynamic> registry;
  late List<Map<String, dynamic>> models;

  setUpAll(() {
    expect(registryFile.existsSync(), isTrue,
        reason: 'the model registry is missing: ${registryFile.path}');
    registry = jsonDecode(registryFile.readAsStringSync()) as Map<String, dynamic>;
    models = [
      for (final m in registry['models'] as List) m as Map<String, dynamic>,
    ];
  });

  /// Repository-root-relative path resolved from `mobile/`, where tests run.
  File repoFile(String path) => File('../$path');

  /// The one entry with this identity, or a failure naming what was found.
  ///
  /// R-04. These lookups used to be `firstWhere((m) => m['bundled'] != true)`,
  /// which selects by POSITION among the entries that happen to satisfy a
  /// predicate. That was correct while the registry held exactly two entries
  /// and the second was equipment v2. It stopped being correct the moment a
  /// third model was registered: `content_qa@baseline-v1` is also not bundled,
  /// so reordering the file — a formatting change, an alphabetical sort, an
  /// append in the other order — silently repoints the fence at a different
  /// model. It would not have failed; it would have policed the wrong figures
  /// and stayed green, which is worse than not existing.
  ///
  /// `model_id` + `model_version` is the registry's own identity, and
  /// [hasLength] rather than `first` means an ambiguous registry is a failure
  /// instead of a coin toss.
  Map<String, dynamic> entry(String id, String version) {
    final hits = models
        .where((m) => m['model_id'] == id && m['model_version'] == version)
        .toList();
    expect(hits, hasLength(1),
        reason: 'expected exactly one $id@$version in the registry, found '
            '${hits.length}. Registered: '
            '${models.map((m) => '${m['model_id']}@${m['model_version']}').join(', ')}');
    return hits.single;
  }

  group('the registry describes a real tree', () {
    /// R-06 — where the artefact lives, declared rather than guessed.
    ///
    /// The existence and digest checks below used to run over
    /// `bundled == true` and nothing else. That left the two entries that are
    /// not bundled entirely unchecked, including one whose artefact IS in the
    /// repository and is readable right now: `content_qa@baseline-v1` points
    /// at `scripts/ct1/baseline.py`, the deterministic champion of its task.
    /// The registry could have named a path that does not exist and no test
    /// would have said so.
    ///
    /// The obvious repair — "every entry must have an artefact on disk" — is
    /// wrong, and would have been wrong the moment it was written. `v2` lives
    /// at `D:/tools/equipment-model/out_v2/`, off this machine's repository
    /// and off every other machine; a retired model's blob is legitimately
    /// deleted. A rule that demands a local file forever turns an accurate
    /// historical record into a test failure, and the way that gets resolved
    /// is by deleting the history.
    ///
    /// So the registry declares it, per entry, and the fence checks what the
    /// declaration implies. `artifact_in_repository` already existed on the
    /// entries that needed it; this makes it required and load-bearing.
    test('every model says whether its artefact is in this repository', () {
      expect(models, isNotEmpty);
      for (final m in models) {
        expect(m['artifact_in_repository'], isA<bool>(),
            reason: '${m['model_id']}@${m['model_version']} does not say where '
                'its artefact lives, so nothing can be checked about it. This '
                'is a required field: "we did not say" is how an entry ends up '
                'describing a file nobody has');
      }
    });

    test('an in-repository artefact is actually there', () {
      final inRepo =
          models.where((m) => m['artifact_in_repository'] == true).toList();
      expect(inRepo, isNotEmpty,
          reason: 'no entry claims a local artefact, so this test polices '
              'nothing');
      for (final m in inRepo) {
        final path = m['artifact_path'] as String;
        // The flag and the path have to agree. Flipping the flag to true and
        // leaving an absolute path behind would satisfy every check below by
        // accident of `repoFile` resolving somewhere unexpected.
        expect(RegExp(r'^([a-zA-Z]:|/|\\)').hasMatch(path), isFalse,
            reason: '${m['model_id']}@${m['model_version']} claims its '
                'artefact is in this repository and gives the absolute path '
                '$path. A repository path is relative to the repository');
        expect(repoFile(path).existsSync(), isTrue,
            reason: '${m['model_id']}@${m['model_version']} claims '
                'artifact_in_repository=true but $path is not there. Either '
                'the artefact was removed — in which case say so by setting '
                'the flag false, which is a legitimate state for a retired or '
                'externally built model — or the registry is describing a '
                'deployment that does not exist');
      }
    });

    test('an artefact outside the repository is not required to be here, and '
        'may not ship', () {
      // The explicit half of the rule, so that "not checked" is a recorded
      // decision rather than a gap. What an external artefact still may not do
      // is claim to be in the build users install.
      for (final m in models.where((m) => m['artifact_in_repository'] == false)) {
        expect(m['bundled'], isNot(isTrue),
            reason: '${m['model_id']}@${m['model_version']} is bundled into '
                'the app and its artefact is not in the repository. One of the '
                'two is false; nothing can ship from a path that only exists '
                'on one machine');
      }
    });

    test('a recorded digest matches the bytes it describes', () {
      // The assertion ML-F1 would have failed. A hash is what makes "which
      // model is this" answerable without trusting a filename -- v1 and v2
      // are both called `equipment_v*.tflite` and are within 1.5% of each
      // other in size.
      //
      // Widened past `bundled` for R-06: the claim being checked is "these
      // bytes are those bytes", and it is checkable for any local artefact
      // that records a digest. A null digest is a legitimate state and is
      // handled by the test below rather than by silently skipping here.
      var checked = 0;
      for (final m in models.where((m) => m['artifact_in_repository'] == true)) {
        if (m['artifact_sha256'] == null) continue;
        final f = repoFile(m['artifact_path'] as String);
        final digest = sha256.convert(f.readAsBytesSync()).toString();
        expect(digest, m['artifact_sha256'],
            reason: '${m['artifact_path']} does not hash to the registry\'s '
                'recorded digest. A model artefact was replaced without the '
                'registry being updated, which is precisely the state ML-F1 '
                'described');
        expect(f.lengthSync(), m['artifact_bytes'], reason: m['artifact_path']);
        checked++;
      }
      expect(checked, greaterThan(0),
          reason: 'no local artefact records a digest, so this test verified '
              'nothing at all');
    });

    test('what ships is pinned by a digest', () {
      // Narrower than the test above and the reason it exists separately: a
      // null digest is defensible for a versioned source file (CT-1's baseline
      // says so in `$artifact_note`, and its identity is pinned by the dataset
      // manifest's commit instead). It is not defensible for a binary in the
      // APK, which is the exact artefact ML-F1 was wrong about.
      final bundled = models.where((m) => m['bundled'] == true).toList();
      expect(bundled, isNotEmpty);
      for (final m in bundled) {
        expect(m['artifact_in_repository'], isTrue, reason: 'unshippable');
        expect(m['artifact_sha256'], isNotNull,
            reason: '${m['model_id']}@${m['model_version']} ships without a '
                'recorded digest, so "which model is in this build" is '
                'answerable only by trusting the filename');
        expect(m['artifact_bytes'], isNotNull);
      }
    });

    test('exactly one equipment model is bundled, and it is the champion', () {
      final bundled = models
          .where((m) => m['model_id'] == 'equipment_recognition')
          .where((m) => m['bundled'] == true)
          .toList();
      expect(bundled, hasLength(1),
          reason: 'two bundled equipment models is the ambiguity this file '
              'exists to prevent');
      expect(bundled.single['champion'], isTrue,
          reason: 'the bundled model is by definition the one serving users');
      expect(bundled.single['model_version'], 'v1',
          reason: 'if this changes, D3 has been reopened and there must be a '
              'new promotion decision recorded to go with it');
    });

    test('a model that is not shipped does not claim to be', () {
      for (final m in models.where((m) => m['bundled'] != true)) {
        expect(m['deployment_status'], isNot('BUNDLED'), reason: '${m['model_version']}');
      }
    });

    test('an on-device champion is in the APK, or it serves nobody', () {
      // This used to read "not bundled implies not champion", which conflated
      // two different things and was only correct while every registered model
      // ran on the phone. CT-1's champion is a rule set that runs offline and
      // is nobody's APK asset; under the old rule it could not have been
      // recorded as champion at all, which would have made the registry
      // silent about the thing actually in charge of content QA.
      //
      // The guarantee that mattered is kept exactly: a model users' devices
      // execute cannot be champion unless it is in the build they have.
      for (final m in models.where((m) => m['deployment_surface'] == 'ON_DEVICE')) {
        if (m['champion'] != true) continue;
        expect(m['bundled'], isTrue,
            reason: '${m['model_version']} is the on-device champion and is '
                'not in the APK');
      }
    });

    test('every model declares where it runs', () {
      // Otherwise the rule above silently exempts anything that forgets the
      // field, which is the failure mode of every allowlist.
      const surfaces = {'ON_DEVICE', 'OFFLINE_ADVISORY'};
      for (final m in models) {
        expect(surfaces, contains(m['deployment_surface']),
            reason: '${m['model_id']}@${m['model_version']}');
      }
    });
  });

  group('the code loads what the registry says it loads', () {
    /// Every `.tflite` path that appears in a Dart source file under `lib/`.
    Set<String> modelPathsInCode() {
      final found = <String>{};
      // Both quote styles. The single-quoted form was the only one matched,
      // and nothing in this project forces single quotes -- `prefer_single_
      // quotes` is commented out in analysis_options.yaml and flutter_lints
      // does not include it. So `"assets/models/equipment_v2.tflite"` was
      // legal, unflagged Dart that shipped a second model with the registry
      // never told, which is precisely the drift this scanner exists to catch.
      //
      // Fourth instance in this programme of a scanner blind to a quoting or
      // commenting variant. The lesson has stopped being about quotes: a
      // matcher written against one spelling of a thing is evidence about that
      // spelling, not about the thing.
      final pattern =
          RegExp(r'''(?:'|")(assets/models/[A-Za-z0-9_.\-]+\.tflite)(?:'|")''');
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in pattern.allMatches(f.readAsStringSync())) {
          found.add(m.group(1)!);
        }
      }
      return found;
    }

    test('no source file loads an artefact the registry does not know', () {
      // The other direction of drift, and the one a hash check cannot see: a
      // new model added to assets and referenced in code, with the registry
      // never told. It would ship, and the registry would go on describing the
      // old world quite happily.
      final registered = {
        for (final m in models)
          if (m['artifact_in_repository'] != false)
            (m['artifact_path'] as String).replaceFirst('mobile/', ''),
      };
      final unregistered = modelPathsInCode().difference(registered);
      expect(unregistered, isEmpty,
          reason: 'these model artefacts are loaded by the app and are absent '
              'from core/ml/MODEL_REGISTRY.json. Every deployed model needs an '
              'entry, including its provenance and whether it can abstain: '
              '$unregistered');
    });

    test('the registry\'s bundled path is the one the code actually names', () {
      // EVERY bundled entry, not the first one. A registry that grows a second
      // shipped model must not leave the new one unchecked, and there is no
      // reason to pick one out by identity here — the claim is about all of
      // them.
      final bundled = models.where((m) => m['bundled'] == true);
      expect(bundled, isNotEmpty,
          reason: 'no model claims to be bundled, so this test proves nothing');
      for (final m in bundled) {
        final assetPath =
            (m['artifact_path'] as String).replaceFirst('mobile/', '');
        expect(modelPathsInCode(), contains(assetPath),
            reason: 'the registry says $assetPath is bundled but no Dart source '
                'loads it. This is the ML-F1 shape exactly, in the other '
                'direction: a documented deployment nothing performs');
      }
    });

    test('the asset is declared in pubspec, or it never reaches a device', () {
      // A file in `assets/` that pubspec does not declare is not in the APK.
      // The registry would be accurate about the repository and wrong about
      // the product.
      // Comments stripped: `assets/models/` occurs exactly once in pubspec, so
      // commenting the line out dropped the model from the APK while leaving
      // this test green.
      final pubspec = File('pubspec.yaml')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('#'))
          .join('\n');
      expect(pubspec, contains('assets/models/'),
          reason: 'the model directory is not declared as an asset');
    });
  });

  group('the registry keeps promotion honest', () {
    test('no model is champion and challenger at once', () {
      for (final m in models) {
        expect(m['champion'] == true && m['challenger'] == true, isFalse,
            reason: '${m['model_id']}@${m['model_version']}');
      }
    });

    /// R-08 note, and it applies to every `models.where(...)` loop in this
    /// file. A filtered loop over an empty set passes, so the assertions below
    /// are only worth what the filter matches. Non-vacuity is asserted where
    /// an empty result would mean the registry has stopped saying something it
    /// must say, and NOT where empty is a legitimate state:
    ///
    ///   champion == true        -> asserted. A registry with nothing in
    ///                              charge of anything is not a state this
    ///                              project can be in; every registered task
    ///                              has a champion by construction.
    ///   bundled != true         -> NOT asserted. A registry whose every entry
    ///                              ships is unusual, not wrong.
    ///   deployment_surface ==
    ///     'ON_DEVICE'           -> NOT asserted. If the app ever stops
    ///                              shipping an on-device classifier, this set
    ///                              empties legitimately, and a guard here
    ///                              would fail for being right.
    ///   artifact_in_repository
    ///     == false              -> NOT asserted. Every artefact being local
    ///                              is the better world, not a defect.
    ///
    /// An assertion that empty is impossible where it is merely unusual buys
    /// nothing and costs a false failure later.
    test('a champion that is not the first of its kind has a rollback target',
        () {
      // A first champion legitimately has none — there is nothing behind it.
      // Anything that replaces it must name what it falls back to, because "we
      // promoted and cannot go back" is not a deployment, it is a hope.
      //
      // The exemption was `model_version == 'v1'`, which is a version string
      // and not a fact about the model — it would have exempted any future
      // task's v1 by coincidence of naming, and CT-1 arriving as a second task
      // is what made that visible. It is now a declared flag, and declaring it
      // still costs a written reason.
      final champions = models.where((m) => m['champion'] == true).toList();
      expect(champions, isNotEmpty,
          reason: 'the registry names no champion at all, so every rule below '
              'about what serves users is checking nothing');
      for (final m in champions) {
        if (m['first_of_its_kind'] == true) {
          expect(m['rollback_note'], isNotNull,
              reason: '${m['model_id']}@${m['model_version']} claims to be the '
                  'first of its kind and does not say why that is true');
          continue;
        }
        expect(m['rollback_target'], isNotNull,
            reason: '${m['model_id']}@${m['model_version']} is champion with '
                'no rollback target');
      }
    });

    test('lifecycle_state is one the registry declares', () {
      final allowed = (registry['lifecycle_states'] as List).cast<String>();
      for (final m in models) {
        expect(allowed, contains(m['lifecycle_state']),
            reason: '${m['model_version']}: ${m['lifecycle_state']}');
      }
    });

    test('nothing is CHAMPION without having been EVALUATED first', () {
      // The state machine's one non-negotiable ordering. A model cannot serve
      // users on the strength of having been trained.
      final champions = models.where((m) => m['champion'] == true).toList();
      expect(champions, isNotEmpty,
          reason: 'no champion is recorded, so the ordering this test pins is '
              'not being checked against anything');
      for (final m in champions) {
        expect(m['evaluations'], isNotEmpty,
            reason: '${m['model_version']} is champion with no evaluation '
                'recorded at all');
      }
    });

    test('missing provenance is stated, never invented', () {
      // The rule that keeps this file honest. `training_code_commit` is
      // genuinely unresolvable for both models -- the pipeline is not under
      // version control -- and writing a plausible sha would be worse than
      // useless. UNKNOWN is the accurate value and the useful one.
      const permitted = {'UNKNOWN', 'NOT_RECORDED', 'LEGACY',
                         'RECORDED_PER_BUILD'};
      for (final m in models) {
        for (final field in const [
          'training_code_commit',
          'training_dataset_version',
        ]) {
          final value = m[field] as String;
          final looksLikeSha = RegExp(r'^[0-9a-f]{7,40}$').hasMatch(value);
          expect(permitted.contains(value) || looksLikeSha, isTrue,
              reason: '${m['model_version']}.$field = "$value" is neither a '
                  'real commit nor an honest admission that there is not one');
        }
      }
    });

    /// `RECORDED_PER_BUILD` is a pointer, and a pointer that resolves to
    /// nothing is worse than `UNKNOWN` — it claims provenance exists.
    ///
    /// So it is permitted above only on the condition enforced here: the named
    /// evaluation report must exist and must carry a real commit. This is
    /// strictly stronger than what the legacy models are held to, which is the
    /// intent — CT-1 exists to start doing provenance properly, and a token
    /// that let it off would defeat the point.
    test('RECORDED_PER_BUILD resolves to a commit that exists', () {
      // R-05. This used to assert `^[0-9a-f]{7,40}$` and stop there, which
      // tests the SHAPE of the string and calls it provenance. `deadbeef` is
      // hex, seven-to-forty characters long, and names nothing at all — it
      // passed. So the guard certified a pointer it had never followed, which
      // is the ML-F1 failure in miniature: a record that reads as verified
      // because something checked it, where what was checked was not the
      // claim.
      //
      // The claim is "this artefact was built from a known revision of this
      // repository". The narrowest thing that actually establishes it is that
      // the revision RESOLVES — a commit object with that name is present
      // here. That is what git is asked, and nothing beyond it: the fence does
      // not require the commit to be an ancestor of HEAD, because a manifest
      // built on a branch that was later rebased still records where it came
      // from honestly, and demanding reachability would push the next person
      // to rewrite the manifest rather than keep it true.
      final pointers = models
          .where((m) => m['training_code_commit'] == 'RECORDED_PER_BUILD')
          .toList();
      expect(pointers, isNotEmpty,
          reason: 'no model uses the token, so this test polices nothing. If '
              'the token was retired, delete this test deliberately');

      for (final m in pointers) {
        final report = m['evaluation_report'] as String?;
        expect(report, isNotNull,
            reason: '${m['model_version']} says its commit is recorded per '
                'build and does not say where');
        final manifest = File('../${report!}')
            .parent
            .uri
            .resolve('manifest.json')
            .toFilePath();
        final f = File(manifest);
        expect(f.existsSync(), isTrue, reason: 'no manifest at $manifest');
        final commit =
            (jsonDecode(f.readAsStringSync()) as Map)['source_commit'] as String;

        // Shape first, so `UNKNOWN` — what the builder writes when git cannot
        // answer — reports as the honest admission it is rather than as a
        // failed object lookup.
        expect(RegExp(r'^[0-9a-f]{7,40}$').hasMatch(commit), isTrue,
            reason: '${m['model_version']} points at a manifest whose '
                'source_commit is "$commit". A model may not claim '
                'RECORDED_PER_BUILD provenance on a build that did not record '
                'one — that is what UNKNOWN in the registry is for');

        // `^{commit}` and not a bare `-e`: a bare existence check is satisfied
        // by a blob or a tree whose id happens to be this string, and "the
        // object exists" is not the claim. The peel makes git assert the type.
        final probe = Process.runSync(
          'git',
          ['-C', '..', 'cat-file', '-e', '$commit^{commit}'],
        );
        expect(probe.exitCode, 0,
            reason: '${m['model_version']}: $manifest records source_commit '
                '$commit, and no such commit exists in this repository.\n'
                'Either the manifest records a revision that was never here, '
                'or the checkout does not carry enough history to tell — a '
                'shallow clone cannot verify provenance, which is why '
                '.github/workflows/flutter.yml pins fetch-depth: 0 on the job '
                'that runs this suite.\n'
                'git said: ${probe.stderr}');
      }
    });
  });

  group('the abstention gap is recorded, because it is the product limit', () {
    test('the bundled model records that it cannot abstain', () {
      // Not decoration. This single boolean is the difference between "the
      // scanner is 62% accurate" and "the scanner answers confidently about
      // machines it has never seen", and only the second is true of what
      // ships.
      final bundled = entry('equipment_recognition', 'v1');
      expect(bundled['supports_unknown_or_abstain'], isFalse);
      expect(bundled['abstention_note'], isNotEmpty);
      expect(bundled['class_count'], 10,
          reason: 'ten classes against a 69-machine catalogue is the finding, '
              'and the count is what makes it checkable');
    });

    test('every model states whether it can abstain', () {
      for (final m in models) {
        expect(m['supports_unknown_or_abstain'], isA<bool>(),
            reason: '${m['model_version']} does not say. For a classifier that '
                'faces open-world input this is a required field, not an '
                'optional one');
      }
    });
  });

  group('documentation cannot silently contradict the registry', () {
    test('the model README does not claim v2 is what ships', () {
      // ML-F1's regression guard, pointed at the document that was right and
      // the one that was wrong. Deriving prose from the registry would be
      // better; a fence is what is affordable now, and it fails loudly.
      final readme = File('assets/models/README.md').readAsStringSync();
      expect(readme, contains('equipment_v1.tflite'));
      expect(readme.toLowerCase(), contains('not shipped'),
          reason: 'the README must keep saying that v2 is not shipped for as '
              'long as the registry says v1 is bundled');
    });

    test('the strategy document distinguishes shipped from measured', () {
      final strategy =
          File('../core/plans/ML_STRATEGY_2026-08-11.md').readAsStringSync();
      // NOT `contains('SHIPPED')`. That is a substring of 'NOT SHIPPED', so
      // the assertion guarding the v1 row was satisfied by the v2 row beside
      // it -- deleting the marking this test exists to protect left it green.
      final v1Marked = strategy
          .split('\n')
          .any((l) => l.contains('**v1**') && l.contains('**SHIPPED**'));
      expect(v1Marked, isTrue,
          reason: 'ML-F1 corrected this document to mark which classifier is '
              'in the APK. If that marking is removed, the defect returns');
      final v2Marked = strategy
          .split('\n')
          .any((l) => l.contains('**v2**') && l.contains('**NOT SHIPPED**'));
      expect(v2Marked, isTrue);
    });

    /// The fence covered `assets/models/README.md` and the strategy document.
    /// It did not cover `core/ml/` — the directory the registry lives in and
    /// whose stated job is being the authoritative answer to "which model is
    /// actually deployed". ML-F1's defect recurred there: a v2 measurement was
    /// attributed to the shipped model, which overstated the shipped model's
    /// confident-error severity by ~0.2 absolute.
    ///
    /// The figures are read out of the registry rather than hardcoded, so the
    /// fence tracks the registry instead of drifting alongside it.
    test('no ML document attributes a v2-only measurement to what ships', () {
      final v2 = entry('equipment_recognition', 'v2');
      final v1 = entry('equipment_recognition', 'v1');

      // Confidence figures that appear in v2's evidence and nowhere in v1's.
      final v2Text = jsonEncode(v2);
      final v1Text = jsonEncode(v1);
      final figures = RegExp(r'0\.\d{3}')
          .allMatches(v2Text)
          .map((m) => m.group(0)!)
          .where((f) => !v1Text.contains(f))
          .toSet();
      expect(figures, isNotEmpty,
          reason: 'the parser found no v2-only figures, so this test would '
              'police nothing');

      final docs = [
        File('../core/ml/CT_CANDIDATE_DECISION.md'),
        File('../core/ML_PLATFORM_ARCHITECTURE.md'),
      ];
      for (final doc in docs) {
        final lines = doc.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final figure = figures.where(line.contains);
          if (figure.isEmpty) continue;
          // A line may carry a v2 figure -- it just has to say so.
          expect(
            line.contains('v2'),
            isTrue,
            reason:
                '${doc.path}:${i + 1} quotes ${figure.join(', ')}, which is a '
                'v2 measurement, without naming v2. The shipped model is v1; '
                'attributing v2 numbers to it is the ML-F1 defect.\n  $line',
          );
        }
      }
    });
  });
}
