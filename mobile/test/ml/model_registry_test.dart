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

  group('the registry describes a real tree', () {
    test('every model marked bundled has an artefact that exists', () {
      for (final m in models.where((m) => m['bundled'] == true)) {
        final f = repoFile(m['artifact_path'] as String);
        expect(f.existsSync(), isTrue,
            reason: '${m['model_id']}@${m['model_version']} claims '
                'bundled=true but ${m['artifact_path']} is not there. Either '
                'the asset was removed and the app is broken, or the registry '
                'is describing a deployment that does not exist');
      }
    });

    test('the bundled artefact hashes to the recorded digest', () {
      // The assertion ML-F1 would have failed. A hash is what makes "which
      // model is this" answerable without trusting a filename -- v1 and v2
      // are both called `equipment_v*.tflite` and are within 1.5% of each
      // other in size.
      for (final m in models.where((m) => m['bundled'] == true)) {
        final f = repoFile(m['artifact_path'] as String);
        final digest = sha256.convert(f.readAsBytesSync()).toString();
        expect(digest, m['artifact_sha256'],
            reason: '${m['artifact_path']} does not hash to the registry\'s '
                'recorded digest. A model artefact was replaced without the '
                'registry being updated, which is precisely the state ML-F1 '
                'described');
        expect(f.lengthSync(), m['artifact_bytes'], reason: m['artifact_path']);
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
        expect(m['champion'], isNot(true), reason: '${m['model_version']}');
      }
    });
  });

  group('the code loads what the registry says it loads', () {
    /// Every `.tflite` path that appears in a Dart source file under `lib/`.
    Set<String> modelPathsInCode() {
      final found = <String>{};
      final pattern = RegExp(r"'(assets/models/[A-Za-z0-9_.\-]+\.tflite)'");
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
      final bundled = models.firstWhere((m) => m['bundled'] == true);
      final assetPath =
          (bundled['artifact_path'] as String).replaceFirst('mobile/', '');
      expect(modelPathsInCode(), contains(assetPath),
          reason: 'the registry says $assetPath is bundled but no Dart source '
              'loads it. This is the ML-F1 shape exactly, in the other '
              'direction: a documented deployment nothing performs');
    });

    test('the asset is declared in pubspec, or it never reaches a device', () {
      // A file in `assets/` that pubspec does not declare is not in the APK.
      // The registry would be accurate about the repository and wrong about
      // the product.
      final pubspec = File('pubspec.yaml').readAsStringSync();
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

    test('a champion that is not the first of its kind has a rollback target',
        () {
      // v1 legitimately has none — there is nothing behind it. Anything that
      // replaces it must name what it falls back to, because "we promoted and
      // cannot go back" is not a deployment, it is a hope.
      for (final m in models.where((m) => m['champion'] == true)) {
        if (m['model_version'] == 'v1') continue;
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
      for (final m in models.where((m) => m['champion'] == true)) {
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
      const permitted = {'UNKNOWN', 'NOT_RECORDED', 'LEGACY'};
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
  });

  group('the abstention gap is recorded, because it is the product limit', () {
    test('the bundled model records that it cannot abstain', () {
      // Not decoration. This single boolean is the difference between "the
      // scanner is 62% accurate" and "the scanner answers confidently about
      // machines it has never seen", and only the second is true of what
      // ships.
      final bundled = models.firstWhere((m) => m['bundled'] == true);
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
      final registry = jsonDecode(
        File('../core/ml/MODEL_REGISTRY.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final models = (registry['models'] as List).cast<Map<String, dynamic>>();
      final v2 = models.firstWhere((m) => m['bundled'] != true);
      final v1 = models.firstWhere((m) => m['bundled'] == true);

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
