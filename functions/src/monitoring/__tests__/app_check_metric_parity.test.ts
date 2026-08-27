import { discoverOnCallExports } from "../../__tests__/discover_callables";
import { APP_CHECK_KNOWN_CALLABLES } from "../alert_definitions";

/**
 * GPT-PM's review of commit `8a1c00a`: `APP_CHECK_KNOWN_CALLABLES` is a
 * manually maintained list with no mechanical guard against a future
 * callable being added without updating it -- such a callable would pass
 * `__tests__/scaling.test.ts`'s own "every callable reports its
 * attestation" test (it calls `noteAppCheck` correctly) while still being
 * silently excluded from the App Check metric's bounded filter, exactly
 * the historical failure this whole monitoring effort exists to prevent
 * (the same gap `scaling.test.ts`'s own header describes: "coverage was
 * six of thirteen callables").
 *
 * This test closes that gap directly: it reuses `discoverOnCallExports()`
 * -- the same real-source-scanning inventory `scaling.test.ts` already
 * uses, not a third independent copy -- and compares it against
 * `APP_CHECK_KNOWN_CALLABLES` as exact sets in both directions.
 */
describe("App Check metric's fn bounding list has parity with the real callable inventory", () => {
  const discovered = new Set(discoverOnCallExports().map((c) => c.fn));
  const bounded = new Set<string>(APP_CHECK_KNOWN_CALLABLES);

  test("the discovered inventory is not empty", () => {
    // Otherwise both sets below could vacuously match and this test would
    // pass forever without checking anything real.
    expect(discovered.size).toBeGreaterThanOrEqual(17);
  });

  test("every real callable is present in APP_CHECK_KNOWN_CALLABLES", () => {
    const missing = [...discovered].filter((fn) => !bounded.has(fn));
    expect(missing).toEqual([]);
  });

  test("APP_CHECK_KNOWN_CALLABLES has no stale entry with no matching callable", () => {
    const stale = [...bounded].filter((fn) => !discovered.has(fn));
    expect(stale).toEqual([]);
  });

  test("the two sets are the exact same size", () => {
    expect(bounded.size).toBe(discovered.size);
  });
});
