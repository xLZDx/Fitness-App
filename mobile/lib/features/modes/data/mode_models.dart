/// Pure-Dart models of the S03 mode state (design 2.2, 5.1; contract 4.1-4.2).
///
/// No Flutter import: this is the data layer.
library;

/// The four product modes. [name] is the persisted token.
enum AppMode {
  train,
  ride,
  explore,
  body;

  /// The mode with this persisted name, or null for an unknown name.
  static AppMode? tryParse(String? name) {
    if (name == null) return null;
    for (final m in AppMode.values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// Who decides about the first-run chooser (contract 4.2). [absent] is also the
/// in-memory value for "no key stored"; it is a legal stored value only so that
/// an explicit user action can repair an unreadable value (design 5.1).
enum ChooserStatus {
  absent,
  pending,
  migrated,
  resolved;

  static ChooserStatus? tryParse(String? name) {
    if (name == null) return null;
    for (final s in ChooserStatus.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Whether a mode can be selected in this build (contract 4.1).
enum ModeAvailability { available, comingLater }

/// One availability table (contract 4.1: S05/S06 switch a mode on by changing
/// this table). Tests pass their own table.
const Map<AppMode, ModeAvailability> kDefaultModeAvailability = {
  AppMode.train: ModeAvailability.available,
  AppMode.body: ModeAvailability.available,
  AppMode.explore: ModeAvailability.comingLater,
  AppMode.ride: ModeAvailability.comingLater,
};

/// Pure availability lookup. A mode missing from [table] is comingLater
/// (fail closed). [table] defaults to [kDefaultModeAvailability].
ModeAvailability availabilityOfMode(
  AppMode mode, {
  Map<AppMode, ModeAvailability> table = kDefaultModeAvailability,
}) =>
    table[mode] ?? ModeAvailability.comingLater;

/// The three-state answer pattern of `TrainingContextAnswer` (contract 4.2).
enum ModeAnswerKind { unanswered, skipped, answered }

/// Longest accepted answer value; a longer stored value reads as unanswered.
const int kModeAnswerMaxLength = 32;

class ModeAnswer {
  const ModeAnswer._(this.kind, this.value);

  static const ModeAnswer unanswered = ModeAnswer._(ModeAnswerKind.unanswered, null);
  static const ModeAnswer skipped = ModeAnswer._(ModeAnswerKind.skipped, null);

  /// An answered question with a short [value]. An empty, over-long or
  /// control-character value yields [unanswered] (never throws).
  factory ModeAnswer.answered(String value) {
    if (value.isEmpty || value.length > kModeAnswerMaxLength) {
      return unanswered;
    }
    for (final unit in value.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) return unanswered;
    }
    return ModeAnswer._(ModeAnswerKind.answered, value);
  }

  final ModeAnswerKind kind;

  /// Non-null only when [kind] is [ModeAnswerKind.answered].
  final String? value;

  bool get isAnswered => kind == ModeAnswerKind.answered;

  @override
  bool operator ==(Object other) =>
      other is ModeAnswer && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'ModeAnswer(${kind.name})';
}

/// The persisted mode state of one account. Immutable.
class ModeState {
  ModeState({
    required this.selectedMode,
    required this.chooserStatus,
    Map<AppMode, ModeAnswer> answers = const {},
  }) : answers = Map<AppMode, ModeAnswer>.unmodifiable(answers);

  /// Default for a missing or unreadable store (design 2.2).
  factory ModeState.initial() => ModeState(
        selectedMode: AppMode.train,
        chooserStatus: ChooserStatus.absent,
      );

  final AppMode selectedMode;
  final ChooserStatus chooserStatus;

  /// Only modes with a stored answer; a mode not in the map is unanswered.
  final Map<AppMode, ModeAnswer> answers;

  ModeAnswer answerFor(AppMode mode) => answers[mode] ?? ModeAnswer.unanswered;

  ModeState copyWith({
    AppMode? selectedMode,
    ChooserStatus? chooserStatus,
    Map<AppMode, ModeAnswer>? answers,
  }) =>
      ModeState(
        selectedMode: selectedMode ?? this.selectedMode,
        chooserStatus: chooserStatus ?? this.chooserStatus,
        answers: answers ?? this.answers,
      );

  /// Returns a copy with the answer of [mode] set. [ModeAnswer.unanswered]
  /// removes the entry.
  ModeState withAnswer(AppMode mode, ModeAnswer answer) {
    final next = Map<AppMode, ModeAnswer>.of(answers);
    if (answer.kind == ModeAnswerKind.unanswered) {
      next.remove(mode);
    } else {
      next[mode] = answer;
    }
    return copyWith(answers: next);
  }

  @override
  bool operator ==(Object other) {
    if (other is! ModeState ||
        other.selectedMode != selectedMode ||
        other.chooserStatus != chooserStatus ||
        other.answers.length != answers.length) {
      return false;
    }
    for (final e in answers.entries) {
      if (other.answers[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        selectedMode,
        chooserStatus,
        Object.hashAllUnordered(
            answers.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() =>
      'ModeState(${selectedMode.name}, ${chooserStatus.name}, ${answers.length} answers)';
}

/// Why a stored value could not be used (design 5.1, RV-2). Content-free: safe
/// to log.
enum UnreadableReason { corrupt, newerVersion, unknownShape }

/// Three-way result of reading the stored mode state (RV-2). Only
/// [ModeReadMissing] means "no key"; [ModeReadUnreadable] is never overwritten
/// at start-up.
sealed class ModeRead {
  const ModeRead();
}

class ModeReadMissing extends ModeRead {
  const ModeReadMissing();
}

class ModeReadValue extends ModeRead {
  const ModeReadValue(this.state);
  final ModeState state;
}

class ModeReadUnreadable extends ModeRead {
  const ModeReadUnreadable(this.reason);
  final UnreadableReason reason;
}

/// Outcome of a store write. The store never throws on write.
enum ModeWriteResult {
  written,

  /// The uid is being or was wiped (account deletion, RV-14); nothing stays
  /// on disk.
  refusedWipedUid,

  /// Empty uid; nothing written.
  refusedInvalidUid,

  /// The platform store reported failure or threw.
  failed,
}
