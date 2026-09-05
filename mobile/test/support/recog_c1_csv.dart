// RECOG-C1 — CSV reading/writing shared by the generator and the validator.
//
// Test-only support, deliberately NOT in `lib/`: nothing the app ships needs
// to parse a CSV, and the measurement gate's scope is measurement. It is also
// deliberately shared rather than copied, because the generator writing the
// ground truth and the test validating it must disagree about the file's
// CONTENT if anything is wrong — never about how a quoted field is parsed.
//
// Named without the `_test.dart` suffix so `flutter test` does not collect it.

import 'dart:io';

/// Minimal RFC4180 reader: quoted fields, doubled quotes inside them, and
/// commas or newlines inside quotes. The labelled sheet contains all three,
/// so a `split(',')` silently shifts columns — which it did once already, on
/// the one row whose subject text contains a comma.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  var sawAnyChar = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // A trailing newline must not produce a phantom empty row.
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
    sawAnyChar = false;
  }

  while (i < text.length) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(c);
      i++;
      continue;
    }
    if (c == '"') {
      inQuotes = true;
      sawAnyChar = true;
      i++;
      continue;
    }
    if (c == ',') {
      endField();
      sawAnyChar = true;
      i++;
      continue;
    }
    if (c == '\r') {
      i++;
      continue;
    }
    if (c == '\n') {
      endRow();
      i++;
      continue;
    }
    field.write(c);
    sawAnyChar = true;
    i++;
  }
  if (sawAnyChar || field.isNotEmpty) endRow();
  return rows;
}

/// Header row -> a map per data row. A row whose cell count disagrees with the
/// header is a stop: that is exactly the silent column shift this exists to
/// catch, and a lenient reader would turn it into wrong ground truth.
List<Map<String, String>> readCsv(File f) {
  final rows = parseCsv(f.readAsStringSync());
  if (rows.isEmpty) throw StateError('${f.path} is empty');
  final header = rows.first;
  return rows.skip(1).map((r) {
    if (r.length != header.length) {
      throw StateError(
        '${f.path}: row has ${r.length} cells, header has ${header.length}: $r',
      );
    }
    return <String, String>{
      for (var i = 0; i < header.length; i++) header[i]: r[i],
    };
  }).toList();
}

/// Every field is quoted, so a label containing a comma cannot shift a column.
String csvRow(List<Object?> cells) =>
    cells.map((c) => '"${'$c'.replaceAll('"', '""')}"').join(',');

/// The ground-truth schema: the plan's own column list, verbatim and in its
/// order (plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, step 3).
const List<String> kGroundTruthColumns = <String>[
  'image_id',
  'arm',
  'source_file',
  'transformed_sha256',
  'gt_kind',
  'canonical_label',
  'canonical_equipment_id',
  'semantic_label',
  'central_subject',
  'gt_equivalent',
  'gt_status',
  'pass1_label',
  'pass2_label',
  'features_the_label_rests_on',
];

/// The four states the plan allows. `out_of_catalog_single` and `none` are
/// legal and simply do not occur in this corpus — a real gap, disclosed in the
/// results rather than papered over by narrowing the enum.
const Set<String> kGroundTruthKinds = <String>{
  'canonical_single',
  'out_of_catalog_single',
  'multiple',
  'none',
};

/// The two arms, in the order the ground truth lists them. Arm A is the
/// untouched original; Arm B is the same photograph cropped to what the
/// scanner viewfinder actually keeps.
const List<String> kArms = <String>['A', 'B'];

/// The FROZEN equivalence rule, declared once and used by both the generator
/// and the validator so they cannot drift.
///
/// Two arms of one photograph are equivalent when the labeller, looking at
/// each arm on its own, arrived at the same semantic target: the same kind of
/// frame, the same catalogue label, the same resolved equipment id, and the
/// same adjudication status. Anything else means the CROP CHANGED THE TASK,
/// and step 8 must not then read a difference in the model's answers as an
/// effect of the crop on recognition.
///
/// Derived, never asserted. An earlier version of the generator hard-coded
/// `true` here, which GPT-PM's round-1 review correctly returned as a BLOCKER:
/// a hard-coded equivalence cannot be wrong, and therefore cannot be evidence.
bool armsAreEquivalent(
  Map<String, String> armA,
  Map<String, String> armB,
  Map<String, String> equipmentIds,
) =>
    armA['gt_kind']!.trim() == armB['gt_kind']!.trim() &&
    armA['canonical_label']!.trim() == armB['canonical_label']!.trim() &&
    armA['gt_status']!.trim() == armB['gt_status']!.trim() &&
    equipmentIds['A'] == equipmentIds['B'];
