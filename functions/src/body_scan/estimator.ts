/**
 * Estimator provider registry (design s8, D-52).
 *
 * The server registry has exactly two entries:
 *
 *  - `licensed-api`: RESERVED. It throws `failed-precondition:
 *    provider-not-configured` until an operator wires a vendor adapter (one
 *    adapter file plus `BODY_SCAN_PROVIDER=licensed-api`; OPEN Q-1).
 *  - `test-fake`: a test double, selectable ONLY under the emulator or jest, so
 *    a production deploy can never be pointed at it by a stray env value.
 *
 * There is deliberately NO server-side provisional estimator: the provisional
 * (Deurenberg) estimate is a deterministic formula that runs on the device
 * (D-52), so it needs no callable, no quota and no server copy of body metrics.
 * With no provider configured, no server estimate can be produced and
 * `createBodyScan` answers `provider-not-configured`.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { bodyScanProviderId } from "./flags";
import type { BodyCompositionEstimator } from "./types";

/** Reserved for a licensed vendor adapter (not implemented in this sprint). */
export const LICENSED_API_PROVIDER_ID = "licensed-api";

/** Test-only provider id; resolved only when {@link isTestRuntime} is true. */
export const TEST_FAKE_PROVIDER_ID = "test-fake";

/** The closed slug a missing / unusable provider answers with. */
export const PROVIDER_NOT_CONFIGURED = "provider-not-configured";

/**
 * A provider throws this for a NON-retryable failure (the vendor rejected the
 * input for good). `estimateBodyScan` then marks the scan `failed`; any other
 * thrown error (or a timeout) is treated as transient and leaves it `pending`.
 */
export class EstimatorTerminalError extends Error {
  constructor(message = "estimator-terminal") {
    super(message);
    this.name = "EstimatorTerminalError";
  }
}

let testEstimator: BodyCompositionEstimator | undefined;

/** True under the Functions emulator or jest; never true in a deployed function. */
function isTestRuntime(): boolean {
  return (
    process.env.FUNCTIONS_EMULATOR === "true" ||
    process.env.JEST_WORKER_ID !== undefined
  );
}

/**
 * Test seam: installs (or, with `undefined`, clears) the estimator `test-fake`
 * resolves to. Refuses outside the emulator/jest so production code can never
 * register a double. Not called anywhere outside tests.
 */
export function __setTestEstimatorForTests(
  estimator: BodyCompositionEstimator | undefined,
): void {
  if (!isTestRuntime()) {
    throw new Error("test estimator can only be set under the emulator or jest");
  }
  testEstimator = estimator;
}

/**
 * The configured estimator.
 *
 * @throws HttpsError('failed-precondition', 'provider-not-configured') when
 * `BODY_SCAN_PROVIDER` is unset, names an unknown provider, names the reserved
 * `licensed-api` (no adapter yet), or names `test-fake` outside a test runtime
 * or before a double was installed.
 */
export function resolveEstimator(): BodyCompositionEstimator {
  const id = bodyScanProviderId();
  if (id === TEST_FAKE_PROVIDER_ID && isTestRuntime() && testEstimator) {
    return testEstimator;
  }
  throw new HttpsError("failed-precondition", PROVIDER_NOT_CONFIGURED);
}
