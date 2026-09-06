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
        gtKind: _gtKind(r.gt['gt_kind']!, r.id),
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
    // The universe is every pair that was OBSERVED, not every pair that
    // survived the filters. Building it from `resolved` alone made a pair whose
    // ground truth is unresolved on both arms disappear from the report
    // entirely: it was in neither list, and 25 comparable + 0 not-comparable
    // silently described 26 pairs. The report's own sentence -- "a pair dropped
    // without a reason is a pair nobody can check" -- was false about itself.
    // Found by running this against the real window 1; the unit test for
    // unresolved rows asserted only that such a pair is not COMPARED, which was
    // true and insufficient.
    final observedPairs = <String, List<_Row>>{};
    for (final r in observations) {
      observedPairs.putIfAbsent(r.pairId, () => <_Row>[]).add(r);
    }
    final byPair = <String, List<_Row>>{};
    for (final r in resolved) {
      byPair.putIfAbsent(r.pairId, () => <_Row>[]).add(r);
    }

    final comparable = <String, List<_Row>>{};
    final notComparable = <String, String>{};
    for (final pairId in observedPairs.keys) {
      final entry = MapEntry(pairId, byPair[pairId] ?? const <_Row>[]);
      final observedArms = {for (final r in observedPairs[pairId]!) r.arm};
      if (entry.value.isEmpty) {
        notComparable[pairId] = observedArms.length == 2
            ? 'neither arm entered a correctness number: ground truth '
                'unresolved, or the attempt never reached the model'
            : 'only arm ${observedArms.join()} was observed, and it is not '
                'scorable';
        continue;
      }
      final arms = {for (final r in entry.value) r.arm: r};
      if (arms.length != 2) {
        final missing = observedArms.difference(arms.keys.toSet());
        notComparable[entry.key] = missing.isEmpty
            ? 'only arm ${arms.keys.join()} is scorable'
            : 'only arm ${arms.keys.join()} is scorable; arm '
                '${missing.join()} was observed but is unresolved or never '
                'reached the model';
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

    // Every observed pair lands in exactly one bucket. Without this, a pair can
    // fall out of both and the two published counts describe fewer pairs than
    // the corpus has, with nothing in the output saying so.
    //
    // DEFENSIVE, and said plainly rather than dressed up as a tested guarantee:
    // this check survived its own mutation. With the loop above iterating the
    // observed pairs, no pair can fall out, so disabling this line leaves all
    // 22 tests green. It is kept as a backstop for a future edit that adds a
    // `continue` without recording a reason -- the exact shape of the defect it
    // was written after -- not because any test proves it load-bearing today.
    final accounted = comparable.length + notComparable.length;
    if (accounted != observedPairs.length) {
      throw StateError(
        'pair accounting is short: ${observedPairs.length} pairs were '
        'observed but only $accounted are reported as comparable or '
        'not-comparable',
      );
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
    // `attempt_started` is a write-ahead marker written before EVERY attempt,
    // so listing them individually buries the records this section exists for
    // under one routine row per observation -- 52 of them for a full window.
    // What matters about them is the count and, above all, any marker with no
    // matching observation, which is an attempt whose outcome nobody knows.
    final markers =
        control.where((c) => c['record_type'] == 'attempt_started').toList();
    final exceptional =
        control.where((c) => c['record_type'] != 'attempt_started').toList();
    final observedIds = {for (final r in observations) r.id};
    final orphaned = markers
        .where((m) => !observedIds.contains(m['observation_id']))
        .toList();

    if (markers.isNotEmpty) {
      b
        ..writeln('${markers.length} write-ahead `attempt_started` markers, '
            '${orphaned.length} of them with no matching observation.')
        ..writeln();
      if (orphaned.isNotEmpty) {
        b
          ..writeln('> **${orphaned.length} attempt(s) started and never '
              'finished.** Each was sent, so each may have spent quota, and '
              'nothing here says what came back. They are named individually '
              'below because an unknown outcome must never be averaged into a '
              'total.')
          ..writeln();
        for (final m in orphaned) {
          b.writeln('- `${m['observation_id']}` '
              '(pair `${m['pair_id']}`, arm ${m['arm']}, '
              'attempt ${m['attempt_no']})');
        }
        b.writeln();
      }
    }

    if (exceptional.isEmpty) {
      b.writeln('No stop, abort or resume record — every stop condition would '
          'have left one.');
    } else {
      b
        ..writeln('| type | detail |')
        ..writeln('| --- | --- |');
      for (final c in exceptional) {
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

/// The frozen ground truth writes `gt_kind` in snake_case; the frozen contract
/// names the same four cases in Dart's camelCase. Both files are committed and
/// hashed, so neither can be edited to agree with the other -- the translation
/// has to live here.
///
/// It is an explicit table rather than a name transformation on purpose. A
/// mechanical de-snake would silently accept `canonical_singles` or a typo'd
/// `cannonical_single` as something, and a wrong `gt_kind` changes what an
/// answer is worth without changing anything visible in the output. Anything
/// not in this table is a stop.
///
/// This existed as a latent crash until the script was first run against the
/// real CSV: `RecogC1GtKind.values.firstWhere((k) => k.name == ...)` threw
/// `Bad state: No element` on the first `canonical_single` row. The unit tests
/// missed it because their fixtures wrote `canonicalSingle` -- a format the
/// frozen data has never used.
RecogC1GtKind _gtKind(String raw, String observationId) {
  const table = <String, RecogC1GtKind>{
    'canonical_single': RecogC1GtKind.canonicalSingle,
    'out_of_catalog_single': RecogC1GtKind.outOfCatalogSingle,
    'multiple': RecogC1GtKind.multiple,
    'none': RecogC1GtKind.none,
  };
  final kind = table[raw.trim()];
  if (kind == null) {
    throw StateError(
      'unknown gt_kind "${raw.trim()}" on $observationId; the frozen ground '
      'truth may only use ${table.keys.join(", ")}',
    );
  }
  return kind;
}

void main() {
  // Required, not boilerplate: `EquipmentAliasIndex.load()` reads the alias
  // table through `rootBundle`, and without an initialised binding the whole
  // run dies with "Binding has not yet been initialized" before it reads a
  // single observation. The unit tests never caught it because they exercise
  // `computeMetrics` directly with an injected index -- so every guarantee in
  // this file was proved, and the one path that actually runs against real
  // data had never executed once.
  TestWidgetsFlutterBinding.ensureInitialized();

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
