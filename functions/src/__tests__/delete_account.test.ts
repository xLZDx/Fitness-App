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
      set: jest.fn(async (data: any) => {
        stored = data;
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

const seed = (collection: string, docs: Array<{ id: string; data: any }>) =>
  seededDocs.set(collection, docs);

const makeQuery = (name: string, field?: string, value?: unknown): any => ({
  where: (f: string, _op: string, v: unknown) => makeQuery(name, f, v),
  get: jest.fn(async () => {
    const all = seededDocs.get(name) ?? [];
    const matched =
      field === undefined ? all : all.filter((d) => d.data[field] === value);
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
    batch: jest.fn(() => ({
      update: (ref: any, data: any) =>
        batchOps.push({ op: "update", path: ref.path, data }),
      delete: (ref: any) => batchOps.push({ op: "delete", path: ref.path }),
      commit,
    })),
    recursiveDelete,
  }));
  return {
    initializeApp: jest.fn(),
    firestore: firestoreFn,
    auth: jest.fn(() => ({ deleteUser })),
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
  commit.mockClear();
  listSubscriptions.mockReset().mockResolvedValue({ data: [] });
  recursiveDelete.mockReset().mockResolvedValue(undefined);
  deleteUser.mockReset().mockResolvedValue(undefined);
  cancel.mockReset().mockResolvedValue(undefined);
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

      expect(res).toEqual({ success: true });
      expect(retrieve).toHaveBeenCalledWith("sub_123");
      expect(cancel).toHaveBeenCalledWith("sub_123");
      // Three collections: users/{uid}, donor_wall/{uid}, coach_listings/{uid}.
      expect(recursiveDelete).toHaveBeenCalledTimes(3);
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

      expect(targeted.sort()).toEqual([
        "coach_listings/u1",
        "donor_wall/u1",
        "users/u1",
      ]);
    });

  test("no subscription on file: skips Stripe, still deletes everything else",
    async () => {
      // No __setStored -- the doc read resolves `exists: false`.
      const res = await deleteAccount.run(req({ uid: "u1" }));

      expect(res).toEqual({ success: true });
      expect(retrieve).not.toHaveBeenCalled();
      expect(cancel).not.toHaveBeenCalled();
      expect(recursiveDelete).toHaveBeenCalledTimes(3);
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

        expect(res).toEqual({ success: true });
        expect(retrieve).toHaveBeenCalledWith("sub_123");
        expect(cancel).not.toHaveBeenCalled();
      });

    test("deleting an already-deleted Auth user is treated as success",
      async () => {
        const err: any = new Error("There is no user record...");
        err.code = "auth/user-not-found";
        deleteUser.mockRejectedValue(err);

        const res = await deleteAccount.run(req({ uid: "u1" }));

        expect(res).toEqual({ success: true });
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

      expect(batchOps).toEqual(
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
      // The record survives: a coach who was paid for a session keeps their
      // own row, with nothing in it pointing at a person any more.
      expect(batchOps.some((o) => o.op === "delete")).toBe(false);
    });

  test("deletes a booking whose OTHER side was already deleted", async () => {
    seed("coach_bookings", [
      { id: "b3", data: { clientUid: "u1", coachUid: "deleted_user" } },
    ]);

    await deleteAccount.run(req({ uid: "u1" }));

    expect(batchOps).toContainEqual({
      op: "delete",
      path: "coach_bookings/b3",
    });
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

  test("leaves other users' shared records alone", async () => {
    seed("coach_bookings", [
      { id: "b9", data: { clientUid: "someone_else", coachUid: "coach_9" } },
    ]);
    seed("equipment_reports", [
      { id: "r9", data: { reporterUid: "someone_else" } },
    ]);

    await deleteAccount.run(req({ uid: "u1" }));

    expect(batchOps).toEqual([]);
  });
});
