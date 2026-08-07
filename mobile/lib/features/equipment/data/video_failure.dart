import 'dart:io';

import 'package:flutter/services.dart';

/// Why a clip did not play, as far as the app can actually tell.
///
/// ## Why this exists
///
/// The player used to choose its message from ONE fact: whether a poster
/// image was on screen. With a poster it said "Нет сети — показан кадр".
/// Nothing anywhere checked the network.
///
/// Reported from a real device on 2026-08-08: that sentence appeared on a
/// 1 Gb home connection. The message was not merely unhelpful, it was
/// actively misleading -- it sent the reader to look at their router while
/// the real fault was somewhere else entirely, and it is still unknown
/// because the app never recorded it.
///
/// So: name only what is known. A failure that does not look like a network
/// failure is reported as a playback failure WITH its technical detail
/// attached, the same way `CameraUnavailable(...permissionDenied)` on the
/// coach screen made that bug diagnosable from a single screenshot.
enum VideoFailureReason {
  /// The signed URL could not be obtained: the `clipUrl` callable refused,
  /// the object is missing, or signing failed. Distinct from offline --
  /// this one happens with a perfectly good connection.
  linkUnavailable,

  /// A genuine network fault, positively identified.
  offline,

  /// Everything else: codec, corrupt file, permission on the bucket, a
  /// platform error with no useful shape. Shown together with its detail
  /// rather than guessed at.
  playbackFailed,
}

/// Sentinel stored by the player when `ClipUrlResolver.resolve` returns null.
const String kUnresolvedClip = 'unresolved';

/// Substrings that only appear in genuine connectivity failures.
///
/// Deliberately narrow. A broad list ("error", "failed") would put us back
/// where we started -- confidently naming the network for faults that have
/// nothing to do with it. When in doubt this returns [playbackFailed], which
/// shows the raw detail and blames nothing.
const _networkMarkers = <String>[
  'failed host lookup',
  'no address associated with hostname',
  'network is unreachable',
  'connection refused',
  'connection reset',
  'connection closed',
  'connection timed out',
  'software caused connection abort',
  'unable to resolve host',
  'no internet',
];

/// Classifies a failure captured by the player. Pure: no I/O, no platform
/// calls, so every branch is unit-testable without a device.
VideoFailureReason classifyVideoFailure(Object error) {
  if (error is String && error == kUnresolvedClip) {
    return VideoFailureReason.linkUnavailable;
  }
  // SocketException is unambiguous and needs no string matching.
  if (error is SocketException) return VideoFailureReason.offline;
  if (error is HttpException) {
    return _looksLikeNetwork(error.message)
        ? VideoFailureReason.offline
        : VideoFailureReason.playbackFailed;
  }
  if (error is PlatformException) {
    // Android's video_player wraps ExoPlayer failures here; the message is
    // the only thing carrying the cause, and most of them are NOT network.
    final text = '${error.message ?? ''} ${error.details ?? ''}';
    return _looksLikeNetwork(text)
        ? VideoFailureReason.offline
        : VideoFailureReason.playbackFailed;
  }
  return _looksLikeNetwork(error.toString())
      ? VideoFailureReason.offline
      : VideoFailureReason.playbackFailed;
}

bool _looksLikeNetwork(String text) {
  final t = text.toLowerCase();
  return _networkMarkers.any(t.contains);
}

/// One line of technical detail for the failure note, or null when there is
/// nothing worth showing.
///
/// Trimmed hard: this sits under a video on a phone, not in a log. The point
/// is that a screenshot carries enough to diagnose from, which is exactly how
/// the coach-screen camera bug was solved.
String? videoFailureDetail(Object error) {
  if (error is String) return error == kUnresolvedClip ? null : error;
  if (error is PlatformException) {
    final m = error.message?.trim();
    return m == null || m.isEmpty ? error.code : '${error.code}: $m';
  }
  final s = error.toString().trim();
  if (s.isEmpty) return null;
  return s.length <= 160 ? s : '${s.substring(0, 157)}...';
}
