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

  group('parseCommand whole-word matching', () {
    const accepted = <String, VoiceCommandKind>{
      'Go': VoiceCommandKind.startSet,
      'go!': VoiceCommandKind.startSet,
      'ok go now': VoiceCommandKind.startSet,
      'Start set!': VoiceCommandKind.startSet,
      'Set done.': VoiceCommandKind.doneSet,
      'rest now': VoiceCommandKind.startRest,
      'skip rest': VoiceCommandKind.skipRest,
      "what's next?": VoiceCommandKind.whatsNext,
      'what’s next': VoiceCommandKind.whatsNext,
      'what‘s next': VoiceCommandKind.whatsNext,
      'whatʼs next': VoiceCommandKind.whatsNext,
      'stop': VoiceCommandKind.cancel,
      'help': VoiceCommandKind.help,
    };
    accepted.forEach((phrase, kind) {
      test('accepts "$phrase" as ${kind.name}', () {
        expect(parseCommand(phrase).kind, kind);
      });
    });

    test('accepts "log 40 kg" as weight 40', () {
      final c = parseCommand('log 40 kg');
      expect(c.kind, VoiceCommandKind.logWeight);
      expect(c.numericArg, 40.0);
    });

    test('accepts "10 reps" as reps 10', () {
      final c = parseCommand('10 reps');
      expect(c.kind, VoiceCommandKind.logReps);
      expect(c.numericArg, 10.0);
    });

    const rejected = <String, VoiceCommandKind>{
      'good': VoiceCommandKind.startSet,
      'ago': VoiceCommandKind.startSet,
      'mango': VoiceCommandKind.startSet,
      'gone': VoiceCommandKind.startSet,
      'undone': VoiceCommandKind.doneSet,
      'stopped': VoiceCommandKind.cancel,
      'nonstop': VoiceCommandKind.cancel,
      'helpful': VoiceCommandKind.help,
      'interest now': VoiceCommandKind.startRest,
      'timer started': VoiceCommandKind.startRest,
      'catalog 40 kg': VoiceCommandKind.logWeight,
    };
    rejected.forEach((phrase, oldKind) {
      test('"$phrase" no longer triggers ${oldKind.name}', () {
        final c = parseCommand(phrase);
        expect(c.kind, isNot(oldKind));
        expect(c.kind, VoiceCommandKind.unknown);
      });
    });

    test(
        "KNOWN GAP (product decision): 'let's go home' still parses as "
        'startSet because "go" is a standalone word', () {
      // Documents current behaviour, not desired behaviour. Closing it needs a
      // stricter grammar (short-utterance or exact matching).
      expect(parseCommand("let's go home").kind, VoiceCommandKind.startSet);
    });
  });
}
