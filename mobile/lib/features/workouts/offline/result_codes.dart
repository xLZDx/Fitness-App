/// Server result codes and their classes (protocol section 4.4) as the V0
/// sender needs them. Classes C7 (`NOT_ATTEMPTED`) and C8 (unknown codes) are
/// handled as in sections 3.5 and 4.4.
library;

enum ResultClass {
  /// `COMMITTED` -> T7 SYNCED.
  applied,

  /// `ALREADY_COMMITTED`, `ALREADY_COMMITTED_DETAIL_EXPIRED`, `SUPERSEDED`
  /// -> T7 SYNCED.
  alreadyApplied,

  /// Terminal data-state refusal -> T8 CONFLICTED (terminal).
  refusedTerminal,

  /// `OUTCOME_UNKNOWN_REPLAY_CLOSED` -> T8 CONFLICTED (terminal).
  outcomeUnknownReplayClosed,

  /// Client defect -> T9 CONFLICTED (terminal-local).
  clientDefect,

  /// Record-level non-terminal (`DEPENDENCY_PENDING`, `VERSION_RETIRED`)
  /// -> T11 ACCEPTED.
  recordNonTerminal,

  /// Session-level non-terminal that proves no effect (`MIGRATION_HOLD`,
  /// `AUTH_REVOKED`, `ACCOUNT_DELETING`, `RATE_LIMITED`) -> T11 ACCEPTED plus
  /// a session hold.
  sessionHold,

  /// `NOT_WRITER`, `SESSION_COMMAND_LIMIT` -> T12 CONFLICTED (non-terminal),
  /// session loop paused.
  sessionConflict,

  /// Retryable (`UNAVAILABLE`, `FENCE_SHARD_FULL`) -> T10 UNKNOWN_EFFECT with
  /// backoff.
  retryable,

  /// `FENCE_SHARD_FULL`: answered before any mutation, so it proves no effect
  /// -> T11 ACCEPTED with backoff.
  retryableNoEffect,

  /// `NOT_ATTEMPTED` -> record back to ACCEPTED, session loop stops.
  notAttempted,

  /// Any code not listed -> treated as a retryable session hold (3.5).
  unknown,
}

const Set<String> kAppliedCodes = {'COMMITTED'};

const Set<String> kAlreadyAppliedCodes = {
  'ALREADY_COMMITTED',
  'ALREADY_COMMITTED_DETAIL_EXPIRED',
  'SUPERSEDED',
};

const Set<String> kTerminalRefusalCodes = {
  'ALREADY_REJECTED',
  'SESSION_DELETED_ELSEWHERE',
  'GENERATION_MISMATCH',
  'SESSION_CLOSED',
  'EXERCISE_NOT_IN_SESSION',
  'EXERCISE_ALREADY_IN_SESSION',
  'DUPLICATE_LOGICAL_SET',
  'SET_NOT_FOUND',
  'DEPENDENCY_REJECTED',
};

const Set<String> kClientDefectCodes = {
  'ID_PAYLOAD_MISMATCH',
  'UID_MISMATCH',
  'ID_UID_MISMATCH',
  'ID_SESSION_MISMATCH',
  'INVALID_PAYLOAD',
};

const Set<String> kRecordNonTerminalCodes = {
  'DEPENDENCY_PENDING',
  'VERSION_RETIRED',
};

const Set<String> kSessionHoldCodes = {
  'MIGRATION_HOLD',
  'AUTH_REVOKED',
  'ACCOUNT_DELETING',
  'RATE_LIMITED',
};

const Set<String> kSessionConflictCodes = {
  'NOT_WRITER',
  'SESSION_COMMAND_LIMIT',
};

const Set<String> kRetryableCodes = {
  'UNAVAILABLE',
};

const Set<String> kRetryableNoEffectCodes = {
  'FENCE_SHARD_FULL',
};

ResultClass classifyResultCode(String code) {
  if (kAppliedCodes.contains(code)) return ResultClass.applied;
  if (kAlreadyAppliedCodes.contains(code)) return ResultClass.alreadyApplied;
  if (kTerminalRefusalCodes.contains(code)) return ResultClass.refusedTerminal;
  if (code == 'OUTCOME_UNKNOWN_REPLAY_CLOSED') {
    return ResultClass.outcomeUnknownReplayClosed;
  }
  if (kClientDefectCodes.contains(code)) return ResultClass.clientDefect;
  if (kRecordNonTerminalCodes.contains(code)) {
    return ResultClass.recordNonTerminal;
  }
  if (kSessionHoldCodes.contains(code)) return ResultClass.sessionHold;
  if (kSessionConflictCodes.contains(code)) return ResultClass.sessionConflict;
  if (kRetryableCodes.contains(code)) return ResultClass.retryable;
  if (kRetryableNoEffectCodes.contains(code)) {
    return ResultClass.retryableNoEffect;
  }
  if (code == 'NOT_ATTEMPTED') return ResultClass.notAttempted;
  return ResultClass.unknown;
}
