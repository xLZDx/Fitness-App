import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/tts_voice_coach.dart';

/// `TtsVoiceCoach` had no test coverage before MVP1.G3 Step 10C wired its
/// failure paths to `FirebaseCrashlytics.recordError` (OBS-1 item #11 -- this
/// class was one of the two files the reconciliation found still bare
/// `debugPrint`). These tests exist to prove that wiring is safe -- Firebase
/// is never initialized in a plain `flutter test` run, so every path below
/// must complete without throwing even though the underlying Crashlytics
/// call itself cannot succeed -- and that the "no voice installed" case
/// stays a state ([voiceUnavailable]), not just a swallowed exception.
///
/// The `flutter_tts` plugin talks to a `MethodChannel('flutter_tts')`; there
/// is no live engine in a widget/unit test, so every call is intercepted
/// here the same way `rest_timer_card_test.dart` intercepts
/// `SystemChannels.platform`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  final List<MethodCall> calls = <MethodCall>[];
  bool languageAvailable = true;
  bool speakThrows = false;

  setUp(() {
    calls.clear();
    languageAvailable = true;
    speakThrows = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isLanguageAvailable':
          return languageAvailable;
        case 'speak':
          if (speakThrows) {
            throw PlatformException(code: 'ERROR', message: 'engine busy');
          }
          return 1;
        default:
          return 1;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a device with no installed voice reports unavailable, not an error',
      () async {
    languageAvailable = false;
    final coach = TtsVoiceCoach();

    await coach.utter('стоп, спина');

    // The "no voice" branch is `expected: true` -- it must still surface as
    // state (this is the whole point of `voiceUnavailable`), but must not
    // read as a Crashlytics-worthy bug. There is nothing externally
    // observable that distinguishes "recorded, but marked expected" from
    // "not recorded" -- both are proven safe by the fact this call
    // completes without throwing, since FirebaseCrashlytics.instance itself
    // throws (no Firebase app) in this test environment.
    expect(coach.voiceUnavailable, isTrue);
    expect(coach.lastErrorMessage, isNotNull);
  });

  test('a genuine engine failure is recorded and does not crash the caller',
      () async {
    speakThrows = true;
    final coach = TtsVoiceCoach();

    await coach.utter('держи спину прямо');

    expect(coach.voiceUnavailable, isFalse);
    expect(coach.lastErrorMessage, contains('engine busy'));
  });

  test('a successful cue configures once and speaks with no error state',
      () async {
    final coach = TtsVoiceCoach();

    await coach.utter('присед');

    expect(coach.voiceUnavailable, isFalse);
    expect(coach.lastErrorMessage, isNull);
    expect(calls.map((c) => c.method), contains('speak'));
  });

  group('sayAndWait', () {
    List<String> methods() => calls.map((c) => c.method).toList();

    test('waits for completion only around the one call, then restores',
        () async {
      final coach = TtsVoiceCoach();

      await coach.sayAndWait('  Squat. Two sets.  ');

      final m = methods();
      final on = m.indexOf('awaitSpeakCompletion');
      final speak = m.indexOf('speak');
      final off = m.lastIndexOf('awaitSpeakCompletion');
      expect(on, greaterThanOrEqualTo(0));
      expect(speak, greaterThan(on), reason: 'wait is switched on before speak');
      expect(off, greaterThan(speak), reason: 'and restored after');
      final args = calls
          .where((c) => c.method == 'awaitSpeakCompletion')
          .map((c) => c.arguments)
          .toList();
      expect(args, [true, false]);
      expect(calls.firstWhere((c) => c.method == 'speak').arguments,
          'Squat. Two sets.',
          reason: 'text is trimmed');
      expect(coach.lastErrorMessage, isNull);
    });

    test('utter stays fire-and-forget: it never touches awaitSpeakCompletion',
        () async {
      final coach = TtsVoiceCoach();
      await coach.utter('присед');
      expect(methods(), isNot(contains('awaitSpeakCompletion')));
    });

    test('a muted coach does nothing at all', () async {
      final coach = TtsVoiceCoach()..setMuted(true);
      await coach.sayAndWait('Squat.');
      expect(calls, isEmpty);
    });

    test('blank text does nothing', () async {
      final coach = TtsVoiceCoach();
      await coach.sayAndWait('   ');
      expect(calls, isEmpty);
    });

    test('an engine failure is recorded, completion mode is still restored',
        () async {
      speakThrows = true;
      final coach = TtsVoiceCoach();

      await coach.sayAndWait('Squat.');

      expect(coach.lastErrorMessage, contains('engine busy'));
      final args = calls
          .where((c) => c.method == 'awaitSpeakCompletion')
          .map((c) => c.arguments)
          .toList();
      expect(args, [true, false],
          reason: 'a failed wait must not leave later cues blocking');
    });

    test('no installed voice completes without throwing', () async {
      languageAvailable = false;
      final coach = TtsVoiceCoach();
      await coach.sayAndWait('Squat.');
      expect(coach.voiceUnavailable, isTrue);
    });
  });

  test('stopSpeaking failure is recorded without throwing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stop') {
        throw PlatformException(code: 'ERROR', message: 'nothing playing');
      }
      return 1;
    });
    final coach = TtsVoiceCoach();

    await coach.stopSpeaking();

    expect(coach.lastErrorMessage, contains('nothing playing'));
  });
}
