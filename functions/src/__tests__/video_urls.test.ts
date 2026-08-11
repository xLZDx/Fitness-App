/**
 * The clip signer, and specifically the thing that makes it survive 1,000
 * concurrent users: one signature serves everyone who asks for the same clip
 * inside the reuse window.
 *
 * Every signature is an external IAM round trip, so the assertions that
 * matter here are counts of `getSignedUrl` calls, not the URLs themselves.
 */
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

const getSignedUrl = jest.fn();
const file = jest.fn(() => ({ getSignedUrl }));
const bucket = jest.fn(() => ({ file }));

jest.mock("firebase-admin/storage", () => ({
  getStorage: jest.fn(() => ({ bucket })),
}));

/**
 * A6-lite gave both endpoints a per-user daily quota, which is a Firestore
 * transaction. Modelled rather than stubbed away: `usage` starts at whatever
 * `__setUsage` says, the transaction reads and writes it, so a test can drive
 * the counter to the ceiling and see the endpoint refuse.
 */
let usage: Record<string, number> = {};
const usagePaths: string[] = [];
jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({
    doc: jest.fn((path: string) => {
      usagePaths.push(path);
      return { path };
    }),
    runTransaction: jest.fn(async (fn: (tx: any) => Promise<void>) =>
      fn({
        get: async () => ({ data: () => ({ ...usage }) }),
        set: (_ref: any, data: Record<string, number>) => {
          usage = { ...usage, ...data };
        },
      }),
    ),
  })),
}));

import { clipUrl, clipUrls, __resetSignatureCache } from "../video_urls";
import { QUOTAS } from "../abuse_guard";

const TTL_SECONDS = 15 * 60;

/** A callable request with the shape `onCall` hands the handler. */
const req = (data: unknown, uid: string | null = "u1"): any => ({
  data,
  auth: uid ? { uid, token: {} } : undefined,
});

/** Distinct URL per call so a reused one is distinguishable from a fresh one. */
let signCount = 0;
beforeEach(() => {
  __resetSignatureCache();
  jest.clearAllMocks();
  usage = {};
  usagePaths.length = 0;
  signCount = 0;
  getSignedUrl.mockImplementation(async () => [
    `https://signed.test/${++signCount}`,
  ]);
});

describe("clipUrl", () => {
  const OBJ = "exercises/men/Chest/Barbell Bench Press.mp4";

  test("signs once and returns a url", async () => {
    const res = await clipUrl.run(req({ object: OBJ }));
    expect(res.url).toBe("https://signed.test/1");
    expect(getSignedUrl).toHaveBeenCalledTimes(1);
  });

  test("a second caller for the same clip does not sign again", async () => {
    // The finding this gate exists for: a V4 signature covers bucket, object
    // and expiry, and nothing about the caller — so two users were being
    // handed two different strings authorising exactly the same thing.
    const first = await clipUrl.run(req({ object: OBJ }, "u1"));
    const second = await clipUrl.run(req({ object: OBJ }, "u2"));
    expect(second.url).toBe(first.url);
    expect(getSignedUrl).toHaveBeenCalledTimes(1);
  });

  test("a burst of concurrent callers collapses to one signature", async () => {
    // Without in-flight de-duplication the cache is nearly useless against
    // the case it exists for: 80 concurrent requests all miss an empty map,
    // all sign, and 79 results race to overwrite each other.
    let release!: (v: [string]) => void;
    getSignedUrl.mockImplementationOnce(
      () => new Promise<[string]>((r) => (release = r)),
    );

    const inFlight = Array.from({ length: 50 }, () =>
      clipUrl.run(req({ object: OBJ })),
    );
    // A6-lite put the quota transaction in front of the signer, so no call
    // reaches `getSignedUrl` in the same turn any more and `release` is still
    // unassigned here. One macrotask is enough for all 50 to clear the
    // transaction and collapse onto the in-flight signature — which is the
    // property under test, and it survives the reordering.
    await new Promise((r) => setTimeout(r, 0));
    release(["https://signed.test/burst"]);
    const results = await Promise.all(inFlight);

    expect(getSignedUrl).toHaveBeenCalledTimes(1);
    for (const r of results) expect(r.url).toBe("https://signed.test/burst");
  });

  test("different clips are signed separately", async () => {
    await clipUrl.run(req({ object: OBJ }));
    await clipUrl.run(req({ object: "exercises/girl/Back/Lat Pulldown.mp4" }));
    expect(getSignedUrl).toHaveBeenCalledTimes(2);
  });

  test("every url handed out has at least the full TTL left", async () => {
    // The client caches for 13 minutes and ignores this field, so a URL
    // served with less than 15 minutes left would let the phone's cache
    // outlive the signature — a clip that starts and then 403s part-way, the
    // exact failure the 15-vs-13 margin was chosen to prevent.
    const first = await clipUrl.run(req({ object: OBJ }));
    expect(first.expiresInSeconds).toBeGreaterThanOrEqual(TTL_SECONDS);

    jest.spyOn(Date, "now").mockReturnValue(Date.now() + 4 * 60 * 1000);
    const reused = await clipUrl.run(req({ object: OBJ }));
    expect(reused.url).toBe(first.url);
    expect(reused.expiresInSeconds).toBeGreaterThanOrEqual(TTL_SECONDS);
    jest.restoreAllMocks();
  });

  test("a signature is re-minted once it falls under the TTL", async () => {
    const first = await clipUrl.run(req({ object: OBJ }));
    // 6 minutes on: 20 minutes minted minus 6 leaves 14, under the 15 the
    // reuse rule requires, so the cached entry must be dropped rather than
    // handed out with a shortened life.
    jest.spyOn(Date, "now").mockReturnValue(Date.now() + 6 * 60 * 1000);
    const second = await clipUrl.run(req({ object: OBJ }));
    expect(second.url).not.toBe(first.url);
    expect(getSignedUrl).toHaveBeenCalledTimes(2);
    jest.restoreAllMocks();
  });

  test("the cache is not a way around the auth gate", async () => {
    await clipUrl.run(req({ object: OBJ }, "u1"));
    await expect(clipUrl.run(req({ object: OBJ }, null))).rejects.toThrow(
      /Sign in/,
    );
  });

  test("a path outside the clip prefix is rejected before signing", async () => {
    await expect(
      clipUrl.run(req({ object: "../../etc/passwd" })),
    ).rejects.toThrow(/clip path/);
    expect(getSignedUrl).not.toHaveBeenCalled();
  });
});

describe("clipUrls", () => {
  const A = "exercises/men/Chest/Barbell Bench Press.mp4";
  const B = "exercises/girl/Back/Lat Pulldown.mp4";

  test("shares the cache with the single signer", async () => {
    // A prefetch after a play should not re-sign what the player already
    // minted, and vice versa.
    await clipUrl.run(req({ object: A }));
    const res = await clipUrls.run(req({ objects: [A, B] }));
    expect(getSignedUrl).toHaveBeenCalledTimes(2);
    expect(res.urls[A]).toBe("https://signed.test/1");
  });

  test("one bad object does not fail the batch", async () => {
    getSignedUrl
      .mockImplementationOnce(async () => ["https://signed.test/ok"])
      .mockImplementationOnce(async () => {
        throw new Error("no such object");
      });
    const res = await clipUrls.run(req({ objects: [A, B] }));
    expect(res.urls[A]).toBe("https://signed.test/ok");
    expect(res.urls[B]).toBeUndefined();
  });

  test("reports the shortest life in the batch", async () => {
    const res = await clipUrls.run(req({ objects: [A, B] }));
    expect(res.expiresInSeconds).toBeGreaterThanOrEqual(TTL_SECONDS);
  });

  test("still refuses more than sixty", async () => {
    const many = Array.from(
      { length: 61 },
      (_, i) => `exercises/men/Chest/clip ${i}.mp4`,
    );
    await expect(clipUrls.run(req({ objects: many }))).rejects.toThrow(
      /Too many/,
    );
    expect(getSignedUrl).not.toHaveBeenCalled();
  });
});

describe("A6-lite — per-user daily quota", () => {
  const OBJ = "exercises/men/Chest/Barbell Bench Press.mp4";

  test("refuses once the day's single-clip ceiling is reached", async () => {
    // The signed-in check stops an anonymous crawler. It does nothing about a
    // signed-in one looping the 2,539-clip library, which is the licence
    // breach the endpoint's own comment describes.
    usage = { clipUrl: QUOTAS.clipUrl };

    await expect(clipUrl.run(req({ object: OBJ }))).rejects.toThrow(
      /limit for this action/,
    );
    expect(getSignedUrl).not.toHaveBeenCalled();
  });

  test("the batch endpoint is charged in objects, not in calls", async () => {
    // Otherwise the two endpoints play against each other: 60 objects for the
    // price of one call is a way around the single-clip ceiling.
    await clipUrls.run(req({ objects: [OBJ, "exercises/girl/Back/Row.mp4"] }));

    expect(usage.clipUrlsObjects).toBe(2);
  });

  test("one call short of the ceiling still works", async () => {
    usage = { clipUrl: QUOTAS.clipUrl - 1 };

    const res = await clipUrl.run(req({ object: OBJ }));

    expect(res.url).toBe("https://signed.test/1");
    expect(usage.clipUrl).toBe(QUOTAS.clipUrl);
  });

  test("refunds the objects that never signed", async () => {
    // Charging must happen before signing -- otherwise a caller consumes IAM
    // operations for free by asking for objects that fail -- but a batch of
    // stale paths must not bill for work that never happened.
    getSignedUrl
      .mockImplementationOnce(async () => ["https://signed.test/ok"])
      .mockImplementationOnce(async () => {
        throw new Error("no such object");
      });

    await clipUrls.run(
      req({ objects: [OBJ, "exercises/girl/Back/Row.mp4"] }),
    );

    expect(usage.clipUrlsObjects).toBe(1);
  });

  test("a batch where NOTHING signs is an error, not an empty success",
    async () => {
      // It used to return `{urls: {}}` with a normal expiry. A systemic
      // signing fault -- the missing tokenCreator grant this file names --
      // then reached the phone as successful, empty prefetches instead of
      // errors, which reads as "this session has no clips".
      getSignedUrl.mockImplementation(async () => {
        throw new Error("SigningError: permission denied");
      });

      await expect(
        clipUrls.run(req({ objects: [OBJ] })),
      ).rejects.toThrow(/Could not prepare any/);
      // ...and the whole charge came back.
      expect(usage.clipUrlsObjects ?? 0).toBe(0);
    });

  test("the counter lives under the user document, so deletion erases it",
    async () => {
      // A top-level `usage/{uid}` would have become a fourth entry on
      // `core/DATA_INVENTORY_2026-08-11.md`'s orphan list the day it shipped.
      await clipUrl.run(req({ object: OBJ }, "u7"));

      expect(usagePaths.some((p) => p.startsWith("users/u7/usage/"))).toBe(true);
    });
});
