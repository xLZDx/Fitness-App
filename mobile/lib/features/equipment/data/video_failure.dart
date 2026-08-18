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

  /// The backend refused ON PURPOSE: this account has spent its daily budget
  /// for clip links.
  ///
  /// Split out of [linkUnavailable] because the two need opposite messages.
  /// A link that is unavailable is a fault the user can do nothing about and
  /// should probably report. A quota refusal is not a fault at all -- it is
  /// the product working as designed, it resolves by itself at the next UTC
  /// midnight, and it is the ONE video failure with an action the user can
  /// take. Reporting it as "unavailable" sends someone to look for a bug in
  /// a system that is behaving correctly, which is the same defect this file
  /// was created to fix, arriving from the backend instead of the player.
  quotaExhausted,

  /// A genuine network fault, positively identified.
  offline,

  /// Everything else: codec, corrupt file, permission on the bucket, a
  /// platform error with no useful shape. Shown together with its detail
  /// rather than guessed at.
  playbackFailed,
}

/// Sentinel stored by the player when `ClipUrlResolver.resolve` returns null.
const String kUnresolvedClip = 'unresolved';

/// A deliberate daily-budget refusal from the backend, as a domain type.
///
/// `enforceDailyQuota` throws `resource-exhausted` with a sentence already
/// written for a reader ("It resets tomorrow"). That sentence used to die in
/// `ClipUrlResolver.fetch`, which caught every exception alike. It is carried
/// here instead of a `FirebaseFunctionsException` so that this file, and the
/// classifier below, stay free of a Firebase dependency and remain testable
/// with no plugins registered.
class ClipQuotaExhausted implements Exception {
  const ClipQuotaExhausted([this.message]);

  /// The backend's own sentence, when it sent one.
  final String? message;

  @override
  String toString() => message ?? 'Daily limit reached for clip links.';
}

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
  // First, because it is the only branch that is a decision rather than a
  // guess: the backend said so, in a documented error code.
  if (error is ClipQuotaExhausted) return VideoFailureReason.quotaExhausted;
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
  // The refusal's own sentence is the headline, not a footnote under one.
  if (error is ClipQuotaExhausted) return null;
  if (error is String) return error == kUnresolvedClip ? null : error;
  if (error is PlatformException) {
    final m = error.message?.trim();
    return m == null || m.isEmpty ? error.code : '${error.code}: $m';
  }
  final s = error.toString().trim();
  if (s.isEmpty) return null;
  return s.length <= 160 ? s : '${s.substring(0, 157)}...';
}
