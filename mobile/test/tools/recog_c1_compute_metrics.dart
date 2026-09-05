// RECOG-C1 step 8 — the metrics, computed by committed code rather than by
// hand.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, step 8: "Compute the
// metrics with a committed script, joining on (image_id, arm) and applying the
// already-tested matrix."
//
// Written BEFORE the numbers exist, for the same reason the scoring contract
// was: a rule chosen after seeing the results is not a measurement. This file
// contains no thresholds, no judgement and no scoring of its own — every
// decision about what an observation is worth comes from
// `recog_c1_contract.dart`, which is frozen and committed. What lives here is
// only the join, the denominators and the arithmetic.
//
// Run it explicitly:
//
//   flutter test test/tools/recog_c1_compute_metrics.dart
//
//   RECOG_C1_RAW   one or more raw JSONL files, comma-separated (one per window)
//   RECOG_C1_GT    core/plans/RECOG_C1_GROUND_TRUTH_2026-09-05.csv
//   RECOG_C1_PLAN  core/plans/RECOG_C1_RUN_PLAN_2026-09-05.csv
//   RECOG_C1_OUT   the Markdown measurement document to write
//
// Three properties this file is built around, each of which exists because
// getting it wrong would produce a number that looks fine and is false:
//
//   * EVERY parsed row is re-classified from its own `raw_reply` and the
//     result must equal the class the device recorded. That is verification
//     clause (f). A disagreement is a stop, not a warning: it would mean the
//     device and the analysis disagree about what the model said, and no
//     metric computed after that point means anything.
//
//   * Operational failures are excluded from every SEMANTIC denominator and
//     counted on their own axis, and correctness is computed over
//     `gt_status = resolved` rows only. Both are the frozen contract's rules,
//     not this file's.
//
//   * A pair counts toward the crop effect only when both arms share a
//     `pair_id` AND a `session_id`. The comparison rests entirely on A and B
//     running back to back; a resume between them leaves two rows that still
//     share a pair id and still sit adjacent in the file while being separated
//     in reality by however long the app was down. Declared before the first
//     inference, in the step-5 decision-log entry and in the GPT-PM round-2
//     exchange.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/visual_equipment/data/scan_outcome.dart';
import 'package:fitness_app/features/visual_equipment/measurement/recog_c1_contract.dart';
import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';

import '../support/recog_c1_csv.dart';

String _env(String name) {
  final v = Platform.environment[name];
  if (v == null || v.trim().isEmpty) {
    throw StateError('$name is not set; see the header of this file');
  }
  return v.trim();
}

/// One row of the raw JSONL, joined to its ground truth.
class _Row {
  _Row(this.raw, this.gt);
  final Map<String, Object?> raw;
  final Map<String, String> gt;

  String get id => raw['observation_id']! as String;
  String get arm => raw['arm']! as String;
  String get pairId => raw['pair_id']! as String;
  String get imageId => raw['image_id']! as String;
  String? get sessionId => raw['session_id'] as String?;
  bool get resolved => gt['gt_status']!.trim() == 'resolved';

  RecogC1ResponseClass get responseClass => RecogC1ResponseClass.values
      .firstWhere((c) => c.name == raw['response_class']);

  ScanOutcome? get productionOutcome {
    final name = raw['production_outcome'] as String?;
    if (name == null) return null;
    return ScanOutcome.values.firstWhere((o) => o.name == name);
  }

  List<Map<String, Object?>> get candidates =>
      ((raw['candidates'] as List<Object?>?) ?? const <Object?>[])
          .cast<Map<String, Object?>>();

  /// The top candidate is the one production would have opened.
  bool get topMatchesGt {
    final want = gt['canonical_equipment_id']!.trim();
    if (want.isEmpty || candidates.isEmpty) return false;
    return candidates.first['equipment_id'] == want;
  }

  bool get gtAmongCandidates {
    final want = gt['canonical_equipment_id']!.trim();
    if (want.isEmpty) return false;
    return candidates.any((c) => c['equipment_id'] == want);
  }
}

/// The outcome of one analysis, so a test can assert on the numbers rather
/// than on the prose that reports them.
class RecogC1Metrics {
  RecogC1Metrics({
    required this.observations,
    required this.operational,
    required this.scores,
    required this.comparablePairs,
    required this.notComparable,
    required this.control,
    required this.markdown,
  });

  final int observations;
  final int operational;
  final Map<String, RecogC1SemanticScore> scores;
  final Set<String> comparablePairs;
  final Map<String, String> notComparable;
  final int control;
  final String markdown;
}

/// Everything the tool does, with no file or environment access, so the rules
/// it enforces can be tested with synthetic rows. The wrapper below supplies
/// the real inputs.
RecogC1Metrics computeMetrics({
  required List<String> rawLines,
  required List<Map<String, String>> gtRows,
  required List<Map<String, String>> planRows,
  required EquipmentAliasIndex index,
}) {
    final gtByKey = <String, Map<String, String>>{
      for (final r in gtRows) '${r['image_id']}|${r['arm']}': r,
    };

    // ---------------------------------------------------------------- read
    final observations = <_Row>[];
    final control = <Map<String, Object?>>[];
    final seenIds = <String>{};

    for (final line in rawLines) {
      {
        if (line.trim().isEmpty) continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(line);
        } catch (e) {
          // A truncated final line is a real possibility (the process can be
          // killed mid-write) and must be visible, not skipped in silence.
          throw StateError('unparseable line: $line');
        }
        final m = (decoded! as Map).cast<String, Object?>();
        if (m['record_type'] != 'observation') {
          control.add(m);
          continue;
        }
        // A duplicate observation id would mean the same target was measured
        // twice and both rows counted — the exact double-count the resume
        // logic exists to prevent. Never silently deduplicate it.
        final id = m['observation_id']! as String;
        if (!seenIds.add(id)) {
          throw StateError('duplicate observation id $id across the raw files');
        }
        final key = '${m['image_id']}|${m['arm']}';
        final gt = gtByKey[key];
        if (gt == null) throw StateError('no ground truth for $key');
        observations.add(_Row(m, gt));
      }
    }

    // -------------------------------------------- (f) reconstruction check
    //
    // Every parsed row re-derived from its own raw reply. If the analysis and
    // the device disagree about what class a reply belongs to, nothing after
    // this line is worth computing.
    for (final r in observations) {
      final replyForClassification = r.raw['call_returned'] == true
          ? ((r.raw['raw_reply'] as String?) ?? '')
          : r.raw['raw_reply'] as String?;
      final recomputed = classifyResponse(
        rawReply: replyForClassification,
        index: index,
        operationalError: r.raw['transport_error'] != null,
      );
      if (recomputed != r.responseClass) {
        throw StateError(
          'reconstruction failed for ${r.id}: the device recorded '
          '${r.responseClass.name}, this analysis derives ${recomputed.name} '
          'from the same raw reply',
        );
      }
    }

    // ----------------------------------------------- the operational axis
    final operational = observations
        .where((r) => r.responseClass == RecogC1ResponseClass.operationalFailure)
        .toList();
    final reachedModel =
        observations.where((r) => !operational.contains(r)).toList();

    // ------------------------------------------------- the semantic axis
    final scores = <_Row, RecogC1SemanticScore>{};
    for (final r in reachedModel) {
      final s = scoreObservation(
        gtKind: RecogC1GtKind.values
            .firstWhere((k) => k.name == r.gt['gt_kind']!.trim()),
        responseClass: r.responseClass,
        productionOutcome: r.productionOutcome,
        topMatchesGt: r.topMatchesGt,
        gtAmongCandidates: r.gtAmongCandidates,
      );
      if (s != null) scores[r] = s;
    }

    // Correctness is computed over resolved rows only — the three unresolved
    // photographs contribute to no accuracy number in either direction.
    final resolved =
        scores.keys.where((r) => r.resolved).toList();

    Map<String, int> tally(Iterable<_Row> rows) {
      final m = <String, int>{};
      for (final r in rows) {
        final k = scores[r]!.name;
        m[k] = (m[k] ?? 0) + 1;
      }
      return Map.fromEntries(
          m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    }

    Map<String, int> classTally(Iterable<_Row> rows) {
      final m = <String, int>{};
      for (final r in rows) {
        final k = r.responseClass.name;
        m[k] = (m[k] ?? 0) + 1;
      }
      return Map.fromEntries(
          m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    }

    // ------------------------------------------------------ the crop effect
    //
    // Both arms present, both resolved, ground truth equivalent between arms,
    // and — the rule declared before any inference — the SAME session, because
    // a pair split by a restart is not the back-to-back pair the plan
    // designed.
    final byPair = <String, List<_Row>>{};
    for (final r in resolved) {
      byPair.putIfAbsent(r.pairId, () => <_Row>[]).add(r);
    }

    final comparable = <String, List<_Row>>{};
    final notComparable = <String, String>{};
    for (final entry in byPair.entries) {
      final arms = {for (final r in entry.value) r.arm: r};
      if (arms.length != 2) {
        notComparable[entry.key] = 'only arm ${arms.keys.join()} is scorable';
        continue;
      }
      if (arms['A']!.gt['gt_equivalent']!.trim() != 'true') {
        notComparable[entry.key] =
            'the crop changed the task: ground truth differs between arms';
        continue;
      }
      if (arms['A']!.sessionId == null ||
          arms['A']!.sessionId != arms['B']!.sessionId) {
        notComparable[entry.key] =
            'the two arms ran in different sessions, so they were not '
            'adjacent in time';
        continue;
      }
      comparable[entry.key] = entry.value;
    }

    int correctIn(String arm) => comparable.values
        .map((rows) => rows.firstWhere((r) => r.arm == arm))
        .where((r) => scores[r] == RecogC1SemanticScore.correctConfident)
        .length;

    // ------------------------------------------------------------- report
    final b = StringBuffer()
      ..writeln('# RECOG-C1 — the measurement')
      ..writeln()
      ..writeln('Generated by `test/tools/recog_c1_compute_metrics.dart`, '
          'which was committed before the first observation existed. Every '
          'scoring decision below comes from the frozen '
          '`recog_c1_contract.dart`; this file contributes the join, the '
          'denominators and the arithmetic only.')
      ..writeln()
      ..writeln('## Counts')
      ..writeln()
      ..writeln('| | |')
      ..writeln('| --- | --- |')
      ..writeln('| observations recorded | ${observations.length} |')
      ..writeln('| planned | ${planRows.length} |')
      ..writeln('| reached the model | ${reachedModel.length} |')
      ..writeln('| operational failures | ${operational.length} |')
      ..writeln('| scored (semantic) | ${scores.length} |')
      ..writeln('| scored and resolved | ${resolved.length} |')
      ..writeln('| control records | ${control.length} |')
      ..writeln();

    if (observations.length != planRows.length) {
      b
        ..writeln('> **The run is short of its plan.** '
            '${planRows.length - observations.length} planned observations '
            'have no row. The control records below say why; a short file is '
            'never read as a complete one.')
        ..writeln();
    }

    b
      ..writeln('## Control records')
      ..writeln();
    if (control.isEmpty) {
      b.writeln('None — every stop condition would have left one.');
    } else {
      b
        ..writeln('| type | detail |')
        ..writeln('| --- | --- |');
      for (final c in control) {
        final detail = Map<String, Object?>.from(c)
          ..remove('record_type')
          ..remove('run_id')
          ..remove('session_id')
          ..remove('plan_sha256');
        b.writeln('| `${c['record_type']}` | `${jsonEncode(detail)}` |');
      }
    }

    b
      ..writeln()
      ..writeln('## Response classes, per arm')
      ..writeln()
      ..writeln('| class | arm A | arm B |')
      ..writeln('| --- | --- | --- |');
    final ca = classTally(observations.where((r) => r.arm == 'A'));
    final cb = classTally(observations.where((r) => r.arm == 'B'));
    for (final k in {...ca.keys, ...cb.keys}.toList()..sort()) {
      b.writeln('| `$k` | ${ca[k] ?? 0} | ${cb[k] ?? 0} |');
    }

    b
      ..writeln()
      ..writeln('## Semantic scores over resolved rows, per arm')
      ..writeln()
      ..writeln('| score | arm A | arm B |')
      ..writeln('| --- | --- | --- |');
    final sa = tally(resolved.where((r) => r.arm == 'A'));
    final sb = tally(resolved.where((r) => r.arm == 'B'));
    for (final k in {...sa.keys, ...sb.keys}.toList()..sort()) {
      b.writeln('| `$k` | ${sa[k] ?? 0} | ${sb[k] ?? 0} |');
    }

    b
      ..writeln()
      ..writeln('## The crop effect')
      ..writeln()
      ..writeln('Comparable pairs: **${comparable.length}**. '
          'Not comparable: **${notComparable.length}** — each named below, '
          'because a pair dropped without a reason is a pair nobody can '
          'check.')
      ..writeln()
      ..writeln('| | arm A (full frame) | arm B (viewfinder crop) |')
      ..writeln('| --- | --- | --- |')
      ..writeln('| correct and confident | ${correctIn('A')} | '
          '${correctIn('B')} |')
      ..writeln();
    if (notComparable.isNotEmpty) {
      b
        ..writeln('| pair | why it is not comparable |')
        ..writeln('| --- | --- |');
      for (final e in (notComparable.keys.toList()..sort())) {
        b.writeln('| `$e` | ${notComparable[e]} |');
      }
    }

    b
      ..writeln()
      ..writeln('## What these numbers cannot tell you')
      ..writeln()
      ..writeln('- The corpus holds **0** out-of-catalogue single machines and '
          '**0** frames with no equipment, so it cannot measure whether the '
          'model overclaims on a machine it was never told about, nor whether '
          'it abstains honestly on an empty frame. Two of the most important '
          'properties are simply not covered.')
      ..writeln('- Three photographs are frozen `unresolved` and enter no '
          'correctness number in either direction.')
      ..writeln('- Both arms were labelled by one person in one sitting, each '
          'from its own images. Per-arm structure makes a genuine divergence '
          'visible; it does not make the judgement independent.');

  return RecogC1Metrics(
    observations: observations.length,
    operational: operational.length,
    scores: {for (final e in scores.entries) e.key.id: e.value},
    comparablePairs: comparable.keys.toSet(),
    notComparable: notComparable,
    control: control.length,
    markdown: b.toString(),
  );
}

void main() {
  test('compute the RECOG-C1 metrics', () async {
    final rawLines = <String>[];
    for (final path in _env('RECOG_C1_RAW').split(',')) {
      final f = File(path.trim());
      if (!f.existsSync()) throw StateError('no raw file at ${f.path}');
      rawLines.addAll(const LineSplitter().convert(f.readAsStringSync()));
    }

    final result = computeMetrics(
      rawLines: rawLines,
      gtRows: readCsv(File(_env('RECOG_C1_GT'))),
      planRows: readCsv(File(_env('RECOG_C1_PLAN'))),
      index: await EquipmentAliasIndex.load(),
    );

    File(_env('RECOG_C1_OUT')).writeAsStringSync(result.markdown);
    // ignore: avoid_print
    print('wrote ${_env('RECOG_C1_OUT')}: ${result.observations} observations, '
        '${result.comparablePairs.length} comparable pairs');
  });
}
