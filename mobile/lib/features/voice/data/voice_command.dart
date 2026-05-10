/// TX.6 / MK.1 — Voice-only hands-free workout control.
///
/// Domain-restricted command grammar that maps free-form speech onto
/// a finite set of actions. Pure: no audio bindings; the speech-to-text
/// adapter lives next door.

enum VoiceCommandKind {
  startSet,
  doneSet,
  startRest,
  skipRest,
  nextExercise,
  previousExercise,
  logWeight,
  logReps,
  whatsNext,
  cancel,
  help,
  unknown,
}

class VoiceCommand {
  const VoiceCommand({
    required this.kind,
    this.numericArg,
    this.rawTranscript,
  });

  final VoiceCommandKind kind;
  final double? numericArg;
  final String? rawTranscript;
}

/// Pure parser. Takes a transcript like "log forty kilos" and returns a
/// [VoiceCommand]. Returns [VoiceCommandKind.unknown] when nothing
/// matches — the caller can either ignore or say "I didn't catch that".
VoiceCommand parseCommand(String transcript) {
  final raw = transcript.toLowerCase().trim();
  if (raw.isEmpty) {
    return VoiceCommand(kind: VoiceCommandKind.unknown, rawTranscript: raw);
  }

  bool any(List<String> needles) =>
      needles.any((n) => raw.contains(n));

  if (any(['start set', 'go', 'begin set'])) {
    return VoiceCommand(kind: VoiceCommandKind.startSet, rawTranscript: raw);
  }
  if (any(['done', 'finished set', 'rep done', 'set done'])) {
    return VoiceCommand(kind: VoiceCommandKind.doneSet, rawTranscript: raw);
  }
  if (any(['start rest', 'rest now', 'timer start'])) {
    return VoiceCommand(kind: VoiceCommandKind.startRest, rawTranscript: raw);
  }
  if (any(['skip rest', 'cancel rest', 'go again'])) {
    return VoiceCommand(kind: VoiceCommandKind.skipRest, rawTranscript: raw);
  }
  if (any(['next exercise', 'move on', 'next one'])) {
    return VoiceCommand(
        kind: VoiceCommandKind.nextExercise, rawTranscript: raw);
  }
  if (any(['previous exercise', 'go back', 'last exercise'])) {
    return VoiceCommand(
        kind: VoiceCommandKind.previousExercise, rawTranscript: raw);
  }
  if (any(['what\'s next', 'whats next', 'what is next', 'tell me next'])) {
    return VoiceCommand(
        kind: VoiceCommandKind.whatsNext, rawTranscript: raw);
  }
  if (any(['cancel', 'stop'])) {
    return VoiceCommand(kind: VoiceCommandKind.cancel, rawTranscript: raw);
  }
  if (any(['help', 'commands'])) {
    return VoiceCommand(kind: VoiceCommandKind.help, rawTranscript: raw);
  }

  // "log forty kilos" / "log 40 kg" / "log 40 pounds"
  final logKgMatch = RegExp(r'log\s+([\d\.]+|[a-z\- ]+?)\s*(kg|kilos?|pounds?|lbs?)\b')
      .firstMatch(raw);
  if (logKgMatch != null) {
    final raw1 = logKgMatch.group(1) ?? '';
    final unit = logKgMatch.group(2) ?? 'kg';
    final asNum = _wordsToNumber(raw1);
    if (asNum != null) {
      final kg = unit.startsWith('p') || unit.startsWith('lb')
          ? asNum * 0.4536
          : asNum;
      return VoiceCommand(
        kind: VoiceCommandKind.logWeight,
        numericArg: kg,
        rawTranscript: raw,
      );
    }
  }

  // "ten reps" / "10 reps"
  final repMatch = RegExp(r'\b([\d]+|[a-z\- ]+?)\s*reps?\b').firstMatch(raw);
  if (repMatch != null) {
    final asNum = _wordsToNumber(repMatch.group(1) ?? '');
    if (asNum != null) {
      return VoiceCommand(
        kind: VoiceCommandKind.logReps,
        numericArg: asNum,
        rawTranscript: raw,
      );
    }
  }

  return VoiceCommand(kind: VoiceCommandKind.unknown, rawTranscript: raw);
}

double? _wordsToNumber(String s) {
  final clean = s.trim();
  if (clean.isEmpty) return null;
  final asNum = double.tryParse(clean);
  if (asNum != null) return asNum;
  const ones = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4,
    'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13,
    'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
  };
  const tens = {
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };
  if (ones.containsKey(clean)) return ones[clean]!.toDouble();
  if (tens.containsKey(clean)) return tens[clean]!.toDouble();
  // "twenty five" / "forty-two" forms.
  final parts = clean.split(RegExp(r'[\s\-]'));
  if (parts.length == 2 && tens.containsKey(parts[0]) &&
      ones.containsKey(parts[1])) {
    return (tens[parts[0]]! + ones[parts[1]]!).toDouble();
  }
  return null;
}
