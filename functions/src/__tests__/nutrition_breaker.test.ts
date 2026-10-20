/**
 * nutrition_breaker (FOOD-13): 3 consecutive upstream failures or one 429 open a breaker for
 * 5 minutes (injected clock: 4:59 open, 5:01 closed); only UpstreamError counts; success resets.
 */
import {
  BREAKER_FAILURE_THRESHOLD,
  BREAKER_NAMES,
  BREAKER_OPEN_MS,
  __resetBreakersForTests,
  isBreakerOpen,
  recordBreakerFailure,
  recordBreakerSuccess,
  withBreaker,
} from "../nutrition_breaker";
import { UpstreamError } from "../nutrition_http";

const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);
const MIN = 60_000;

beforeEach(() => __resetBreakersForTests());

const failing = (slug: ConstructorParameters<typeof UpstreamError>[0] = "upstream-unavailable") =>
  jest.fn(async () => {
    throw new UpstreamError(slug);
  });

describe("constants", () => {
  test("5 minutes, threshold 3, four named breakers", () => {
    expect(BREAKER_OPEN_MS).toBe(5 * MIN);
    expect(BREAKER_FAILURE_THRESHOLD).toBe(3);
    expect([...BREAKER_NAMES]).toEqual(["off_read", "off_search", "off_legacy", "usda"]);
  });
});

describe("withBreaker", () => {
  test("success returns the value and a closed breaker stays closed", async () => {
    await expect(withBreaker("off_read", () => T0, async () => 42)).resolves.toBe(42);
    expect(isBreakerOpen("off_read", T0)).toBe(false);
  });

  test("two failures keep it closed; the third opens it", async () => {
    const fn = failing();
    for (let i = 0; i < 2; i++) await expect(withBreaker("off_read", () => T0, fn)).rejects.toBeInstanceOf(UpstreamError);
    expect(isBreakerOpen("off_read", T0)).toBe(false);
    await expect(withBreaker("off_read", () => T0, fn)).rejects.toBeInstanceOf(UpstreamError);
    expect(isBreakerOpen("off_read", T0)).toBe(true);
    expect(fn).toHaveBeenCalledTimes(3);
  });

  test("an open breaker answers upstream-unavailable WITHOUT calling the function", async () => {
    for (let i = 0; i < 3; i++) await withBreaker("off_read", () => T0, failing()).catch(() => undefined);
    const fn = jest.fn(async () => "ok");
    const err = await withBreaker("off_read", () => T0 + MIN, fn).catch((e) => e);
    expect(err).toBeInstanceOf(UpstreamError);
    expect(err.slug).toBe("upstream-unavailable");
    expect(fn).not.toHaveBeenCalled();
  });

  test("injected clock: open at 4:59, closed at 5:00 and 5:01", async () => {
    for (let i = 0; i < 3; i++) await withBreaker("off_read", () => T0, failing()).catch(() => undefined);
    expect(isBreakerOpen("off_read", T0 + 4 * MIN + 59_000)).toBe(true);
    expect(isBreakerOpen("off_read", T0 + 5 * MIN)).toBe(false);
    const fn = jest.fn(async () => "back");
    await expect(withBreaker("off_read", () => T0 + 5 * MIN + 1000, fn)).resolves.toBe("back");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  test("one 429 opens the breaker immediately", async () => {
    await withBreaker("usda", () => T0, failing("upstream-rate-limited")).catch(() => undefined);
    expect(isBreakerOpen("usda", T0 + 1)).toBe(true);
    expect(isBreakerOpen("usda", T0 + 5 * MIN)).toBe(false);
  });

  test("a success resets the failure count: fail, fail, ok, fail, fail does not open", async () => {
    const f = failing();
    await withBreaker("off_search", () => T0, f).catch(() => undefined);
    await withBreaker("off_search", () => T0, f).catch(() => undefined);
    await withBreaker("off_search", () => T0, async () => "ok");
    await withBreaker("off_search", () => T0, f).catch(() => undefined);
    await withBreaker("off_search", () => T0, f).catch(() => undefined);
    expect(isBreakerOpen("off_search", T0)).toBe(false);
  });

  test("a non-upstream error is rethrown and does NOT count", async () => {
    const boom = jest.fn(async () => {
      throw new TypeError("parse bug");
    });
    for (let i = 0; i < 5; i++) await expect(withBreaker("off_read", () => T0, boom)).rejects.toBeInstanceOf(TypeError);
    expect(isBreakerOpen("off_read", T0)).toBe(false);
  });

  test("breakers are independent per name", async () => {
    await withBreaker("usda", () => T0, failing("upstream-rate-limited")).catch(() => undefined);
    expect(isBreakerOpen("usda", T0)).toBe(true);
    for (const other of ["off_read", "off_search", "off_legacy"] as const) expect(isBreakerOpen(other, T0)).toBe(false);
  });

  test("after reopening window the count starts from zero again", async () => {
    for (let i = 0; i < 3; i++) await withBreaker("off_read", () => T0, failing()).catch(() => undefined);
    const later = T0 + 6 * MIN;
    await withBreaker("off_read", () => later, failing()).catch(() => undefined);
    await withBreaker("off_read", () => later, failing()).catch(() => undefined);
    expect(isBreakerOpen("off_read", later)).toBe(false);
    await withBreaker("off_read", () => later, failing()).catch(() => undefined);
    expect(isBreakerOpen("off_read", later)).toBe(true);
  });
});

describe("direct recorders and reset seam", () => {
  test("recordBreakerFailure x3 opens, recordBreakerSuccess closes", () => {
    for (let i = 0; i < 3; i++) recordBreakerFailure("off_legacy", "upstream-timeout", T0);
    expect(isBreakerOpen("off_legacy", T0 + 1)).toBe(true);
    recordBreakerSuccess("off_legacy");
    expect(isBreakerOpen("off_legacy", T0 + 1)).toBe(false);
  });

  test("__resetBreakersForTests clears an open breaker", () => {
    recordBreakerFailure("usda", "upstream-rate-limited", T0);
    expect(isBreakerOpen("usda", T0)).toBe(true);
    __resetBreakersForTests();
    expect(isBreakerOpen("usda", T0)).toBe(false);
  });
});
