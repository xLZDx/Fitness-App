import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/video_failure.dart';

/// The player used to pick its message from one fact — whether a poster was on
/// screen — and announce "Нет сети — показан кадр" for every failure. Reported
/// from a real device on a 1 Gb connection, 2026-08-08.
///
/// The rule these tests pin is not "classify well". It is: **never name the
/// network unless the network is what broke.** A wrong cause sends the reader
/// to their router while the real fault goes unrecorded, which is exactly what
/// happened — the actual reason that clip failed is still unknown.
void main() {
  group('classifyVideoFailure', () {
    test('the resolver sentinel is a link failure, not a network one', () {
      expect(classifyVideoFailure(kUnresolvedClip),
          VideoFailureReason.linkUnavailable);
    });

    test('a SocketException is offline without any string matching', () {
      expect(classifyVideoFailure(const SocketException('no route')),
          VideoFailureReason.offline);
    });

    test('DNS failure text is recognised as offline', () {
      expect(
        classifyVideoFailure(
            Exception('Failed host lookup: firebasestorage.googleapis.com')),
        VideoFailureReason.offline,
      );
    });

    // The case that motivated the whole change. A 403 on the signed URL, a
    // codec the device cannot decode, an ExoPlayer source error -- none of
    // these are the network, and every one of them used to be reported as it.
    test('a 403 from the bucket is NOT reported as offline', () {
      expect(
        classifyVideoFailure(PlatformException(
            code: 'VideoError',
            message: 'Source error: Response code: 403')),
        VideoFailureReason.playbackFailed,
      );
    });

    test('a decoder failure is NOT reported as offline', () {
      expect(
        classifyVideoFailure(PlatformException(
            code: 'VideoError',
            message: 'MediaCodecVideoRenderer error, index=0')),
        VideoFailureReason.playbackFailed,
      );
    });

    test('an App Check rejection is NOT reported as offline', () {
      expect(
        classifyVideoFailure(Exception(
            'FirebaseException: unauthenticated: App attestation failed')),
        VideoFailureReason.playbackFailed,
      );
    });

    test('an unrecognisable error falls back to playbackFailed', () {
      expect(classifyVideoFailure(StateError('nope')),
          VideoFailureReason.playbackFailed);
    });

    // Guards the marker list against being widened into uselessness: a
    // generic word must not start meaning "offline".
    test('the word "error" alone does not mean the network', () {
      expect(classifyVideoFailure(Exception('error')),
          VideoFailureReason.playbackFailed);
    });
  });

  group('videoFailureDetail', () {
    test('the sentinel carries no detail — the headline says it all', () {
      expect(videoFailureDetail(kUnresolvedClip), isNull);
    });

    test('a PlatformException keeps its code and message', () {
      final d = videoFailureDetail(
          PlatformException(code: 'VideoError', message: 'Response code: 403'));
      expect(d, contains('VideoError'));
      expect(d, contains('403'),
          reason: 'the status code is the whole diagnostic value');
    });

    test('a bare code survives when there is no message', () {
      expect(videoFailureDetail(PlatformException(code: 'VideoError')),
          'VideoError');
    });

    test('a long detail is truncated so it fits under a video', () {
      final d = videoFailureDetail(Exception('x' * 500))!;
      expect(d.length, lessThanOrEqualTo(160));
      expect(d, endsWith('...'));
    });
  });
}
