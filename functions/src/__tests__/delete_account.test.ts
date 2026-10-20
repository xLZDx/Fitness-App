/**
 * L0b — the entrypoint whose failure mode is either "still billed with no
 * way back in" or "signed out of an account nobody deleted". Ordered so
 * neither can happen: cancel Stripe, then delete Firestore data, then
 * delete the Auth user last, and a failure at any step throws before the
 * next one runs.
 *
 * Own admin mock rather than reusing index.test.ts's: this function is the
 * only one that calls `db.collection().doc()`, `db.recursiveDelete()` and
 * `admin.auth().deleteUser()`, none of which the shared mock models.
 */

const refs = new Map<string, any>();
const getRef = (path: string): any => {
  let ref = refs.get(path);
  if (!ref) {
    let stored: any = undefined;
    ref = {
      path,
      get: jest.fn(async () => ({
        exists: stored !== undefined,
        data: () => stored,
      })),
      set: jest.fn(async (data: any, options?: any) => {
        stored = options?.merge ? { ...(stored ?? {}), ...data } : data;
      }),
      delete: jest.fn(async () => {
        stored = undefined;
      }),
      __setStored: (v: any) => {
        stored = v;
      },
    };
    refs.set(path, ref);
  }
  return ref;
};

const recursiveDelete = jest.fn(async (_ref?: any) => undefined);
const deleteUser = jest.fn(async () => undefined);
const revokeRefreshTokens = jest.fn(async (_uid?: string) => undefined);

/**
 * A1 — the shared-record sweep needs three things the original mock did not
 * model: single-field `where` queries, a write batch, and documents that
 * exist without anyone having called `doc()` for them first. Seeded per test
 * via `seed()`; asserted via `batchOps`.
 */
const seededDocs = new Map<string, Array<{ id: string; data: any }>>();
const batchOps: Array<{ op: "update" | "delete"; path: string; data?: any }> =
  [];
const commit = jest.fn(async () => undefined);
/**
 * Booking rows are now settled by one `db.runTransaction` per booking (not a
 * write batch). The fake transaction reads the CURRENT `seededDocs` state,
 * buffers writes, and applies them at commit, recording each applied write in
 * `txOps` (the transaction counterpart of `batchOps`).
 */
const txOps: Array<{ op: "update" | "delete"; path: string; data?: any }> = [];
const txCommit = jest.fn(async () => undefined);

const seed = (collection: string, docs: Array<{ id: string; data: any }>) =>
  seededDocs.set(collection, docs);

const makeQuery = (
  name: string,
  field?: string,
  value?: unknown,
  max = Infinity,
): any => ({
  where: (f: string, _op: string, v: unknown) => makeQuery(name, f, v, max),
  limit: (n: number) => makeQuery(name, field, value, n),
  get: jest.fn(async () => {
    const all = seededDocs.get(name) ?? [];
    const matched = (
      field === undefined ? all : all.filter((d) => d.data[field] === value)
    ).slice(0, max);
    return {
      docs: matched.map((d) => ({
        id: d.id,
        ref: { path: `${name}/${d.id}` },
        data: () => d.data,
      })),
    };
  }),
});

jest.mock("firebase-admin", () => {
  const firestoreFn: any = jest.fn(() => ({
    doc: jest.fn((path: string) => getRef(path)),
    collection: jest.fn((name: string) => ({
      doc: jest.fn((id: string) => getRef(`${name}/${id}`)),
      where: (f: string, op: string, v: unknown) => makeQuery(name, f, v),
    })),
    // Commit applies the writes to `seededDocs`, as Firestore would, so a paged
    // sweep sees its own deletions and updates on the next page.
    batch: jest.fn(() => {
      const pending: Array<{ op: string; path: string; data?: any }> = [];
      return {
        update: (ref: any, data: any) => {
          batchOps.push({ op: "update", path: ref.path, data });
          pending.push({ op: "update", path: ref.path, data });
        },
        delete: (ref: any) => {
          batchOps.push({ op: "delete", path: ref.path });
          pending.push({ op: "delete", path: ref.path });
        },
        commit: async () => {
          await commit();
          for (const p of pending) {
            const [col, id] = p.path.split("/");
            const rows = seededDocs.get(col) ?? [];
            if (p.op === "delete") {
              seededDocs.set(col, rows.filter((r) => r.id !== id));
            } else {
              const row = rows.find((r) => r.id === id);
              if (row) row.data = { ...row.data, ...p.data };
            }
          }
        },
      };
    }),
    runTransaction: jest.fn(async (fn: (tx: any) => Promise<unknown>) => {
      const pending: Array<{ op: "update" | "delete"; path: string; data?: any }> = [];
      const tx = {
        get: async (ref: any) => {
          const [col, id] = ref.path.split("/");
          const row = (seededDocs.get(col) ?? []).find((r) => r.id === id);
          return {
            exists: !!row,
            id,
            ref,
            data: () => (row ? { ...row.data } : undefined),
          };
        },
        update: (ref: any, data: any) => {
          pending.push({ op: "update", path: ref.path, data });
        },
        // S02 fence write (`activity_account_state/{uid}`) uses tx.set; the
        // fence is not part of the booking/sweep assertions, so it is not
        // recorded in `txOps`.
        set: (_ref: any, _data: any) => undefined,
        delete: (ref: any) => {
          pending.push({ op: "delete", path: ref.path });
        },
      };
      const result = await fn(tx);
      // The S02 fence transaction writes only via `set` (no pending ops); it is
      // not a booking commit, so it must not count as one.
      if (pending.length > 0) await txCommit();
      for (const p of pending) {
        txOps.push(p);
        const [col, id] = p.path.split("/");
        const rows = seededDocs.get(col) ?? [];
        if (p.op === "delete") {
          seededDocs.set(col, rows.filter((r) => r.id !== id));
        } else {
          const row = rows.find((r) => r.id === id);
          if (row) row.data = { ...row.data, ...p.data };
        }
      }
      return result;
    }),
    recursiveDelete,
  }));
  // The retry record stores Timestamps; a plain marker object is enough here.
  firestoreFn.Timestamp = {
    fromMillis: (ms: number) => ({ __ts: ms }),
  };
  return {
    initializeApp: jest.fn(),
    firestore: firestoreFn,
    auth: jest.fn(() => ({ deleteUser, revokeRefreshTokens })),
    __getRef: getRef,
    __reset: () => refs.clear(),
  };
});

const cancel = jest.fn();
const retrieve = jest.fn();
const listSubscriptions = jest.fn();
jest.mock("stripe", () => {
  const instance = {
    subscriptions: { cancel, retrieve, list: listSubscriptions },
  };
  const ctor: any = jest.fn(() => instance);
  ctor.__instance = instance;
  return ctor;
});

jest.mock("firebase-functions/logger", () => ({
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

/**
 * C12: `sweepAccountData` also deletes the user's objects in the private
 * body-scan bucket (`BODY_SCAN_BUCKET`). Storage is modelled by `deleteFiles`
 * only; the bucket name requested is recorded so the tests can prove which
 * bucket the sweep addressed.
 */
const storageDeleteFiles = jest.fn(async (_opts?: unknown) => undefined as unknown);
const storageBucket = jest.fn((_name?: string) => ({ deleteFiles: storageDeleteFiles }));
jest.mock("firebase-admin/storage", () => ({
  getStorage: jest.fn(() => ({ bucket: storageBucket })),
}));

import * as logger from "firebase-functions/logger";
import { HttpsError } from "firebase-functions/v2/https";
import { deleteAccount } from "../index";

function req(auth?: { uid: string }, data: unknown = {}): any {
  return { data, auth, rawRequest: {} };
}

async function expectHttpsError(
  p: Promise<unknown>,
  code: string,
): Promise<HttpsError> {
  const err = await p.then(
    () => {
      throw new Error(`expected HttpsError("${code}") but the call resolved`);
    },
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  expect((err as HttpsError).code).toBe(code);
  return err as HttpsError;
}

beforeEach(() => {
  refs.clear();
  seededDocs.clear();
  batchOps.length = 0;
  txOps.length = 0;
  commit.mockClear();
  txCommit.mockReset().mockResolvedValue(undefined);
  listSubscriptions.mockReset().mockResolvedValue({ data: [] });
  recursiveDelete.mockReset().mockResolvedValue(undefined);
  deleteUser.mockReset().mockResolvedValue(undefined);
  revokeRefreshTokens.mockReset().mockResolvedValue(undefined);
  cancel.mockReset().mockResolvedValue(undefined);
  storageDeleteFiles.mockReset().mockResolvedValue(undefined);
  storageBucket.mockClear();
  delete process.env.BODY_SCAN_BUCKET;
  // Not-yet-canceled by default -- most tests exercise the ordinary path
  // where cancel() is actually expected to run. The idempotency tests below
  // override this per-case.
  retrieve.mockReset().mockResolvedValue({ status: "active" });
});

describe("deleteAccount", () => {
  test("rejects when signed out", async () => {
    await expectHttpsError(deleteAccount.run(req(undefined)), "unauthenticated");
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("happy path with a subscription: cancels, deletes data, deletes the user",
    async () => {
      const ref = getRef("users/u1/subscription/main");
      ref.__setStored({ stripeSubscriptionId: "sub_123" });

      const res = await deleteAccount.run(req({ uid: "u1" }));

      expect(res).toEqual({ success: true, finalCleanup: "complete" });
      expect(retrieve).toHaveBeenCalledWith("sub_123");
      expect(cancel).toHaveBeenCalledWith("sub_123");
      // Three collections: users/{uid}, donor_wall/{uid}, coach_listings/{uid}.
      expect(recursiveDelete).toHaveBeenCalledTimes(6);
      expect(deleteUser).toHaveBeenCalledWith("u1");
    });

  test("revokes refresh tokens before any data is touched", async () => {
    const order: string[] = [];
    revokeRefreshTokens.mockImplementation(async () => {
      order.push("revoke");
    });
    recursiveDelete.mockImplementation(async () => {
      order.push("recursiveDelete");
    });
    await deleteAccount.run(req({ uid: "u1" }));
    expect(revokeRefreshTokens).toHaveBeenCalledWith("u1");
    expect(order[0]).toBe("revoke");
    expect(order).toContain("recursiveDelete");
  });

  test("a failed token revocation is logged by name and does not block deletion",
    async () => {
      revokeRefreshTokens.mockRejectedValue(new Error("auth backend down"));
      const res = await deleteAccount.run(req({ uid: "u1" }));
      expect(res).toEqual({ success: true, finalCleanup: "complete" });
      expect(logger.error).toHaveBeenCalledWith(
        "delete_account_revoke_tokens_failed",
        expect.objectContaining({ uid: "u1" }),
      );
      expect(recursiveDelete).toHaveBeenCalledTimes(6);
      expect(deleteUser).toHaveBeenCalledWith("u1");
    });

  test("deletes donor_wall and coach_listings too, not only users/{uid}",
    async () => {
      // Both are separate top-level collections keyed by uid
      // (optInDonorWall, startCoachOnboarding) -- missed entirely by the
      // first version of this function, which only reached users/{uid}.
      const targeted: string[] = [];
      recursiveDelete.mockImplementation(async (ref: any) => {
        targeted.push(ref.path);
      });

      await deleteAccount.run(req({ uid: "u1" }));

      // Each is swept twice: before and after the Auth deletion.
      expect(targeted.sort()).toEqual([
        "coach_listings/u1",
        "coach_listings/u1",
        "donor_wall/u1",
        "donor_wall/u1",
        "users/u1",
        "users/u1",
      ]);
    });

  test("no subscription on file: skips Stripe, still deletes everything else",
    async () => {
      // No __setStored -- the doc read resolves `exists: false`.
      const res = await deleteAccount.run(req({ uid: "u1" }));

      expect(res).toEqual({ success: true, finalCleanup: "complete" });
      expect(retrieve).not.toHaveBeenCalled();
      expect(cancel).not.toHaveBeenCalled();
      expect(recursiveDelete).toHaveBeenCalledTimes(6);
      expect(deleteUser).toHaveBeenCalledWith("u1");
    });

  describe("idempotency: a retried call converges instead of erroring", () => {
    // Three independent reviewers converged on the same gap: a client retry
    // (a dropped response after the server already finished, or the
    // client's own token-refresh-and-retry on 'unauthenticated') must not
    // report "your account has not been deleted" for an account that, in
    // fact, already was.

    test("an already-canceled subscription is not re-cancelled, and is not an error",
      async () => {
        getRef("users/u1/subscription/main").__setStored({
          stripeSubscriptionId: "sub_123",
        });
        retrieve.mockResolvedValue({ status: "canceled" });

        const res = await deleteAccount.run(req({ uid: "u1" }));

        expect(res).toEqual({ success: true, finalCleanup: "complete" });
        expect(retrieve).toHaveBeenCalledWith("sub_123");
        expect(cancel).not.toHaveBeenCalled();
      });

    test("deleting an already-deleted Auth user is treated as success",
      async () => {
        const err: any = new Error("There is no user record...");
        err.code = "auth/user-not-found";
        deleteUser.mockRejectedValue(err);

        const res = await deleteAccount.run(req({ uid: "u1" }));

        expect(res).toEqual({ success: true, finalCleanup: "complete" });
      });

    test("a genuinely different Auth error still fails loudly, not silently",
      async () => {
        // The idempotency fix must not become a blanket swallow -- only the
        // one code that means "already done" is forgiven.
        const err: any = new Error("internal auth backend error");
        err.code = "auth/internal-error";
        deleteUser.mockRejectedValue(err);

        await expectHttpsError(
          deleteAccount.run(req({ uid: "u1" })),
          "internal",
        );
      });
  });

  test("ORDER: Stripe is cancelled before Firestore data is touched, "
    + "which is deleted before the Auth user is",
    async () => {
      const order: string[] = [];
      cancel.mockImplementation(async () => {
        order.push("cancel");
      });
      // recursiveDelete runs three times in parallel (users, donor_wall,
      // coach_listings) -- what matters for ordering is that all three
      // land as a group between "cancel" and "deleteUser", not their
      // relative order against each other.
      recursiveDelete.mockImplementation(async () => {
        order.push("recursiveDelete");
      });
      deleteUser.mockImplementation(async () => {
        order.push("deleteUser");
      });
      getRef("users/u1/subscription/main").__setStored({
        stripeSubscriptionId: "sub_123",
      });

      await deleteAccount.run(req({ uid: "u1" }));

      expect(order).toEqual([
        "cancel",
        "recursiveDelete",
        "recursiveDelete",
        "recursiveDelete",
        "deleteUser",
        // Final sweep after the Auth deletion.
        "recursiveDelete",
        "recursiveDelete",
        "recursiveDelete",
      ]);
    });

  test(
    "a failed cancellation stops the call before any data is deleted",
    async () => {
      getRef("users/u1/subscription/main").__setStored({
        stripeSubscriptionId: "sub_123",
      });
      cancel.mockRejectedValue(new Error("stripe is down"));

      await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

      // The whole reason cancellation runs first: a failure here must never
      // be followed by deleting the account anyway.
      expect(recursiveDelete).not.toHaveBeenCalled();
      expect(deleteUser).not.toHaveBeenCalled();
    },
  );

  test(
    "a failed Firestore delete stops the call before the Auth user is touched",
    async () => {
      recursiveDelete.mockRejectedValue(new Error("bulkwriter failed"));

      await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

      // Stripe was already cancelled (there was nothing to cancel here, so
      // this asserts the NEXT step didn't run, not that the first one was
      // skipped) -- the account must stay reachable for a retry, which means
      // the Auth user must still exist.
      expect(deleteUser).not.toHaveBeenCalled();
    },
  );

  test("a failed Auth deletion still reports the real failure, not a false success",
    async () => {
      deleteUser.mockRejectedValue(new Error("auth backend down"));

      await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");
    });

  test("a spoofed uid in the request body is ignored -- only request.auth.uid counts",
    async () => {
      // The plan's own worry is "deleting someone else's account". Closed
      // structurally: the handler never reads `request.data` for a uid at
      // all, only `request.auth.uid`, which `onCall` derives from the
      // caller's own verified ID token and a client cannot forge. This
      // proves it rather than asserting the absence of a code path -- a
      // `data.uid` that pointed at a different account and got used anyway
      // would show up here as `deleteUser` being called with "attacker",
      // not "u1".
      await deleteAccount.run(req({ uid: "u1" }, { uid: "attacker" }));

      expect(deleteUser).toHaveBeenCalledWith("u1");
      expect(deleteUser).not.toHaveBeenCalledWith("attacker");
    });

  // ---------------------------------------------------------------------
  // A1 — what the audit of 2026-08-11 found this function did NOT do.
  // ---------------------------------------------------------------------

  test("cancels EVERY subscription on the customer, not just the stored id",
    async () => {
      // The failure this closes: two Checkout sessions produce two live
      // subscriptions, the webhook overwrites `stripeSubscriptionId` with the
      // second, and deleting the account cancelled only that one -- leaving
      // the first billing a card its owner can no longer reach.
      getRef("users/u1/subscription/main").__setStored({
        stripeSubscriptionId: "sub_second",
        stripeCustomerId: "cus_1",
      });
      listSubscriptions.mockResolvedValue({
        data: [{ id: "sub_first" }, { id: "sub_second" }],
      });

      await deleteAccount.run(req({ uid: "u1" }));

      expect(listSubscriptions).toHaveBeenCalledWith({
        customer: "cus_1",
        status: "all",
        limit: 100,
      });
      expect(cancel).toHaveBeenCalledWith("sub_first");
      expect(cancel).toHaveBeenCalledWith("sub_second");
      expect(cancel).toHaveBeenCalledTimes(2);
    });

  test("an already-canceled subscription in the listing is not cancelled twice",
    async () => {
      getRef("users/u1/subscription/main").__setStored({
        stripeCustomerId: "cus_1",
      });
      listSubscriptions.mockResolvedValue({
        data: [{ id: "sub_live" }, { id: "sub_dead" }],
      });
      retrieve.mockImplementation(async (id: string) => ({
        status: id === "sub_dead" ? "canceled" : "active",
      }));

      await deleteAccount.run(req({ uid: "u1" }));

      expect(cancel).toHaveBeenCalledWith("sub_live");
      expect(cancel).not.toHaveBeenCalledWith("sub_dead");
    });

  test("anonymises the departing side of a booking and keeps the counterparty's record",
    async () => {
      seed("coach_bookings", [
        { id: "b1", data: { clientUid: "u1", coachUid: "coach_9" } },
        { id: "b2", data: { clientUid: "client_7", coachUid: "u1" } },
      ]);

      await deleteAccount.run(req({ uid: "u1" }));

      // OLD expectation (batch ops) replaced: bookings are settled by one
      // transaction each, so the writes show up in `txOps`, not `batchOps`.
      expect(txOps).toEqual(
        expect.arrayContaining([
          {
            op: "update",
            path: "coach_bookings/b1",
            data: { clientUid: "deleted_user" },
          },
          {
            op: "update",
            path: "coach_bookings/b2",
            data: { coachUid: "deleted_user" },
          },
        ]),
      );
      expect(txOps).toHaveLength(2);
      // The record survives: a coach who was paid for a session keeps their
      // own row, with nothing in it pointing at a person any more.
      expect(txOps.some((o) => o.op === "delete")).toBe(false);
      expect(seededDocs.get("coach_bookings")).toEqual([
        { id: "b1", data: { clientUid: "deleted_user", coachUid: "coach_9" } },
        { id: "b2", data: { clientUid: "client_7", coachUid: "deleted_user" } },
      ]);
      // No booking write goes through a write batch any more.
      expect(batchOps.filter((o) => o.path.startsWith("coach_bookings/"))).toEqual([]);
    });

  test("deletes a booking whose OTHER side was already deleted", async () => {
    seed("coach_bookings", [
      { id: "b3", data: { clientUid: "u1", coachUid: "deleted_user" } },
    ]);

    await deleteAccount.run(req({ uid: "u1" }));

    // OLD expectation (batch delete) replaced by the transaction write.
    expect(txOps).toEqual([{ op: "delete", path: "coach_bookings/b3" }]);
    expect(seededDocs.get("coach_bookings")).toEqual([]);
  });

  test("a booking with an undefined counterparty side counts that side as gone and is deleted", async () => {
    seed("coach_bookings", [{ id: "b4", data: { clientUid: "u1" } }]);

    await deleteAccount.run(req({ uid: "u1" }));

    expect(txOps).toEqual([{ op: "delete", path: "coach_bookings/b4" }]);
    expect(seededDocs.get("coach_bookings")).toEqual([]);
  });

  test("a failed booking transaction fails the sweep with the same internal error and keeps the Auth user", async () => {
    seed("coach_bookings", [
      { id: "b1", data: { clientUid: "u1", coachUid: "coach_9" } },
    ]);
    txCommit.mockRejectedValueOnce(new Error("tx aborted"));

    await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");
    expect(deleteUser).not.toHaveBeenCalled();
    // Nothing was applied: the row is untouched and a retry can finish it.
    expect(seededDocs.get("coach_bookings")).toEqual([
      { id: "b1", data: { clientUid: "u1", coachUid: "coach_9" } },
    ]);
  });

  test("anonymises equipment reports and deletes debug telemetry", async () => {
    seed("equipment_reports", [
      { id: "r1", data: { reporterUid: "u1", fault: "cable frayed" } },
    ]);
    seed("debug_sessions", [{ id: "d1", data: { uid: "u1" } }]);

    await deleteAccount.run(req({ uid: "u1" }));

    // The gym still has to fix the cable; the person who reported it is gone.
    expect(batchOps).toContainEqual({
      op: "update",
      path: "equipment_reports/r1",
      data: { reporterUid: "deleted_user" },
    });
    // Telemetry has no counterparty, and `firestore.rules` forbids the client
    // deleting it -- the Admin SDK is the only thing that can.
    expect(batchOps).toContainEqual({
      op: "delete",
      path: "debug_sessions/d1",
    });
    expect(commit).toHaveBeenCalled();
  });

  test("splits the sweep across batches instead of blowing Firestore's 500 cap",
    async () => {
      // Act-gate finding: one `db.batch()` with no bound. A coach with a long
      // booking history would make `commit()` throw, and the caller's own
      // message says the step "is safe to repeat" -- which it is, and it fails
      // identically every time, leaving the account permanently half-deleted.
      seed(
        "debug_sessions",
        Array.from({ length: 600 }, (_, i) => ({
          id: `d$${i}`,
          data: { uid: "u1" },
        })),
      );

      await deleteAccount.run(req({ uid: "u1" }));

      expect(batchOps).toHaveLength(600);
      expect(commit).toHaveBeenCalledTimes(2); // 450 + 150
    });

  test("pages the sweep: more rows than one page are all deleted, none left",
    async () => {
      const total = 1000; // more than two pages of 450
      seed(
        "debug_sessions",
        Array.from({ length: total }, (_, i) => ({
          id: `p${i}`,
          data: { uid: "u1" },
        })),
      );
      seed("debug_sessions", [
        ...(seededDocs.get("debug_sessions") ?? []),
        { id: "other", data: { uid: "someone_else" } },
      ]);

      await deleteAccount.run(req({ uid: "u1" }));

      expect(batchOps.filter((o) => o.op === "delete")).toHaveLength(total);
      expect(seededDocs.get("debug_sessions")).toEqual([
        { id: "other", data: { uid: "someone_else" } },
      ]);
      expect(commit).toHaveBeenCalledTimes(3); // 450 + 450 + 100
    });

  test("a sweep over an empty collection commits nothing", async () => {
    await deleteAccount.run(req({ uid: "u1" }));

    expect(batchOps).toEqual([]);
    expect(commit).not.toHaveBeenCalled();
  });

  test("boundary: exactly one page (450) is fully deleted in one commit",
    async () => {
      seed(
        "debug_sessions",
        Array.from({ length: 450 }, (_, i) => ({
          id: `one${i}`,
          data: { uid: "u1" },
        })),
      );

      await deleteAccount.run(req({ uid: "u1" }));

      expect(batchOps.filter((o) => o.op === "delete")).toHaveLength(450);
      expect(seededDocs.get("debug_sessions")).toEqual([]);
      // The follow-up read returns an empty page and commits nothing.
      expect(commit).toHaveBeenCalledTimes(1);
    });

  test("boundary: exactly two pages (900) are fully deleted in two commits",
    async () => {
      seed(
        "debug_sessions",
        Array.from({ length: 900 }, (_, i) => ({
          id: `two${i}`,
          data: { uid: "u1" },
        })),
      );

      await deleteAccount.run(req({ uid: "u1" }));

      expect(batchOps.filter((o) => o.op === "delete")).toHaveLength(900);
      expect(seededDocs.get("debug_sessions")).toEqual([]);
      expect(commit).toHaveBeenCalledTimes(2);
    });

  test("boundary: one row past a page (451) takes a second commit",
    async () => {
      seed(
        "debug_sessions",
        Array.from({ length: 451 }, (_, i) => ({
          id: `x${i}`,
          data: { uid: "u1" },
        })),
      );

      await deleteAccount.run(req({ uid: "u1" }));

      expect(batchOps.filter((o) => o.op === "delete")).toHaveLength(451);
      expect(seededDocs.get("debug_sessions")).toEqual([]);
      expect(commit).toHaveBeenCalledTimes(2); // 450 + 1
    });

  test("pages booking and report sweeps too: every row anonymised, none left",
    async () => {
      seed(
        "coach_bookings",
        Array.from({ length: 1000 }, (_, i) => ({
          id: `bk${i}`,
          data: { clientUid: "u1", coachUid: `coach_${i}` },
        })),
      );
      seed(
        "equipment_reports",
        Array.from({ length: 500 }, (_, i) => ({
          id: `er${i}`,
          data: { reporterUid: "u1" },
        })),
      );

      await deleteAccount.run(req({ uid: "u1" }));

      const bookings = seededDocs.get("coach_bookings") ?? [];
      expect(bookings).toHaveLength(1000); // counterparty records survive
      expect(bookings.every((b) => b.data.clientUid === "deleted_user")).toBe(
        true,
      );
      const reports = seededDocs.get("equipment_reports") ?? [];
      expect(reports).toHaveLength(500);
      expect(reports.every((r) => r.data.reporterUid === "deleted_user")).toBe(
        true,
      );
    });

  test("a failed page commit still surfaces the same internal error",
    async () => {
      seed(
        "debug_sessions",
        Array.from({ length: 600 }, (_, i) => ({
          id: `f${i}`,
          data: { uid: "u1" },
        })),
      );
      commit.mockRejectedValueOnce(new Error("commit failed"));

      await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");
      expect(deleteUser).not.toHaveBeenCalled();
    });

  test("leaves other users' shared records alone", async () => {
    seed("coach_bookings", [
      { id: "b9", data: { clientUid: "someone_else", coachUid: "coach_9" } },
    ]);
    seed("equipment_reports", [
      { id: "r9", data: { reporterUid: "someone_else" } },
    ]);

    await deleteAccount.run(req({ uid: "u1" }));

    expect(batchOps).toEqual([]);
    expect(txOps).toEqual([]);
    expect(txCommit).not.toHaveBeenCalled();
  });

  // -------------------------------------------------------------------
  // Partial failure, retries, pagination edges.
  // -------------------------------------------------------------------

  test("a self-booking (both sides u1) is deleted once, not anonymised twice", async () => {
    // The row matches BOTH booking queries. Two updates against one ref leave
    // a row naming deleted_user on both sides, which nobody can read again.
    seed("coach_bookings", [
      { id: "self", data: { clientUid: "u1", coachUid: "u1" } },
    ]);

    await deleteAccount.run(req({ uid: "u1" }));

    // OLD expectation (batch delete) replaced: one transaction, one delete.
    expect(txOps).toEqual([{ op: "delete", path: "coach_bookings/self" }]);
    expect(batchOps).toEqual([]);
    expect(seededDocs.get("coach_bookings")).toEqual([]);
  });

  test("a customer's subscriptions are listed across pages and every one is cancelled", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeCustomerId: "cus_1" });
    listSubscriptions
      .mockResolvedValueOnce({ data: [{ id: "s1" }, { id: "s2" }], has_more: true })
      .mockResolvedValueOnce({ data: [{ id: "s3" }], has_more: false });

    await deleteAccount.run(req({ uid: "u1" }));

    expect(listSubscriptions).toHaveBeenCalledTimes(2);
    expect(listSubscriptions).toHaveBeenLastCalledWith({
      customer: "cus_1",
      status: "all",
      limit: 100,
      starting_after: "s2",
    });
    expect(cancel.mock.calls.map((c) => c[0]).sort()).toEqual(["s1", "s2", "s3"]);
  });

  test("subscription paging is bounded at 20 pages even if Stripe never stops", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeCustomerId: "cus_1" });
    let n = 0;
    listSubscriptions.mockImplementation(async () => ({
      data: [{ id: `s${n++}` }],
      has_more: true,
    }));

    await deleteAccount.run(req({ uid: "u1" }));

    expect(listSubscriptions).toHaveBeenCalledTimes(20);
  });

  test("a failing subscription listing aborts before cancelling or deleting anything", async () => {
    getRef("users/u1/subscription/main").__setStored({
      stripeSubscriptionId: "sub_1",
      stripeCustomerId: "cus_1",
    });
    listSubscriptions.mockRejectedValue(new Error("stripe list 500"));

    await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(cancel).not.toHaveBeenCalled();
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("a failing status lookup aborts before any data is deleted", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeSubscriptionId: "sub_1" });
    retrieve.mockRejectedValue(new Error("stripe retrieve 500"));

    await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(cancel).not.toHaveBeenCalled();
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("half-cancelled then retried: the retry cancels only what is still live and finishes", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeCustomerId: "cus_1" });
    listSubscriptions.mockResolvedValue({ data: [{ id: "sA" }, { id: "sB" }], has_more: false });
    const live = new Set(["sA", "sB"]);
    retrieve.mockImplementation(async (id: string) => ({
      status: live.has(id) ? "active" : "canceled",
    }));
    cancel.mockImplementation(async (id: string) => {
      if (id === "sB") throw new Error("stripe cancel 500");
      live.delete(id);
    });

    await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();

    // Retry once Stripe recovers: sA is already gone and must not be cancelled again.
    cancel.mockClear();
    cancel.mockImplementation(async (id: string) => {
      live.delete(id);
    });
    await expect(deleteAccount.run(req({ uid: "u1" }))).resolves.toEqual({ success: true, finalCleanup: "complete" });

    expect(cancel.mock.calls.map((c) => c[0])).toEqual(["sB"]);
    expect(deleteUser).toHaveBeenCalledTimes(1);
    expect(deleteUser).toHaveBeenCalledWith("u1");
  });

  test("a Firestore failure leaves the Auth user, and the retry completes the deletion", async () => {
    recursiveDelete.mockRejectedValueOnce(new Error("bulkwriter failed"));

    await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");
    expect(deleteUser).not.toHaveBeenCalled();

    await expect(deleteAccount.run(req({ uid: "u1" }))).resolves.toEqual({ success: true, finalCleanup: "complete" });
    expect(deleteUser).toHaveBeenCalledTimes(1);
    expect(deleteUser).toHaveBeenCalledWith("u1");
  });

  test("a failed sweep commit after a successful Stripe cancel reports the data failure, not a Stripe one", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeSubscriptionId: "sub_1" });
    seed("debug_sessions", [{ id: "d1", data: { uid: "u1" } }]);
    commit.mockRejectedValueOnce(new Error("commit failed"));

    const err = await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(cancel).toHaveBeenCalledWith("sub_1");
    expect(err.message).toMatch(/some of your data could not be deleted/);
    expect(deleteUser).not.toHaveBeenCalled();
  });
});

describe("deleteAccount ordering and the final sweep", () => {
  const trace = (order: string[]) => {
    cancel.mockImplementation(async () => {
      order.push("cancel");
    });
    revokeRefreshTokens.mockImplementation(async () => {
      order.push("revoke");
    });
    recursiveDelete.mockImplementation(async (ref: any) => {
      order.push(`sweep:${ref.path}`);
    });
    deleteUser.mockImplementation(async () => {
      order.push("deleteUser");
    });
  };

  test("cancel, then revoke, then sweep, then deleteUser, then the final sweep", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeSubscriptionId: "sub_1" });
    const order: string[] = [];
    trace(order);

    await deleteAccount.run(req({ uid: "u1" }));

    const sweeps = (from: number, to: number) => order.slice(from, to).sort();
    const paths = ["sweep:coach_listings/u1", "sweep:donor_wall/u1", "sweep:users/u1"];
    expect(order.slice(0, 2)).toEqual(["cancel", "revoke"]);
    expect(sweeps(2, 5)).toEqual(paths);
    expect(order[5]).toBe("deleteUser");
    expect(sweeps(6, 9)).toEqual(paths);
    expect(order).toHaveLength(9);
  });

  test("the durable intent record is written after the first sweep and BEFORE the Auth user is deleted", async () => {
    const order: string[] = [];
    recursiveDelete.mockImplementation(async () => {
      order.push("sweep");
    });
    getRef("accountDeletionRetries/u1").set.mockImplementation(
      async (data: any) => {
        order.push("intent");
        getRef("accountDeletionRetries/u1").__setStored(data);
      },
    );
    deleteUser.mockImplementation(async () => {
      order.push("deleteUser");
    });

    await deleteAccount.run(req({ uid: "u1" }));

    // 3 first-pass sweeps, the intent record, deleteUser, 3 final sweeps.
    expect(order).toEqual([
      "sweep",
      "sweep",
      "sweep",
      "intent",
      "deleteUser",
      "sweep",
      "sweep",
      "sweep",
    ]);
  });

  test("the intent record has exactly the agreed fields: pending, attempts 0, createdAt, nextAttemptAt +15 min, expireAt +30 days, no error code", async () => {
    let recordAtDeleteUser: any;
    deleteUser.mockImplementation(async () => {
      recordAtDeleteUser = (await getRef("accountDeletionRetries/u1").get()).data();
    });

    await deleteAccount.run(req({ uid: "u1" }));

    expect(Object.keys(recordAtDeleteUser).sort()).toEqual([
      "attempts",
      "createdAt",
      "expireAt",
      "nextAttemptAt",
      "status",
      "uid",
    ]);
    expect(recordAtDeleteUser).toMatchObject({
      uid: "u1",
      status: "pending",
      attempts: 0,
    });
    expect(
      recordAtDeleteUser.nextAttemptAt.__ts - recordAtDeleteUser.createdAt.__ts,
    ).toBe(15 * 60 * 1000);
    expect(
      recordAtDeleteUser.expireAt.__ts - recordAtDeleteUser.createdAt.__ts,
    ).toBe(30 * 24 * 60 * 60 * 1000);
  });

  test("a clean final sweep removes the intent record and reports complete", async () => {
    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(getRef("accountDeletionRetries/u1").delete).toHaveBeenCalledTimes(1);
    expect((await getRef("accountDeletionRetries/u1").get()).exists).toBe(false);
  });

  test("a failed delete of the intent record after a clean sweep is harmless", async () => {
    getRef("accountDeletionRetries/u1").delete.mockRejectedValue(
      new Error("firestore blip"),
    );

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(logger.error).not.toHaveBeenCalledWith(
      "delete_account_final_sweep_failed",
      expect.anything(),
    );
  });

  test("if the intent record cannot be written, the call aborts BEFORE the Auth user is deleted and can be repeated", async () => {
    (logger.error as jest.Mock).mockClear();
    getRef("accountDeletionRetries/u1").set.mockRejectedValueOnce(
      new Error("firestore down"),
    );

    const err = await expectHttpsError(
      deleteAccount.run(req({ uid: "u1" })),
      "internal",
    );

    expect(err.message).toMatch(/try again/i);
    expect(deleteUser).not.toHaveBeenCalled();
    expect(logger.error).toHaveBeenCalledWith(
      "delete_account_intent_record_failed",
      expect.objectContaining({ uid: "u1" }),
    );

    // Firestore recovered: the same call now completes.
    const res = await deleteAccount.run(req({ uid: "u1" }));
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(deleteUser).toHaveBeenCalledTimes(1);
  });

  test("the final sweep failure is logged by name, the intent record stays with an error code, and the call is NOT reported as complete", async () => {
    let afterDeleteUser = false;
    deleteUser.mockImplementation(async () => {
      afterDeleteUser = true;
    });
    recursiveDelete.mockImplementation(async () => {
      if (afterDeleteUser) {
        throw Object.assign(new Error("firestore down for user@example.com"), {
          code: "unavailable",
        });
      }
    });

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(recursiveDelete).toHaveBeenCalledTimes(6);
    expect(logger.error).toHaveBeenCalledWith(
      "delete_account_final_sweep_failed",
      expect.objectContaining({ uid: "u1" }),
    );
    expect(getRef("accountDeletionRetries/u1").delete).not.toHaveBeenCalled();
    // Bookkeeping only: a bare code, never the error message.
    const record = (await getRef("accountDeletionRetries/u1").get()).data();
    expect(Object.keys(record).sort()).toEqual([
      "attempts",
      "createdAt",
      "expireAt",
      "lastErrorCode",
      "nextAttemptAt",
      "status",
      "uid",
    ]);
    expect(record).toMatchObject({
      uid: "u1",
      status: "pending",
      attempts: 1,
      lastErrorCode: "unavailable",
    });
    expect(JSON.stringify(record)).not.toContain("example.com");
  });

  test("a non-Error throw in the final sweep still leaves the record and reports scheduled", async () => {
    let afterDeleteUser = false;
    deleteUser.mockImplementation(async () => {
      afterDeleteUser = true;
    });
    recursiveDelete.mockImplementation(async () => {
      // eslint-disable-next-line no-throw-literal
      if (afterDeleteUser) throw "string, not an Error";
    });

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    const record = (await getRef("accountDeletionRetries/u1").get()).data();
    expect(record).toMatchObject({ status: "pending", lastErrorCode: "unknown" });
  });

  test("if even the failure note cannot be written, the record from before the Auth deletion keeps the deletion retryable", async () => {
    let afterDeleteUser = false;
    deleteUser.mockImplementation(async () => {
      afterDeleteUser = true;
      // Only the failure note (a merge write) fails; the intent already landed.
      getRef("accountDeletionRetries/u1").set.mockRejectedValue(
        new Error("firestore still down"),
      );
    });
    recursiveDelete.mockImplementation(async () => {
      if (afterDeleteUser) throw new Error("firestore down");
    });

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    const record = (await getRef("accountDeletionRetries/u1").get()).data();
    expect(record).toMatchObject({ uid: "u1", status: "pending", attempts: 0 });
  });

  test("a failed Stripe cancel leaves refresh tokens unrevoked", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeSubscriptionId: "sub_1" });
    cancel.mockRejectedValue(new Error("stripe down"));

    await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(revokeRefreshTokens).not.toHaveBeenCalled();
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });
});

describe("deleteAccount journey: failure combinations a user can hit and retry", () => {
  const FIRESTORE_FAILED = "account deletion: failed to delete Firestore data";
  const AUTH_FAILED = "account deletion: failed to delete the Auth user";
  const STRIPE_FAILED = "account deletion: failed to cancel subscription";

  test("a failed cancel keeps all data and tokens, answers a retryable error, and the retry completes", async () => {
    getRef("users/u1/subscription/main").__setStored({ stripeSubscriptionId: "sub_1" });
    seed("debug_sessions", [{ id: "d1", data: { uid: "u1" } }]);
    cancel.mockRejectedValueOnce(new Error("stripe down"));

    const err = await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(err.message).toMatch(/Your account has not been deleted/);
    expect(err.message).toMatch(/try again/i);
    expect(logger.error).toHaveBeenCalledWith(
      STRIPE_FAILED,
      expect.objectContaining({ uid: "u1", subscriptionId: "sub_1" }),
    );
    expect(revokeRefreshTokens).not.toHaveBeenCalled();
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
    expect(batchOps).toEqual([]);
    expect(seededDocs.get("debug_sessions")).toHaveLength(1);
    expect(deleteUser).not.toHaveBeenCalled();

    // Stripe recovered: the same call now deletes everything, revoking once.
    const res = await deleteAccount.run(req({ uid: "u1" }));
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(cancel).toHaveBeenCalledTimes(2);
    expect(revokeRefreshTokens).toHaveBeenCalledTimes(1);
    expect(seededDocs.get("debug_sessions")).toEqual([]);
    expect(deleteUser).toHaveBeenCalledTimes(1);
  });

  test("a failed revoke plus a failed first sweep: error, Auth user kept, no final sweep; the retry converges", async () => {
    revokeRefreshTokens.mockRejectedValueOnce(new Error("auth backend down"));
    recursiveDelete.mockRejectedValueOnce(new Error("bulkwriter failed"));

    const err = await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(err.message).toMatch(/some of your data could not be deleted/);
    expect(logger.error).toHaveBeenCalledWith(
      "delete_account_revoke_tokens_failed",
      expect.objectContaining({ uid: "u1" }),
    );
    expect(logger.error).toHaveBeenCalledWith(
      FIRESTORE_FAILED,
      expect.objectContaining({ uid: "u1" }),
    );
    // Only the three first-pass sweeps ran; the final sweep belongs after deleteUser.
    expect(recursiveDelete).toHaveBeenCalledTimes(3);
    expect(deleteUser).not.toHaveBeenCalled();

    const res = await deleteAccount.run(req({ uid: "u1" }));
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    // Retry adds three first-pass sweeps, deleteUser and three final sweeps.
    expect(recursiveDelete).toHaveBeenCalledTimes(9);
    expect(deleteUser).toHaveBeenCalledTimes(1);
  });

  test("a failed revoke plus a failed final sweep: still a success, scheduled for reconciliation, both named in the log", async () => {
    (logger.error as jest.Mock).mockClear(); // the logger mock is shared across tests
    revokeRefreshTokens.mockRejectedValue(new Error("auth backend down"));
    let afterDeleteUser = false;
    deleteUser.mockImplementation(async () => {
      afterDeleteUser = true;
    });
    recursiveDelete.mockImplementation(async () => {
      if (afterDeleteUser) throw new Error("firestore down");
    });

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(deleteUser).toHaveBeenCalledTimes(1);
    const events = (logger.error as jest.Mock).mock.calls.map((c) => c[0]);
    expect(events).toContain("delete_account_revoke_tokens_failed");
    expect(events).toContain("delete_account_final_sweep_failed");
    expect(events).not.toContain(FIRESTORE_FAILED);
    expect(events).not.toContain(AUTH_FAILED);
  });

  test("a failed Auth deletion after the wipe: the message says so, no final sweep runs, the retry finishes", async () => {
    deleteUser.mockRejectedValueOnce(
      Object.assign(new Error("auth internal"), { code: "auth/internal-error" }),
    );

    const err = await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(err.message).toMatch(/Your data was deleted, but signing out could not be completed/);
    expect(logger.error).toHaveBeenCalledWith(
      AUTH_FAILED,
      expect.objectContaining({ uid: "u1" }),
    );
    expect(recursiveDelete).toHaveBeenCalledTimes(3);

    const res = await deleteAccount.run(req({ uid: "u1" }));
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(deleteUser).toHaveBeenCalledTimes(2);
    expect(recursiveDelete).toHaveBeenCalledTimes(9);
  });

  test("the shared-record sweep commits fall after the first recursive sweep and before deleteUser", async () => {
    seed("coach_bookings", [{ id: "b1", data: { clientUid: "u1", coachUid: "coach_9" } }]);
    seed("equipment_reports", [{ id: "r1", data: { reporterUid: "u1" } }]);
    seed("debug_sessions", [{ id: "d1", data: { uid: "u1" } }]);
    const order: string[] = [];
    recursiveDelete.mockImplementation(async (ref: any) => {
      order.push(`sweep:${ref.path}`);
    });
    deleteUser.mockImplementation(async () => {
      order.push("deleteUser");
    });
    commit.mockImplementation(async () => {
      order.push(`commit:${batchOps[batchOps.length - 1].path}`);
    });
    // The booking is committed by a transaction now (OLD: a batch commit); its
    // pending write is not in `txOps` yet when `txCommit` fires, so name it.
    txCommit.mockImplementation(async () => {
      order.push("commit:coach_bookings/b1");
    });
    try {
      await deleteAccount.run(req({ uid: "u1" }));
    } finally {
      commit.mockImplementation(async () => undefined);
    }

    const commits = order.filter((o) => o.startsWith("commit:"));
    expect(commits).toEqual([
      "commit:coach_bookings/b1",
      "commit:equipment_reports/r1",
      "commit:debug_sessions/d1",
    ]);
    const lastFirstPassSweep = 2; // three Promise.all sweeps occupy indexes 0..2
    expect(order.slice(0, 3).every((o) => o.startsWith("sweep:"))).toBe(true);
    for (const c of commits) {
      expect(order.indexOf(c)).toBeGreaterThan(lastFirstPassSweep);
      expect(order.indexOf(c)).toBeLessThan(order.indexOf("deleteUser"));
    }
    // The final sweep comes strictly after deleteUser.
    expect(order.slice(order.indexOf("deleteUser") + 1).filter((o) => o.startsWith("sweep:"))).toHaveLength(3);
  });
});

/* ------------------------------------------------------------------ */
/* C12: the private body-scan bucket is part of the account sweep      */
/* ------------------------------------------------------------------ */

describe("deleteAccount: body-scan storage sweep (C12, design s7.6, SD-6)", () => {
  const BUCKET = "body-scan-test-bucket";
  const fail = (code?: number | string): Error => Object.assign(new Error("gcs failure for users/u1/scans/x/front.jpg"), code === undefined ? {} : { code });
  const errorLogs = (): string => JSON.stringify((logger.error as jest.Mock).mock.calls);

  beforeEach(() => {
    (logger.info as jest.Mock).mockClear();
    (logger.error as jest.Mock).mockClear();
  });

  test("bucket unset: a logged no-op, storage is never touched and the deletion completes", async () => {
    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(storageBucket).not.toHaveBeenCalled();
    expect(storageDeleteFiles).not.toHaveBeenCalled();
    const skipped = (logger.info as jest.Mock).mock.calls.filter(
      (c) => c[0] === "body_scan_storage_sweep_skipped_unconfigured",
    );
    expect(skipped).toHaveLength(2); // the Step 2 sweep and the final sweep
    expect(JSON.stringify(skipped)).not.toContain("u1");
  });

  test("a malformed bucket name counts as unset (a typo never points the purge elsewhere)", async () => {
    process.env.BODY_SCAN_BUCKET = "Not A Bucket";
    await deleteAccount.run(req({ uid: "u1" }));
    expect(storageBucket).not.toHaveBeenCalled();
  });

  test("bucket set: deleteFiles({prefix: users/<uid>/, force: true}) on the configured bucket, in the Step 2 sweep AND the final sweep", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(storageBucket.mock.calls).toEqual([[BUCKET], [BUCKET]]);
    expect(storageDeleteFiles.mock.calls).toEqual([
      [{ prefix: "users/u1/", force: true }],
      [{ prefix: "users/u1/", force: true }],
    ]);
  });

  test("the prefix is built from the caller's uid only (a different uid addresses a different prefix)", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    await deleteAccount.run(req({ uid: "u2" }));
    expect(storageDeleteFiles.mock.calls.map((c) => (c[0] as any).prefix)).toEqual(["users/u2/", "users/u2/"]);
  });

  test("storage runs LAST in each sweep: all three Firestore sweeps, then storage, then (second time) after deleteUser", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    const order: string[] = [];
    recursiveDelete.mockImplementation(async (ref: any) => {
      order.push(`sweep:${ref.path}`);
    });
    storageDeleteFiles.mockImplementation(async () => {
      order.push("storage");
      return undefined;
    });
    deleteUser.mockImplementation(async () => {
      order.push("deleteUser");
    });

    await deleteAccount.run(req({ uid: "u1" }));

    expect(order.map((o) => (o.startsWith("sweep:") ? "sweep" : o))).toEqual([
      "sweep", "sweep", "sweep", "storage", "deleteUser", "sweep", "sweep", "sweep", "storage",
    ]);
  });

  test.each([
    ["a single 404 (bucket or object not found)", fail(404)],
    ["an array of 404s (force: true reports every failure)", [fail(404), fail(404), fail(404)]],
  ])("%s means nothing to delete: not an error", async (_name, rejection) => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockRejectedValue(rejection);

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(deleteUser).toHaveBeenCalledWith("u1");
    expect(logger.error).not.toHaveBeenCalledWith("delete_account_final_sweep_failed", expect.anything());
  });

  test.each([
    ["403 (IAM denied)", fail(403), "403"],
    ["500", fail(500), "500"],
    ["no code at all (network)", fail(), undefined],
    ["a mixed array [404, 403]: one real failure is enough", [fail(404), fail(403)], "404"],
    ["an array that starts with a real failure", [fail(403), fail(404)], "403"],
  ])("Step 2: %s throws after the Firestore sweep ran, so the call fails BEFORE the Auth user is deleted and can be repeated", async (_name, rejection, _code) => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockRejectedValue(rejection);

    const err = await expectHttpsError(deleteAccount.run(req({ uid: "u1" })), "internal");

    expect(err.message).toMatch(/some of your data could not be deleted/i);
    expect(recursiveDelete).toHaveBeenCalledTimes(3); // Firestore was swept first
    expect(deleteUser).not.toHaveBeenCalled();
    expect(getRef("accountDeletionRetries/u1").set).not.toHaveBeenCalled(); // no intent record yet
    // The logged error carries the sweep's generic message, never the SDK text with the object path.
    expect(errorLogs()).not.toContain("front.jpg");
    expect(errorLogs()).not.toContain("users/u1/scans");
  });

  test("final sweep: a 403 after the Auth user is gone -> finalCleanup scheduled and the retry record persists with the bare error code", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles
      .mockResolvedValueOnce(undefined) // Step 2 sweep
      .mockRejectedValueOnce(fail(403)); // final sweep

    const res = await deleteAccount.run(req({ uid: "u1" }));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(deleteUser).toHaveBeenCalledWith("u1");
    expect(recursiveDelete).toHaveBeenCalledTimes(6); // Firestore finished in BOTH sweeps
    const record = (await getRef("accountDeletionRetries/u1").get()).data();
    expect(record).toMatchObject({ uid: "u1", status: "pending", attempts: 1, lastErrorCode: "403" });
    expect(getRef("accountDeletionRetries/u1").delete).not.toHaveBeenCalled();
    expect(logger.error).toHaveBeenCalledWith("delete_account_final_sweep_failed", expect.anything());
    expect(JSON.stringify(record)).not.toContain("front.jpg");
  });

  test("final sweep: a 404 is not a failure, so the intent record is removed", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockResolvedValueOnce(undefined).mockRejectedValueOnce([fail(404)]);
    const res = await deleteAccount.run(req({ uid: "u1" }));
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect((await getRef("accountDeletionRetries/u1").get()).exists).toBe(false);
  });
});
