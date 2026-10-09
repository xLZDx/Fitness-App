/**
 * CR-09 regression: a deadline timer must not outlive the race it guards.
 * Before the fix `withTimeout` left its timer armed for the whole budget after
 * every call that finished on time, which is what a Jest worker reports as
 * "failed to exit gracefully". Fake timers make the leak countable.
 */
import { withTimeout, ProbeTimeoutError } from "../canary_probe";

describe("canary_probe withTimeout timer lifecycle (CR-09)", () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  test("no timer survives a promise that resolves in time", async () => {
    await expect(withTimeout(Promise.resolve("ok"), 45_000)).resolves.toBe("ok");
    expect(jest.getTimerCount()).toBe(0);
  });

  test("no timer survives a promise that rejects in time", async () => {
    await expect(withTimeout(Promise.reject(new Error("boom")), 45_000)).rejects.toThrow("boom");
    expect(jest.getTimerCount()).toBe(0);
  });

  test("the deadline still fires when the promise never settles", async () => {
    const pending = withTimeout(new Promise<string>(() => {}), 1_000);
    const assertion = expect(pending).rejects.toBeInstanceOf(ProbeTimeoutError);
    jest.advanceTimersByTime(1_000);
    await assertion;
    expect(jest.getTimerCount()).toBe(0);
  });
});
