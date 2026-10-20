import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';

/// A camera that implements nothing optional.
class _BareCamera extends ScanCamera {
  @override
  Stream<PoseFrame> frames() => const Stream.empty();
  @override
  ValueListenable<bool> get lowLight => throw UnimplementedError();
  @override
  ValueListenable<SessionFacing> get facing => throw UnimplementedError();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> flip() async {}
  @override
  Future<Uint8List?> captureStill() async => null;
  @override
  Widget buildPreview(BuildContext context) => const SizedBox();
  @override
  Future<void> dispose() async {}
}

class _Coach extends MockVoiceCoach {
  final List<String> said = [];
  int stops = 0;
  Object? sayError;
  Object? stopError;

  @override
  Future<void> say(String text) async {
    if (sayError != null) throw sayError!;
    said.add(text);
  }

  @override
  Future<void> stop() async {
    stops++;
    if (stopError != null) throw stopError!;
  }
}

void main() {
  group('ScanCamera.luminance default', () {
    test('an implementer that does not measure reports null (not a crash)', () {
      expect(_BareCamera().luminance, isNull);
    });
  });

  group('manual timer provider', () {
    test('choices are 3, 5 and 10 s with a 5 s default', () {
      expect(kScanManualTimerChoices, [3, 5, 10]);
      expect(kScanManualTimerDefault, 5);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(scanManualTimerSecondsProvider), 5);
      expect(kScanManualTimerChoices.contains(kScanManualTimerDefault), isTrue);
    });
  });

  group('speaker bridge to the voice coach', () {
    ProviderContainer make(_Coach coach) {
      final c = ProviderContainer(
          overrides: [voiceCoachProvider.overrideWithValue(coach)]);
      addTearDown(c.dispose);
      return c;
    }

    test('say resolves true when the coach took the phrase', () async {
      final coach = _Coach();
      final ok = await make(coach).read(scanSpeakerProvider).say('3');
      expect(ok, isTrue);
      expect(coach.said, ['3']);
    });

    test('a failing engine resolves false and never throws', () async {
      final coach = _Coach()..sayError = StateError('no tts voice');
      final ok = await make(coach).read(scanSpeakerProvider).say('3');
      expect(ok, isFalse, reason: 'failure must be observable for the live-region fallback');
      expect(coach.said, isEmpty);
    });

    test('stop is forwarded and a failing stop is swallowed', () async {
      final coach = _Coach();
      await make(coach).read(scanSpeakerProvider).stop();
      expect(coach.stops, 1);
      final bad = _Coach()..stopError = StateError('x');
      await make(bad).read(scanSpeakerProvider).stop();
      expect(bad.stops, 1);
    });
  });

  group('haptic patterns', () {
    test('six named patterns, one per cue class', () {
      expect(ScanHapticPattern.values.map((e) => e.name), [
        'ready',
        'lost',
        'distance',
        'lighting',
        'position',
        'pose',
      ]);
    });

    test('the platform haptics provider accepts every pattern without throwing',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Record the platform channel calls instead of touching a device.
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final h = c.read(scanHapticsProvider);

      h.pattern(ScanHapticPattern.ready);
      h.pattern(ScanHapticPattern.lost);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, ['HapticFeedbackType.mediumImpact', 'HapticFeedbackType.heavyImpact']);

      calls.clear();
      h.pattern(ScanHapticPattern.position);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(calls, hasLength(3), reason: 'position is a triple burst');
      expect(calls.toSet(), {'HapticFeedbackType.lightImpact'});

      calls.clear();
      h.pattern(ScanHapticPattern.lighting);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(calls, hasLength(2));

      calls.clear();
      h.pattern(ScanHapticPattern.distance);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, hasLength(1));

      calls.clear();
      h.pattern(ScanHapticPattern.pose);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(calls, [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('the patterns are distinguishable call sequences', () async {
      final seqs = <ScanHapticPattern, List<String>>{};
      final calls = <String>[];
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final h = c.read(scanHapticsProvider);
      for (final p in ScanHapticPattern.values) {
        calls.clear();
        h.pattern(p);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        seqs[p] = List.of(calls);
      }
      expect(seqs.values.map((s) => s.join('|')).toSet(), hasLength(6),
          reason: 'six patterns must be six different sequences');
    });
  });

  group('clock provider', () {
    test('the default clock is the wall clock in milliseconds', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final now = DateTime.now().millisecondsSinceEpoch;
      final v = c.read(scanClockProvider)();
      expect(v, inInclusiveRange(now - 1000, now + 1000));
    });
  });
}
