// S04-27 (DT-27-2): the bare error codes and type-name sanitiser.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/activity/repository/journal_cipher.dart';
import 'package:fitness_app/features/activity/repository/journal_errors.dart';
import 'package:fitness_app/features/recording/l10n/recording_error_codes.dart';

class SecretBoxAuthenticationError implements Exception {}

class ClosedException implements Exception {}

class Plain implements Exception {}

class Generic<T, U> implements Exception {}

// A very long class name to exercise the length cap.
class AVeryLongExceptionTypeNameThatKeepsGoingAndGoingAndGoingForeverAndEver
    implements Exception {}

void main() {
  group('recorderErrorCodeOf', () {
    final table = <String, MapEntry<Object, RecorderErrorCode>>{
      'FormatException':
          MapEntry(const FormatException('m'), RecorderErrorCode.decode),
      'TimeoutException':
          MapEntry(TimeoutException('m'), RecorderErrorCode.timeout),
      'ArgumentError':
          MapEntry(ArgumentError('m'), RecorderErrorCode.invariant),
      'StateError': MapEntry(StateError('m'), RecorderErrorCode.invariant),
      'UnsupportedError':
          MapEntry(UnsupportedError('m'), RecorderErrorCode.invariant),
      'AssertionError':
          MapEntry(AssertionError('m'), RecorderErrorCode.invariant),
      'FileSystemException': MapEntry(
          const FileSystemException('m'), RecorderErrorCode.fileSystem),
      'PathAccessException': MapEntry(
          const PathAccessException('p', OSError()),
          RecorderErrorCode.fileSystem),
      'PathNotFoundException': MapEntry(
          const PathNotFoundException('p', OSError()),
          RecorderErrorCode.fileSystem),
      'PathExistsException': MapEntry(
          const PathExistsException('p', OSError()),
          RecorderErrorCode.fileSystem),
      'OSError': MapEntry(const OSError('m', 5), RecorderErrorCode.fileSystem),
      'JournalKeyUnavailable': MapEntry(
          const JournalKeyUnavailable('m'), RecorderErrorCode.keyUnavailable),
      'JournalDecryptFailure': MapEntry(
          const JournalDecryptFailure('r'), RecorderErrorCode.decrypt),
      'SecretBoxAuthenticationError': MapEntry(
          SecretBoxAuthenticationError(), RecorderErrorCode.decrypt),
      'RemoteError': MapEntry(
          RemoteError('d', StackTrace.empty.toString()),
          RecorderErrorCode.isolate),
      'IsolateSpawnException':
          MapEntry(IsolateSpawnException('m'), RecorderErrorCode.isolate),
      'ClosedException':
          MapEntry(ClosedException(), RecorderErrorCode.isolate),
      'PlatformException': MapEntry(
          PlatformException(code: 'c'), RecorderErrorCode.platform),
      'MissingPluginException': MapEntry(
          MissingPluginException('m'), RecorderErrorCode.platform),
    };
    for (final e in table.entries) {
      test('${e.key} -> ${e.value.value.name}', () {
        expect(recorderErrorCodeOf(e.value.key), e.value.value);
      });
    }

    test('an unrecognised type is unknown (generic code)', () {
      expect(recorderErrorCodeOf(Plain()), RecorderErrorCode.unknown);
      expect(recorderErrorCodeOf('a string'), RecorderErrorCode.unknown);
      expect(recorderErrorCodeOf(7), RecorderErrorCode.unknown);
    });

    test('the code never depends on the message', () {
      expect(recorderErrorCodeOf(StateError('FileSystemException timeout')),
          RecorderErrorCode.invariant);
      expect(recorderErrorCodeOf(const FormatException('PlatformException')),
          RecorderErrorCode.decode);
      expect(recorderErrorCodeOf(Exception('JournalKeyUnavailable')),
          RecorderErrorCode.unknown);
    });

    test('typed journal exceptions without a dedicated code are still a bare '
        'code, never a throw', () {
      // OBSERVATION (see findings): storage-full / IO map to `unknown` today.
      for (final e in <Object>[
        const JournalStorageFullException('m'),
        const JournalIoException('m'),
        const JournalUnbound(),
        JournalTombstonedException('x'),
        const JournalNotStartedException(),
      ]) {
        expect(RecorderErrorCode.values, contains(recorderErrorCodeOf(e)));
      }
    });
  });

  group('logName', () {
    test('equals the enum name for every code and is an identifier', () {
      for (final c in RecorderErrorCode.values) {
        expect(c.logName, c.name);
        expect(c.logName, matches(RegExp(r'^[a-z][A-Za-z]*$')));
      }
    });

    test('the code set is the documented nine', () {
      expect(RecorderErrorCode.values.map((c) => c.name).toSet(), {
        'decode',
        'decrypt',
        'keyUnavailable',
        'fileSystem',
        'timeout',
        'isolate',
        'platform',
        'invariant',
        'unknown',
      });
    });
  });

  group('safeTypeName', () {
    test('plain type names pass through', () {
      expect(safeTypeName(Plain()), 'Plain');
      expect(safeTypeName(StateError('x')), 'StateError');
    });

    test('generics keep only identifier, <, > and comma', () {
      final n = safeTypeName(Generic<int, List<String>>());
      expect(n, matches(RegExp(r'^[A-Za-z0-9_<>,]+$')));
      expect(n.startsWith('Generic<'), isTrue);
    });

    test('capped at kMaxLoggedTypeNameLength', () {
      final n = safeTypeName(
          AVeryLongExceptionTypeNameThatKeepsGoingAndGoingAndGoingForeverAndEver());
      expect(n.length, kMaxLoggedTypeNameLength);
      expect(kMaxLoggedTypeNameLength, 48);
    });

    test('built-in runtime types are safe', () {
      expect(safeTypeName('s'), 'String');
      expect(safeTypeName(1), 'int');
    });
  });
}
