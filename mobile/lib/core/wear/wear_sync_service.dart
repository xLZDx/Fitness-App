import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// State the watch face mirrors. Kept tiny on purpose — the Wear OS
/// data-layer Wearable API has a 100 KB per-message ceiling, and a
/// circular-watch font is unforgiving. Anything that can't be expressed
/// in this struct lives on the phone.
class WearWorkoutState {
  const WearWorkoutState({
    required this.exerciseTitle,
    required this.setNumber,
    required this.totalSets,
    required this.suggestedWeightKg,
    required this.restRemainingSeconds,
    this.isResting = false,
  });

  final String exerciseTitle;
  final int setNumber;
  final int totalSets;
  final double? suggestedWeightKg;
  final int restRemainingSeconds;
  final bool isResting;

  Map<String, dynamic> toMessage() => {
        'title': exerciseTitle,
        'set': setNumber,
        'totalSets': totalSets,
        if (suggestedWeightKg != null) 'kg': suggestedWeightKg,
        'rest': restRemainingSeconds,
        'isResting': isResting,
      };

  factory WearWorkoutState.fromMessage(Map<String, dynamic> m) {
    return WearWorkoutState(
      exerciseTitle: (m['title'] as String?) ?? 'Workout',
      setNumber: (m['set'] as num?)?.toInt() ?? 1,
      totalSets: (m['totalSets'] as num?)?.toInt() ?? 1,
      suggestedWeightKg: (m['kg'] as num?)?.toDouble(),
      restRemainingSeconds: (m['rest'] as num?)?.toInt() ?? 0,
      isResting: m['isResting'] == true,
    );
  }
}

/// Bridges the phone app to the Wear OS watch face.
///
/// Implementation detail: we use a [MethodChannel] (`wear_sync`) that the
/// Android side translates into Wearable Data Layer calls. Watch-side
/// Kotlin lives under `wear/` and is loaded by the watch APK. iOS/Apple
/// Watch parity is a Phase 7 item — `WatchKit` will plug into the same
/// abstraction here.
abstract class WearSyncService {
  Future<bool> isWatchPaired();

  /// Pushes the current workout state to the paired watch. Best-effort —
  /// returns false on no-pair / channel error.
  Future<bool> pushState(WearWorkoutState state);

  /// Stream of inbound messages from the watch (e.g. "done set" tap).
  Stream<WearMessage> incoming();
}

class WearMessage {
  const WearMessage(this.kind, this.payload);
  final String kind;
  final Map<String, dynamic> payload;
}

class MethodChannelWearSyncService implements WearSyncService {
  static const _channel = MethodChannel('fitnessapp/wear_sync');
  static const _events = EventChannel('fitnessapp/wear_sync/events');

  @override
  Future<bool> isWatchPaired() async {
    try {
      final r = await _channel.invokeMethod<bool>('isPaired');
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> pushState(WearWorkoutState state) async {
    try {
      final r = await _channel.invokeMethod<bool>(
        'pushState',
        jsonEncode(state.toMessage()),
      );
      return r ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<WearMessage> incoming() {
    return _events.receiveBroadcastStream().map((raw) {
      if (raw is! Map) return const WearMessage('unknown', {});
      final kind = raw['kind'] as String? ?? 'unknown';
      final payload = (raw['payload'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return WearMessage(kind, payload);
    });
  }
}

class MockWearSyncService implements WearSyncService {
  bool paired = false;
  final List<WearWorkoutState> pushed = [];
  final StreamController<WearMessage> _ctrl =
      StreamController<WearMessage>.broadcast();

  @override
  Future<bool> isWatchPaired() async => paired;

  @override
  Future<bool> pushState(WearWorkoutState state) async {
    pushed.add(state);
    return paired;
  }

  @override
  Stream<WearMessage> incoming() => _ctrl.stream;

  void simulateMessage(WearMessage m) => _ctrl.add(m);
  void dispose() => _ctrl.close();
}
