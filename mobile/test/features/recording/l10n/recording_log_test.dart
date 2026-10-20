// S04-27 (DT-27-1 log half, DT-27-2): the log mapper emits only a fixed scope,
// a bare code and a type name.
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/l10n/recording_log.dart';

class _LeakyError implements Exception {
  @override
  String toString() => 'lat=12.3456789 lon=-98.7654321 /data/user/0/app/f';
}

void main() {
  late List<String> lines;
  setUp(() {
    lines = [];
    recorderLogSink = lines.add;
  });
  tearDown(() => recorderLogSink = null);

  group('recorderLogLine', () {
    test('format is recorder.<scope> code=<code> type=<type>', () {
      expect(recorderLogLine('journal.put', StateError('x')),
          'recorder.journal.put code=invariant type=StateError');
    });

    test('the exception text never appears', () {
      final line = recorderLogLine('s', _LeakyError());
      expect(line, 'recorder.s code=unknown type=_LeakyError');
      expect(line.contains('12.3456789'), isFalse);
      expect(line.contains('98.7654321'), isFalse);
      expect(line.contains('/data/user'), isFalse);
    });

    test('a hostile scope is reduced to identifier characters', () {
      final line = recorderLogLine('a b=12.3456789,\n/x;y-z', StateError('x'));
      expect(line.contains(' b='), isFalse);
      expect(line.contains('\n'), isFalse);
      expect(line.startsWith('recorder.ab12.3456789xyz'), isTrue,
          reason: 'digits and dots are identifier characters; spaces, '
              'commas, slashes, newlines and = are dropped');
    });
  });

  group('sanitizeScope', () {
    test('keeps letters, digits, underscore and dot', () {
      expect(sanitizeScope('Ab_9.z'), 'Ab_9.z');
    });
    test('drops everything else', () {
      expect(sanitizeScope('a-b c/d\\e=f:g,h\ni'), 'abcdefghi');
    });
    test('is capped at 32 characters', () {
      expect(sanitizeScope('x' * 100).length, 32);
    });
    test('empty stays empty', () {
      expect(sanitizeScope(''), '');
      expect(sanitizeScope('-- --'), '');
    });
  });

  group('logRecorderError', () {
    test('emits exactly one content-free line to the sink', () {
      logRecorderError('consent.persist', _LeakyError());
      expect(lines, ['recorder.consent.persist code=unknown type=_LeakyError']);
    });

    test('silent when no sink is wired', () {
      recorderLogSink = null;
      expect(() => logRecorderError('s', StateError('x')), returnsNormally);
      expect(lines, isEmpty);
    });

    test('a throwing sink never breaks the recorder', () {
      recorderLogSink = (_) => throw StateError('sink down');
      expect(() => logRecorderError('s', StateError('x')), returnsNormally);
      expect(() => logRecorderEvent('s', 'e'), returnsNormally);
    });
  });

  group('logRecorderEvent', () {
    test('emits scope and a sanitised event word', () {
      logRecorderEvent('pipeline', 'gap detected');
      expect(lines, ['recorder.pipeline event=gapdetected']);
    });

    test('an event string with a coordinate keeps only identifier characters',
        () {
      logRecorderEvent('x', 'fix -98.7654321,12.3456789');
      // Digits and dots survive by design; commas, minus and spaces do not.
      // The scope/event contract says both must be FIXED words chosen in
      // code, so the leak guard is the call-site scan (static_scans).
      expect(lines.single.contains(','), isFalse);
      expect(lines.single.contains(' fix'), isFalse);
    });

    test('silent without a sink', () {
      recorderLogSink = null;
      logRecorderEvent('a', 'b');
      expect(lines, isEmpty);
    });
  });
}
