// RECOG-C1 step 7 — the run plan: which observation happens when, decided
// before any of them happen.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, step 7: "A and B for the
// same image adjacent in time under one pair_id, order alternated by the
// predeclared rule, ~26 pairs per window."
//
// The alternation rule, declared here and nowhere else:
//
//   pair k (0-based, in manifest index order) runs A then B when k is EVEN,
//   and B then A when k is ODD.
//
// Why alternate at all: if every pair always ran A first, then every B would
// sit second, and anything that drifts within a pair — a warming cache, a
// model revision rolling out, the network — would land entirely on one arm and
// masquerade as an effect of the crop. Alternating makes that drift cancel
// instead of accumulate.
//
// Why two windows: the daily quota is 60 recognition calls per user per UTC
// day, enforced BEFORE the model call (`functions/src/abuse_guard.ts`), and
// the measurement is 104 observations. 26 pairs = 52 calls per window leaves
// 8 calls of retry budget inside the same window, so a retry does not have to
// cross a UTC boundary away from the pair it belongs to.
//
// Not a test. Run it explicitly:
//
//   flutter test test/tools/recog_c1_generate_run_plan.dart
//
//   RECOG_C1_GT        core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv
//   RECOG_C1_PLAN_OUT  the CSV to write

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/recog_c1_csv.dart';

String _env(String name) {
  final v = Platform.environment[name];
  if (v == null || v.trim().isEmpty) {
    throw StateError('$name is not set; see the header of this file');
  }
  return v.trim();
}

const int kPairsPerWindow = 26;

void main() {
  test('generate the RECOG-C1 run plan', () {
    final gtFile = File(_env('RECOG_C1_GT'));
    final outFile = File(_env('RECOG_C1_PLAN_OUT'));
    expect(gtFile.existsSync(), isTrue, reason: '${gtFile.path} must exist');

    final gt = readCsv(gtFile);
    expect(gt.length, 104);

    // Pairs in the order the ground truth lists them, which is manifest index
    // order — a fixed, already-committed order, so the run plan is a pure
    // function of a committed file and this rule.
    final pairOrder = <String>[];
    final byImageArm = <String, Map<String, String>>{};
    for (final r in gt) {
      final id = r['image_id']!;
      if (!byImageArm.containsKey('$id|A') && !byImageArm.containsKey('$id|B')) {
        pairOrder.add(id);
      }
      byImageArm['$id|${r['arm']}'] = r;
    }
    expect(pairOrder.length, 52);

    final rows = <String>[
      csvRow(const [
        'seq',
        'window',
        'pair_id',
        'pair_index',
        'image_id',
        'arm',
        'attempt_no',
        'source_file',
        'transformed_sha256',
        'gt_kind',
        'gt_status',
      ]),
    ];

    var seq = 0;
    for (var k = 0; k < pairOrder.length; k++) {
      final imageId = pairOrder[k];
      final window = (k ~/ kPairsPerWindow) + 1;
      final pairId = 'p${k.toString().padLeft(2, '0')}';
      // The predeclared rule, in one line so it cannot be misread.
      final arms = k.isEven ? const ['A', 'B'] : const ['B', 'A'];
      for (final arm in arms) {
        final r = byImageArm['$imageId|$arm'];
        expect(r, isNotNull, reason: 'ground truth is missing $imageId arm $arm');
        rows.add(csvRow([
          seq++,
          window,
          pairId,
          k,
          imageId,
          arm,
          1,
          r!['source_file'],
          r['transformed_sha256'],
          r['gt_kind'],
          r['gt_status'],
        ]));
      }
    }

    expect(rows.length, 105, reason: '104 observations plus the header');
    outFile.writeAsStringSync('${rows.join('\n')}\n');

    // ignore: avoid_print
    print('wrote ${outFile.path}: ${rows.length - 1} observations, '
        '${pairOrder.length} pairs, '
        '${(pairOrder.length / kPairsPerWindow).ceil()} UTC windows');
  });
}
