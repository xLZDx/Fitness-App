import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/voice/data/voice_command.dart';

void main() {
  group('parseCommand', () {
    test('intent words map to enums', () {
      expect(parseCommand('start set').kind, VoiceCommandKind.startSet);
      expect(parseCommand('go').kind, VoiceCommandKind.startSet);
      expect(parseCommand('done').kind, VoiceCommandKind.doneSet);
      expect(parseCommand('skip rest').kind, VoiceCommandKind.skipRest);
      expect(parseCommand('next exercise').kind, VoiceCommandKind.nextExercise);
      expect(parseCommand('what\'s next').kind, VoiceCommandKind.whatsNext);
      expect(parseCommand('cancel').kind, VoiceCommandKind.cancel);
    });

    test('log weight numeric (digits)', () {
      final c = parseCommand('log 40 kg');
      expect(c.kind, VoiceCommandKind.logWeight);
      expect(c.numericArg, 40.0);
    });

    test('log weight numeric (words)', () {
      final c = parseCommand('log forty kilos');
      expect(c.kind, VoiceCommandKind.logWeight);
      expect(c.numericArg, 40.0);
    });

    test('log weight pounds → kilograms', () {
      final c = parseCommand('log 100 pounds');
      expect(c.kind, VoiceCommandKind.logWeight);
      expect(c.numericArg, closeTo(45.36, 0.1));
    });

    test('log reps numeric', () {
      final c = parseCommand('ten reps');
      expect(c.kind, VoiceCommandKind.logReps);
      expect(c.numericArg, 10.0);
    });

    test('compound numbers (twenty five)', () {
      final c = parseCommand('twenty five reps');
      expect(c.kind, VoiceCommandKind.logReps);
      expect(c.numericArg, 25.0);
    });

    test('empty / nonsense returns unknown', () {
      expect(parseCommand('').kind, VoiceCommandKind.unknown);
      expect(parseCommand('quack quack').kind, VoiceCommandKind.unknown);
    });
  });
}
