/**
 * T02 (SCAN-40, FOOD-31, FOOD-32, FOOD-33 server infrastructure) -- the server
 * side of the Body Scan + Nutrition Coach flags and the shared outbound/budget
 * helpers that C02 added:
 *
 *  - `assertFeatureEnabled` / `FEATURE_DISABLED_MESSAGE` (`feature_flags.ts`)
 *  - `foodAiEnabled` / `foodLookupEnabled` (`food_flags.ts`)
 *  - `bodyScanBucketName` / `bodyScanCloudEnabled` / `bodyScanProviderId`
 *    (`body_scan/flags.ts`)
 *  - `safeFetch` and `buildUrl` (`nutrition_http.ts`, D-65)
 *  - the upstream budget helpers and `takeUpstreamBudget` (`nutrition_budget.ts`,
 *    D-64)
 *
 * No emulator, no network: environment variables are set per test, `fetch` and
 * Firestore are injected fakes. Every expected value below (document ids, TTL,
 * the 10/6 budgets, the encoded query strings) is written out literally rather
 * than derived from the implementation.
 */
import { assertFeatureEnabled, FEATURE_DISABLED_MESSAGE } from "../feature_flags";
import { foodAiEnabled, foodLookupEnabled } from "../food_flags";
import { bodyScanBucketName, bodyScanCloudEnabled, bodyScanProviderId } from "../body_scan/flags";
import {
  buildUrl,
  safeFetch,
  UpstreamError,
  NUTRITION_HOSTS,
  UPSTREAM_ERROR_SLUGS,
  DEFAULT_TIMEOUT_MS,
  MAX_BODY_BYTES,
  MAX_REDIRECTS,
} from "../nutrition_http";
import {
  OFF_READS_PER_MINUTE,
  OFF_SEARCHES_PER_MINUTE,
  BUDGET_TTL_MS,
  budgetLimit,
  budgetDocId,
  budgetExpireAt,
  takeUpstreamBudget,
} from "../nutrition_budget";

const ENV_KEYS = ["FOOD_AI_ENABLED", "FOOD_LOOKUP_ENABLED", "BODY_SCAN_BUCKET", "BODY_SCAN_PROVIDER"];
let saved: Record<string, string | undefined>;
beforeEach(() => {
  saved = {};
  for (const k of ENV_KEYS) {
    saved[k] = process.env[k];
    delete process.env[k];
  }
});
afterEach(() => {
  for (const k of ENV_KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
});

/* ------------------------------------------------------------------ */
/* assertFeatureEnabled                                                */
/* ------------------------------------------------------------------ */

describe("assertFeatureEnabled", () => {
  test("the slug is exactly 'feature-disabled'", () => {
    expect(FEATURE_DISABLED_MESSAGE).toBe("feature-disabled");
  });

  test("a disabled feature throws failed-precondition with the exact slug (client maps it, never retries)", () => {
    let thrown: unknown;
    try {
      assertFeatureEnabled(false);
    } catch (e) {
      thrown = e;
    }
    expect(thrown).toMatchObject({ code: "failed-precondition", message: "feature-disabled" });
    // No details payload: the error carries no user data and nothing to log.
    expect((thrown as { details?: unknown }).details).toBeUndefined();
  });

  test("an enabled feature returns undefined and throws nothing", () => {
    expect(assertFeatureEnabled(true)).toBeUndefined();
  });

  test("a falsy-but-not-false value is not accepted as enabled by the type system; only the boolean true passes", () => {
    // The helper takes the flag VALUE. `false` refuses, `true` passes -- no third state.
    expect(() => assertFeatureEnabled(false)).toThrow("feature-disabled");
    expect(() => assertFeatureEnabled(true)).not.toThrow();
  });
});

/* ------------------------------------------------------------------ */
/* food flags                                                          */
/* ------------------------------------------------------------------ */

describe("food flags default OFF and accept only the exact string 'true'", () => {
  test("unset -> both off", () => {
    expect(foodAiEnabled()).toBe(false);
    expect(foodLookupEnabled()).toBe(false);
  });

  test.each(["", "1", "TRUE", "True", "yes", "on", " true", "true ", "false", "0", "tru"])(
    "value %j keeps both flags off",
    (value) => {
      process.env.FOOD_AI_ENABLED = value;
      process.env.FOOD_LOOKUP_ENABLED = value;
      expect(foodAiEnabled()).toBe(false);
      expect(foodLookupEnabled()).toBe(false);
    },
  );

  test("'true' turns on only its own flag", () => {
    process.env.FOOD_AI_ENABLED = "true";
    expect(foodAiEnabled()).toBe(true);
    expect(foodLookupEnabled()).toBe(false);
    delete process.env.FOOD_AI_ENABLED;
    process.env.FOOD_LOOKUP_ENABLED = "true";
    expect(foodAiEnabled()).toBe(false);
    expect(foodLookupEnabled()).toBe(true);
  });

  test("read per call, not at module load: toggling at runtime is visible immediately", () => {
    expect(foodAiEnabled()).toBe(false);
    process.env.FOOD_AI_ENABLED = "true";
    expect(foodAiEnabled()).toBe(true);
    process.env.FOOD_AI_ENABLED = "false";
    expect(foodAiEnabled()).toBe(false);
  });
});

/* ------------------------------------------------------------------ */
/* body scan flags                                                     */
/* ------------------------------------------------------------------ */

describe("body scan bucket / provider flags", () => {
  test("unset -> no bucket, cloud path disabled, no provider", () => {
    expect(bodyScanBucketName()).toBeUndefined();
    expect(bodyScanCloudEnabled()).toBe(false);
    expect(bodyScanProviderId()).toBeUndefined();
  });

  test.each([
    "fitness-app-korostelev-body-scans",
    "abc",
    "a.b_c-d",
    "0abc9",
    "a".repeat(222),
  ])("valid bucket name %j enables the cloud path", (name) => {
    process.env.BODY_SCAN_BUCKET = name;
    expect(bodyScanBucketName()).toBe(name);
    expect(bodyScanCloudEnabled()).toBe(true);
  });

  test.each([
    "",
    "   ",
    "ab", // 2 chars: below the 3-char minimum
    "a".repeat(223), // above the 222 maximum
    "Upper-Case",
    "-leading",
    "trailing-",
    ".dot-start",
    "dot-end.",
    "_under-start",
    "has space",
    "has/slash",
    "gs://bucket",
    "bucket\n",
    "bücket",
  ])("invalid bucket name %j is 'not configured' (a typo disables, never retargets)", (name) => {
    process.env.BODY_SCAN_BUCKET = name;
    // The reader trims first, so "bucket\n" trims to a VALID "bucket"; every other
    // value above is invalid after trimming.
    if (name.trim() === "bucket") {
      expect(bodyScanBucketName()).toBe("bucket");
      return;
    }
    expect(bodyScanBucketName()).toBeUndefined();
    expect(bodyScanCloudEnabled()).toBe(false);
  });

  test("surrounding whitespace is trimmed before validation", () => {
    process.env.BODY_SCAN_BUCKET = "  my-bucket-1  ";
    expect(bodyScanBucketName()).toBe("my-bucket-1");
  });

  test("provider id is trimmed, empty/blank is undefined, anything else is passed through verbatim", () => {
    process.env.BODY_SCAN_PROVIDER = "  licensed-api ";
    expect(bodyScanProviderId()).toBe("licensed-api");
    process.env.BODY_SCAN_PROVIDER = "   ";
    expect(bodyScanProviderId()).toBeUndefined();
    process.env.BODY_SCAN_PROVIDER = "test-fake";
    expect(bodyScanProviderId()).toBe("test-fake");
    // No server-side provisional estimator (D-52): the reader does not special-case it.
    process.env.BODY_SCAN_PROVIDER = "provisional-anthropometric";
    expect(bodyScanProviderId()).toBe("provisional-anthropometric");
  });

  test("the bucket and provider flags are independent", () => {
    process.env.BODY_SCAN_PROVIDER = "test-fake";
    expect(bodyScanCloudEnabled()).toBe(false);
    delete process.env.BODY_SCAN_PROVIDER;
    process.env.BODY_SCAN_BUCKET = "some-bucket";
    expect(bodyScanProviderId()).toBeUndefined();
  });
});

/* ------------------------------------------------------------------ */
/* nutrition_budget                                                    */
/* ------------------------------------------------------------------ */

describe("nutrition_budget constants and pure helpers", () => {
  test("budgets sit BELOW Open Food Facts' documented 15 reads / 10 searches per minute", () => {
    expect(OFF_READS_PER_MINUTE).toBe(10);
    expect(OFF_SEARCHES_PER_MINUTE).toBe(6);
    expect(budgetLimit("read")).toBe(10);
    expect(budgetLimit("search")).toBe(6);
    expect(OFF_READS_PER_MINUTE).toBeLessThan(15);
    expect(OFF_SEARCHES_PER_MINUTE).toBeLessThan(10);
  });

  test("TTL is exactly one day", () => {
    expect(BUDGET_TTL_MS).toBe(86_400_000);
    const now = Date.UTC(2026, 9, 15, 14, 7, 33);
    expect(budgetExpireAt(now).getTime()).toBe(now + 86_400_000);
    expect(budgetExpireAt(now).toISOString()).toBe("2026-10-16T14:07:33.000Z");
  });

  test("document id is kind + UTC minute (hand-derived)", () => {
    const t = Date.UTC(2026, 9, 15, 14, 7, 33, 999);
    expect(budgetDocId("read", t)).toBe("budget_off_read_202610151407");
    expect(budgetDocId("search", t)).toBe("budget_off_search_202610151407");
  });

  test("the id changes exactly at the minute boundary, not before", () => {
    expect(budgetDocId("read", Date.UTC(2026, 9, 15, 14, 7, 59, 999))).toBe("budget_off_read_202610151407");
    expect(budgetDocId("read", Date.UTC(2026, 9, 15, 14, 8, 0, 0))).toBe("budget_off_read_202610151408");
  });

  test("the id is UTC, zero-padded, and rolls over midnight and the year", () => {
    expect(budgetDocId("read", Date.UTC(2026, 0, 2, 3, 4))).toBe("budget_off_read_202601020304");
    expect(budgetDocId("read", Date.UTC(2026, 11, 31, 23, 59))).toBe("budget_off_read_202612312359");
    expect(budgetDocId("read", Date.UTC(2027, 0, 1, 0, 0))).toBe("budget_off_read_202701010000");
  });
});

describe("takeUpstreamBudget (fake Firestore)", () => {
  /** A transactional fake: serial transactions over an in-memory map. */
  function fakeDb(opts: { failTransaction?: boolean } = {}) {
    const docs = new Map<string, Record<string, unknown>>();
    const sets: Array<{ path: string; data: Record<string, unknown>; options: unknown }> = [];
    const db = () =>
      ({
        collection: (c: string) => ({ doc: (id: string) => ({ path: `${c}/${id}` }) }),
        runTransaction: async (fn: (tx: unknown) => Promise<boolean>) => {
          if (opts.failTransaction) throw new Error("firestore unavailable");
          const tx = {
            get: async (ref: { path: string }) => ({ data: () => docs.get(ref.path) }),
            set: (ref: { path: string }, data: Record<string, unknown>, options: unknown) => {
              sets.push({ path: ref.path, data, options });
              docs.set(ref.path, { ...(docs.get(ref.path) ?? {}), ...data });
            },
          };
          return fn(tx);
        },
      }) as never;
    return { db, docs, sets };
  }
  const NOW = Date.UTC(2026, 9, 15, 14, 7, 33);

  test("10 reads win a slot in one minute and the 11th is refused", async () => {
    const f = fakeDb();
    const results: boolean[] = [];
    for (let i = 0; i < 11; i++) results.push(await takeUpstreamBudget("read", NOW, f.db));
    expect(results).toEqual([true, true, true, true, true, true, true, true, true, true, false]);
    expect(f.docs.get("nutrition_cache/budget_off_read_202610151407")?.count).toBe(10);
  });

  test("6 searches win and the 7th is refused", async () => {
    const f = fakeDb();
    const results: boolean[] = [];
    for (let i = 0; i < 7; i++) results.push(await takeUpstreamBudget("search", NOW, f.db));
    expect(results).toEqual([true, true, true, true, true, true, false]);
    expect(f.docs.get("nutrition_cache/budget_off_search_202610151407")?.count).toBe(6);
  });

  test("reads and searches have independent counters", async () => {
    const f = fakeDb();
    for (let i = 0; i < 10; i++) await takeUpstreamBudget("read", NOW, f.db);
    expect(await takeUpstreamBudget("read", NOW, f.db)).toBe(false);
    expect(await takeUpstreamBudget("search", NOW, f.db)).toBe(true);
  });

  test("a new UTC minute starts a fresh counter (separate document)", async () => {
    const f = fakeDb();
    for (let i = 0; i < 10; i++) await takeUpstreamBudget("read", NOW, f.db);
    expect(await takeUpstreamBudget("read", NOW, f.db)).toBe(false);
    const next = Date.UTC(2026, 9, 15, 14, 8, 0, 0);
    expect(await takeUpstreamBudget("read", next, f.db)).toBe(true);
    expect(f.docs.get("nutrition_cache/budget_off_read_202610151408")?.count).toBe(1);
    expect(f.docs.get("nutrition_cache/budget_off_read_202610151407")?.count).toBe(10);
  });

  test("a won slot writes {count, expireAt = now + 1 day} with merge, under nutrition_cache", async () => {
    const f = fakeDb();
    await takeUpstreamBudget("read", NOW, f.db);
    expect(f.sets).toHaveLength(1);
    expect(f.sets[0].path).toBe("nutrition_cache/budget_off_read_202610151407");
    expect(f.sets[0].options).toEqual({ merge: true });
    expect(f.sets[0].data.count).toBe(1);
    expect((f.sets[0].data.expireAt as Date).toISOString()).toBe("2026-10-16T14:07:33.000Z");
    expect(Object.keys(f.sets[0].data).sort()).toEqual(["count", "expireAt"]);
  });

  test("an exhausted minute writes NOTHING (refusal does not extend the counter)", async () => {
    const f = fakeDb();
    for (let i = 0; i < 6; i++) await takeUpstreamBudget("search", NOW, f.db);
    const writesBefore = f.sets.length;
    expect(await takeUpstreamBudget("search", NOW, f.db)).toBe(false);
    expect(f.sets.length).toBe(writesBefore);
  });

  test("fail-CLOSED: a Firestore failure rejects instead of granting a slot", async () => {
    const f = fakeDb({ failTransaction: true });
    await expect(takeUpstreamBudget("read", NOW, f.db)).rejects.toThrow("firestore unavailable");
  });

  test("a counter document without a numeric count is treated as zero", async () => {
    const f = fakeDb();
    f.docs.set("nutrition_cache/budget_off_read_202610151407", { expireAt: new Date(0) });
    expect(await takeUpstreamBudget("read", NOW, f.db)).toBe(true);
    expect(f.docs.get("nutrition_cache/budget_off_read_202610151407")?.count).toBe(1);
  });
});

/* ------------------------------------------------------------------ */
/* safeFetch / buildUrl                                                */
/* ------------------------------------------------------------------ */

describe("nutrition_http constants", () => {
  test("host allowlist, limits and slug set are exactly the designed ones", () => {
    expect([...NUTRITION_HOSTS]).toEqual(["world.openfoodfacts.org", "search.openfoodfacts.org", "api.nal.usda.gov"]);
    expect(DEFAULT_TIMEOUT_MS).toBe(5000);
    expect(MAX_BODY_BYTES).toBe(1_048_576);
    expect(MAX_REDIRECTS).toBe(3);
    expect([...UPSTREAM_ERROR_SLUGS]).toEqual([
      "upstream-host-not-allowed",
      "upstream-timeout",
      "upstream-unreachable",
      "upstream-rate-limited",
      "upstream-unavailable",
      "upstream-redirect-rejected",
      "upstream-too-large",
      "upstream-invalid-request",
    ]);
  });

  test("UpstreamError carries only the slug", () => {
    const e = new UpstreamError("upstream-timeout");
    expect(e.message).toBe("upstream-timeout");
    expect(e.slug).toBe("upstream-timeout");
    expect(e.name).toBe("UpstreamError");
    expect(e).toBeInstanceOf(Error);
    // Own properties: the slug and the class name. No URL, key, header or body field.
    expect(Object.keys(e).sort()).toEqual(["name", "slug"]);
  });
});

describe("buildUrl (FOOD-31: outbound request construction)", () => {
  test("a query term 'x&api_key=evil' stays ONE percent-encoded value", () => {
    const url = buildUrl({
      host: "world.openfoodfacts.org",
      pathSegments: ["cgi", "search.pl"],
      query: { search_terms: "x&api_key=evil" },
    });
    expect(url.toString()).toBe("https://world.openfoodfacts.org/cgi/search.pl?search_terms=x%26api_key%3Devil");
    expect(url.searchParams.get("search_terms")).toBe("x&api_key=evil");
    expect(url.searchParams.has("api_key")).toBe(false);
    expect([...url.searchParams.keys()]).toEqual(["search_terms"]);
  });

  test("a path segment 'a/../b' is one encoded segment, not a traversal", () => {
    const url = buildUrl({ host: "api.nal.usda.gov", pathSegments: ["fdc", "v1", "a/../b"] });
    expect(url.pathname).toBe("/fdc/v1/a%2F..%2Fb");
    expect(url.pathname.split("/")).toHaveLength(4);
  });

  test("a bare '..' or '.' segment is REFUSED: the URL parser would collapse it into path navigation (defect found by this test, fixed in nutrition_http.ts)", () => {
    for (const seg of ["..", "."]) {
      for (const segments of [["fdc", seg, "x"], [seg], [seg, "x"]]) {
        let slug: string | undefined;
        try {
          buildUrl({ host: "api.nal.usda.gov", pathSegments: segments });
        } catch (e) {
          slug = (e as UpstreamError).slug;
        }
        expect(slug).toBe("upstream-invalid-request");
      }
    }
  });

  test("segments that merely CONTAIN dots are fine and stay encoded (3017620422003.json, '...', '.a', 'a..b')", () => {
    const url = buildUrl({ host: "api.nal.usda.gov", pathSegments: ["3017620422003.json", "...", ".a", "a..b"] });
    expect(url.pathname).toBe("/3017620422003.json/.../.a/a..b");
  });

  test("safeFetch rejects a dot segment before any fetch", async () => {
    let called = 0;
    const fetchImpl = (async () => {
      called++;
      return new Response("x");
    }) as unknown as typeof fetch;
    await expect(safeFetch({ host: "api.nal.usda.gov", pathSegments: ["fdc", ".."] }, { fetchImpl })).rejects.toMatchObject({
      slug: "upstream-invalid-request",
    });
    expect(called).toBe(0);
  });

  test("query values are stringified, undefined values are skipped, order is preserved", () => {
    const url = buildUrl({
      host: "search.openfoodfacts.org",
      pathSegments: ["search"],
      query: { q: "oat milk", page_size: 10, page: undefined, fields: "code,product_name" },
    });
    expect(url.search).toBe("?q=oat+milk&page_size=10&fields=code%2Cproduct_name");
  });

  test("no query -> no '?' at all", () => {
    expect(buildUrl({ host: "api.nal.usda.gov", pathSegments: ["x"] }).toString()).toBe("https://api.nal.usda.gov/x");
  });

  test("a barcode path segment is encoded as given", () => {
    const url = buildUrl({ host: "world.openfoodfacts.org", pathSegments: ["api", "v2", "product", "3017620422003.json"] });
    expect(url.toString()).toBe("https://world.openfoodfacts.org/api/v2/product/3017620422003.json");
  });

  test.each(["evil.example.com", "world.openfoodfacts.org.evil.com", "openfoodfacts.org", "localhost", "127.0.0.1", ""])(
    "host %j outside the allowlist is rejected with upstream-host-not-allowed",
    (host) => {
      expect(() => buildUrl({ host: host as never, pathSegments: ["x"] })).toThrow(UpstreamError);
      try {
        buildUrl({ host: host as never, pathSegments: ["x"] });
      } catch (e) {
        expect((e as UpstreamError).slug).toBe("upstream-host-not-allowed");
      }
    },
  );
});

describe("safeFetch", () => {
  const BASE = { host: "world.openfoodfacts.org", pathSegments: ["api", "v2", "product", "123.json"] } as const;

  const res = (body: string | null, init: ResponseInit = {}) => new Response(body, init);
  const redirect = (location: string | null, status = 302) =>
    new Response(null, { status, headers: location === null ? {} : { location } });

  /** A fetch fake that serves queued responses and records every call. */
  function queued(...responses: Array<Response | Error | ((init: RequestInit) => Promise<Response>)>) {
    const calls: Array<{ url: string; init: RequestInit }> = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      calls.push({ url: String(url), init });
      const next = responses.shift();
      if (next === undefined) throw new Error("unexpected extra fetch");
      if (next instanceof Error) throw next;
      if (typeof next === "function") return next(init);
      return next;
    }) as unknown as typeof fetch;
    return { fetchImpl, calls };
  }

  async function slugOf(p: Promise<unknown>): Promise<string> {
    try {
      await p;
    } catch (e) {
      expect(e).toBeInstanceOf(UpstreamError);
      return (e as UpstreamError).slug;
    }
    throw new Error("expected safeFetch to reject");
  }

  test("a 200 returns status and the UTF-8 body; one GET with redirect:manual and an abort signal", async () => {
    const f = queued(res('{"status":1}', { status: 200 }));
    const out = await safeFetch(BASE, { fetchImpl: f.fetchImpl });
    expect(out).toEqual({ status: 200, body: '{"status":1}' });
    expect(f.calls).toHaveLength(1);
    expect(f.calls[0].url).toBe("https://world.openfoodfacts.org/api/v2/product/123.json");
    expect(f.calls[0].init.method).toBe("GET");
    expect(f.calls[0].init.redirect).toBe("manual");
    expect(f.calls[0].init.signal).toBeInstanceOf(AbortSignal);
  });

  test("a 404 is returned to the caller (a miss is data, not an error)", async () => {
    const f = queued(res('{"status":0}', { status: 404 }));
    expect(await safeFetch(BASE, { fetchImpl: f.fetchImpl })).toEqual({ status: 404, body: '{"status":0}' });
  });

  test("multi-byte UTF-8 survives the capped reader", async () => {
    const f = queued(res("Crème brûlée / борщ", { status: 200 }));
    expect((await safeFetch(BASE, { fetchImpl: f.fetchImpl })).body).toBe("Crème brûlée / борщ");
  });

  test("credentials travel in headers: the USDA key is in X-Api-Key and never in the URL", async () => {
    const f = queued(res("{}", { status: 200 }));
    await safeFetch(
      { host: "api.nal.usda.gov", pathSegments: ["fdc", "v1", "foods", "search"], query: { query: "apple" }, headers: { "X-Api-Key": "SECRET-KEY-123", "User-Agent": "FitnessApp" } },
      { fetchImpl: f.fetchImpl },
    );
    expect(f.calls[0].init.headers).toEqual({ "X-Api-Key": "SECRET-KEY-123", "User-Agent": "FitnessApp" });
    expect(f.calls[0].url).not.toContain("SECRET-KEY-123");
    expect(f.calls[0].url).not.toContain("api_key");
  });

  test("a hostile query term cannot inject a second parameter on the wire", async () => {
    const f = queued(res("{}", { status: 200 }));
    await safeFetch({ ...BASE, query: { search_terms: "x&api_key=evil" } }, { fetchImpl: f.fetchImpl });
    expect(f.calls[0].url).toContain("search_terms=x%26api_key%3Devil");
    expect(f.calls[0].url).not.toContain("&api_key=");
  });

  test("a host off the allowlist rejects BEFORE any fetch", async () => {
    const f = queued(res("{}", { status: 200 }));
    expect(await slugOf(safeFetch({ host: "evil.example.com" as never, pathSegments: ["x"] }, { fetchImpl: f.fetchImpl }))).toBe(
      "upstream-host-not-allowed",
    );
    expect(f.calls).toHaveLength(0);
  });

  test("429 -> upstream-rate-limited; 500/502/503/599 -> upstream-unavailable; 499 and 400 pass through", async () => {
    expect(await slugOf(safeFetch(BASE, { fetchImpl: queued(res("x", { status: 429 })).fetchImpl }))).toBe("upstream-rate-limited");
    for (const status of [500, 502, 503, 599]) {
      expect(await slugOf(safeFetch(BASE, { fetchImpl: queued(res("x", { status })).fetchImpl }))).toBe("upstream-unavailable");
    }
    expect((await safeFetch(BASE, { fetchImpl: queued(res("bad", { status: 400 })).fetchImpl })).status).toBe(400);
    expect((await safeFetch(BASE, { fetchImpl: queued(res("gone", { status: 410 })).fetchImpl })).status).toBe(410);
  });

  test("a network failure -> upstream-unreachable, and the error message never contains the raw cause (URL, key)", async () => {
    const f = queued(new Error("connect ECONNREFUSED https://world.openfoodfacts.org/?api_key=SECRET-KEY-123"));
    try {
      await safeFetch(BASE, { fetchImpl: f.fetchImpl });
      throw new Error("expected rejection");
    } catch (e) {
      expect((e as UpstreamError).slug).toBe("upstream-unreachable");
      expect((e as UpstreamError).message).toBe("upstream-unreachable");
      expect(JSON.stringify(e)).not.toContain("SECRET-KEY-123");
      expect(String((e as Error).stack)).not.toContain("SECRET-KEY-123");
    }
  });

  describe("redirects", () => {
    test("a same-host https redirect is followed (the final body is returned)", async () => {
      const f = queued(redirect("https://world.openfoodfacts.org/api/v2/product/456.json"), res("final", { status: 200 }));
      expect(await safeFetch(BASE, { fetchImpl: f.fetchImpl })).toEqual({ status: 200, body: "final" });
      expect(f.calls.map((c) => c.url)).toEqual([
        "https://world.openfoodfacts.org/api/v2/product/123.json",
        "https://world.openfoodfacts.org/api/v2/product/456.json",
      ]);
      // Every hop is also manual: the helper, not fetch, decides.
      expect(f.calls.every((c) => c.init.redirect === "manual")).toBe(true);
    });

    test("a relative Location is resolved against the current URL and stays on host", async () => {
      const f = queued(redirect("/api/v2/product/789.json", 301), res("rel", { status: 200 }));
      expect((await safeFetch(BASE, { fetchImpl: f.fetchImpl })).body).toBe("rel");
      expect(f.calls[1].url).toBe("https://world.openfoodfacts.org/api/v2/product/789.json");
    });

    test("headers (including the key header) are re-sent on a same-host hop", async () => {
      const f = queued(redirect("/next"), res("ok", { status: 200 }));
      await safeFetch({ ...BASE, headers: { "X-Api-Key": "K" } }, { fetchImpl: f.fetchImpl });
      expect(f.calls[1].init.headers).toEqual({ "X-Api-Key": "K" });
    });

    test.each([301, 302, 303, 307, 308])("status %d is treated as a redirect", async (status) => {
      const f = queued(redirect("/x", status), res("ok", { status: 200 }));
      expect((await safeFetch(BASE, { fetchImpl: f.fetchImpl })).body).toBe("ok");
    });

    test("a CROSS-HOST redirect (even to another allowlisted host) is rejected and never fetched", async () => {
      for (const target of ["https://evil.example.com/steal", "https://search.openfoodfacts.org/x", "https://api.nal.usda.gov/x"]) {
        const f = queued(redirect(target), res("SHOULD-NOT-BE-READ", { status: 200 }));
        expect(await slugOf(safeFetch(BASE, { fetchImpl: f.fetchImpl }))).toBe("upstream-redirect-rejected");
        expect(f.calls).toHaveLength(1);
      }
    });

    test("an https -> http downgrade on the same host is rejected", async () => {
      const f = queued(redirect("http://world.openfoodfacts.org/x"), res("no", { status: 200 }));
      expect(await slugOf(safeFetch(BASE, { fetchImpl: f.fetchImpl }))).toBe("upstream-redirect-rejected");
      expect(f.calls).toHaveLength(1);
    });

    test("a redirect without a Location header is rejected", async () => {
      const f = queued(redirect(null));
      expect(await slugOf(safeFetch(BASE, { fetchImpl: f.fetchImpl }))).toBe("upstream-redirect-rejected");
    });

    test("an unparseable Location is rejected", async () => {
      const f = queued(redirect("http://[bad"));
      expect(await slugOf(safeFetch(BASE, { fetchImpl: f.fetchImpl }))).toBe("upstream-redirect-rejected");
    });

    test("exactly 3 redirects are followed; the 4th is rejected", async () => {
      const ok = queued(redirect("/a"), redirect("/b"), redirect("/c"), res("done", { status: 200 }));
      expect((await safeFetch(BASE, { fetchImpl: ok.fetchImpl })).body).toBe("done");
      expect(ok.calls).toHaveLength(4);

      const loop = queued(redirect("/a"), redirect("/b"), redirect("/c"), redirect("/d"), res("never", { status: 200 }));
      expect(await slugOf(safeFetch(BASE, { fetchImpl: loop.fetchImpl }))).toBe("upstream-redirect-rejected");
      expect(loop.calls).toHaveLength(4);
    });

    test("a 429 or 5xx after a redirect still maps to its slug", async () => {
      const f = queued(redirect("/a"), res("x", { status: 429 }));
      expect(await slugOf(safeFetch(BASE, { fetchImpl: f.fetchImpl }))).toBe("upstream-rate-limited");
    });
  });

  describe("body cap", () => {
    test("a declared content-length above the cap aborts without reading", async () => {
      const f = queued(res("x", { status: 200, headers: { "content-length": "2000" } }));
      expect(await slugOf(safeFetch({ ...BASE, maxBytes: 1000 }, { fetchImpl: f.fetchImpl }))).toBe("upstream-too-large");
    });

    test("a streamed body above the cap (no content-length) is aborted", async () => {
      const f = queued(res("a".repeat(1001), { status: 200 }));
      expect(await slugOf(safeFetch({ ...BASE, maxBytes: 1000 }, { fetchImpl: f.fetchImpl }))).toBe("upstream-too-large");
    });

    test("a body of exactly the cap is accepted; one byte more is not", async () => {
      expect((await safeFetch({ ...BASE, maxBytes: 1000 }, { fetchImpl: queued(res("a".repeat(1000), { status: 200 })).fetchImpl })).body).toHaveLength(1000);
      expect(await slugOf(safeFetch({ ...BASE, maxBytes: 1000 }, { fetchImpl: queued(res("a".repeat(1001), { status: 200 })).fetchImpl }))).toBe("upstream-too-large");
    });

    test("the default cap is 1 MiB", async () => {
      expect((await safeFetch(BASE, { fetchImpl: queued(res("a".repeat(1_048_576), { status: 200 })).fetchImpl })).body).toHaveLength(1_048_576);
      expect(await slugOf(safeFetch(BASE, { fetchImpl: queued(res("a".repeat(1_048_577), { status: 200 })).fetchImpl }))).toBe("upstream-too-large");
    });

    test("an empty body is an empty string", async () => {
      expect(await safeFetch(BASE, { fetchImpl: queued(new Response(null, { status: 204 })).fetchImpl })).toEqual({ status: 204, body: "" });
    });
  });

  describe("timeout", () => {
    test("a fetch that never answers maps to upstream-timeout once the deadline passes", async () => {
      const hang = (init: RequestInit) =>
        new Promise<Response>((_, reject) => {
          init.signal!.addEventListener("abort", () => reject(new Error("aborted")));
        });
      const started = Date.now();
      const f = queued(hang);
      expect(await slugOf(safeFetch({ ...BASE, timeoutMs: 40 }, { fetchImpl: f.fetchImpl }))).toBe("upstream-timeout");
      expect(Date.now() - started).toBeLessThan(2000);
    });

    test("the deadline also covers the BODY read: a stream that stalls maps to upstream-timeout", async () => {
      const stalling = async (init: RequestInit) => {
        const stream = new ReadableStream<Uint8Array>({
          start(controller) {
            controller.enqueue(new TextEncoder().encode("partial"));
            init.signal!.addEventListener("abort", () => controller.error(new Error("aborted")));
          },
        });
        return new Response(stream, { status: 200 });
      };
      const f = queued(stalling);
      expect(await slugOf(safeFetch({ ...BASE, timeoutMs: 40 }, { fetchImpl: f.fetchImpl }))).toBe("upstream-timeout");
    });

    test("the timer is cleared after a fast success (no open handle left behind)", async () => {
      jest.useFakeTimers();
      try {
        const f = queued(res("ok", { status: 200 }));
        await safeFetch(BASE, { fetchImpl: f.fetchImpl });
        expect(jest.getTimerCount()).toBe(0);
      } finally {
        jest.useRealTimers();
      }
    });

    test("the timer is cleared after a failure too", async () => {
      jest.useFakeTimers();
      try {
        const f = queued(res("x", { status: 503 }));
        await expect(safeFetch(BASE, { fetchImpl: f.fetchImpl })).rejects.toBeInstanceOf(UpstreamError);
        expect(jest.getTimerCount()).toBe(0);
      } finally {
        jest.useRealTimers();
      }
    });
  });
});
