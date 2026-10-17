// Journal parts of S04-26 (off the UI isolate, 100k budget) and S04-31
// (sanitising wrapper and global error handlers). Rows DT-26-1, 2, 4(partial), 5,
// 6 and DT-31-1, 2, 3 of docs/phase2/s04/S04_TEST_PLAN.md. DT-26-3 (S02 golden
// bytes), DT-26-7 (device), DT-31-4 (widgets) are other groups / NOT_RUN.
// Oracle: the plan rows and Design 2.5 / 10, not the code.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fitness_app/features/activity/data/native_session_id.dart';
import 'package:fitness_app/features/activity/repository/file_activity_journal.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/recording/journal/recording_codec.dart';
import 'package:fitness_app/features/recording/journal/file_recording_journal.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';
import 'package:fitness_app/features/recording/safety/recorder_safe_error.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart' show StopReason;
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/journal_fault_fs.dart';
import 'journal_kit.dart';

final String id1 = recId(1);

const List<String> kSentinelForms = [
  '12.3456789',
  '98.7654321',
  '12,3456789',
  '98,7654321',
  '12.34568',
  '98.76543',
];

bool hasSentinel(String text) => kSentinelForms.any(text.contains);

const PipelineSample kSentinelSample =
    PipelineSample(offsetMs: 1000, lat: kSentinelLat, lon: kSentinelLon, accuracyM: 4);

class SentinelRunner extends HeavyWorkRunner {
  const SentinelRunner();
  @override
  Future<R> run<P, R>(R Function(P input) fn, P input) async =>
      throw StateError('worker failed at $kSentinelLat,$kSentinelLon');
}

/// The "isolate boundary": a real isolate whose error text carries the sentinel.
class BoundaryRunner extends HeavyWorkRunner {
  const BoundaryRunner();
  @override
  Future<R> run<P, R>(R Function(P input) fn, P input) =>
      Isolate.run<R>(() => throw StateError('isolate failed at $kSentinelLat,$kSentinelLon'));
}

String describe(Object e, StackTrace? s) => '$e|${e.runtimeType}|${s ?? ''}';

void main() {
  group('DT-26-1 / DT-26-2 heavy work goes through the runner', () {
    test('DT-26-1 a full finish and a recovery read run decode, calculators and the S02 put through the runner', () async {
      final k = await RecKit.create();
      await k.record(id1, 12);
      await k.kill();
      final c0 = k.runner.calls;
      await k.journal.listUnfinished(); // the recovery decode
      expect(k.runner.calls, greaterThan(c0), reason: 'recovery decode ran through the runner');
      final c1 = k.runner.calls;
      await k.journal.seal(id1, const SealRequest(reason: StopReason.user));
      expect(k.runner.calls, greaterThan(c1), reason: 'seal (decode + verify) ran through the runner');
      final c2 = k.runner.calls;
      final a0 = k.activityRunner.calls;
      expect(await k.journal.handOff(id1), HandOffResult.done);
      expect(k.runner.calls, greaterThan(c2), reason: 'track build, smoothing and calculators ran through the runner');
      expect(k.activityRunner.calls, greaterThan(a0), reason: 'payload build, gzip, SHA-256 and seal of the put ran through the runner');
      await k.dispose();
    });

    test('DT-26-2 state/, pages/, widgets/ never call the heavy functions directly', () {
      final pattern = RegExp(
          r'analyseRecording\(|buildSessionSummary\(|encodeFrame\(|AesGcmJournalCipher|gzip|sha256|summary_builder\.dart|recording_codec\.dart|journal_cipher\.dart|dart:isolate');
      final hits = <String>[];
      var scanned = 0;
      for (final dir in ['state', 'pages', 'widgets']) {
        for (final e in Directory('lib/features/recording/$dir').listSync(recursive: true)) {
          if (e is! File || !e.path.endsWith('.dart')) continue;
          scanned++;
          final src = e.readAsStringSync().split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
          if (pattern.hasMatch(src)) hits.add(e.path);
        }
      }
      expect(scanned, greaterThan(10));
      expect(hits, isEmpty);
    });
  });

  group('DT-26-5 / DT-26-6 the 100k corpus (measure-only, then integrity)', () {
    test('F-100k: record, seal, hand off and reopen: equal content, no exception; timings recorded', () async {
      final k = await RecKit.create();
      const n = 100000;
      final sw = Stopwatch()..start();
      await k.journal.begin(k.meta(id1));
      for (var i = 1; i <= n; i++) {
        k.journal.enqueueSample(
            PipelineSample(
                offsetMs: i * 1000,
                lat: 47.0 + (i % 1000) * 0.00003,
                lon: 8.0 + (i ~/ 1000) * 0.0002,
                accuracyM: 5,
                altitudeM: 400 + (i % 50) * 0.2,
                speedMps: 3),
            GateCounters.zero);
        if (i % 1000 == 0) await Future<void>.delayed(Duration.zero);
      }
      await k.journal.flush();
      final tWrite = sw.elapsedMilliseconds;
      sw.reset();
      await k.journal.seal(id1, const SealRequest(reason: StopReason.user));
      final tSeal = sw.elapsedMilliseconds;
      await k.kill();
      sw.reset();
      final r = await k.journal.listUnfinished(); // SEALED -> silent hand-off; or offered
      final tOpen = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('DT-26-5 F-100k (JIT test timing, NOT a frame-budget proof): write=${tWrite}ms seal=${tSeal}ms open+hand-off=${tOpen}ms samples=$n');
      expect(r, isEmpty, reason: 'the sealed recording was handed off at recovery');
      final back = await k.activityReal.read(nativeActivityId(id1));
      expect(back, isNotNull);
      expect(back!.streamLost, isFalse);
      final gps = back.session.streams.values.firstWhere((s) => s.offsetsMs.length > 1000);
      expect(gps.offsetsMs.length, n, reason: 'seal then open: equal content');
      expect(gps.offsetsMs.first, 1000);
      expect(gps.offsetsMs.last, n * 1000);
      await k.dispose();
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  group('DT-31-1 a sanitising layer: no raw error leaves with the sentinel', () {
    test('/journal-decode: a sentinel inside a valid frame is a content-free damage code', () async {
      final k = await RecKit.create();
      await k.record(id1, 4);
      await k.kill();
      // append a well-formed, authenticated frame whose extra field carries the sentinel
      final c = k.cipher();
      final bad = encodeSentinelFrame(c, 2);
      final p = k.segPath(id1, 1);
      k.put(p, Uint8List.fromList([...k.bytesOf(p)!, ...bad]));
      final errors = <String>[];
      List<UnfinishedRecording>? r;
      try {
        r = await k.journal.listUnfinished();
      } catch (e, s) {
        errors.add(describe(e, s));
      }
      expect(errors, isEmpty);
      expect(r!.single.status, UnfinishedStatus.unreadable);
      expect(hasSentinel('${r.single.status} ${r.single.recordingId} ${r.single.sport}'), isFalse);
      await k.dispose();
    });

    test('/worker-entry: a throwing worker gives a bare RecordingJournalError and failedKept', () async {
      final k = await RecKit.create();
      await k.record(id1, 4);
      k.runnerOverride = const SentinelRunner();
      await k.kill();
      Object? err;
      StackTrace? st;
      try {
        await k.journal.seal(id1, const SealRequest(reason: StopReason.user));
      } catch (e, s) {
        err = e;
        st = s;
      }
      expect(err, isA<RecordingJournalError>());
      expect(hasSentinel(describe(err!, st)), isFalse, reason: 'message, type and stack carry no sentinel');
      expect((err as RecordingJournalError).code, 'unreadable');
      // the hand-off path
      k.runnerOverride = null;
      await k.kill();
      await k.journal.seal(id1, const SealRequest(reason: StopReason.user));
      k.runnerOverride = const SentinelRunner();
      await k.kill();
      expect(await k.journal.handOff(id1), HandOffResult.failedKept);
      expect((await k.journal.listUnfinished()).single.status, isNot(UnfinishedStatus.quarantined));
      await k.dispose();
    });

    test('/isolate-boundary: the error text of a real isolate does not cross', () async {
      final k = await RecKit.create();
      await k.record(id1, 4);
      k.runnerOverride = const BoundaryRunner();
      await k.kill();
      Object? err;
      StackTrace? st;
      try {
        await k.journal.seal(id1, const SealRequest(reason: StopReason.user));
      } catch (e, s) {
        err = e;
        st = s;
      }
      expect(err, isA<RecordingJournalError>());
      expect(hasSentinel(describe(err!, st)), isFalse);
      final r = await k.journal.listUnfinished();
      expect(r.single.status, UnfinishedStatus.unavailable,
          reason: 'a failed worker is retryable, not damage and not "recovered" (review C3)');
      expect(hasSentinel(r.toString()), isFalse);
      await k.dispose();
    });

    test('a raw file-system error escaping the journal is stripped by the sanitiser', () async {
      final k = await RecKit.create();
      await k.record(id1, 4);
      await k.kill();
      final probe = await RecKit.create(uid: 'user-p');
      await probe.record(id1, 4);
      await probe.kill();
      probe.fs.clearLog();
      await probe.journal.seal(id1, const SealRequest(reason: StopReason.user));
      final idx = probe.fs.log.firstWhere((o) => o.kind == FsOpKind.write && o.path.contains('SEALED')).index;
      await probe.dispose();
      k.fs.clearLog();
      k.fs.arm(FaultPlan(idx, FaultMode.failAt));
      Object? err;
      StackTrace? st;
      try {
        await k.journal.seal(id1, const SealRequest(reason: StopReason.user));
      } catch (e, s) {
        err = e;
        st = s;
      }
      expect(err, isNotNull);
      final safe = sanitizeRecorderError(err!);
      expect(hasSentinel(safe.toString()), isFalse);
      expect(hasSentinel(describe(safe, sanitizeRecorderStack(st!))), isFalse);
      await k.dispose();
    });
  });

  group('DT-31-2 sentinel flows reach no process-wide sink', () {
    test('record, kill-recover, finish and fail: zone, FlutterError, debugPrint and print see no sentinel', () async {
      final captured = <String>[];
      final zoneErrors = <String>[];
      final flutterErrors = <String>[];
      final oldOnError = FlutterError.onError;
      final oldDebugPrint = debugPrint;
      FlutterError.onError = (d) => flutterErrors.add('${d.exception}|${d.stack}');
      debugPrint = (String? m, {int? wrapWidth}) => captured.add(m ?? '');
      final done = Completer<void>();
      runZonedGuarded(() async {
        try {
          final k = await RecKit.create();
          // record with sentinel fixes
          await k.journal.begin(k.meta(id1));
          for (var i = 1; i <= 15; i++) {
            k.journal.enqueueSample(
                PipelineSample(offsetMs: i * 1000, lat: kSentinelLat + i * 1e-9, lon: kSentinelLon, accuracyM: 4, altitudeM: 12.3456789, speedMps: 3),
                GateCounters.zero);
          }
          await k.journal.flush();
          // kill-recover
          await k.kill();
          await k.journal.listUnfinished();
          await k.journal.openForResume(id1);
          await k.journal.flush();
          // finish
          await k.finish(id1);
          // fail: the store throws an error whose message carries the sentinel; the layer must not leak it
          await k.record(recId(2), 5);
          k.activity.putError = StateError('store failed for $kSentinelLat,$kSentinelLon');
          await k.finish(recId(2));
          k.activity.putError = null;
          k.runnerOverride = const SentinelRunner();
          await k.kill();
          await k.journal.listUnfinished();
          await k.journal.handOff(recId(2));
          // at rest: nothing readable
          for (final e in k.mem.files.entries) {
            expect(hasSentinel(String.fromCharCodes(e.value)), isFalse, reason: e.key);
          }
          await k.dispose();
          done.complete();
        } catch (e, s) {
          done.completeError(e, s);
        }
      }, (e, s) => zoneErrors.add('$e|$s'), zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => captured.add(line),
      ));
      try {
        await done.future;
      } finally {
        FlutterError.onError = oldOnError;
        debugPrint = oldDebugPrint;
      }
      expect(zoneErrors.where(hasSentinel), isEmpty, reason: '/zone-handler');
      expect(flutterErrors.where(hasSentinel), isEmpty, reason: '/recordFlutterFatalError');
      expect(captured.where(hasSentinel), isEmpty, reason: '/debugPrint-telemetry-sink and print');
      expect(zoneErrors, isEmpty, reason: 'no uncaught error at all');
    });
  });

  group('DT-31-3 no raw exception path in the journal', () {
    test('/no-raw-exception-reaches-a-global-handler: only fixed-code throws, no logging, no stack printing', () {
      final src = File('lib/features/recording/journal/file_recording_journal.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final throws = RegExp(r'\bthrow\b[^;]*;').allMatches(src).map((m) => m.group(0)!).toList();
      expect(throws, isNotEmpty);
      for (final t in throws) {
        expect(t.contains('RecordingJournalError('), isTrue, reason: 'only a fixed-code error is thrown: $t');
      }
      for (final bad in ['debugPrint(', 'print(', 'printStack', 'FlutterError', 'Zone.current', 'e.toString()', r"'$e'", r'${e}', 'e.message']) {
        expect(src.contains(bad), isFalse, reason: 'the journal must not format or log caught errors: $bad');
      }
      // the only rethrow keeps the original runtime TYPE for the code mapping, never reads its message
      expect(RegExp(r'\brethrow\b').allMatches(src).length, lessThanOrEqualTo(1));
    });

    test('RecordingJournalError carries a fixed code and no message', () {
      const e = RecordingJournalError('io');
      expect(e.toString(), 'RecordingJournalError(io)');
      expect(e.code, 'io');
    });
  });
}

/// A well-formed authenticated frame whose extra field carries the sentinel
/// (counter [n] continues the log): the schema check must reject it with a code.
Uint8List encodeSentinelFrame(AesGcmJournalCipher cipher, int n) {
  final plain = Uint8List.fromList(
      '{"k":"e","n":$n,"e":"pause","o":9000,"place":"$kSentinelLat,$kSentinelLon"}'.codeUnits);
  return encodeFrame(cipher, plain);
}
