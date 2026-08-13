import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'set_session.dart';

/// Plays the timer's cues.
///
/// Behind an interface for the same reason the pose detector is: the widget
/// tests must not need an audio device, and a session's logic is worth testing
/// without one.
abstract class CuePlayer {
  Future<void> play(SetCue cue);

  /// Silence whatever is sounding right now.
  ///
  /// [play] being gated on the mute flag is not the same thing: it decides
  /// what the NEXT cue does and leaves the gong that is already ringing to
  /// finish. A user who hits mute during the end gong hears the sound
  /// continue and reads that as a dead button.
  Future<void> stop();

  Future<void> dispose();
}

/// The real one.
///
/// Three players rather than one, held open for the life of the session. A
/// single player re-loading a different asset takes long enough that the tick
/// at "3" can still be loading when "2" arrives, and the two either stack or
/// cut each other off. Pre-warmed on construction so the first tick is not the
/// slow one — the first tick is also the one that matters, because it is the
/// user's signal that the thing works at all.
class AssetCuePlayer implements CuePlayer {
  AssetCuePlayer({AudioPlayer Function()? create})
      : _create = create ?? AudioPlayer.new;

  final AudioPlayer Function() _create;
  final Map<SetCue, AudioPlayer> _players = {};

  static const _assets = <SetCue, String>{
    SetCue.tick: 'sounds/tick.wav',
    SetCue.startGong: 'sounds/start_gong.wav',
    SetCue.endGong: 'sounds/end_gong.wav',
    // `finished` deliberately has no sound of its own: it lands on the same
    // instant as the last endGong, and two gongs at once is a clatter rather
    // than a finale. It is there for the UI and the voice, not the speaker.
  };

  Future<void> warmUp() async {
    for (final entry in _assets.entries) {
      try {
        final player = _create()
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource(entry.value));
        _players[entry.key] = player;
      } catch (e) {
        // A phone with no audio route, or a locked-down emulator. Silence is
        // a survivable outcome for a timer; a crash mid-set is not.
        debugPrint('CuePlayer could not prepare ${entry.value}: $e');
      }
    }
  }

  @override
  Future<void> play(SetCue cue) async {
    final player = _players[cue];
    if (player == null) return;
    try {
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('CuePlayer failed on $cue: $e');
    }
  }

  @override
  Future<void> stop() async {
    // Every player, not just the last one used: three are held open at once
    // (see the class doc), so a tick and a gong can be sounding together.
    for (final p in _players.values) {
      try {
        await p.stop();
      } catch (e) {
        // Same reasoning as `play`: a phone with no audio route must not turn
        // "be quiet" into a crash.
        debugPrint('CuePlayer failed to stop: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    for (final p in _players.values) {
      try {
        await p.dispose();
      } catch (_) {
        // Disposing a player that never opened throws on some platforms.
      }
    }
    _players.clear();
  }
}

/// Records instead of playing. For tests, and for a user who has muted cues.
class SilentCuePlayer implements CuePlayer {
  final List<SetCue> played = [];

  /// How many times the player was told to shut up. Counted rather than
  /// ignored so a test can assert that muting actually reaches the speaker.
  int stopCalls = 0;

  @override
  Future<void> play(SetCue cue) async => played.add(cue);

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}
}
