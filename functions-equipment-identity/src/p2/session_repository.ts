/**
 * P2.G3 T6 -- the real session RUNTIME primitive that P1.G1's
 * authority_tuple.ts explicitly deferred to this gate (see that file's own
 * header comment: "the *runtime* session-mutation test ... is P2.G3's DoD
 * item, once a session runtime exists to test against -- see that gate").
 *
 * Firestore rules already make `equipment_identity_sessions` entirely
 * client-inaccessible (firestore.rules), but the Admin SDK this Cloud
 * Function runs under bypasses Security Rules completely -- so immutability
 * has to be a property of THIS write path's own logic, not of rules
 * (GPT-PM round-2 MAJOR, P2.G3 plan review, 2026-09-10).
 *
 * Redesigned around a two-phase CLAIM/FINALIZE lifecycle (GPT-PM MAJOR,
 * P2.G3 pre-commit review round 3, 2026-09-11 -- correcting round 2's own
 * remediation, which advanced the latest-session pointer only at the FINAL
 * pin, after the entire expensive pipeline had already run): a slow-running
 * request for an OLDER scan could still win the "latest" race against a
 * newer, faster request purely on timing, because nothing recorded which
 * scan was admitted first until the very end. `admitSessionClaim` now
 * performs admission -- session ownership, latest-session ordering, AND
 * quota -- atomically, in ONE transaction, BEFORE the pipeline runs.
 * `finalizeSessionOutcome` re-verifies "am I still latest" at the end, so a
 * scan that was superseded WHILE it was still running discovers this at
 * finalize time and never emits a stale result.
 */
import { randomUUID } from "crypto";
import type { RecognitionAuthorityTuple } from "../p1/contracts";
import { userEquipmentIdentitySessionDocPath } from "../p1/firestore_paths";
import { userEquipmentIdentityLatestSessionDocPath } from "./firestore_paths";
import { db } from "./firestore_admin";
import {
  decideQuota,
  usageDocRef,
  IDENTITY_TEXT_LOOKUP_ACTION,
  IDENTITY_TEXT_LOOKUP_DAILY_LIMIT,
} from "./quota";

/**
 * The resolved-model fields, persisted alongside `authority` so a genuine
 * retry of the SAME logical request (see `requestFingerprint` below) can
 * be answered from this record alone -- without re-running quota, catalog
 * lookup or policy evaluation a second time (GPT-PM MAJOR "idempotent
 * retry semantics", P2.G3 pre-commit review, 2026-09-11). `textSupportStatus`
 * is what the orchestrator uses to decide whether a replay is a real MATCH
 * (VERIFIED) or a non-authoritative shadow candidate (EXPERIMENTAL) --
 * see `contract.ts`'s `ShadowCandidateSchema`.
 */
export interface PinnedMatchOutcome {
  modelId: string;
  catalogVersion: string;
  textSupportStatus: "EXPERIMENTAL" | "VERIFIED";
}

/** Admitted, pipeline running, not yet resolved. `leaseExpiresAt` bounds how
 * long a caller may hold this claim before another caller is allowed to
 * reclaim it -- a crashed or hung request can never permanently wedge a
 * (uid, scanId), and no separate sweeper process is needed: any later
 * `admitSessionClaim` call simply notices an expired lease and reclaims it
 * itself, lazily, the next time anyone actually asks.
 *
 * `claimId` fences exactly ONE thing: a caller whose OWN lease has since
 * expired and been reclaimed by someone else must never be able to finalize
 * the RECLAIMER's generation of this same (uid, scanId) slot (GPT-PM MAJOR,
 * P2.G3 pre-commit review round 4, 2026-09-11 -- "Старый ещё живой owner
 * после reclaim вызывает finalizeSessionOutcome ... не способен отличить
 * старую lease от новой"). A genuinely still-alive original owner is not an
 * edge case: the lease is a heuristic bound on a MERELY SLOW pipeline, not
 * proof of a crash. Minted fresh on every admission AND every reclaim;
 * `finalizeSessionOutcome` requires an exact match against whichever
 * generation is currently stored, so a stale generation's finalize call
 * observes ABANDONED instead of overwriting the reclaimer's live claim. */
export interface PendingSessionClaim {
  schemaVersion: 1;
  status: "PENDING";
  scanId: string;
  requestFingerprint: string;
  claimId: string;
  createdAt: string;
  leaseExpiresAt: string;
}

/** A real, replayable exact-resolution outcome. */
export interface ResolvedSession {
  schemaVersion: 1;
  status: "RESOLVED";
  scanId: string;
  requestFingerprint: string;
  authority: RecognitionAuthorityTuple;
  createdAt: string;
  matchOutcome: PinnedMatchOutcome;
}

/** Terminal, never replayable: the pipeline finished, but a genuinely newer
 * scan had already been admitted as this uid's latest by the time this one
 * tried to finalize. Recorded (rather than left PENDING-until-lease-expiry)
 * so a retry of THIS scanId gets a fast, correct CANCELLED_STALE instead of
 * waiting out a lease that will never resolve into anything real. */
export interface SupersededClaim {
  schemaVersion: 1;
  status: "SUPERSEDED";
  scanId: string;
  requestFingerprint: string;
  createdAt: string;
}

export type EquipmentIdentitySessionRecord = PendingSessionClaim | ResolvedSession | SupersededClaim;

/**
 * Points at whichever `recognitionSessionId` this uid's most recently
 * ADMITTED (not finished) scan is -- advanced at CLAIM time, not at
 * resolution time, which is the whole fix: admission order is a real total
 * order (Firestore transactions commit sequentially), so a brand-new claim
 * is always, by construction, the most recently admitted scan for this uid
 * regardless of how long its own pipeline later takes.
 */
export interface LatestSessionPointer {
  recognitionSessionId: string;
  scanId: string;
  pinnedAt: string;
}

export type AdmissionResult =
  | { outcome: "ADMITTED"; claimId: string }
  | { outcome: "REPLAY"; record: ResolvedSession }
  | { outcome: "WAIT" }
  | { outcome: "STALE" }
  | { outcome: "RATE_LIMITED" };

export type FinalizeResult =
  | { outcome: "RESOLVED"; record: ResolvedSession }
  | { outcome: "SUPERSEDED" }
  /** Defensive-only: some OTHER write reclaimed/resolved/superseded this
   * exact claim between this caller's own admission and its finalize
   * attempt. Should not happen via the normal admit -> pipeline -> finalize
   * flow (this caller held the only currently-valid claim for its own
   * fingerprint), but never silently overwrites whatever is actually
   * stored if it somehow does. */
  | { outcome: "ABANDONED" };

/**
 * How long an admitted claim may sit PENDING before another caller is
 * allowed to reclaim it. Generous relative to a real pipeline run (a
 * handful of sequential Firestore reads) so a merely-slow-but-alive request
 * is never raced out from under itself, while still being a genuinely
 * bounded wait for anyone stuck behind it.
 */
export const CLAIM_LEASE_MS = 30_000;

/**
 * `RecognitionAuthorityTuple` has several optional fields
 * (`identityParserVersion`, `embeddingModelVersion`, ...), typed as
 * `T | undefined` rather than as genuinely absent-or-present -- TypeScript
 * without `exactOptionalPropertyTypes` accepts `{ ...tuple, foo: undefined }`
 * as a valid tuple, and the Firestore Admin SDK throws on `tx.set`/`tx.update`
 * the moment such a literal `undefined` property value reaches it. Today's
 * only producer (`orchestrator.ts`'s `baseAuthority()`) already avoids this
 * via a conditional spread, but that discipline lives at ONE call site and
 * the type system does not enforce it -- a future producer, or a test
 * fixture built directly instead of through `baseAuthority()`, can
 * reintroduce the exact Firestore-throw bug that was already found and
 * fixed once (type-design-analyzer finding, P2.G3 pre-commit review,
 * 2026-09-11). Stripped here, at the actual write boundary, so the
 * guarantee holds regardless of how the caller constructed `authority`.
 */
export function stripUndefinedFields<T extends object>(value: T): T {
  const cleaned = {} as T;
  for (const [key, val] of Object.entries(value)) {
    if (val !== undefined) {
      (cleaned as Record<string, unknown>)[key] = val;
    }
  }
  return cleaned;
}

/**
 * Phase 1: admission. Linearizes THREE things in one Firestore transaction
 * -- session ownership for (uid, sessionId), this uid's latest-scan
 * ordering, and the identity-lookup quota charge -- so a genuinely
 * concurrent duplicate request cannot pass all three "not yet claimed"
 * windows independently (GPT-PM MAJOR, P2.G3 pre-commit review round 3,
 * 2026-09-11, the specific required change: "В одной Firestore transaction
 * нужно линеаризовать logical session ownership/latest-session ordering и
 * quota admission"). Quota is charged directly against the SAME
 * `users/{uid}/usage/{day}` document `quota.ts`'s own `enforceDailyQuota`
 * writes (via the shared `decideQuota` decision function and `usageDocRef`
 * path helper) -- one atomic store, never a second one -- but as part of
 * THIS transaction rather than a separate call, since Firestore
 * transactions cannot compose across separate `runTransaction` invocations.
 *
 * Reclaiming an expired lease (GPT-PM MAJOR, P2.G3 pre-commit review round
 * 4, 2026-09-11, correcting round 3's own remediation) is fenced by THREE
 * checks, all inside this same transaction, before it is allowed to behave
 * like a fresh admission: (1) the expired claim's own `requestFingerprint`
 * must match -- a reclaim is only ever a genuine retry of the SAME logical
 * request that itself timed out, never a different fingerprint barging in
 * on someone else's expired slot; (2) `latestRef` is read and must still
 * name THIS sessionId -- an expired claim for a scan that a genuinely newer
 * admission has since superseded must never resurrect itself as latest
 * again; (3) quota is never re-charged on reclaim -- this (uid, sessionId)
 * already paid for itself at its ORIGINAL admission, and the doc's mere
 * existence is proof of that.
 */
export async function admitSessionClaim(
  uid: string,
  sessionId: string,
  scanId: string,
  requestFingerprint: string,
): Promise<AdmissionResult> {
  const ref = db().doc(userEquipmentIdentitySessionDocPath(uid, sessionId));
  const latestRef = db().doc(userEquipmentIdentityLatestSessionDocPath(uid));
  const day = new Date().toISOString().slice(0, 10);
  const usageRef = usageDocRef(uid, day);

  return db().runTransaction(async (tx) => {
    const [snap, latestSnap] = await Promise.all([tx.get(ref), tx.get(latestRef)]);
    const nowIso = new Date().toISOString();
    const latest = latestSnap.exists ? (latestSnap.data() as LatestSessionPointer) : null;

    let reclaiming: PendingSessionClaim | null = null;
    if (snap.exists) {
      const existing = snap.data() as EquipmentIdentitySessionRecord;
      if (existing.status === "RESOLVED") {
        return existing.requestFingerprint === requestFingerprint
          ? ({ outcome: "REPLAY", record: existing } as const)
          : ({ outcome: "STALE" } as const);
      }
      if (existing.status === "SUPERSEDED") {
        return { outcome: "STALE" } as const;
      }
      // PENDING.
      if (existing.leaseExpiresAt > nowIso) {
        return existing.requestFingerprint === requestFingerprint
          ? ({ outcome: "WAIT" } as const)
          : ({ outcome: "STALE" } as const);
      }
      // Lease expired -- the original owner never finalized (crashed, timed
      // out, or is simply still running past its own lease). Reclaim is
      // allowed ONLY for the identical logical request this expired claim
      // itself recorded, and ONLY if this session is still this uid's
      // latest admission -- otherwise it is exactly as stale as any other
      // conflicting/superseded attempt.
      if (existing.requestFingerprint !== requestFingerprint) {
        return { outcome: "STALE" } as const;
      }
      if (!latest || latest.recognitionSessionId !== sessionId) {
        return { outcome: "STALE" } as const;
      }
      reclaiming = existing;
      // No separate sweeper needed: reclaiming happens lazily, the next
      // time anyone actually asks.
    }

    if (!reclaiming) {
      const usageSnap = await tx.get(usageRef);
      const used = (usageSnap.data()?.[IDENTITY_TEXT_LOOKUP_ACTION] as number | undefined) ?? 0;
      const quota = decideQuota(used, IDENTITY_TEXT_LOOKUP_DAILY_LIMIT);
      if (!quota.allowed) {
        return { outcome: "RATE_LIMITED" } as const;
      }
      tx.set(usageRef, { [IDENTITY_TEXT_LOOKUP_ACTION]: quota.newUsed, updatedAt: nowIso }, { merge: true });
    }

    const claimId = randomUUID();
    const pending: PendingSessionClaim = {
      schemaVersion: 1,
      status: "PENDING",
      scanId,
      requestFingerprint,
      claimId,
      createdAt: reclaiming ? reclaiming.createdAt : nowIso,
      leaseExpiresAt: new Date(Date.now() + CLAIM_LEASE_MS).toISOString(),
    };
    tx.set(ref, pending);
    // A fresh claim is, by construction, committing strictly after every
    // transaction that has already committed, so it is unconditionally the
    // most recently ADMITTED scan for this uid. A reclaim already verified
    // above that `latest` still names THIS sessionId, so writing the same
    // pointer again here is a harmless, idempotent no-op, not a new
    // assertion. `finalizeSessionOutcome` re-verifies this pointer still
    // names THIS session before ever emitting a real result.
    const pointer: LatestSessionPointer = { recognitionSessionId: sessionId, scanId, pinnedAt: nowIso };
    tx.set(latestRef, pointer);

    return { outcome: "ADMITTED", claimId } as const;
  });
}

/**
 * Phase 2: finalize. Called after the pipeline has computed a real
 * `matchOutcome`, for a claim this caller was itself ADMITTED for. Re-reads
 * the latest-session pointer inside the SAME transaction that would write
 * the resolved outcome -- if a newer scan has since been admitted, this
 * finalize aborts (SUPERSEDED) instead of emitting a stale MATCH. This is
 * also the runtime immutability guarantee P1.G1's authority_tuple.ts DoD
 * comment defers to this gate: once a claim transitions to RESOLVED (or
 * SUPERSEDED), no later finalize attempt for the same fingerprint can ever
 * overwrite it -- it observes ABANDONED and returns without writing.
 *
 * `claimId` must match the CURRENTLY stored generation (GPT-PM MAJOR, P2.G3
 * pre-commit review round 4, 2026-09-11): `requestFingerprint` alone cannot
 * distinguish a genuinely still-alive original owner, whose OWN lease has
 * since expired and been reclaimed by a fresh retry of the identical
 * request, from that reclaim's own live claim -- both share the same
 * fingerprint by construction. Without this check the old owner could
 * finalize the RECLAIMER's in-flight claim out from under it. A caller
 * presenting a stale claimId observes ABANDONED, exactly like any other
 * claim it no longer owns.
 */
export async function finalizeSessionOutcome(
  uid: string,
  sessionId: string,
  authority: RecognitionAuthorityTuple,
  outcome: { requestFingerprint: string; claimId: string; matchOutcome: PinnedMatchOutcome },
): Promise<FinalizeResult> {
  const ref = db().doc(userEquipmentIdentitySessionDocPath(uid, sessionId));
  const latestRef = db().doc(userEquipmentIdentityLatestSessionDocPath(uid));

  return db().runTransaction(async (tx) => {
    const [snap, latestSnap] = await Promise.all([tx.get(ref), tx.get(latestRef)]);

    if (!snap.exists) {
      return { outcome: "ABANDONED" } as const;
    }
    const current = snap.data() as EquipmentIdentitySessionRecord;
    if (
      current.status !== "PENDING" ||
      current.requestFingerprint !== outcome.requestFingerprint ||
      current.claimId !== outcome.claimId
    ) {
      return { outcome: "ABANDONED" } as const;
    }

    const latest = latestSnap.exists ? (latestSnap.data() as LatestSessionPointer) : null;
    if (!latest || latest.recognitionSessionId !== sessionId) {
      const superseded: SupersededClaim = {
        schemaVersion: 1,
        status: "SUPERSEDED",
        scanId: current.scanId,
        requestFingerprint: current.requestFingerprint,
        createdAt: current.createdAt,
      };
      tx.set(ref, superseded);
      return { outcome: "SUPERSEDED" } as const;
    }

    const resolved: ResolvedSession = {
      schemaVersion: 1,
      status: "RESOLVED",
      scanId: current.scanId,
      requestFingerprint: outcome.requestFingerprint,
      authority: stripUndefinedFields(authority),
      createdAt: current.createdAt,
      matchOutcome: outcome.matchOutcome,
    };
    tx.set(ref, resolved);
    return { outcome: "RESOLVED", record: resolved } as const;
  });
}

export async function readSession(
  uid: string,
  sessionId: string,
): Promise<EquipmentIdentitySessionRecord | null> {
  const ref = db().doc(userEquipmentIdentitySessionDocPath(uid, sessionId));
  const snap = await ref.get();
  if (!snap.exists) return null;
  return snap.data() as EquipmentIdentitySessionRecord;
}

/**
 * A plain (non-transactional) read -- this is a staleness HEURISTIC, not a
 * linearizability requirement: the authoritative content of any given
 * session is decided entirely by `admitSessionClaim`/`finalizeSessionOutcome`'s
 * own transactions above, never by this pointer. A rare read of a
 * not-yet-propagated value risks, at most, one extra retry being allowed to
 * proceed before the next call observes the update -- it can never corrupt
 * a write.
 */
export async function readLatestSession(uid: string): Promise<LatestSessionPointer | null> {
  const snap = await db().doc(userEquipmentIdentityLatestSessionDocPath(uid)).get();
  if (!snap.exists) return null;
  return snap.data() as LatestSessionPointer;
}
