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

import { clipUrl, clipUrls, __resetSignatureCache } from "../video_urls";

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
