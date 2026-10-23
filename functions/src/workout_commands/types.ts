/**
 * Types of the offline workout command protocol, slice V0 (one CompleteSet APPEND).
 * Source of truth: docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md sections 2.2, 2.3, 4.1, 4.4.
 */

/** Hard limits of `limitsVersion` 1 (protocol 2.5 item 5). */
export const LIMITS_V1 = {
  maxBatchItems: 25,
  maxDependsOn: 3,
  maxSetIndex: 1000,
  maxReps: 1000,
  maxLoadGrams: 1_000_000,
  /** Session limit of resolved operations (4.2 step 6e). */
  maxResolvedOps: 2000,
  /** Per-user daily limits (4.2 step 2). */
  maxAppliedPerDay: 2000,
  maxSessionCreationsPerDay: 50,
  /** Per-document fence guard (5.2). */
  maxFenceEntriesPerShard: 12000,
  /** Upper bound for received canonical payload text (defence against abuse). */
  maxPayloadChars: 8192,
} as const;

export type CompleteSetBody = {
  mode: "APPEND";
  setId: string;
  performedConfirmed: boolean;
  actualReps: number | null;
  actualRepsConfirmed: boolean;
  targetReps: number | null;
  loadGrams: number | null;
  source: string;
  performedAtClientMs: number;
};

export type SessionInit = {
  titleKey: string;
  dayId: string | null;
  startedAtClientMs: number;
};

/** The hashed canonical object of protocol 2.2 (hashVersion 2), restricted to CompleteSet. */
export type CommandPayload = {
  protocolVersion: 2;
  hashVersion: 2;
  limitsVersion: 1;
  operationId: string;
  uid: string;
  sessionId: string;
  originDeviceInstallId: string;
  sessionGeneration: number;
  acceptedEpoch: number;
  seq: number;
  dependsOn: string[];
  exerciseId: string;
  operation: "CompleteSet";
  logicalSetId: string;
  sessionInit: SessionInit | null;
  body: CompleteSetBody;
};

/** Envelope of protocol 2.3. Only `payloadBytes`, `payloadHash` and `writerProof` carry authority checks. */
export type CommandEnvelope = {
  /** The canonical payload text exactly as the client hashed it (UTF-8 JSON). */
  payloadBytes: string;
  payloadHash: string;
  writerProof: string;
  writerEpochClaim?: number;
  deviceInstallId?: string;
  clientBuild?: string;
};

export type SubmitWorkoutCommandsRequest = {
  sessionId: string;
  items: CommandEnvelope[];
};

/** Per-answer session state (4.1). Never carries the token hash. */
export type SessionStateView = {
  exists: boolean;
  sessionGeneration: number;
  /** Always 0 in V0: tombstones are not part of this slice. */
  deletedGeneration: number;
  writerEpoch: number;
  writerDeviceInstallId: string | null;
};

/** Result codes of 4.4 that slice V0 can produce, plus `NOT_ATTEMPTED` (C7) and `UNAVAILABLE` (C6). */
export type ResultCode =
  | "COMMITTED"
  | "ALREADY_COMMITTED"
  | "ALREADY_COMMITTED_DETAIL_EXPIRED"
  | "ALREADY_REJECTED"
  | "SUPERSEDED"
  | "SESSION_DELETED_ELSEWHERE"
  | "GENERATION_MISMATCH"
  | "SESSION_CLOSED"
  | "DUPLICATE_LOGICAL_SET"
  | "DEPENDENCY_REJECTED"
  | "DEPENDENCY_PENDING"
  | "ID_PAYLOAD_MISMATCH"
  | "UID_MISMATCH"
  | "ID_UID_MISMATCH"
  | "ID_SESSION_MISMATCH"
  | "INVALID_PAYLOAD"
  | "MIGRATION_HOLD"
  | "ACCOUNT_DELETING"
  | "RATE_LIMITED"
  | "NOT_WRITER"
  | "SESSION_COMMAND_LIMIT"
  | "FENCE_SHARD_FULL"
  | "UNAVAILABLE"
  | "NOT_ATTEMPTED";

/** Result classes of 4.4. */
export type ResultClass = "C1" | "C2" | "C3" | "C4" | "C5a" | "C5b" | "C6" | "C7";

export const RESULT_CLASS: Record<ResultCode, ResultClass> = {
  COMMITTED: "C1",
  ALREADY_COMMITTED: "C2",
  ALREADY_COMMITTED_DETAIL_EXPIRED: "C2",
  SUPERSEDED: "C2",
  ALREADY_REJECTED: "C3",
  SESSION_DELETED_ELSEWHERE: "C3",
  GENERATION_MISMATCH: "C3",
  SESSION_CLOSED: "C3",
  DUPLICATE_LOGICAL_SET: "C3",
  DEPENDENCY_REJECTED: "C3",
  ID_PAYLOAD_MISMATCH: "C4",
  UID_MISMATCH: "C4",
  ID_UID_MISMATCH: "C4",
  ID_SESSION_MISMATCH: "C4",
  INVALID_PAYLOAD: "C4",
  DEPENDENCY_PENDING: "C5a",
  MIGRATION_HOLD: "C5b",
  ACCOUNT_DELETING: "C5b",
  RATE_LIMITED: "C5b",
  NOT_WRITER: "C5b",
  SESSION_COMMAND_LIMIT: "C5b",
  FENCE_SHARD_FULL: "C6",
  UNAVAILABLE: "C6",
  NOT_ATTEMPTED: "C7",
};

/** Batch semantics 4.5: processing stops after a C5b or C6 result. */
export function stopsBatch(code: ResultCode): boolean {
  const c = RESULT_CLASS[code];
  return c === "C5b" || c === "C6";
}

/** The stored or returned detail of an applied or refused command (5.3, reduced to what V0 needs). */
export type ReceiptView = {
  status: "COMMITTED" | "REJECTED" | "SUPERSEDED";
  reasonCode: string | null;
  effect: string | null;
  revisionBefore: number | null;
  revisionAfter: number | null;
  serverTimeMs: number;
};

export type ItemResult = {
  /** Best-effort operation id (absent when the payload could not be parsed). */
  operationId: string | null;
  code: ResultCode;
  resultClass: ResultClass;
  receipt?: ReceiptView;
  /** `UNAVAILABLE` for an I4 replay whose detail expired. */
  reason?: string;
  /** Non-terminal rate limit: milliseconds until the daily window resets. */
  retryAfterMs?: number;
  sessionState?: SessionStateView;
};

export type SubmitWorkoutCommandsResponse = {
  results: ItemResult[];
  serverNowMs: number;
};
