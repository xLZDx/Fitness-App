// RECOG-C1 step 5 — the measurement harness.
//
// Plan fitness_app-2026-09-05T11-25-16-919Z-377ee0, step 5. This file exists
// for exactly one gate and step 10 deletes it again, proving the tree
// byte-identical to where it started.
//
// It is dead code in every build that does not ask for it: [kEnabled] is
// `kDebugMode && bool.fromEnvironment('RECOG_C1_HARNESS')`, both compile-time
// constants, so a release build folds every guard to `false` and the compiler
// removes this whole path. Same shape as `g3_step10b_probe.dart`, which was
// built for the same reason and reviewed on the same grounds.
//
// What it does NOT do, deliberately:
//   * it does not re-implement recognition. It drives the production
//     `GeminiVisualEquipmentService` and the production
//     `ScanResult.fromMatches`, so the outcome it records is the outcome the
//     app would have shown;
//   * it does not touch the OCR text anchor, the on-device hybrid fallback or
//     the describer. The plan measures the CLOUD SERVICE BOUNDARY; a number
//     that silently included the fallback would not be that;
//   * it does not decide the observation order. That comes from a committed
//     run plan pushed to the device, so the alternation rule is auditable data
//     rather than a line of code nobody re-reads.
//
// Second gap, in the same spirit -- CLOSED during step 5's review, and this
// paragraph is the corrected record of it. The quota is charged BEFORE the
// model call while the row is written AFTER it returns, so a process death
// between the two spends a charged call that leaves no trace. The original
// design accepted that, reasoning that a "call started" marker would introduce
// its own crash window -- one where a row looks spent but never was, and is
// therefore never measured, which is the worse failure.
//
// That reasoning was wrong in one respect: it assumed the two states have to be
// conflated. They do not. `_recordingAsk` writes an `attempt_started` marker
// before the call and `readJournal` splits the file into OBSERVED (marker plus
// observation) and UNCERTAIN (marker, no observation). An uncertain row is
// neither retried nor retired -- it is skipped and named in a control record,
// so a later retry plan can decide about it deliberately. The marker write is
// fail-closed: if it cannot be written, the observation is not attempted.
//
// Window 1, 2026-09-06, produced 52 markers and 52 observations with zero
// uncertain rows, which is the first real evidence that the two agree.
//
// Known gap, recorded rather than worked around: the plan asks each row to
// carry a SERVER CORRELATION ID, and the callable contract has none. The Cloud
// Function returns `{ text }` and nothing else
// (`functions/src/ai_equipment_recognition.ts:165`), so there is no
// server-side identifier a client can record. Every row therefore carries
// `server_correlation_id: null` plus the reason, and records instead what does
// exist: a client-side observation id, exact UTC start/end, the callable name
// and region, and — on a failure — the `FirebaseFunctionsException` code,
// message and details verbatim. This is a real observability gap in the
// product (nothing links a client-side failure to a server log line), and it
// is written down as a finding rather than quietly re-scoped.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;

import '../../equipment/data/equipment_alias_index.dart';
import '../data/gemini_equipment_service.dart';
import '../data/scan_outcome.dart';
import '../data/visual_equipment_match.dart';
import 'recog_c1_contract.dart';

/// Compile-time configuration. Every value defaults to off/empty, so a build
/// that forgets a define behaves exactly like a normal debug build.
class RecogC1Harness {
  const RecogC1Harness._();

  /// Master switch. `kDebugMode` as well as the define: a release build cannot
  /// reach this path even if someone passes the define by accident.
  static const bool kEnabled =
      kDebugMode && bool.fromEnvironment('RECOG_C1_HARNESS');

  /// Directory on the device holding `run_plan.csv` and the images, and
  /// receiving the raw JSONL. Use the app's own external files directory
  /// (`/sdcard/Android/data/<pkg>/files/recog_c1`), which `adb push` can write
  /// and the app can read with no runtime permission.
  static const String dir = String.fromEnvironment('RECOG_C1_DIR');

  /// Identifies one execution of the harness. Every row carries it, so rows
  /// from two UTC windows stay distinguishable after they are concatenated.
  static const String runId = String.fromEnvironment('RECOG_C1_RUN_ID');

  /// The working-tree identity this build was compiled from — the same
  /// provenance discipline `g3_step10b_probe.dart` adopted after probe APKs
  /// were rebuilt across a live fix with no way to tell them apart.
  static const String sourceSha = String.fromEnvironment('RECOG_C1_SOURCE_SHA');

  /// Which UTC window of the committed run plan to execute, 0 meaning "every
  /// row". The daily quota is 60 recognition calls per user per UTC day and
  /// the full measurement is 104 observations, so the plan is split into two
  /// windows of 26 pairs. This selects by the plan's own `window` COLUMN
  /// rather than by a row count: a bare "first N rows" limit would silently
  /// re-run window 1 on the second day instead of advancing to window 2.
  static const int window = int.fromEnvironment('RECOG_C1_WINDOW');

  /// sha256 of the COMMITTED run plan this build is entitled to execute.
  ///
  /// Without it the instrument validates itself in a circle: `observe` checks
  /// each image against a hash it reads out of the very plan under suspicion,
  /// so a stale or hand-edited plan pushed together with its own matching
  /// images passes every check on both sides perfectly. Binding the expected
  /// hash into the BINARY breaks the circle, because the binary is the one
  /// artifact the deploy step cannot silently substitute.
  static const String planSha256 = String.fromEnvironment('RECOG_C1_PLAN_SHA');

  /// Stop after this many observations within the selected window, 0 meaning
  /// "all of them". A smoke-test lever, not the window mechanism.
  static const int limit = int.fromEnvironment('RECOG_C1_LIMIT');

  /// Give up after this many CONSECUTIVE operational failures. Hitting the
  /// daily quota returns an error per call, and grinding through the rest of
  /// the window against a wall would record dozens of failures that measure
  /// the quota rather than the model -- and would leave those targets looking
  /// attempted. Stopping keeps them simply not-yet-run.
  static const int abortAfterConsecutiveFailures =
      int.fromEnvironment('RECOG_C1_ABORT_AFTER', defaultValue: 3);

  /// Seconds to wait between observations. Not throttling for its own sake:
  /// back-to-back callable invocations from one client are exactly the shape
  /// an abuse guard is built to notice, and a measurement that trips one is
  /// measuring the guard.
  static const int gapSeconds =
      int.fromEnvironment('RECOG_C1_GAP_S', defaultValue: 3);
}

/// One observation's captured facts. Filled by the recording `ask` at the
/// exact call boundary, so `sent_sha256` is the sha of the bytes the cloud
/// really received — after the production `resizeForCloud`, not before it.
class _Capture {
  String? sentSha256;
  int? sentBytes;
  DateTime? startUtc;
  DateTime? endUtc;
  String? rawReply;

  /// True once the cloud call RETURNED, whether or not it carried any text.
  /// This is the one fact `classifyResponse` cannot recover on its own: it
  /// decides "operational" from `rawReply == null`, which cannot tell "the
  /// function answered with nothing" apart from "we never got an answer".
  bool callReturned = false;
  String? transportError;

  /// Set when the write-ahead marker could not be made durable. Kept on the
  /// capture rather than thrown straight up, because the production service
  /// wraps EVERYTHING the ask throws in a `VisualEquipmentException`
  /// (`gemini_equipment_service.dart:227`), so by the time it reaches
  /// `observe` a storage failure is indistinguishable from a recognition
  /// failure -- and would be filed as one.
  Object? journalError;
  String? errorCode;
  String? errorMessage;
  String? errorDetails;
}

/// What a partially-written raw file already contains.
class RecogC1Journal {
  const RecogC1Journal(this.observed, this.uncertain);

  /// Observations that completed and reached disk.
  final Set<String> observed;

  /// Attempts whose start marker reached disk but whose observation did not.
  /// Whether the call was charged is genuinely unknown, so these are neither
  /// re-run nor counted as done.
  final Set<String> uncertain;
}

/// A short random identifier for one runner invocation. Random rather than a
/// timestamp: two runs started inside the same second must not collide, and a
/// clock that jumps -- which a device left overnight does -- must not make two
/// separate sessions look like one.
String _newSessionId() {
  final r = Random.secure();
  return List<String>.generate(
    8,
    (_) => r.nextInt(16).toRadixString(16),
  ).join();
}

/// Drives the production service and writes one JSON object per observation.
class RecogC1Runner {
  RecogC1Runner({
    required this.dir,
    required this.runId,
    this.cloudAsk,
    this.serviceTimeout,
    this.openSink,
    this.gapSecondsOverride,
    this.windowOverride,
    this.expectedPlanShaOverride,
  });

  final String dir;
  final String runId;

  /// Identifies ONE invocation of the runner, so a pair whose two arms landed
  /// either side of a restart is visibly not the contiguous pair the plan
  /// intended. The crop comparison rests entirely on A and B being adjacent in
  /// time -- that is what makes drift cancel instead of accumulate -- and a
  /// resume ten minutes later, or after the backend has moved, silently breaks
  /// that while leaving the two rows sharing a `pair_id` and sitting next to
  /// each other in the file. Step 8 requires both arms to share this before it
  /// admits a pair to the crop-effect metric.
  final String sessionId = _newSessionId();

  /// sha256 of the run plan actually read on the device. Set by [run].
  String? _planSha256;

  /// Stands in for `cloudFunctionsEquipmentAsk()` in a test. Injected INSIDE
  /// the recording wrapper, not instead of it, so a test exercises the real
  /// capture logic rather than a parallel copy of it.
  @visibleForTesting
  final CloudRecognitionAsk? cloudAsk;

  /// Overrides `GeminiVisualEquipmentService`'s 30s client-side budget so a
  /// test can reach the timeout path in milliseconds. Null in every real run,
  /// which keeps the production default.
  @visibleForTesting
  final Duration? serviceTimeout;

  /// Opens the raw-output sink. Overridable ONLY so a test can supply a sink
  /// that fails the way a full or detached storage volume does. That is the
  /// one condition the `run_aborted` record exists to make visible, and it is
  /// also the one condition under which the record cannot be written through
  /// the sink itself -- so without this seam the abort path can only ever be
  /// exercised with a healthy sink, which proves nothing about the case that
  /// matters. Null in every real run.
  @visibleForTesting
  final IOSink Function(File out)? openSink;

  /// Overrides the inter-observation gap so a test can drive the abort valve
  /// without spending the real 3 seconds per step. Null in every real run,
  /// which keeps the compile-time default -- the throttle is there because
  /// back-to-back callable invocations are exactly the shape an abuse guard
  /// notices, and a measurement that trips one is measuring the guard.
  @visibleForTesting
  final int? gapSecondsOverride;

  /// Stands in for the compile-time `RECOG_C1_WINDOW`/`RECOG_C1_PLAN_SHA`, so
  /// the window-shape and plan-identity guards can be driven from a test.
  /// Without these the guards are unreachable off-device: both defines are
  /// absent in a `flutter test` run, which is exactly the state that must fail
  /// closed at the production entry point.
  @visibleForTesting
  final int? windowOverride;

  @visibleForTesting
  final String? expectedPlanShaOverride;

  int get _window => windowOverride ?? RecogC1Harness.window;

  /// Waits for a signed-in user, then runs. The callable rejects an
  /// unauthenticated request, so starting before sign-in would record a run of
  /// `unauthenticated` errors and call them measurements.
  static Future<void> runWhenSignedIn() async {
    if (!RecogC1Harness.kEnabled) return;
    final problem = configurationProblem();
    if (problem != null) {
      debugPrint('RECOG-C1: NOT RUNNING -- $problem');
      return;
    }
    // The try covers the SIGN-IN WAIT as well as the run. `firstWhere` throws
    // `Bad state: No element` if the auth stream closes without ever emitting
    // a user, and that exception would otherwise escape into the
    // `unawaited(...)` at the call site -- where, because Crashlytics
    // collection is `!kDebugMode` and this harness only runs in debug, nothing
    // would record it.
    try {
      final user = FirebaseAuth.instance.currentUser ??
          await FirebaseAuth.instance
              .authStateChanges()
              .firstWhere((u) => u != null);
      debugPrint('RECOG-C1: signed in as ${user?.uid}, starting run '
          '${RecogC1Harness.runId}');
      await RecogC1Runner(dir: RecogC1Harness.dir, runId: RecogC1Harness.runId)
          .run();
    } catch (e) {
      // This is launched with `unawaited(...)` from `main()`, so an exception
      // escaping here reaches the zone handler and, in practice, nobody. The
      // durable record is the `run_aborted` row `run()` already wrote; this
      // is the line the operator watching `adb logcat` actually sees.
      debugPrint('RECOG-C1: run ${RecogC1Harness.runId} ENDED WITH AN ERROR '
          '-- see the run_aborted record in the raw file: $e');
    }
  }

  /// Why the production entry point must refuse to start, or null if it may.
  ///
  /// Fails CLOSED, and the reason is the quota. `RECOG_C1_WINDOW` has no
  /// non-zero default and the code defines 0 as "every row", so a build that
  /// sets the harness on and forgets this ONE define does not run a smaller
  /// measurement -- it runs all 104 observations inside a single UTC day
  /// against a 60-call allowance, burns through the wall, and then spends the
  /// remainder failing until the abort valve fires. The window design exists
  /// precisely to prevent that, and defaulting to "no window" made forgetting
  /// a define more dangerous than passing a wrong one.
  ///
  /// Window 0 stays available to `run()` itself, which is what the tests
  /// drive: they supply their own small plans and never reach this guard.
  /// Every argument defaults to the compile-time value, so production calls
  /// this with no arguments and gets the real configuration. They exist so a
  /// test can vary ONE input at a time: the defines are compile-time constants
  /// and a `flutter test` run has none of them, so a check written against the
  /// constants directly can only ever be tested in the all-missing state --
  /// where any single guard passing makes the whole function look correct.
  @visibleForTesting
  static String? configurationProblem({
    String? dir,
    String? runId,
    int? window,
    String? planSha,
    String? sourceSha,
  }) {
    if ((dir ?? RecogC1Harness.dir).isEmpty) return 'RECOG_C1_DIR is not set';
    if ((runId ?? RecogC1Harness.runId).isEmpty) {
      return 'RECOG_C1_RUN_ID is not set';
    }
    final w = window ?? RecogC1Harness.window;
    if (w != 1 && w != 2) {
      return 'RECOG_C1_WINDOW must be 1 or 2, not $w; refusing to run every '
          'window in one UTC day against a 60-call quota';
    }
    if ((planSha ?? RecogC1Harness.planSha256).isEmpty) {
      return 'RECOG_C1_PLAN_SHA is not set; without it nothing binds the '
          'pushed run plan to the committed one';
    }
    if ((sourceSha ?? RecogC1Harness.sourceSha).isEmpty) {
      return 'RECOG_C1_SOURCE_SHA is not set; a measurement that cannot name '
          'the tree it was built from is not evidence';
    }
    return null;
  }

  Future<void> run() async {
    final planFile = File('$dir/run_plan.csv');
    if (!planFile.existsSync()) {
      debugPrint('RECOG-C1: no run plan at ${planFile.path}');
      return;
    }
    // The plan's own identity, checked against the value compiled into this
    // binary. Everything else in this file trusts the plan; this is the only
    // thing that checks it.
    final planSha = sha256.convert(planFile.readAsBytesSync()).toString();
    final expectedPlanSha =
        expectedPlanShaOverride ?? RecogC1Harness.planSha256;
    if (expectedPlanSha.isNotEmpty && planSha != expectedPlanSha) {
      throw StateError(
        'run plan sha256 mismatch: this build is compiled for '
        '$expectedPlanSha, the file on the device is $planSha',
      );
    }
    _planSha256 = planSha;

    final out = File('$dir/recog_c1_raw_$runId.jsonl');

    // Resume rather than repeat. This runs from `main()`, so ANY restart of
    // the app -- a crash, the operator reopening it, the OS killing it in the
    // background -- would otherwise re-execute the whole window and spend a
    // second set of quota on targets already measured. Observations already
    // written for this run id are skipped, which makes a restart a resume.
    //
    // "Written" means written, success or operational failure alike: a row
    // that failed is NOT retried under the same run id. That is deliberate,
    // not an oversight. The plan treats a retry as a planned activity whose
    // cost comes out of the same quota budget and which re-runs a WHOLE pair,
    // so retries belong in a fresh run id driving a retry plan -- not in an
    // automatic re-attempt that would, on the quota-exhausted path this abort
    // valve exists for, immediately spend more of the wall it just hit.
    final journal = readJournal(out);
    final done = journal.observed;

    // An attempt whose marker was written but whose observation never was.
    // The server charges the quota BEFORE the model call, so this row may
    // have cost a real call -- or the process may have died between the marker
    // and the call and cost nothing. The harness cannot tell, and neither can
    // anyone else, which is exactly why it must not guess. Re-running it would
    // spend a second call for an answer possibly already given; marking it
    // "done" would silently retire a photograph that was never measured. So it
    // is neither: it is left UNCERTAIN, skipped here, and named in a control
    // record for a later retry plan to decide about deliberately.
    final uncertain = journal.uncertain;

    var rows = readPlan(planFile);
    if (_window > 0) {
      rows = rows
          .where((r) => int.tryParse(r['window'] ?? '') == _window)
          .toList();
      // The window is only a protection if it is the size it claims to be.
      final pairs = rows.map((r) => r['pair_id']).toSet();
      if (rows.length != 52 || pairs.length != 26) {
        throw StateError(
          'window $_window of this plan has ${rows.length} '
          'rows across ${pairs.length} pairs; the design is 52 rows / 26 pairs '
          'because the daily quota is 60 calls',
        );
      }
    }
    final planned = rows.length;

    // Which pairs a resume is about to split. Both arms of a pair are supposed
    // to run back to back inside one session; if one arm is already durable
    // from an EARLIER session, running its partner now produces two rows that
    // still share a `pair_id` and still sit next to each other in the file
    // while being separated in reality by however long the app was down. The
    // rows are kept -- each is a valid single-arm observation -- but the pair
    // is named here so step 8 excludes it from the crop-effect metric instead
    // of having to infer the split from timestamps.
    final splitPairs = <String>{};
    for (final r in rows) {
      final id = observationId(r);
      if (done.contains(id) || uncertain.contains(id)) continue;
      final partnerDone = rows.any((o) =>
          o['pair_id'] == r['pair_id'] &&
          o['arm'] != r['arm'] &&
          (done.contains(observationId(o)) ||
              uncertain.contains(observationId(o))));
      if (partnerDone) splitPairs.add(r['pair_id']!);
    }

    rows = rows
        .where((r) =>
            !done.contains(observationId(r)) &&
            !uncertain.contains(observationId(r)))
        .toList();
    if (RecogC1Harness.limit > 0 && rows.length > RecogC1Harness.limit) {
      rows = rows.sublist(0, RecogC1Harness.limit);
    }

    debugPrint('RECOG-C1: window $_window, $planned planned, '
        '${done.length} already observed, ${uncertain.length} uncertain, '
        '${rows.length} to run');
    if (rows.isEmpty && uncertain.isEmpty && splitPairs.isEmpty) return;

    final index = await EquipmentAliasIndex.load();
    final sink = openSink?.call(out) ?? out.openWrite(mode: FileMode.append);
    if (uncertain.isNotEmpty) {
      sink.writeln(jsonEncode(_controlRecord(
        'attempts_uncertain',
        <String, Object?>{
          'observation_ids': uncertain.toList()..sort(),
          'note': 'a start marker with no observation: the call may or may not '
              'have been charged. Not re-run automatically; schedule a whole '
              'pair retry under a new run id.',
        },
      )));
      await sink.flush();
    }
    if (splitPairs.isNotEmpty) {
      sink.writeln(jsonEncode(_controlRecord(
        'pairs_split_by_resume',
        <String, Object?>{
          'pair_ids': splitPairs.toList()..sort(),
          'note': 'one arm ran in an earlier session. Both rows stay valid as '
              'single-arm observations; the pair is not comparable for the '
              'crop-effect metric.',
        },
      )));
      await sink.flush();
    }
    if (rows.isEmpty) {
      await sink.close();
      return;
    }
    var consecutiveFailures = 0;
    try {
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final record = await observe(row, index, journal: sink);
        sink.writeln(jsonEncode(record));
        await sink.flush();

        // Reads the frozen operational-failure flag, NOT `transport_error`:
        // the client-side timeout — the exact stall this codebase has already
        // hit in production (`gemini_equipment_service.dart:103-124`) — leaves
        // `transport_error` null, so a valve keyed on that field would reset
        // to zero on every timeout and grind through the whole window against
        // a wall, which is precisely what it exists to prevent.
        final failed = record['operational_failure'] == true;
        consecutiveFailures = failed ? consecutiveFailures + 1 : 0;
        debugPrint('RECOG-C1 [${i + 1}/${rows.length}] ${row['source_file']} '
            'arm ${row['arm']} -> '
            '${record['production_outcome'] ?? record['response_class']}');
        if (consecutiveFailures >=
            RecogC1Harness.abortAfterConsecutiveFailures) {
          // Recorded, not just printed. This is the MOST LIKELY way the run
          // ever stops early -- it is the quota wall -- and until this record
          // existed it was the one stop condition that left no trace: a short
          // JSONL, identical to a run that was killed, and identical to a
          // window that was planned short. `debugPrint` does not close that
          // gap, because it reaches `adb logcat` and the deploy script pulls
          // only the JSONL. The counts are on the row so the offline analysis
          // can check the file against the plan instead of assuming.
          sink.writeln(jsonEncode(_controlRecord(
            'run_stopped_consecutive_failures',
            <String, Object?>{
              'consecutive_failures': consecutiveFailures,
              'threshold': RecogC1Harness.abortAfterConsecutiveFailures,
              'observations_written': i + 1,
              'observations_left_unrun': rows.length - (i + 1),
            },
          )));
          await sink.flush();
          debugPrint('RECOG-C1: $consecutiveFailures consecutive operational '
              'failures -- stopping so the rest of the window stays unrun '
              'rather than recorded as attempted');
          break;
        }
        final gap = gapSecondsOverride ?? RecogC1Harness.gapSeconds;
        if (i + 1 < rows.length && gap > 0) {
          await Future<void>.delayed(Duration(seconds: gap));
        }
      }
    } catch (e, st) {
      // A stop, not a hidden failure. `observe` throws when the bytes on the
      // device are not the bytes the run plan names, which is unrecoverable:
      // a measurement of the wrong photograph is not a measurement. Without a
      // record the offline analysis would have to INFER an abort from a short
      // file, and "the run ended early" and "the run was planned short" look
      // identical in a JSONL.
      //
      // Written through a FRESH file handle, not `sink`. One of the two things
      // that reaches this catch is `sink.flush()` failing -- storage full,
      // detached, permission revoked -- and recording that on the same faulted
      // sink would throw again, which would replace the real exception with
      // the secondary one and skip the `rethrow` below. The failure this
      // record exists to make visible is precisely the failure the old version
      // could not record.
      //
      // The sink is closed FIRST, and its failure swallowed. Whatever it still
      // holds is either already lost or about to be flushed, and flushing it
      // after the abort line -- possibly as the tail of a half-written record
      // -- would splice the two together into one unparseable line. Closing
      // here makes the abort record the genuinely last thing in the file.
      // `close()` is idempotent, so `finally` closing again is harmless.
      try {
        await sink.close();
      } catch (_) {
        // The sink failing is one of the two reasons we are here at all.
      }
      _writeAbortRecord(out, e);
      debugPrint('RECOG-C1: RUN ABORTED -- $e');
      debugPrint('$st');
      rethrow;
    } finally {
      // Closed even if the loop throws: a half-written JSONL whose last line
      // never reached disk is a measurement silently missing a row. Guarded,
      // because by Dart's `finally` semantics a throw here REPLACES the
      // exception already propagating -- so an unguarded close on a faulted
      // sink would hide the very error being reported.
      try {
        await sink.close();
      } catch (closeError) {
        debugPrint('RECOG-C1: closing the raw file also failed: $closeError');
      }
    }
    debugPrint('RECOG-C1: wrote ${out.path}');
  }

  /// The shared shape of every non-observation row. A control record exists to
  /// tell the offline analysis WHY a file is shorter than its plan, so the run
  /// id, the window and the timestamp are the minimum every one of them needs.
  Map<String, Object?> _controlRecord(String type, Map<String, Object?> extra) =>
      <String, Object?>{
        'record_type': type,
        'run_id': runId,
        'session_id': sessionId,
        'window': _window,
        'plan_sha256': _planSha256,
        'utc': DateTime.now().toUtc().toIso8601String(),
        ...extra,
      };

  /// Appends the abort record on its own file handle, and gives up loudly
  /// rather than throwing: this runs from inside a catch block, so an
  /// exception here would destroy the error it is trying to report.
  void _writeAbortRecord(File out, Object error) {
    try {
      out.writeAsStringSync(
        '${jsonEncode(_controlRecord(
          'run_aborted',
          <String, Object?>{'error': '$error'},
        ))}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (writeError) {
      debugPrint('RECOG-C1: could not record the abort ($writeError). The '
          'original error follows and is the one that matters.');
    }
  }

  /// What the raw file already says about this run.
  ///
  /// Read defensively: a truncated last line (killed mid-write) must not abort
  /// the resume, it must simply not count.
  @visibleForTesting
  RecogC1Journal readJournal(File out) {
    final observed = <String>{};
    final started = <String>{};
    if (!out.existsSync()) return RecogC1Journal(observed, started);
    for (final line in const LineSplitter().convert(out.readAsStringSync())) {
      if (line.trim().isEmpty) continue;
      try {
        final m = jsonDecode(line);
        if (m is! Map || m['observation_id'] is! String) continue;
        final id = m['observation_id'] as String;
        if (m['record_type'] == 'observation') observed.add(id);
        if (m['record_type'] == 'attempt_started') started.add(id);
      } catch (_) {
        // A partial final line. Ignore it; that observation simply re-runs.
      }
    }
    return RecogC1Journal(observed, started.difference(observed));
  }

  /// The observation ids already present in the output file.
  @visibleForTesting
  Set<String> alreadyObserved(File out) => readJournal(out).observed;

  @visibleForTesting
  String observationId(Map<String, String> row) =>
      '$runId-${row['pair_id']}-${row['arm']}-${row['attempt_no']}';

  @visibleForTesting
  Future<Map<String, Object?>> observe(
    Map<String, String> row,
    EquipmentAliasIndex index, {
    IOSink? journal,
  }) async {
    final cap = _Capture();
    final id = observationId(row);

    // The two arms share filenames -- 20260810_131311.jpg is both an original
    // and a crop -- so they live in SEPARATE directories. A single flat
    // directory would serve whichever arm was copied last, and the entire
    // measurement is a comparison between those two arms.
    final imageFile = File('$dir/images/${row['arm']}/${row['source_file']}');
    if (!imageFile.existsSync()) {
      throw StateError('missing input for arm ${row['arm']}: ${imageFile.path}');
    }

    // The run plan records the sha256 of the bytes each arm is supposed to
    // send. Checking the FILE here is the only thing tying "the photograph
    // this row is about" to "the photograph that was actually opened": a
    // stale or mixed-up corpus directory would otherwise produce a full set
    // of confident, well-formed, entirely wrong rows. A mismatch is a stop,
    // not a flag on the row -- a measurement of the wrong image is not a
    // measurement. (`sent_sha256` is a different thing: those are the bytes
    // AFTER the production `resizeForCloud`.)
    final sourceSha = sha256.convert(imageFile.readAsBytesSync()).toString();
    final expected = row['transformed_sha256'];
    if (expected != null && expected.isNotEmpty && sourceSha != expected) {
      throw StateError(
        'sha256 mismatch for arm ${row['arm']} ${row['source_file']}: the run '
        'plan says $expected, the file on the device is $sourceSha',
      );
    }

    // The production service, with the ONLY seam it already exposes for this.
    // No production code is modified to make this possible: the `ask:`
    // parameter is a public constructor argument that exists for tests.
    final service = GeminiVisualEquipmentService(
      index: Future<EquipmentAliasIndex>.value(index),
      ask: _recordingAsk(cap, row: row, id: id, journal: journal),
      timeout: serviceTimeout ?? const Duration(seconds: 30),
    );

    List<VisualMatch>? matches;
    String? classifyError;
    try {
      // `topK` deliberately left at the default: the shipped path calls
      // `service.classifyFile(path: path)` with no topK
      // (`visual_equipment_providers.dart:121`), so passing a number here --
      // even the same number -- would be a second place for it to drift.
      matches = await service.classifyFile(path: imageFile.path);
    } catch (e) {
      // `classifyFile` throws `VisualEquipmentException` for a malformed reply
      // AND for a transport failure — production's own conflation (plan item
      // C3). Recorded verbatim so the offline analysis can tell them apart by
      // whether a raw reply was captured, which production cannot.
      classifyError = '$e';
    }

    // A storage failure is NOT a recognition result. `classifyFile` above has
    // just swallowed it into `classifyError`, because the production service
    // wraps anything the ask throws, so without this the row would claim the
    // model failed when in fact the device could not write. Re-raised as the
    // original error so `run` records a `run_aborted` naming the real cause,
    // and so the run stops: every subsequent marker would fail the same way,
    // and a run that cannot account for its calls must not keep making them.
    final journalError = cap.journalError;
    if (journalError != null) throw journalError;

    // A client-side timeout leaves `cap.endUtc` unset: the production timeout
    // is applied OUTSIDE the injected ask
    // (`gemini_equipment_service.dart:147` — `_cloud(bytes).timeout(timeout)`),
    // and `Future.timeout` races a timer instead of cancelling the inner
    // future, so the recording closure has not run its catch yet. Stamping the
    // end here means every row has a duration, including the ones that ended
    // because we stopped waiting.
    cap.endUtc ??= DateTime.now().toUtc();

    ScanResult? result;
    if (matches != null) {
      // The REAL production classifier, not a reconstruction of it.
      result = ScanResult.fromMatches(matches, answeredOffline: false);
    }

    // A callable that RETURNED but carried no text is a MODEL/server failure,
    // not an operational one: the request reached the function and the
    // function answered. The frozen `classifyResponse` decides "operational"
    // from `rawReply == null`, which cannot tell that apart from never having
    // received a reply -- so the harness, which is the only layer that knows,
    // supplies the distinction by passing the empty string. The frozen
    // classifier then reaches `jsonDecode('')`, throws, and returns
    // `malformedParseFailure`: the model answered and the answer was unusable.
    // The taxonomy itself is untouched; `call_returned` is on the row so the
    // offline script can re-derive this rather than take it on trust.
    final replyForClassification =
        cap.callReturned ? (cap.rawReply ?? '') : cap.rawReply;
    final responseClass = classifyResponse(
      rawReply: replyForClassification,
      index: index,
      operationalError: cap.transportError != null,
    );

    // The FROZEN definition of an attempt that never reached the model, taken
    // from the contract rather than re-derived here: `classifyResponse` returns
    // `operationalFailure` exactly when the transport reported an error OR no
    // reply text was captured at all. That second half is what makes a
    // client-side timeout an operational failure even though `transport_error`
    // is null — and it is why the abort valve below must read THIS and not
    // `transport_error`, which a timeout never sets. Note that a MALFORMED
    // reply is deliberately not operational: the text was received, so the
    // model answered and the observation counts.
    final operationalFailure =
        responseClass == RecogC1ResponseClass.operationalFailure;

    return <String, Object?>{
      'record_type': 'observation',
      'run_id': runId,
      'session_id': sessionId,
      'observation_id': id,
      'source_sha': RecogC1Harness.sourceSha,
      'plan_sha256': _planSha256,
      'pair_id': row['pair_id'],
      'image_id': row['image_id'],
      'arm': row['arm'],
      'attempt_no': int.tryParse(row['attempt_no'] ?? '') ?? 1,
      'source_file': row['source_file'],
      'expected_sha256': row['transformed_sha256'],
      'source_sha256': sourceSha,
      'sent_sha256': cap.sentSha256,
      'sent_bytes': cap.sentBytes,
      'utc_start': cap.startUtc?.toIso8601String(),
      'utc_end': cap.endUtc?.toIso8601String(),
      'callable': kEquipmentRecognitionFunctionName,
      // See this file's header: the callable's contract carries no server-side
      // identifier, so this is null by fact, not by omission.
      'server_correlation_id': null,
      'server_correlation_note':
          'aiEquipmentRecognition returns { text } only; no server id exists '
              'in the response contract',
      'raw_reply': cap.rawReply,
      'call_returned': cap.callReturned,
      'transport_error': cap.transportError,
      // True for a transport error AND for a client-side timeout, which sets
      // no transport error at all. A reader must never infer "this attempt
      // reached the model" from `transport_error == null`.
      'operational_failure': operationalFailure,
      'error_code': cap.errorCode,
      'error_message': cap.errorMessage,
      'error_details': cap.errorDetails,
      'classify_error': classifyError,
      'response_class': responseClass.name,
      'candidates': matches
          ?.map((m) => <String, Object?>{
                'equipment_id': m.equipmentId,
                'confidence': m.confidence,
                'label_hint': m.labelHint,
                'source': m.source.name,
              })
          .toList(),
      'production_outcome': result?.outcome.name,
      'top1': (matches != null && matches.isNotEmpty)
          ? matches.first.confidence
          : null,
      'top2': (matches != null && matches.length > 1)
          ? matches[1].confidence
          : null,
      'lead': (matches != null && matches.length > 1)
          ? matches.first.confidence - matches[1].confidence
          : null,
    };
  }

  /// Wraps `cloudFunctionsEquipmentAsk()` — the EXACT function the shipped app
  /// calls — rather than re-assembling the callable here.
  ///
  /// An earlier version built the request itself from
  /// `buildEquipmentRecognitionRequest` / `extractEquipmentRecognitionText` in
  /// order to capture the whole reply map, which `cloudFunctionsEquipmentAsk`
  /// discards on the way to `text`. Two reasons that was worse and is gone:
  /// those helpers are `@visibleForTesting` and this file lives in `lib/`, so
  /// it was a real analyzer warning rather than a nuisance; and the whole map
  /// is `{ text }` and nothing else
  /// (`functions/src/ai_equipment_recognition.ts:165`), so capturing it added
  /// no information at all. Wrapping the production function keeps the request
  /// shape, the function name and the region incapable of drifting from what
  /// the app sends, for free.
  CloudRecognitionAsk _recordingAsk(
    _Capture cap, {
    required Map<String, String> row,
    required String id,
    IOSink? journal,
  }) {
    final real = cloudAsk ?? cloudFunctionsEquipmentAsk();
    return (Uint8List bytes) async {
      cap.sentSha256 = sha256.convert(bytes).toString();
      cap.sentBytes = bytes.length;
      cap.startUtc = DateTime.now().toUtc();

      // WRITE-AHEAD, and this is the only place it can go: after the exact
      // bytes are known and BEFORE the call that the server charges for.
      //
      // The quota is spent before the model runs, while the observation row is
      // written only after the answer comes back. Without this marker a
      // process death in between leaves nothing at all -- and on resume the
      // row looks untouched, so it runs again and pays twice for an answer
      // that may already have been given.
      //
      // The marker deliberately does NOT claim the call was charged. It claims
      // only that a call was about to be made, which is the strongest true
      // statement available at this instant. That is what makes it safe: a
      // crash BEFORE the call leaves a marker for a call that never happened,
      // and because a dangling marker is treated as UNCERTAIN rather than as
      // done, that photograph is never silently retired -- it is named for a
      // deliberate retry instead. A marker meaning "spent" would have had the
      // worse failure: a row that looks measured and never was.
      if (journal != null) {
        try {
          journal.writeln(jsonEncode(_controlRecord(
            'attempt_started',
            <String, Object?>{
              'observation_id': id,
              'pair_id': row['pair_id'],
              'arm': row['arm'],
              'attempt_no': int.tryParse(row['attempt_no'] ?? '') ?? 1,
              'image_id': row['image_id'],
              'sent_sha256': cap.sentSha256,
              'sent_bytes': cap.sentBytes,
            },
          )));
          await journal.flush();
        } catch (e) {
          // Fail CLOSED. If the marker cannot reach disk, the call must not
          // happen: a charged call nobody can account for is the single thing
          // this whole design exists to prevent, and proceeding would produce
          // exactly that. Throwing here also means the call is never made, so
          // nothing is spent.
          cap.journalError = e;
          rethrow;
        }
      }

      try {
        final reply = await real(bytes);
        cap.endUtc = DateTime.now().toUtc();
        cap.callReturned = true;
        cap.rawReply = reply;
        return reply;
      } on FirebaseFunctionsException catch (e) {
        cap.endUtc = DateTime.now().toUtc();
        cap.errorCode = e.code;
        cap.errorMessage = e.message;
        cap.errorDetails = e.details == null ? null : '${e.details}';
        cap.transportError = 'FirebaseFunctionsException(${e.code}): ${e.message}';
        rethrow;
      } catch (e) {
        cap.endUtc = DateTime.now().toUtc();
        cap.transportError = '$e';
        rethrow;
      }
    };
  }

  /// The run plan: one row per observation, in execution order. Reading it
  /// rather than generating it here is the point — the alternation rule is
  /// committed data a reviewer can check, not a line of code.
  @visibleForTesting
  List<Map<String, String>> readPlan(File f) {
    final lines = const LineSplitter().convert(f.readAsStringSync());
    final rows = <Map<String, String>>[];
    if (lines.isEmpty) return rows;
    final header = _splitCsv(lines.first);
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final cells = _splitCsv(line);
      if (cells.length != header.length) {
        throw StateError('run plan row has ${cells.length} cells, '
            'header has ${header.length}: $line');
      }
      rows.add({
        for (var i = 0; i < header.length; i++) header[i]: cells[i],
      });
    }
    return rows;
  }

  /// The run plan is generated by a committed tool that quotes every field,
  /// so this only has to undo that quoting — it is not a general CSV reader.
  List<String> _splitCsv(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          buf.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }
}
