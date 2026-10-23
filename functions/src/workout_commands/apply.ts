/**
 * `submitWorkoutCommands` -- server apply of the offline workout command protocol, slice V0
 * (OFFLINE_COMMAND_PROTOCOL.md 4.1 to 4.5, 5.2, 5.3, 7.1), restricted to ONE kind of command:
 * `CompleteSet` with `mode = APPEND`.
 *
 * Behind an environment feature flag that is OFF by default (`WORKOUT_COMMANDS_ENABLED === "true"`).
 * When off the callable answers `failed-precondition: feature-disabled` and touches nothing.
 *
 * One Firestore transaction per item: every read first, then the decisions of 4.2, then ALL writes
 * (typed session, fence entry, detail receipt, daily counter) together. Non-terminal answers write
 * nothing. Out of scope in V0: projection, head document, triggers, tombstones, legacy conversion,
 * CORRECT, AddEligibleExercise, SetDifficulty, fence spill documents, device revocation lookup.
 *
 * Logging: closed slugs only, never a uid, operation id, session id or payload field (spec 2.6).
 */
import * as admin from "firebase-admin";
import { createHash, timingSafeEqual } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "../scaling";
import { noteAppCheck } from "../abuse_guard";
import { assertFeatureEnabled } from "../feature_flags";
import {
  InvalidPayloadError,
  isLowerHex64,
  operationIdMatchesUid,
  parseAndHashPayloadText,
  setIndexOf,
} from "./canonical";
import {
  fenceDocPath,
  fenceKeyOf,
  fenceShardOf,
  fenceValueOf,
  hashPrefix,
  parseFenceValue,
  sessionDigest,
  type FenceCode,
} from "./fence";
import {
  LIMITS_V1,
  RESULT_CLASS,
  stopsBatch,
  type CommandPayload,
  type ItemResult,
  type ReceiptView,
  type ResultCode,
  type SessionStateView,
  type SubmitWorkoutCommandsResponse,
} from "./types";

/** Feature flag of the callable. OFF unless the environment variable is exactly "true". */
export function workoutCommandsEnabled(): boolean {
  return process.env.WORKOUT_COMMANDS_ENABLED === "true";
}

export interface ApplyDeps {
  firestore(): FirebaseFirestore.Firestore;
  nowMs(): number;
}

export const defaultApplyDeps: ApplyDeps = {
  firestore: () => admin.firestore(),
  nowMs: () => Date.now(),
};

const DAY_MS = 86_400_000;
const RECEIPT_TTL_MS = 90 * DAY_MS;
const MAX_WRITER_PROOF_CHARS = 256;

type Doc = Record<string, unknown>;

export function policyPath(uid: string): string {
  return `users/${uid}/workout_command_policy/current`;
}
export function receiptPath(uid: string, operationId: string): string {
  return `users/${uid}/workout_command_receipts/${operationId}`;
}
export function counterPath(uid: string, utcDay: string): string {
  return `users/${uid}/workout_command_counters/${utcDay}`;
}
export function typedSessionPath(uid: string, sessionId: string): string {
  return `users/${uid}/workout_typed_sessions/${sessionId}`;
}

function utcDayOf(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function sha256Text(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function constantTimeEqualText(a: unknown, b: string): boolean {
  if (typeof a !== "string" || a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

/**
 * Policy gate of 4.2 step 2. Returns the non-terminal code to answer, or `null` when typed commands
 * are accepted. Accepted: `SERVER_ONLY`, `SEALED` (same acceptance as `SERVER_ONLY`, table 8.2) and
 * `DRAIN` in phase `OPEN` from a drain-acknowledged device. Everything else holds.
 */
export function policyGate(policy: Doc | undefined, deviceInstallId: string | undefined): ResultCode | null {
  if (policy === undefined) return "MIGRATION_HOLD";
  const state = policy.migrationState;
  if (state === "DELETING") return "ACCOUNT_DELETING";
  if (policy.sendingPaused === true) return "MIGRATION_HOLD";
  if (state === "SERVER_ONLY" || state === "SEALED") return null;
  if (state === "DRAIN") {
    const devices = policy.drainedDevices;
    const acked =
      policy.drainPhase === "OPEN" &&
      deviceInstallId !== undefined &&
      typeof devices === "object" &&
      devices !== null &&
      Object.prototype.hasOwnProperty.call(devices, deviceInstallId);
    return acked ? null : "MIGRATION_HOLD";
  }
  return "MIGRATION_HOLD";
}

function sessionStateOf(typed: Doc | undefined): SessionStateView {
  if (typed === undefined) {
    return { exists: false, sessionGeneration: 0, deletedGeneration: 0, writerEpoch: 0, writerDeviceInstallId: null };
  }
  return {
    exists: true,
    sessionGeneration: numOr(typed.sessionGeneration, 1),
    deletedGeneration: 0,
    writerEpoch: numOr(typed.writerEpoch, 1),
    writerDeviceInstallId: typeof typed.writerDeviceInstallId === "string" ? typed.writerDeviceInstallId : null,
  };
}

function numOr(v: unknown, d: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : d;
}

function result(
  operationId: string | null,
  code: ResultCode,
  extra: Partial<Pick<ItemResult, "receipt" | "reason" | "retryAfterMs" | "sessionState">> = {},
): ItemResult {
  return { operationId, code, resultClass: RESULT_CLASS[code], ...extra };
}

function receiptViewOf(doc: Doc): ReceiptView {
  const status = doc.status === "REJECTED" || doc.status === "SUPERSEDED" ? doc.status : "COMMITTED";
  return {
    status,
    reasonCode: typeof doc.reasonCode === "string" ? doc.reasonCode : null,
    effect: typeof doc.effect === "string" ? doc.effect : null,
    revisionBefore: typeof doc.revisionBefore === "number" ? doc.revisionBefore : null,
    revisionAfter: typeof doc.revisionAfter === "number" ? doc.revisionAfter : null,
    serverTimeMs: numOr(doc.serverTimeMs, 0),
  };
}

type PreparedItem = {
  payload: CommandPayload;
  payloadHash: string;
  writerProof: string;
  deviceInstallId: string | undefined;
};

/**
 * Step 1 of 4.2, outside any transaction and before any read: envelope shape, strict payload
 * validation, recomputed hash, `UID_MISMATCH` / `ID_UID_MISMATCH`. Returns a refusal or the prepared item.
 */
export function prepareItem(
  uid: string,
  requestSessionId: string,
  envelope: unknown,
): { refusal: ItemResult } | { item: PreparedItem } {
  const bad = (code: ResultCode, opId: string | null = null) => ({ refusal: result(opId, code) });
  if (typeof envelope !== "object" || envelope === null || Array.isArray(envelope)) return bad("INVALID_PAYLOAD");
  const e = envelope as Doc;
  if (typeof e.payloadBytes !== "string" || !isLowerHex64(e.payloadHash)) return bad("INVALID_PAYLOAD");
  if (typeof e.writerProof !== "string" || e.writerProof.length < 1 || e.writerProof.length > MAX_WRITER_PROOF_CHARS) {
    return bad("INVALID_PAYLOAD");
  }
  let parsed;
  try {
    parsed = parseAndHashPayloadText(e.payloadBytes);
  } catch (err) {
    if (err instanceof InvalidPayloadError) return bad("INVALID_PAYLOAD");
    throw err;
  }
  const { payload, payloadHash } = parsed;
  if (payload.uid !== uid) return bad("UID_MISMATCH", payload.operationId);
  if (!operationIdMatchesUid(payload.operationId, uid)) return bad("ID_UID_MISMATCH", payload.operationId);
  if (payloadHash !== e.payloadHash) return bad("INVALID_PAYLOAD", payload.operationId);
  if (payload.sessionId !== requestSessionId) return bad("ID_SESSION_MISMATCH", payload.operationId);
  const dev = e.deviceInstallId;
  return {
    item: {
      payload,
      payloadHash,
      writerProof: e.writerProof,
      deviceInstallId: typeof dev === "string" && dev.length > 0 && dev.length <= 128 ? dev : undefined,
    },
  };
}

function fenceEntries(snap: FirebaseFirestore.DocumentSnapshot | undefined): Record<string, unknown> {
  const e = snap?.exists ? (snap.data() as Doc | undefined)?.e : undefined;
  return typeof e === "object" && e !== null ? (e as Record<string, unknown>) : {};
}

/** Apply ONE item in ONE transaction (4.2). Exported with injected deps so tests can drive it directly. */
export async function applyCommandItem(
  deps: ApplyDeps,
  uid: string,
  prepared: PreparedItem,
): Promise<ItemResult> {
  const { payload, payloadHash, writerProof, deviceInstallId } = prepared;
  const fs = deps.firestore();
  const opId = payload.operationId;
  const shard = fenceShardOf(opId);
  const key = fenceKeyOf(opId);
  const policyRef = fs.doc(policyPath(uid));
  const shardRef = fs.doc(fenceDocPath(uid, shard));
  const receiptRef = fs.doc(receiptPath(uid, opId));
  const typedRef = fs.doc(typedSessionPath(uid, payload.sessionId));

  return fs.runTransaction(async (tx) => {
    const nowMs = deps.nowMs();
    const utcDay = utcDayOf(nowMs);
    const counterRef = fs.doc(counterPath(uid, utcDay));

    // ---- ALL READS FIRST (nothing is written until the decisions below are made) ----
    const depShards = [...new Set(payload.dependsOn.map(fenceShardOf))].filter((s) => s !== shard);
    const [policySnap, shardSnap, receiptSnap, counterSnap, typedSnap, ...depSnaps] = await Promise.all([
      tx.get(policyRef),
      tx.get(shardRef),
      tx.get(receiptRef),
      tx.get(counterRef),
      tx.get(typedRef),
      ...depShards.map((s) => tx.get(fs.doc(fenceDocPath(uid, s)))),
    ]);

    const typed: Doc | undefined = typedSnap.exists ? (typedSnap.data() as Doc) : undefined;
    const state = sessionStateOf(typed);
    const answer = (code: ResultCode, extra: Parameters<typeof result>[2] = {}) =>
      result(opId, code, { sessionState: state, ...extra });

    // ---- Step 2: policy gate. Non-terminal, nothing recorded. ----
    const held = policyGate(policySnap.exists ? (policySnap.data() as Doc) : undefined, deviceInstallId);
    if (held !== null) return answer(held);

    // ---- Step 3: compact fence lookup and idempotency table 4.3 ----
    const entries = fenceEntries(shardSnap);
    const existing = parseFenceValue(entries[key]);
    if (entries[key] !== undefined && existing === undefined) {
      // A malformed stored entry cannot be interpreted: fail closed, never re-apply.
      logger.warn("workout_command_event", { slug: "fence_entry_malformed" });
      return answer("UNAVAILABLE");
    }
    if (existing !== undefined) {
      if (existing.hashPrefix !== hashPrefix(payloadHash)) return answer("ID_PAYLOAD_MISMATCH");
      if (existing.sessionDigest !== sessionDigest(payload.sessionId)) return answer("ID_SESSION_MISMATCH");
      const receipt = receiptSnap.exists ? (receiptSnap.data() as Doc) : undefined;
      if (receipt !== undefined && receipt.payloadHash !== payloadHash) return answer("ID_PAYLOAD_MISMATCH");
      if (existing.code === "C") {
        return receipt === undefined
          ? answer("ALREADY_COMMITTED_DETAIL_EXPIRED")
          : answer("ALREADY_COMMITTED", { receipt: receiptViewOf(receipt) });
      }
      if (existing.code === "R") {
        return receipt === undefined
          ? answer("ALREADY_REJECTED", { reason: "UNAVAILABLE" })
          : answer("ALREADY_REJECTED", {
              receipt: receiptViewOf(receipt),
              reason: typeof receipt.reasonCode === "string" ? receipt.reasonCode : "UNAVAILABLE",
            });
      }
      return answer("SUPERSEDED", receipt === undefined ? {} : { receipt: receiptViewOf(receipt) });
    }

    // ---- Step 3b: per-user daily limits, fence miss only, before any write ----
    const counter: Doc = counterSnap.exists ? (counterSnap.data() as Doc) : {};
    const applied = numOr(counter.applied, 0);
    const sessionsCreated = numOr(counter.sessionsCreated, 0);
    const createsSession = typed === undefined && payload.sessionInit !== null;
    if (
      applied >= LIMITS_V1.maxAppliedPerDay ||
      (createsSession && sessionsCreated >= LIMITS_V1.maxSessionCreationsPerDay)
    ) {
      return answer("RATE_LIMITED", { retryAfterMs: Math.max(1000, (Math.floor(nowMs / DAY_MS) + 1) * DAY_MS - nowMs) });
    }

    // ---- Shard capacity (5.2): fail closed, never evict. Spill documents are not part of V0. ----
    const shardFull = Object.keys(entries).length >= LIMITS_V1.maxFenceEntriesPerShard;

    // ---- Step 6: decisions (no tombstone, no legacy document in V0: T = 0, no conversion) ----
    const g = payload.sessionGeneration;
    const lookupDep = (depId: string): FenceCode | undefined => {
      const s = fenceShardOf(depId);
      const map = s === shard ? entries : fenceEntries(depSnaps[depShards.indexOf(s)]);
      return parseFenceValue(map[fenceKeyOf(depId)])?.code;
    };

    /** Terminal refusal: fence `R` + detail receipt + counter (+ `resolvedOps` when the session exists). */
    const refuse = (code: ResultCode): ItemResult => {
      if (shardFull) return answer("FENCE_SHARD_FULL");
      writeOutcome({ fence: "R", status: "REJECTED", reasonCode: code, effect: null, revisionBefore: null, revisionAfter: null, typedNext: undefined });
      return answer(code);
    };

    // 6a (moved first). Writer check (the proof is a secret; only its SHA-256 is stored). It runs
    // BEFORE the generation checks so a caller without the proof can never cause a recorded
    // refusal (resolvedOps, fence, receipt, counter) on someone else's session: NOT_WRITER writes nothing.
    const proofHash = sha256Text(writerProof);
    let claimsWriter = false;
    if (typed !== undefined) {
      if (typed.writerTokenHash === null || typed.writerTokenHash === undefined) {
        claimsWriter = true; // writerless document: the first proof claims it
      } else if (!constantTimeEqualText(typed.writerTokenHash, proofHash)) {
        return answer("NOT_WRITER");
      }
    }

    // 6b. Existence and generation (never restamped).
    if (typed !== undefined) {
      const G = numOr(typed.sessionGeneration, 1);
      if (g < G) return refuse("SESSION_DELETED_ELSEWHERE");
      if (g > G) return refuse("GENERATION_MISMATCH");
    } else if (payload.sessionInit !== null) {
      if (g !== 1) return refuse("GENERATION_MISMATCH"); // T = 0 in V0, so only generation 1 can create
    } else {
      const pending = payload.dependsOn.some((d) => lookupDep(d) === undefined);
      if (pending) return answer("DEPENDENCY_PENDING");
      return refuse("SESSION_DELETED_ELSEWHERE");
    }

    // 6c. Closed session.
    if (typed !== undefined && typed.status === "abandoned") return refuse("SESSION_CLOSED");

    // 6d. Dependencies.
    const depCodes = payload.dependsOn.map(lookupDep);
    if (depCodes.some((c) => c === undefined)) return answer("DEPENDENCY_PENDING");
    if (depCodes.some((c) => c === "R" || c === "S")) return refuse("DEPENDENCY_REJECTED");

    // 6e. Session size.
    const resolvedOps = typed === undefined ? 0 : numOr(typed.resolvedOps, 0);
    if (resolvedOps >= LIMITS_V1.maxResolvedOps) return answer("SESSION_COMMAND_LIMIT");

    // 6f. APPEND precondition: the logical set slot must be free (full set identity).
    const setIndex = setIndexOf(payload);
    const exercises = (typed?.exercises as Record<string, { sets?: Record<string, unknown> }> | undefined) ?? {};
    if (exercises[payload.exerciseId]?.sets?.[String(setIndex)] !== undefined) {
      return refuse("DUPLICATE_LOGICAL_SET");
    }

    // 6g. Epoch bound: an honest client cannot have observed a writer epoch that does not exist yet.
    const currentEpoch = typed === undefined ? 1 : Math.max(1, numOr(typed.writerEpoch, 1));
    if (payload.acceptedEpoch > currentEpoch) return answer("INVALID_PAYLOAD");

    if (shardFull) return answer("FENCE_SHARD_FULL");

    // ---- Step 7: the one targeted mutation of the typed document ----
    const revisionBefore = typed === undefined ? 0 : numOr(typed.revision, 0);
    const revisionAfter = revisionBefore + 1;
    const body = payload.body;
    const setEntry = {
      setId: body.setId,
      setIndex,
      performedConfirmed: body.performedConfirmed,
      actualReps: body.actualReps,
      actualRepsConfirmed: body.actualRepsConfirmed,
      targetReps: body.targetReps,
      loadGrams: body.loadGrams,
      source: body.source,
      performedAtClientMs: body.performedAtClientMs,
      operationId: opId,
      seq: payload.seq,
      originDeviceInstallId: payload.originDeviceInstallId,
      acceptedEpoch: payload.acceptedEpoch,
      appliedAtMs: nowMs,
    };
    const prevExercise = exercises[payload.exerciseId] ?? { sets: {} };
    const nextExercises = {
      ...exercises,
      [payload.exerciseId]: { ...prevExercise, sets: { ...(prevExercise.sets ?? {}), [String(setIndex)]: setEntry } },
    };
    let typedNext: Doc;
    if (typed === undefined) {
      const init = payload.sessionInit!;
      typedNext = {
        sessionId: payload.sessionId,
        sessionGeneration: g,
        writerEpoch: 1,
        writerDeviceInstallId: deviceInstallId ?? null,
        writerTokenHash: proofHash,
        lastSeqByTarget: {},
        maxSeqSeen: payload.seq,
        resolvedOps: 1,
        revision: revisionAfter,
        quarantineCount: 0,
        status: "pending",
        titleKey: init.titleKey,
        dayId: init.dayId,
        startedAtClientMs: init.startedAtClientMs,
        createdAtMs: nowMs,
        updatedAtMs: nowMs,
        exercises: nextExercises,
      };
    } else {
      typedNext = {
        ...typed,
        revision: revisionAfter,
        maxSeqSeen: Math.max(numOr(typed.maxSeqSeen, 0), payload.seq),
        resolvedOps: resolvedOps + 1,
        updatedAtMs: nowMs,
        exercises: nextExercises,
      };
      if (claimsWriter) {
        typedNext.writerTokenHash = proofHash;
        typedNext.writerEpoch = 1;
        typedNext.writerDeviceInstallId = deviceInstallId ?? null;
      }
    }

    // ---- Step 8: fence entry, receipt, counter; all in this same transaction ----
    writeOutcome({
      fence: "C",
      status: "COMMITTED",
      reasonCode: null,
      effect: "APPENDED",
      revisionBefore,
      revisionAfter,
      typedNext,
    });
    const receipt: ReceiptView = {
      status: "COMMITTED",
      reasonCode: null,
      effect: "APPENDED",
      revisionBefore,
      revisionAfter,
      serverTimeMs: nowMs,
    };
    return result(opId, "COMMITTED", { receipt, sessionState: sessionStateOf(typedNext) });

    /** Writes only; called after every read of this transaction has been awaited. */
    function writeOutcome(o: {
      fence: FenceCode;
      status: "COMMITTED" | "REJECTED";
      reasonCode: string | null;
      effect: string | null;
      revisionBefore: number | null;
      revisionAfter: number | null;
      typedNext: Doc | undefined;
    }): void {
      if (o.typedNext !== undefined) {
        tx.set(typedRef, o.typedNext);
      } else if (typed !== undefined) {
        // Refusals of an existing session still count as resolved operations (4.2 step 8).
        tx.set(typedRef, { ...typed, resolvedOps: numOr(typed.resolvedOps, 0) + 1 });
      }
      const shardData: Doc = { e: { [key]: fenceValueOf(o.fence, payload.sessionId, payloadHash) } };
      if (!shardSnap.exists) shardData.spill = 0;
      tx.set(shardRef, shardData, { merge: true });
      tx.set(receiptRef, {
        payloadHash,
        status: o.status,
        reasonCode: o.reasonCode,
        effect: o.effect,
        sessionId: payload.sessionId,
        exerciseId: payload.exerciseId,
        operation: payload.operation,
        logicalSetId: payload.logicalSetId,
        seq: payload.seq,
        originDeviceInstallId: payload.originDeviceInstallId,
        revisionBefore: o.revisionBefore,
        revisionAfter: o.revisionAfter,
        serverTimeMs: nowMs,
        performedAtClientMs: payload.body.performedAtClientMs,
        clockSuspect: false,
        expireAt: admin.firestore.Timestamp.fromMillis(nowMs + RECEIPT_TTL_MS),
      });
      tx.set(
        counterRef,
        {
          utcDay,
          applied: applied + 1,
          sessionsCreated: sessionsCreated + (o.fence === "C" && createsSession ? 1 : 0),
        },
        { merge: true },
      );
    }
  });
}

/** Strict parse of `{ sessionId, items }` (4.1). Throws an `invalid-argument` HttpsError. */
export function parseSubmitRequest(data: unknown): { sessionId: string; items: unknown[] } {
  const d = (typeof data === "object" && data !== null ? data : {}) as Doc;
  if (typeof d.sessionId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(d.sessionId) || /^__.*__$/.test(d.sessionId)) {
    throw new HttpsError("invalid-argument", "invalid_request");
  }
  if (!Array.isArray(d.items) || d.items.length < 1 || d.items.length > LIMITS_V1.maxBatchItems) {
    throw new HttpsError("invalid-argument", "invalid_request");
  }
  return { sessionId: d.sessionId, items: d.items };
}

/** Batch semantics 4.5: in order, own transaction per item, stop after a C5b or C6 result. */
export async function handleSubmitWorkoutCommands(
  deps: ApplyDeps,
  uid: string,
  data: unknown,
): Promise<SubmitWorkoutCommandsResponse> {
  const req = parseSubmitRequest(data);
  const results: ItemResult[] = [];
  let stopped = false;
  for (const envelope of req.items) {
    if (stopped) {
      results.push(result(null, "NOT_ATTEMPTED"));
      continue;
    }
    const prep = prepareItem(uid, req.sessionId, envelope);
    if ("refusal" in prep) {
      results.push(prep.refusal);
      continue;
    }
    let r: ItemResult;
    try {
      r = await applyCommandItem(deps, uid, prep.item);
    } catch (err) {
      const ec = (err as { code?: unknown } | null)?.code;
      logger.error("workout_command_event", {
        slug: "item_unexpected_error",
        firestoreCode: typeof ec === "string" || typeof ec === "number" ? ec : null,
      });
      r = result(prep.item.payload.operationId, "UNAVAILABLE");
    }
    results.push(r);
    logger.info("workout_command_result", { code: r.code });
    if (stopsBatch(r.code)) stopped = true;
  }
  return { results, serverNowMs: deps.nowMs() };
}

async function assertAccountExists(uid: string): Promise<void> {
  try {
    await admin.auth().getUser(uid);
  } catch (e) {
    if ((e as { code?: string } | null)?.code === "auth/user-not-found") {
      throw new HttpsError("unauthenticated", "This account no longer exists. Sign in again.");
    }
    throw e;
  }
}

/**
 * Callable `submitWorkoutCommands({ sessionId, items })`. Region and options come from the shared
 * `RARE` bundle (europe-west1); it deliberately does NOT use the AI runtime service account.
 */
export const submitWorkoutCommands = onCall(RARE, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "submitWorkoutCommands");
  assertFeatureEnabled(workoutCommandsEnabled());
  await assertAccountExists(request.auth.uid);
  return handleSubmitWorkoutCommands(defaultApplyDeps, request.auth.uid, request.data);
});
