// S04-27 (DT-27-2, DT-27-7, DT-27-1 sanitiser half): the sanitising wrapper
// keeps coordinates out of exceptions, stacks and global handlers.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/recording/l10n/recording_error_codes.dart';
import 'package:fitness_app/features/recording/safety/recorder_safe_error.dart';

/// Every textual form of the sentinel coordinate (DT-27-1 F-sentinel).
const _sentinels = <String>[
  '12.3456789',
  '-98.7654321',
  '98.7654321',
  '12,3456789',
  '98,7654321',
  '12.3457',
  '98.7654',
];

String _hostileMessage() =>
    'fix lat=12.3456789 lon=-98.7654321 (12,3456789;98,7654321) '
    'rounded 12.3457/98.7654 path=/data/user/0/app/files/rec/abc';

void _expectClean(String text) {
  for (final s in _sentinels) {
    expect(text.contains(s), isFalse, reason: 'leaked "$s" in: $text');
  }
  expect(text.contains('/data/user'), isFalse);
  expect(text.contains('lat='), isFalse);
}

class _Hostile implements Exception {
  @override
  String toString() => _hostileMessage();
  String get message => _hostileMessage();
}

class _Generic<T> implements Exception {}

class JournalKeyUnavailableLookalike implements Exception {}

void main() {
  group('sanitizeRecorderError', () {
    test('returns a RecorderSafeError carrying only code and type', () {
      final s = sanitizeRecorderError(_Hostile());
      expect(s.code, RecorderErrorCode.unknown);
      expect(s.originalType, '_Hostile');
      _expectClean(s.toString());
      expect(s.toString(), 'RecorderSafeError(unknown, _Hostile)');
    });

    test('an already sanitised error is returned unchanged (identity)', () {
      final once = sanitizeRecorderError(StateError('x'));
      expect(identical(sanitizeRecorderError(once), once), isTrue);
    });

    test('the message of a FormatException is never read', () {
      final s = sanitizeRecorderError(FormatException(_hostileMessage()));
      expect(s.code, RecorderErrorCode.decode);
      _expectClean(s.toString());
    });

    test('the original exception object is not retained', () {
      final s = sanitizeRecorderError(StateError(_hostileMessage()));
      // Only code + type are fields; nothing can print the message.
      _expectClean('${s.code} ${s.originalType} $s');
    });

    test('a generic type name keeps only safe characters', () {
      final s = sanitizeRecorderError(_Generic<List<int>>());
      expect(s.originalType, matches(RegExp(r'^[A-Za-z0-9_<>,]*$')));
      expect(s.originalType.startsWith('_Generic'), isTrue);
    });
  });

  group('runRecorderSanitized (sync)', () {
    test('passes a value through', () {
      expect(runRecorderSanitized(() => 42), 42);
    });

    test('rethrows a hostile error as RecorderSafeError, stack carries no '
        'message', () {
      Object? caught;
      StackTrace? stack;
      try {
        runRecorderSanitized<void>(() => throw _Hostile());
      } catch (e, s) {
        caught = e;
        stack = s;
      }
      expect(caught, isA<RecorderSafeError>());
      _expectClean(caught.toString());
      _expectClean(stack.toString());
    });

    test('a sanitised error thrown inside is not double wrapped', () {
      const inner = RecorderSafeError(RecorderErrorCode.decode, 'X');
      expect(() => runRecorderSanitized<void>(() => throw inner),
          throwsA(same(inner)));
    });
  });

  group('runRecorderSanitizedAsync', () {
    test('passes a value through', () async {
      expect(await runRecorderSanitizedAsync(() async => 'ok'), 'ok');
    });

    test('async failure becomes RecorderSafeError with a clean stack',
        () async {
      Object? caught;
      StackTrace? stack;
      try {
        await runRecorderSanitizedAsync<void>(() async {
          await Future<void>.delayed(Duration.zero);
          throw FileSystemException(_hostileMessage(), '/data/user/0/x');
        });
      } catch (e, s) {
        caught = e;
        stack = s;
      }
      expect(caught, isA<RecorderSafeError>());
      expect((caught as RecorderSafeError).code, RecorderErrorCode.fileSystem);
      _expectClean(caught.toString());
      _expectClean(stack.toString());
    });

    test('TimeoutException maps to timeout, no duration text kept', () async {
      await expectLater(
          runRecorderSanitizedAsync<void>(
              () async => throw TimeoutException(_hostileMessage())),
          throwsA(isA<RecorderSafeError>()
              .having((e) => e.code, 'code', RecorderErrorCode.timeout)));
    });
  });

  group('sanitizeRecorderStack (DT-27-7 isolate re-throw text)', () {
    test('keeps well-formed frames and suspension markers only', () {
      final raw = StackTrace.fromString([
        'Bad state: ${_hostileMessage()}',
        '#0      foo (package:fitness_app/features/recording/a.dart:10:5)',
        '<asynchronous suspension>',
        'lat=12.3456789 lon=-98.7654321',
        '#1      bar (dart:async/zone.dart:1:1)',
        '#2      baz (file:///x/y.dart:3:3)',
        '#3      hostile (package:x/y.dart:1:1) 12.3456789',
      ].join('\n'));
      final out = sanitizeRecorderStack(raw).toString();
      _expectClean(out);
      final lines = out.split('\n');
      expect(lines, hasLength(4));
      expect(lines[0], startsWith('#0'));
      expect(lines[1], '<asynchronous suspension>');
      expect(lines[2], startsWith('#1'));
      expect(lines[3], startsWith('#2'));
    });

    test('an empty stack stays empty', () {
      expect(sanitizeRecorderStack(StackTrace.fromString('')).toString(), '');
    });

    test('a stack of only free text becomes empty', () {
      final out = sanitizeRecorderStack(
          StackTrace.fromString(_hostileMessage())).toString();
      expect(out, '');
    });

    test('a frame whose parenthesised part contains a space is dropped', () {
      final out = sanitizeRecorderStack(StackTrace.fromString(
              '#0 f (package:a/b.dart: lat=12.3456789)'))
          .toString();
      expect(out, '');
    });
  });

  group('isRecorderOrigin / sanitizeForGlobalHandler', () {
    final recorderStack = StackTrace.fromString(
        '#0 f (package:fitness_app/features/recording/state/x.dart:1:1)');
    final otherStack =
        StackTrace.fromString('#0 f (package:fitness_app/features/food/x.dart:1:1)');

    test('recorder origin by stack marker or by type', () {
      expect(isRecorderOrigin(_Hostile(), recorderStack), isTrue);
      expect(isRecorderOrigin(_Hostile(), otherStack), isFalse);
      expect(isRecorderOrigin(_Hostile(), null), isFalse);
      expect(
          isRecorderOrigin(
              const RecorderSafeError(RecorderErrorCode.unknown, 'X'), null),
          isTrue);
    });

    test('recorder error is replaced by its sanitised form (no message)', () {
      final r = sanitizeForGlobalHandler(_Hostile(), recorderStack);
      expect(r.error, isA<RecorderSafeError>());
      _expectClean(r.error.toString());
      _expectClean(r.stack.toString());
    });

    test('a non-recorder error passes through untouched (identity)', () {
      final e = StateError('some other feature');
      final r = sanitizeForGlobalHandler(e, otherStack);
      expect(identical(r.error, e), isTrue);
      expect(identical(r.stack, otherStack), isTrue);
    });

    test('a recorder error with a null stack yields a null stack', () {
      final r = sanitizeForGlobalHandler(
          const RecorderSafeError(RecorderErrorCode.decode, 'X'), null);
      expect(r.stack, isNull);
      expect(r.error, isA<RecorderSafeError>());
    });

    test('marker constant is the recorder folder', () {
      expect(kRecorderStackMarker, 'features/recording/');
    });
  });

  group('mapper table over real typed exceptions (DT-27-2)', () {
    final table = <String, Object>{
      'FormatException': FormatException(_hostileMessage()),
      'TimeoutException': TimeoutException(_hostileMessage()),
      'ArgumentError': ArgumentError(_hostileMessage()),
      'StateError': StateError(_hostileMessage()),
      'UnsupportedError': UnsupportedError(_hostileMessage()),
      'FileSystemException': FileSystemException(_hostileMessage(), '/p'),
      'PlatformException':
          PlatformException(code: 'x', message: _hostileMessage()),
      'MissingPluginException': MissingPluginException(_hostileMessage()),
      'JournalKeyUnavailable': JournalKeyUnavailable(_hostileMessage()),
      'JournalStorageFullException':
          JournalStorageFullException(_hostileMessage()),
      'JournalIoException': JournalIoException(_hostileMessage()),
      'JournalWriteFailure': JournalWriteFailure(_hostileMessage()),
      'JournalUnbound': const JournalUnbound(),
      'JournalTombstonedException': JournalTombstonedException('x'),
      'JournalReadOnlyException': JournalReadOnlyException('x'),
      'JournalAlreadyOpenException': JournalAlreadyOpenException('/p'),
      'JournalNotStartedException': const JournalNotStartedException(),
      'hostile custom': _Hostile(),
      'String thrown': _hostileMessage(),
      'int thrown': 12,
    };
    for (final e in table.entries) {
      test('${e.key} maps to a bare code and prints clean', () {
        final s = sanitizeRecorderError(e.value);
        expect(RecorderErrorCode.values, contains(s.code));
        _expectClean(s.toString());
        _expectClean(s.originalType);
      });
    }

    test('the specific mappings the recorder relies on', () {
      expect(sanitizeRecorderError(FormatException('x')).code,
          RecorderErrorCode.decode);
      expect(sanitizeRecorderError(JournalKeyUnavailable('x')).code,
          RecorderErrorCode.keyUnavailable);
      expect(sanitizeRecorderError(FileSystemException('x')).code,
          RecorderErrorCode.fileSystem);
      expect(
          sanitizeRecorderError(PlatformException(code: 'c')).code,
          RecorderErrorCode.platform);
      expect(sanitizeRecorderError(StateError('x')).code,
          RecorderErrorCode.invariant);
    });
  });
}
