/**
 * The account-deletion fence shared by every activity callable (S02 design 5.4,
 * 6.1) and the tombstone read used by the stream callables (design 6.2).
 *
 * Two independent guards, both read INSIDE the caller's transaction:
 *   1. documents: the top-level server-only `activity_account_state/{uid}` (written
 *      by `deleteAccount` at its first step, survives `recursiveDelete(users/{uid})`)
 *      and the Phase 1 marker `accountDeletionRetries/{uid}`;
 *   2. Auth: the user must still exist (an ID token stays valid for about an hour
 *      after `deleteUser`). Only "user not found" means gone; any other lookup
 *      failure THROWS so the caller fails closed with a bare code.
 *
 * Returning a closed result instead of throwing keeps each callable's own refusal
 * type; a callable maps `account_deleting` / `account_deleted` to its own codes.
 */
import * as admin from "firebase-admin";
import { activityTombstonePath } from "./paths";

/** Injectable collaborators of any fenced transaction. */
export interface FenceDeps {
  firestore(): FirebaseFirestore.Firestore;
  /** `true` when the Auth user exists, `false` when Auth says it is gone. Other failures must throw. */
  authUserExists(uid: string): Promise<boolean>;
  nowMs(): number;
}

export const defaultFenceDeps: FenceDeps = {
  firestore: () => admin.firestore(),
  async authUserExists(uid) {
    try {
      await admin.auth().getUser(uid);
      return true;
    } catch (e) {
      if ((e as { code?: unknown } | null)?.code === "auth/user-not-found") return false;
      throw e;
    }
  },
  nowMs: () => Date.now(),
};

/** The delete fence of design 6.1: top-level, server-only, survives `recursiveDelete(users/{uid})`. */
export function activityAccountStatePath(uid: string): string {
  return `activity_account_state/${uid}`;
}

/** Existing Phase 1 marker written by `deleteAccount` once a deletion is in flight. */
export function accountDeletionRetriesPath(uid: string): string {
  return `accountDeletionRetries/${uid}`;
}

/** Outcome of a fence check. */
export type FenceState = "clear" | "account_deleting" | "account_deleted";

/**
 * Reads both fence documents through [tx], then checks Auth existence. Call it
 * BEFORE the first write of the transaction (Firestore requires reads first).
 * A write to the fence between this read and the commit makes the transaction
 * retry, so the callable never commits against a stale "clear".
 */
export async function checkAccountFence(
  tx: FirebaseFirestore.Transaction,
  deps: FenceDeps,
  uid: string,
): Promise<FenceState> {
  const fs = deps.firestore();
  const [fenceSnap, retriesSnap] = await Promise.all([
    tx.get(fs.doc(activityAccountStatePath(uid))),
    tx.get(fs.doc(accountDeletionRetriesPath(uid))),
  ]);
  if (fenceSnap.exists || retriesSnap.exists) return "account_deleting";
  if (!(await deps.authUserExists(uid))) return "account_deleted";
  return "clear";
}

/** `true` when a tombstone for the id exists (design 6.2: all callables refuse a tombstoned id). */
export async function activityTombstoned(
  tx: FirebaseFirestore.Transaction,
  deps: FenceDeps,
  uid: string,
  activityId: string,
): Promise<boolean> {
  const snap = await tx.get(deps.firestore().doc(activityTombstonePath(uid, activityId)));
  return snap.exists;
}

/** Signed-URL lifetime of an upload (design 5.2) plus the late-sweep margin (design 6.1). */
export const LATE_SWEEP_DELAY_MS = (10 + 5) * 60 * 1000;

/**
 * Writes `activity_account_state/{uid}` (design 6.1 step 1). Idempotent: when the
 * document already exists the EARLIEST `fenceAt` and `lateSweepAt` are kept and
 * nothing is rewritten. Admin SDK only (no client rule). Throws on a Firestore
 * failure; `deleteAccount` must then abort before it sweeps anything.
 * Returns `true` when this call created the document.
 */
export async function writeActivityAccountFence(
  deps: FenceDeps,
  uid: string,
): Promise<boolean> {
  const fs = deps.firestore();
  const ref = fs.doc(activityAccountStatePath(uid));
  return fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return false;
    const nowMs = deps.nowMs();
    tx.set(ref, {
      fenceAt: admin.firestore.Timestamp.fromMillis(nowMs),
      lateSweepAt: admin.firestore.Timestamp.fromMillis(nowMs + LATE_SWEEP_DELAY_MS),
    });
    return true;
  });
}
