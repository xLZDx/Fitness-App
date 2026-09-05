// RECOG-C1 — the committed ground truth, validated as a file.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, verification (b): "the
// final frozen GT file has exactly 104 rows (52 images x 2 arms); every
// gt_kind is one of the four states; every canonical_single row carries an
// exact CANONICAL_MACHINES label AND a canonical_equipment_id with the
// one-to-one assertion shown as passed, checked by a script parsing the CSV,
// the TypeScript constant and the production alias data rather than by eye."
//
// This reads the COMMITTED files back off disk and re-derives everything from
// the primary sources. The generator asserting its own output would only prove
// the generator agrees with itself; this fails if the file drifts from the
// sources afterwards, whoever edits it and however.
//
// It also answers GPT-PM's round-1 BLOCKER directly. That finding was that the
// preliminary GT was not genuinely arm-specific — one image-level label was
// duplicated into both arms and `gt_equivalent` was hard-coded — and that the
// validator could not have detected it, because it only checked that the
// already-duplicated rows agreed. The `arm provenance` group below is the
// check that was missing: every output row is matched back to ITS OWN arm's
// labelling record, `gt_equivalent` is recomputed from the frozen rule rather
// than trusted, and the per-arm evidence text is required to differ between
// arms — a mechanically duplicated arm cannot pass that.
//
// It is a real `_test.dart`, so `flutter test` runs it on every future change:
// the ground truth cannot be quietly edited later without this going red.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';

import '../../support/recog_c1_csv.dart';

const String _gtPath = '../core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv';
const String _labelsPath = '../core/plans/RECOG_C1_LABELS_2026-09-05.csv';
const String _manifestPath = '../core/plans/RECOG_C1_ARM_MANIFEST_2026-09-05.csv';
const String _aliasPath = 'assets/data/equipment_aliases.json';
const String _serverPath = '../functions/src/ai_equipment_recognition.ts';

File _mustExist(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: 'missing ${f.absolute.path}');
  return f;
}

/// The server's list, parsed out of the TypeScript that actually ships — not
/// the Dart mirror of it. The mirror has its own equality test; using it here
/// would make one transcription check two.
List<String> _canonicalFromServer() {
  final src = _mustExist(_serverPath).readAsStringSync();
  final block = RegExp(
    r'export const CANONICAL_MACHINES: readonly string\[\] = \[(.*?)\] as const;',
    dotAll: true,
  ).firstMatch(src);
  expect(block, isNotNull, reason: 'CANONICAL_MACHINES not found in the server');
  return RegExp('"([^"]+)"')
      .allMatches(block!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
}

void main() {
  late List<Map<String, String>> gt;
  late List<Map<String, String>> labels;
  late List<Map<String, String>> manifest;
  late Map<String, Map<String, String>> manifestByImageId;
  late Map<String, String> indexByImageId;
  late Map<String, Map<String, String>> labelByKey;
  late Map<String, Map<String, String>> gtByKey;
  late EquipmentAliasIndex index;
  late Map<String, String> exactAliases;
  late Set<String> canonical;

  setUpAll(() {
    gt = readCsv(_mustExist(_gtPath));
    labels = readCsv(_mustExist(_labelsPath));
    manifest = readCsv(_mustExist(_manifestPath));
    manifestByImageId = {
      for (final m in manifest) m['image_id_sha256_original']!: m,
    };
    indexByImageId = {
      for (final m in manifest) m['image_id_sha256_original']!: m['index']!,
    };
    labelByKey = {
      for (final l in labels) '${l['index']}|${l['arm']}': l,
    };
    gtByKey = {
      for (final r in gt) '${r['image_id']}|${r['arm']}': r,
    };

    final aliasJson =
        (jsonDecode(_mustExist(_aliasPath).readAsStringSync()) as Map)
            .cast<String, dynamic>();
    index = EquipmentAliasIndex.fromJson(aliasJson);
    exactAliases = <String, String>{};
    aliasJson.forEach((id, aliases) {
      for (final a in (aliases as List).cast<String>()) {
        exactAliases[EquipmentAliasIndex.normalise(a)] = id;
      }
    });

    canonical = _canonicalFromServer().toSet();
  });

  group('shape', () {
    test('the header is the plan\'s schema, verbatim and in order', () {
      final rows = parseCsv(_mustExist(_gtPath).readAsStringSync());
      expect(rows.first, kGroundTruthColumns);
    });

    test('exactly 104 rows: 52 images x 2 arms', () {
      expect(manifest.length, 52, reason: 'the corpus itself is 52 images');
      expect(gt.length, 104);
      expect(labels.length, 104, reason: 'the labelling is also per-arm');
    });

    test('(image_id, arm) is unique, and every image has both arms', () {
      final seen = <String>{};
      final arms = <String, Set<String>>{};
      for (final r in gt) {
        final key = '${r['image_id']}|${r['arm']}';
        expect(seen.add(key), isTrue, reason: 'duplicate row for $key');
        expect(kArms.contains(r['arm']), isTrue,
            reason: 'unknown arm ${r['arm']}');
        arms.putIfAbsent(r['image_id']!, () => <String>{}).add(r['arm']!);
      }
      expect(arms.length, 52);
      for (final e in arms.entries) {
        expect(e.value, kArms.toSet(), reason: '${e.key} is missing an arm');
      }
    });
  });

  group('provenance', () {
    test('every row joins to the manifest on image_id and source_file', () {
      for (final r in gt) {
        final m = manifestByImageId[r['image_id']];
        expect(m, isNotNull,
            reason: 'image_id ${r['image_id']} is not in the manifest');
        expect(r['source_file'], m!['source_file']);
      }
    });

    test('transformed_sha256 is the sha of the bytes that arm actually sends', () {
      for (final r in gt) {
        final m = manifestByImageId[r['image_id']]!;
        final expected = r['arm'] == 'A'
            ? m['image_id_sha256_original']
            : m['arm_b_sha256'];
        expect(r['transformed_sha256'], expected,
            reason: 'arm ${r['arm']} of ${r['source_file']}');
        expect(r['transformed_sha256'], isNotEmpty);
      }
    });
  });

  group('arm provenance', () {
    test('every GT row carries ITS OWN arm\'s labelling, not the other one\'s',
        () {
      for (final r in gt) {
        final idx = indexByImageId[r['image_id']]!;
        final arm = r['arm']!;
        final own = labelByKey['$idx|$arm'];
        expect(own, isNotNull, reason: 'no labelling record for $idx arm $arm');
        for (final field in const [
          'gt_kind',
          'canonical_label',
          'semantic_label',
          'central_subject',
          'gt_status',
          'pass1_label',
          'pass2_label',
        ]) {
          expect(r[field], own![field]!.trim(),
              reason: 'index $idx arm $arm: $field came from somewhere else');
        }
        // The features column carries the multiplicity prefix the plan's
        // schema has no column for, so it is compared by containment.
        expect(r['features_the_label_rests_on'], contains(own!['features']!.trim()),
            reason: 'index $idx arm $arm: feature evidence is not this arm\'s');
      }
    });

    test('the two arms were labelled separately, not duplicated', () {
      // A mechanically duplicated arm — the defect GPT-PM's BLOCKER named —
      // produces identical evidence text for both arms of every image. One
      // coincidence would be plausible; 52 would not be labelling.
      for (final m in manifest) {
        final id = m['image_id_sha256_original']!;
        final a = gtByKey['$id|A']!;
        final b = gtByKey['$id|B']!;
        expect(b['features_the_label_rests_on'],
            isNot(a['features_the_label_rests_on']),
            reason: '${m['source_file']}: both arms carry the same evidence '
                'text, which is what a duplicated label looks like');
      }
    });

    test('gt_equivalent is DERIVED from the frozen rule, not asserted', () {
      for (final m in manifest) {
        final id = m['image_id_sha256_original']!;
        final idx = m['index']!;
        final a = gtByKey['$id|A']!;
        final b = gtByKey['$id|B']!;
        final expected = armsAreEquivalent(
          labelByKey['$idx|A']!,
          labelByKey['$idx|B']!,
          {'A': a['canonical_equipment_id']!, 'B': b['canonical_equipment_id']!},
        );
        for (final r in [a, b]) {
          expect(r['gt_equivalent'], expected ? 'true' : 'false',
              reason: '${m['source_file']} arm ${r['arm']}: gt_equivalent '
                  'disagrees with the frozen rule');
        }
      }
    });

    test('an image marked equivalent really does carry one semantic target',
        () {
      for (final m in manifest) {
        final id = m['image_id_sha256_original']!;
        final a = gtByKey['$id|A']!;
        final b = gtByKey['$id|B']!;
        if (a['gt_equivalent'] != 'true') continue;
        expect(b['gt_kind'], a['gt_kind'], reason: m['source_file']);
        expect(b['canonical_label'], a['canonical_label'],
            reason: m['source_file']);
        expect(b['canonical_equipment_id'], a['canonical_equipment_id'],
            reason: m['source_file']);
        expect(b['gt_status'], a['gt_status'], reason: m['source_file']);
      }
    });
  });

  group('labels', () {
    test('every gt_kind is one of the four states', () {
      for (final r in gt) {
        expect(kGroundTruthKinds.contains(r['gt_kind']), isTrue,
            reason: '${r['source_file']}: gt_kind "${r['gt_kind']}"');
      }
    });

    test('every gt_status is resolved or unresolved', () {
      for (final r in gt) {
        expect(r['gt_status'], anyOf('resolved', 'unresolved'),
            reason: '${r['source_file']}: gt_status "${r['gt_status']}"');
      }
    });

    test('canonical_single rows carry an exact CANONICAL_MACHINES label', () {
      final singles = gt.where((r) => r['gt_kind'] == 'canonical_single');
      expect(singles, isNotEmpty);
      for (final r in singles) {
        final label = r['canonical_label']!;
        expect(label, isNotEmpty, reason: '${r['source_file']} has no label');
        expect(canonical.contains(label), isTrue,
            reason: '"$label" is not in the server\'s CANONICAL_MACHINES');
      }
    });

    test('canonical_equipment_id comes from the production resolver', () {
      for (final r in gt.where((r) => r['gt_kind'] == 'canonical_single')) {
        final label = r['canonical_label']!;
        final id = r['canonical_equipment_id']!;
        expect(id, isNotEmpty, reason: '"$label" has no equipment id');
        expect(index.resolve(label), id,
            reason: 'production resolve("$label") disagrees with the CSV');
        // And by EXACT alias, so the id does not depend on the resolver's
        // longest-substring fallback and therefore on which other aliases
        // happen to exist in the catalogue.
        expect(exactAliases[EquipmentAliasIndex.normalise(label)], id,
            reason: '"$label" is not an exact alias of $id');
      }
    });

    test('label -> equipment id is one-to-one, in both directions', () {
      final labelToId = <String, String>{};
      final idToLabel = <String, String>{};
      for (final r in gt.where((r) => r['gt_kind'] == 'canonical_single')) {
        final label = r['canonical_label']!;
        final id = r['canonical_equipment_id']!;
        final seenId = labelToId[label];
        if (seenId != null) {
          expect(seenId, id, reason: '"$label" resolves two ways');
        }
        labelToId[label] = id;
        final seenLabel = idToLabel[id];
        if (seenLabel != null) {
          expect(seenLabel, label, reason: '$id is claimed by two labels');
        }
        idToLabel[id] = label;
      }
      expect(labelToId.length, idToLabel.length);
      expect(labelToId, isNotEmpty);
    });

    test('a row that is not a canonical_single carries no label and no id', () {
      for (final r in gt.where((r) => r['gt_kind'] != 'canonical_single')) {
        expect(r['canonical_label'], isEmpty,
            reason: '${r['source_file']} is ${r['gt_kind']} but is labelled');
        expect(r['canonical_equipment_id'], isEmpty,
            reason: '${r['source_file']} is ${r['gt_kind']} but has an id');
      }
    });
  });

  group('corpus composition, recorded rather than assumed', () {
    test('the counts this baseline is measured over, per arm', () {
      for (final arm in kArms) {
        final rows = gt.where((r) => r['arm'] == arm).toList();
        final counts = <String, int>{};
        for (final r in rows) {
          counts[r['gt_kind']!] = (counts[r['gt_kind']] ?? 0) + 1;
        }
        final unresolved =
            rows.where((r) => r['gt_status'] == 'unresolved').length;

        // Deliberately asserted per arm, not printed: these numbers are the
        // corpus gap the report must disclose, and asserting them SEPARATELY
        // for A and B means a future edit that silently collapses one arm into
        // the other still has to survive both. `out_of_catalog_single` and
        // `none` are ZERO in both arms, so the overclaim-on-an-unknown-machine
        // property cannot be measured on this corpus at all.
        expect(rows.length, 52, reason: 'arm $arm');
        expect(counts['canonical_single'], 26, reason: 'arm $arm');
        expect(counts['multiple'], 26, reason: 'arm $arm');
        expect(counts['out_of_catalog_single'] ?? 0, 0, reason: 'arm $arm');
        expect(counts['none'] ?? 0, 0, reason: 'arm $arm');
        expect(unresolved, 3, reason: 'arm $arm');
      }
    });
  });
}
