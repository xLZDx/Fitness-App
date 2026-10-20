/**
 * Per-instance circuit breakers for the nutrition upstreams (design s17.4).
 *
 * Open Food Facts rate-limits per IP and Search-a-licious "can be down for
 * hours" (FINDINGS). A breaker opens after 3 consecutive upstream failures or
 * on any 429 and then answers `upstream-unavailable` WITHOUT touching the
 * network for 5 minutes, so a struggling upstream (and the shared egress IP) is
 * left alone. State is module-scope and per warm instance on purpose: the
 * cross-instance protection is the global Firestore budget
 * (`nutrition_budget.ts`); this only stops one instance hammering a dead host.
 *
 * Only `UpstreamError` counts as an upstream failure; a parse or logic error
 * inside the guarded function must not open a breaker.
 */
import { UpstreamError } from "./nutrition_http";

export const BREAKER_OPEN_MS = 5 * 60 * 1000;
export const BREAKER_FAILURE_THRESHOLD = 3;

export const BREAKER_NAMES = ["off_read", "off_search", "off_legacy", "usda"] as const;
export type BreakerName = (typeof BREAKER_NAMES)[number];

interface BreakerState {
  failures: number;
  openUntilMs: number;
}

const states = new Map<BreakerName, BreakerState>();

function state(name: BreakerName): BreakerState {
  let s = states.get(name);
  if (!s) {
    s = { failures: 0, openUntilMs: 0 };
    states.set(name, s);
  }
  return s;
}

export function isBreakerOpen(name: BreakerName, nowMs: number): boolean {
  return nowMs < state(name).openUntilMs;
}

export function recordBreakerSuccess(name: BreakerName): void {
  const s = state(name);
  s.failures = 0;
  s.openUntilMs = 0;
}

export function recordBreakerFailure(name: BreakerName, slug: string, nowMs: number): void {
  const s = state(name);
  s.failures += 1;
  if (slug === "upstream-rate-limited" || s.failures >= BREAKER_FAILURE_THRESHOLD) {
    s.openUntilMs = nowMs + BREAKER_OPEN_MS;
    s.failures = 0;
  }
}

/** Test seam: breaker state is module-scope and would leak between cases. */
export function __resetBreakersForTests(): void {
  states.clear();
}

/**
 * Runs `fn` behind the named breaker. An open breaker throws
 * `upstream-unavailable` immediately; an `UpstreamError` from `fn` is counted
 * and rethrown; success resets the failure count.
 */
export async function withBreaker<T>(
  name: BreakerName,
  nowMs: () => number,
  fn: () => Promise<T>,
): Promise<T> {
  if (isBreakerOpen(name, nowMs())) throw new UpstreamError("upstream-unavailable");
  try {
    const out = await fn();
    recordBreakerSuccess(name);
    return out;
  } catch (e) {
    if (e instanceof UpstreamError) recordBreakerFailure(name, e.slug, nowMs());
    throw e;
  }
}
