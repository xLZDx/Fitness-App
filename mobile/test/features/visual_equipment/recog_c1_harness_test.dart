// RECOG-C1 — the harness's resume logic, which is what protects the quota.
//
// The harness runs from `main()`, so every restart of the app re-enters it: a
// crash, the operator reopening it, the OS reclaiming it in the background.
// Without a correct resume, one restart re-executes the whole window and
// spends a second set of the day's 60 recognition calls on photographs that
// were already measured — and, worse, appends a duplicate row for each of
// them, so the metric script would count the same observation twice.
//
// So these three helpers are load-bearing and are tested against the REAL
// committed run plan rather than a fixture: `readPlan`, `alreadyObserved` and
// `observationId`. The parts that talk to Firebase are not tested here and
// this file does not pretend otherwise — what is testable off-device is the
// bookkeeping, and the bookkeeping is where quota gets burned.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fitness_app/features/equipment/data/equipment_alias_index.dart';
import 'package:fitness_app/features/visual_equipment/measurement/recog_c1_contract.dart';
import 'package:fitness_app/features/visual_equipment/measurement/recog_c1_harness.dart';

const String _planPath = '../core/plans/RECOG_C1_RUN_PLAN_2026-09-05.csv';

/// A sink that fails exactly the way a full or detached volume does: every
/// operation throws, and the SECOND failure carries a different message from
/// the first. That difference is the whole point -- it makes "the original
/// error propagated" distinguishable from "the error raised while trying to
/// report the original error propagated", which is the defect being guarded.
class _FailingSink implements IOSink {
  /// [failOnWriteln] false is the REALISTIC shape and the default: a real
  /// `File.openWrite` sink buffers whatever `writeln` hands it and only
  /// discovers a full or detached volume when the bytes are actually pushed,
  /// which is `flush` or `close`. Throwing straight out of `writeln` would
  /// never let `await sink.flush()` be reached at all -- and that is the
  /// ordering the production comment names as the likely one. Both are worth
  /// covering because the two statements sit in one shared `try`, so a future
  /// narrowing of that block would break them apart.
  _FailingSink({this.failOnWriteln = false});

  final bool failOnWriteln;
  final List<String> calls = <String>[];
  bool _faulted = false;

  Never _fail(String call) {
    final first = !_faulted;
    _faulted = true;
    throw FileSystemException(
      first ? 'no space left on device' : 'sink is already faulted',
    );
  }

  @override
  void writeln([Object? object = '']) {
    calls.add('writeln');
    if (failOnWriteln) _fail('writeln');
    // Otherwise: buffered, exactly as a real sink would, and silently lost
    // when the flush below fails.
  }

  @override
  Future<void> flush() async {
    calls.add('flush');
    _fail('flush');
  }

  @override
  Future<void> close() async {
    calls.add('close');
    _fail('close');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late RecogC1Runner runner;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('recog_c1_harness_test');
    runner = RecogC1Runner(dir: tmp.path, runId: 'w1');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('the committed run plan', () {
    late List<Map<String, String>> rows;

    setUpAll(() {
      final f = File(_planPath);
      expect(f.existsSync(), isTrue, reason: 'missing ${f.absolute.path}');
    });

    setUp(() => rows = runner.readPlan(File(_planPath)));

    test('is 104 observations across two UTC windows', () {
      expect(rows.length, 104);
      final byWindow = <String, int>{};
      for (final r in rows) {
        byWindow[r['window']!] = (byWindow[r['window']] ?? 0) + 1;
      }
      // 26 pairs x 2 arms per window: the daily quota is 60 calls, so a window
      // of 52 leaves 8 calls of retry budget inside the same UTC day.
      expect(byWindow, {'1': 52, '2': 52});
    });

    test('keeps the two arms of a pair adjacent, and alternates their order',
        () {
      for (var i = 0; i < rows.length; i += 2) {
        final a = rows[i];
        final b = rows[i + 1];
        expect(b['pair_id'], a['pair_id'],
            reason: 'the two arms of a pair must be adjacent in time');
        expect({a['arm'], b['arm']}, {'A', 'B'});
        // The frozen alternation rule: even pair index runs A first, odd runs
        // B first, so within-pair drift cancels instead of landing on one arm.
        final k = int.parse(a['pair_index']!);
        expect(a['arm'], k.isEven ? 'A' : 'B',
            reason: 'pair $k starts with the wrong arm');
      }
    });

    test('gives every observation a distinct id', () {
      final ids = rows.map(runner.observationId).toSet();
      expect(ids.length, rows.length);
    });

    test('an id changes with the ATTEMPT, so a retry never looks already-done',
        () {
      // Not covered by the uniqueness test above, and provably so: every one
      // of the 104 committed rows is `attempt_no` 1, and (pair_id, arm) is
      // already unique across all of them -- so that test would still pass
      // with `attempt_no` dropped from the id entirely. It matters because a
      // retry is defined as a fresh run REUSING a pair id with a higher
      // attempt number: if the id ignored `attempt_no`, `alreadyObserved`
      // would recognise the first attempt's id and skip the retry, leaving a
      // photograph permanently unmeasured while the file claims otherwise.
      final one = <String, String>{
        'pair_id': 'p07',
        'arm': 'A',
        'attempt_no': '1',
      };
      final two = <String, String>{...one, 'attempt_no': '2'};
      expect(runner.observationId(one), isNot(runner.observationId(two)));
    });

    test('an id changes with the arm, so the two arms never collide', () {
      final a = rows.firstWhere((r) => r['arm'] == 'A');
      final b = rows.firstWhere(
          (r) => r['arm'] == 'B' && r['pair_id'] == a['pair_id']);
      expect(runner.observationId(a), isNot(runner.observationId(b)));
    });
  });

  group('resume', () {
    File writeRaw(List<String> lines) {
      final f = File('${tmp.path}/recog_c1_raw_w1.jsonl');
      f.writeAsStringSync('${lines.join('\n')}\n');
      return f;
    }

    test('an absent file means nothing has been observed', () {
      expect(runner.alreadyObserved(File('${tmp.path}/nope.jsonl')), isEmpty);
    });

    test('completed observations are remembered', () {
      final f = writeRaw([
        jsonEncode({'record_type': 'observation', 'observation_id': 'w1-p00-A-1'}),
        jsonEncode({'record_type': 'observation', 'observation_id': 'w1-p00-B-1'}),
      ]);
      expect(runner.alreadyObserved(f), {'w1-p00-A-1', 'w1-p00-B-1'});
    });

    test('a truncated final line does not count as done, and does not throw',
        () {
      // The process can be killed between `writeln` and `flush`. That
      // observation must simply re-run — losing it is a missing row, but
      // COUNTING it would mean a photograph silently never measured.
      final f = writeRaw([
        jsonEncode({'record_type': 'observation', 'observation_id': 'w1-p00-A-1'}),
        '{"record_type":"observation","observation_id":"w1-p00-B',
      ]);
      expect(runner.alreadyObserved(f), {'w1-p00-A-1'});
    });

    test('a control record is not mistaken for a completed observation', () {
      // `run_aborted` carries a run id but no observation; treating it as done
      // would silently skip whichever row it happened to resemble.
      final f = writeRaw([
        jsonEncode({'record_type': 'observation', 'observation_id': 'w1-p00-A-1'}),
        jsonEncode({
          'record_type': 'run_aborted',
          'run_id': 'w1',
          'observation_id': 'w1-p00-B-1',
          'error': 'sha256 mismatch',
        }),
      ]);
      expect(runner.alreadyObserved(f), {'w1-p00-A-1'});
    });

    test('blank lines are ignored', () {
      final f = writeRaw([
        '',
        jsonEncode({'record_type': 'observation', 'observation_id': 'w1-p00-A-1'}),
        '   ',
      ]);
      expect(runner.alreadyObserved(f), {'w1-p00-A-1'});
    });

    test('the ids it returns are the ids the plan would generate', () {
      // The whole mechanism is worthless if the two sides spell an id
      // differently, so this joins them rather than trusting the format.
      final rows = runner.readPlan(File(_planPath));
      final first = rows.first;
      final f = writeRaw([
        jsonEncode({
          'record_type': 'observation',
          'observation_id': runner.observationId(first),
        }),
      ]);
      expect(runner.alreadyObserved(f).contains(runner.observationId(first)),
          isTrue);
    });
  });

  group('the run plan reader is strict', () {
    test('a row with the wrong cell count is a stop, not a shifted row', () {
      final f = File('${tmp.path}/bad.csv')
        ..writeAsStringSync('"a","b","c"\n"1","2"\n');
      expect(() => runner.readPlan(f), throwsA(isA<StateError>()));
    });

    test('quoted cells containing commas survive', () {
      final f = File('${tmp.path}/q.csv')
        ..writeAsStringSync('"a","b"\n"one, two","3"\n');
      expect(runner.readPlan(f).single['a'], 'one, two');
    });
  });

  group('a client-side timeout is an operational failure', () {
    // The regression for the review MAJOR. The production client-side budget
    // is applied OUTSIDE the injected ask
    // (`gemini_equipment_service.dart:147` — `_cloud(bytes).timeout(timeout)`)
    // and `Future.timeout` races a timer instead of cancelling the inner
    // future, so on a timeout the recording closure has NOT thrown and
    // `transport_error` stays null. The abort valve used to read that field,
    // which meant the exact stall this codebase has already hit in production
    // reset the counter to zero and let the run grind through the rest of the
    // window against a wall — spending real quota, since the server charges
    // before the model call.

    late Directory work;
    late EquipmentAliasIndex index;

    setUpAll(() {
      // `cropToViewfinder`/`resizeForCloud` run through `compute`.
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() {
      work = Directory.systemTemp.createTempSync('recog_c1_timeout');
      Directory('${work.path}/images/A').createSync(recursive: true);
      index = EquipmentAliasIndex.fromJson(const {
        'treadmill': ['treadmill'],
      });
    });

    tearDown(() => work.deleteSync(recursive: true));

    Map<String, String> writeImage() {
      final bytes = img.encodeJpg(img.Image(width: 64, height: 48), quality: 90);
      final f = File('${work.path}/images/A/probe.jpg')
        ..writeAsBytesSync(bytes);
      return {
        'pair_id': 'p00',
        'arm': 'A',
        'attempt_no': '1',
        'window': '1',
        'image_id': 'probe',
        'source_file': 'probe.jpg',
        'transformed_sha256': sha256.convert(f.readAsBytesSync()).toString(),
      };
    }

    test('is flagged operational even though transport_error is null', () async {
      final row = writeImage();
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 't',
        // Never completes: the production timeout is what ends the wait.
        cloudAsk: (_) => Completer<String?>().future,
        serviceTimeout: const Duration(milliseconds: 50),
      );

      final record = await runner.observe(row, index);

      expect(record['transport_error'], isNull,
          reason: 'a timeout genuinely leaves this unset — that is the trap');
      expect(record['operational_failure'], isTrue,
          reason: 'the abort valve reads THIS, and must fire on a timeout');
      expect(record['response_class'],
          RecogC1ResponseClass.operationalFailure.name);
      expect(record['raw_reply'], isNull);
      expect(record['production_outcome'], isNull);
      expect(record['classify_error'], isNotNull,
          reason: 'production surfaces the timeout as VisualEquipmentException');
      expect(record['utc_end'], isNotNull,
          reason: 'every row carries a duration, including the abandoned ones');
    });

    test('the bytes actually opened are hashed and recorded', () async {
      final row = writeImage();
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 't',
        cloudAsk: (_) => Completer<String?>().future,
        serviceTimeout: const Duration(milliseconds: 50),
      );
      final record = await runner.observe(row, index);
      expect(record['source_sha256'], row['transformed_sha256']);
    });

    test('a photograph that is not the one the plan names is a stop', () async {
      // The only thing tying "the row this observation is about" to "the file
      // that was opened". A stale corpus directory would otherwise produce a
      // full set of confident, well-formed, entirely wrong rows.
      final row = writeImage()..['transformed_sha256'] = 'not-the-right-hash';
      final runner = RecogC1Runner(dir: work.path, runId: 't');
      expect(() => runner.observe(row, index), throwsA(isA<StateError>()));
    });

    test('a missing input for this arm is a stop, not an empty row', () async {
      final row = writeImage()..['source_file'] = 'absent.jpg';
      final runner = RecogC1Runner(dir: work.path, runId: 't');
      expect(() => runner.observe(row, index), throwsA(isA<StateError>()));
    });

    test('a call that RETURNED with no text is a model failure, not an '
        'operational one', () async {
      // The distinction the frozen `classifyResponse` cannot make on its own:
      // it decides "operational" from `rawReply == null`
      // (`recog_c1_contract.dart:166`), which reads identically for "the
      // function answered with nothing" and "we never reached the function".
      // Production itself throws on that reply
      // (`gemini_equipment_service.dart:263` — "cloud recognition returned no
      // answer") and sets no transport error, so without this the harness
      // would file a server that answered uselessly under the one class the
      // contract excludes from every semantic denominator — quietly deflating
      // the measured model-failure rate.
      final row = writeImage();
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 't',
        cloudAsk: (_) async => null,
      );

      final record = await runner.observe(row, index);

      expect(record['call_returned'], isTrue,
          reason: 'the request did reach the function and the function replied');
      expect(record['transport_error'], isNull);
      expect(record['operational_failure'], isFalse,
          reason: 'the abort valve must NOT count a useless answer as a stall');
      expect(record['response_class'],
          RecogC1ResponseClass.malformedParseFailure.name);
      expect(record['classify_error'], isNotNull,
          reason: 'production surfaces it as VisualEquipmentException');
    });

    test('a call that never returned is still operational', () async {
      // The other side of the same seam: `call_returned` must not turn every
      // genuine transport failure into a model failure.
      final row = writeImage();
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 't',
        cloudAsk: (_) async => throw Exception('socket closed'),
      );

      final record = await runner.observe(row, index);

      expect(record['call_returned'], isFalse);
      expect(record['transport_error'], contains('socket closed'));
      expect(record['operational_failure'], isTrue);
      expect(record['response_class'],
          RecogC1ResponseClass.operationalFailure.name);
    });
  });

  group('the production entry point fails closed', () {
    test('a build with no RECOG_C1_WINDOW refuses to run', () {
      // The state of THIS test process is the state of a harness APK built
      // with the enable flag and one forgotten define. `RECOG_C1_WINDOW` has
      // no non-zero default and 0 means "every row", so before this guard that
      // build ran all 104 observations inside one UTC day against a 60-call
      // allowance -- burning through the wall and then spending the remainder
      // failing. Forgetting a define was more dangerous than passing a wrong
      // one, which is the wrong way round for the resource this whole design
      // exists to protect.
      final problem = RecogC1Runner.configurationProblem();
      expect(problem, isNotNull,
          reason: 'no defines are set in a flutter test run, so this must '
              'refuse -- if it ever returns null here, the guard is gone');
      expect(problem, contains('RECOG_C1_'));
    });

    test('an otherwise complete configuration is still refused for the window',
        () {
      // Isolates the window check. Asserting only "something was refused" is
      // satisfied by any one of the five guards, so it cannot tell whether
      // THIS one exists -- a mutation deleting it left that assertion green.
      String? withWindow(int w) => RecogC1Runner.configurationProblem(
            dir: '/sdcard/recog',
            runId: 'w1',
            planSha: 'a' * 64,
            sourceSha: 'b' * 40,
            window: w,
          );
      for (final bad in const [0, 3, -1]) {
        expect(withWindow(bad), contains('RECOG_C1_WINDOW'),
            reason: 'window $bad must be refused; 0 in particular means '
                '"every row", which is 104 calls against a 60-call day');
      }
      expect(withWindow(1), isNull,
          reason: 'a complete configuration must be accepted, or the guard is '
              'just a refusal to run at all');
      expect(withWindow(2), isNull);
    });

    test('each remaining input is refused on its own', () {
      String? probe({
        String dir = '/sdcard/recog',
        String runId = 'w1',
        int window = 1,
        String planSha = 'aaaa',
        String sourceSha = 'bbbb',
      }) =>
          RecogC1Runner.configurationProblem(
            dir: dir,
            runId: runId,
            window: window,
            planSha: planSha,
            sourceSha: sourceSha,
          );
      expect(probe(dir: ''), contains('RECOG_C1_DIR'));
      expect(probe(runId: ''), contains('RECOG_C1_RUN_ID'));
      expect(probe(planSha: ''), contains('RECOG_C1_PLAN_SHA'));
      expect(probe(sourceSha: ''), contains('RECOG_C1_SOURCE_SHA'));
      expect(probe(), isNull);
    });

  });

  group('the instrument is bound to the artifacts it claims', () {
    late Directory work;

    setUp(() {
      work = Directory.systemTemp.createTempSync('recog_c1_bind');
      Directory('${work.path}/images/A').createSync(recursive: true);
    });

    tearDown(() => work.deleteSync(recursive: true));

    File writeTinyPlan({int rows = 1, String window = '1'}) {
      final bytes = img.encodeJpg(img.Image(width: 32, height: 24), quality: 90);
      final sha = sha256.convert(bytes).toString();
      final lines = <String>[];
      for (var i = 0; i < rows; i++) {
        File('${work.path}/images/A/p$i.jpg').writeAsBytesSync(bytes);
        lines.add('"${i + 1}","$window","p$i","$i","p$i","A","1","p$i.jpg",'
            '"$sha"');
      }
      final f = File('${work.path}/run_plan.csv');
      f.writeAsStringSync(
        '"seq","window","pair_id","pair_index","image_id","arm",'
        '"attempt_no","source_file","transformed_sha256"\n'
        '${lines.join('\n')}\n',
      );
      return f;
    }

    test('a run plan that is not the one this build was compiled for is a stop',
        () async {
      // Before this, the instrument validated itself in a circle: `observe`
      // checked each image against a hash it read out of the very plan under
      // suspicion, so a stale plan pushed together with its own matching
      // images passed every check on both sides perfectly, and the day's calls
      // were spent measuring the wrong instrument.
      writeTinyPlan();
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'bind',
        expectedPlanShaOverride: 'a-different-plan-entirely',
        cloudAsk: (_) async => '{"machine": "treadmill", "confidence": 0.9}',
        gapSecondsOverride: 0,
      );
      await expectLater(
        runner.run(),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('run plan sha256'))),
      );
    });

    test('a window that is not 52 rows across 26 pairs is a stop', () async {
      // The window is only a protection if it is the size the quota maths
      // assumed. A plan edited down to 40 rows would run happily and produce a
      // measurement nobody could compare to the other window.
      writeTinyPlan(rows: 2);
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'bind',
        windowOverride: 1,
        cloudAsk: (_) async => '{"machine": "treadmill", "confidence": 0.9}',
        gapSecondsOverride: 0,
      );
      await expectLater(
        runner.run(),
        throwsA(isA<StateError>()
            .having((e) => '$e', 'message', contains('52 rows / 26 pairs'))),
      );
    });

    test('every row carries the plan hash and the session that produced it',
        () async {
      writeTinyPlan();
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'bind',
        cloudAsk: (_) async => '{"machine": "treadmill", "confidence": 0.9}',
        gapSecondsOverride: 0,
      );
      await runner.run();

      final records = File('${work.path}/recog_c1_raw_bind.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();
      final observation =
          records.firstWhere((r) => r['record_type'] == 'observation');
      expect(observation['plan_sha256'], isNotNull);
      expect(observation['plan_sha256'], hasLength(64));
      expect(observation['session_id'], runner.sessionId);
      expect(runner.sessionId, isNot(RecogC1Runner(dir: '', runId: '').sessionId),
          reason: 'two invocations must be distinguishable, or a pair split '
              'across a restart looks contiguous');
    });
  });

  group('a call that may have been charged is never silently retired', () {
    late Directory work;

    setUp(() {
      work = Directory.systemTemp.createTempSync('recog_c1_wal');
      Directory('${work.path}/images/A').createSync(recursive: true);
    });

    tearDown(() => work.deleteSync(recursive: true));

    File writePlan({int rows = 1}) {
      final bytes = img.encodeJpg(img.Image(width: 32, height: 24), quality: 90);
      final sha = sha256.convert(bytes).toString();
      final lines = <String>[];
      for (var i = 0; i < rows; i++) {
        File('${work.path}/images/A/p$i.jpg').writeAsBytesSync(bytes);
        lines.add('"${i + 1}","1","p$i","$i","p$i","A","1","p$i.jpg","$sha"');
      }
      final f = File('${work.path}/run_plan.csv');
      f.writeAsStringSync(
        '"seq","window","pair_id","pair_index","image_id","arm",'
        '"attempt_no","source_file","transformed_sha256"\n'
        '${lines.join('\n')}\n',
      );
      return f;
    }

    test('the marker is durable BEFORE the charged call is made', () async {
      // The quota is charged before the model runs; the observation is written
      // only after the answer comes back. This asserts the ordering that makes
      // a death in between recoverable -- read from inside the call itself,
      // which is the only instant where the question has a meaningful answer.
      writePlan();
      List<Map<String, Object?>>? seenAtCallTime;
      final out = File('${work.path}/recog_c1_raw_wal.jsonl');
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'wal',
        gapSecondsOverride: 0,
        cloudAsk: (_) async {
          seenAtCallTime = out
              .readAsLinesSync()
              .where((l) => l.trim().isNotEmpty)
              .map((l) => jsonDecode(l) as Map<String, Object?>)
              .toList();
          return '{"machine": "treadmill", "confidence": 0.9}';
        },
      );
      await runner.run();

      expect(seenAtCallTime, isNotNull);
      final marker = seenAtCallTime!
          .where((r) => r['record_type'] == 'attempt_started')
          .toList();
      expect(marker, hasLength(1),
          reason: 'without a durable marker at this instant, a crash here '
              'spends a charged call that leaves no trace at all');
      expect(marker.single['observation_id'], 'wal-p0-A-1');
      expect(marker.single['sent_sha256'], isNotNull,
          reason: 'the marker names the exact bytes that were about to be '
              'sent, so a later retry can prove it is repeating the same call');
    });

    test('a dangling marker is neither re-run nor counted as done', () async {
      // The crash case, reconstructed: a marker on disk with no observation.
      // Re-running would pay twice for an answer possibly already given;
      // treating it as done would retire a photograph that was never measured.
      // It is neither -- it is named for a deliberate retry.
      writePlan();
      File('${work.path}/recog_c1_raw_wal.jsonl').writeAsStringSync(
        '${jsonEncode({
              'record_type': 'attempt_started',
              'run_id': 'wal',
              'observation_id': 'wal-p0-A-1',
            })}\n',
      );

      var calls = 0;
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'wal',
        gapSecondsOverride: 0,
        cloudAsk: (_) async {
          calls++;
          return '{"machine": "treadmill", "confidence": 0.9}';
        },
      );
      await runner.run();

      expect(calls, 0, reason: 'an uncertain attempt must not be re-charged');
      final records = File('${work.path}/recog_c1_raw_wal.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();
      final control = records
          .firstWhere((r) => r['record_type'] == 'attempts_uncertain');
      expect(control['observation_ids'], ['wal-p0-A-1']);
      expect(
          RecogC1Runner(dir: work.path, runId: 'wal')
              .alreadyObserved(File('${work.path}/recog_c1_raw_wal.jsonl')),
          isEmpty,
          reason: 'uncertain is not done');
    });

    test('a marker that cannot be made durable stops the run before the call',
        () async {
      // Fail closed. If the marker cannot reach disk there is no safe way to
      // proceed: making the call anyway produces the exact unaccounted charge
      // the marker exists to prevent. Also guards a regression I introduced
      // and this test caught -- the marker failure was being swallowed into
      // `classify_error`, so a full disk would have been recorded as a model
      // failure and the real cause lost.
      writePlan();
      var calls = 0;
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'wal',
        gapSecondsOverride: 0,
        openSink: (_) => _FailingSink(),
        cloudAsk: (_) async {
          calls++;
          return '{"machine": "treadmill", "confidence": 0.9}';
        },
      );

      await expectLater(
        runner.run(),
        throwsA(isA<FileSystemException>().having(
            (e) => e.message, 'message', contains('no space left on device'))),
        reason: 'the storage failure must surface as itself, not as a '
            'recognition failure on the row',
      );
      expect(calls, 0, reason: 'nothing may be spent once the journal is gone');
    });

    test('a pair split across a restart is named, not silently compared',
        () async {
      // The crop comparison rests entirely on A and B running back to back.
      // A resume ten minutes later still produces two rows sharing a pair_id
      // and sitting next to each other in the file, so without this record
      // step 8 cannot tell a contiguous pair from a broken one.
      final bytes = img.encodeJpg(img.Image(width: 32, height: 24), quality: 90);
      final sha = sha256.convert(bytes).toString();
      Directory('${work.path}/images/B').createSync(recursive: true);
      File('${work.path}/images/A/p0.jpg').writeAsBytesSync(bytes);
      File('${work.path}/images/B/p0.jpg').writeAsBytesSync(bytes);
      File('${work.path}/run_plan.csv').writeAsStringSync(
        '"seq","window","pair_id","pair_index","image_id","arm",'
        '"attempt_no","source_file","transformed_sha256"\n'
        '"1","1","p0","0","p0","A","1","p0.jpg","$sha"\n'
        '"2","1","p0","0","p0","B","1","p0.jpg","$sha"\n',
      );
      // Arm A already durable from an earlier session.
      File('${work.path}/recog_c1_raw_wal.jsonl').writeAsStringSync(
        '${jsonEncode({
              'record_type': 'observation',
              'run_id': 'wal',
              'session_id': 'anearlierone',
              'observation_id': 'wal-p0-A-1',
            })}\n',
      );

      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'wal',
        gapSecondsOverride: 0,
        cloudAsk: (_) async => '{"machine": "treadmill", "confidence": 0.9}',
      );
      await runner.run();

      final records = File('${work.path}/recog_c1_raw_wal.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();
      final split =
          records.firstWhere((r) => r['record_type'] == 'pairs_split_by_resume');
      expect(split['pair_ids'], ['p0']);
      // The B observation still runs -- it is a valid single-arm measurement.
      expect(
          records.where((r) =>
              r['record_type'] == 'observation' &&
              r['observation_id'] == 'wal-p0-B-1'),
          hasLength(1));
    });
  });

  group('an abort is recorded even when the sink is what failed', () {
    // The review MAJOR. The `run_aborted` record used to be written through
    // the very `IOSink` whose failure is one of the two things that reaches
    // that catch block, with no independent path: on a storage failure the
    // record could not be written, the secondary exception replaced the real
    // one, and `rethrow` never ran. A run that died of a full disk would look,
    // in the raw file, exactly like a run that was planned short.

    late Directory work;

    setUp(() {
      work = Directory.systemTemp.createTempSync('recog_c1_abort');
      Directory('${work.path}/images/A').createSync(recursive: true);
    });

    tearDown(() => work.deleteSync(recursive: true));

    File writePlan(String transformedSha) {
      // One row, whose sha deliberately does not match the file, so `observe`
      // throws inside the loop and the abort path runs for real.
      final f = File('${work.path}/run_plan.csv');
      f.writeAsStringSync(
        '"seq","window","pair_id","pair_index","image_id","arm","attempt_no",'
        '"source_file","transformed_sha256"\n'
        '"1","1","p00","0","probe","A","1","probe.jpg","$transformedSha"\n',
      );
      return f;
    }

    test('the record survives the loop throwing, and the original error is '
        'the one that propagates', () async {
      File('${work.path}/images/A/probe.jpg').writeAsBytesSync(
          img.encodeJpg(img.Image(width: 32, height: 24), quality: 90));
      writePlan('deliberately-not-the-hash');

      final runner = RecogC1Runner(dir: work.path, runId: 'ab');

      await expectLater(
        runner.run(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('sha256 mismatch'))),
        reason: 'the sha mismatch, not a secondary write failure, is what the '
            'caller must see',
      );

      final lines = File('${work.path}/recog_c1_raw_ab.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();
      expect(lines, hasLength(1));
      expect(lines.single['record_type'], 'run_aborted');
      expect(lines.single['run_id'], 'ab');
      expect('${lines.single['error']}', contains('sha256 mismatch'));
    });

    Future<void> checkFailingSink({required bool failOnWriteln}) async {
      // THE regression for the MAJOR, and the only one of these that fails
      // against the unfixed code. The other tests in this group drive the
      // abort path with a healthy sink, where writing the record through it
      // works perfectly well -- which is exactly why they cannot prove
      // anything about the case the finding is about. Here the sink is the
      // thing that broke, which is one of the two ways this catch block is
      // ever reached in a real run.
      final bytes = img.encodeJpg(img.Image(width: 32, height: 24), quality: 90);
      File('${work.path}/images/A/probe.jpg').writeAsBytesSync(bytes);
      // A sha that MATCHES, so the observation itself succeeds and the sink is
      // unambiguously the only thing that fails.
      writePlan(sha256.convert(bytes).toString());

      final sink = _FailingSink(failOnWriteln: failOnWriteln);
      final out = File('${work.path}/recog_c1_raw_ab2.jsonl');
      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'ab2',
        cloudAsk: (_) async => '{"machine": "treadmill", "confidence": 0.9}',
        openSink: (_) => sink,
      );

      await expectLater(
        runner.run(),
        throwsA(isA<FileSystemException>().having(
            (e) => e.message, 'message', contains('no space left on device'))),
        reason: 'the ORIGINAL storage error must reach the caller -- not a '
            'secondary failure from trying to report it on the same sink',
      );

      expect(out.existsSync(), isTrue,
          reason: 'an abort with nothing written is an invisible abort: the '
              'raw file would be indistinguishable from a run planned short');
      final records = out
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();
      expect(records.single['record_type'], 'run_aborted');
      expect('${records.single['error']}', contains('no space left on device'));
      expect(sink.calls, contains('close'),
          reason: 'the sink is closed before the record is written, so a '
              'half-written line cannot be spliced onto the abort line');
    }

    test('a sink whose FLUSH fails still produces the record, and the storage '
        'error is the one that propagates', () async {
      // The realistic ordering, and the one the production comment names:
      // `writeln` buffers happily, and the volume error surfaces only when the
      // bytes are pushed. The observation row that was queued is genuinely
      // lost -- which is the whole reason a `run_aborted` record has to exist
      // and has to be written some other way.
      await checkFailingSink(failOnWriteln: false);
    });

    test('a sink whose WRITELN fails still produces the record, and the '
        'storage error is the one that propagates', () async {
      // The other side of the same shared `try`. Both statements sit in one
      // catch today, so these two currently exercise the same recovery path --
      // the point is that they would stop doing so the moment anyone narrows
      // that block, which is exactly when the difference would start to matter.
      await checkFailingSink(failOnWriteln: true);
    });

    test('hitting the consecutive-failure threshold leaves a record saying so',
        () async {
      // The stop condition MOST likely to actually fire -- it is the quota
      // wall -- used to `break` with nothing on disk. The resulting short
      // JSONL was indistinguishable from a run that was killed and from a
      // window that was planned short, which is the exact ambiguity the
      // `run_aborted` record exists to remove for the other stop condition.
      final bytes = img.encodeJpg(img.Image(width: 32, height: 24), quality: 90);
      final sha = sha256.convert(bytes).toString();
      final rows = <String>[];
      for (var i = 0; i < 5; i++) {
        File('${work.path}/images/A/p$i.jpg').writeAsBytesSync(bytes);
        rows.add('"${i + 1}","1","p$i","$i","p$i","A","1","p$i.jpg","$sha"');
      }
      File('${work.path}/run_plan.csv').writeAsStringSync(
        '"seq","window","pair_id","pair_index","image_id","arm",'
        '"attempt_no","source_file","transformed_sha256"\n'
        '${rows.join('\n')}\n',
      );

      final runner = RecogC1Runner(
        dir: work.path,
        runId: 'cf',
        // Every call fails operationally, which is what the quota wall looks
        // like from the client.
        cloudAsk: (_) async => throw Exception('resource-exhausted'),
        gapSecondsOverride: 0,
      );
      await runner.run();

      final records = File('${work.path}/recog_c1_raw_cf.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .map((l) => jsonDecode(l) as Map<String, Object?>)
          .toList();

      final observations =
          records.where((r) => r['record_type'] == 'observation').toList();
      expect(observations, hasLength(3),
          reason: 'the default threshold is 3 consecutive failures');
      expect(records.last['record_type'], 'run_stopped_consecutive_failures');
      expect(records.last['consecutive_failures'], 3);
      expect(records.last['observations_written'], 3);
      expect(records.last['observations_left_unrun'], 2,
          reason: 'the analysis must be able to see the window was cut short '
              'deliberately, without inferring it from a row count');
      expect(records.last['run_id'], 'cf');
    });

    test('the stop record is not mistaken for a completed observation', () {
      // Otherwise resuming after a quota wall would skip whichever row the
      // control record happened to resemble.
      final f = File('${work.path}/stop.jsonl')
        ..writeAsStringSync('${jsonEncode({
              'record_type': 'run_stopped_consecutive_failures',
              'run_id': 'cf',
              'observation_id': 'cf-p00-A-1',
            })}\n');
      expect(RecogC1Runner(dir: work.path, runId: 'cf').alreadyObserved(f),
          isEmpty);
    });

    test('the abort record is not mistaken for a completed observation', () {
      // Belt and braces with the resume group above: the two mechanisms have
      // to agree, or a run that aborted would resume by skipping the row it
      // died on.
      final f = File('${work.path}/x.jsonl')
        ..writeAsStringSync('${jsonEncode({
              'record_type': 'run_aborted',
              'run_id': 'ab',
              'error': 'x',
            })}\n');
      expect(RecogC1Runner(dir: work.path, runId: 'ab').alreadyObserved(f),
          isEmpty);
    });
  });
}
