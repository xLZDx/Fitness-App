/**
 * Estimator registry (design s8, D-52): `licensed-api` is reserved and answers
 * `provider-not-configured`; `test-fake` resolves only under jest/the emulator
 * and only after a double was installed; there is NO server provisional entry.
 */
import {
  EstimatorTerminalError,
  LICENSED_API_PROVIDER_ID,
  PROVIDER_NOT_CONFIGURED,
  TEST_FAKE_PROVIDER_ID,
  __setTestEstimatorForTests,
  resolveEstimator,
} from "../../body_scan/estimator";
import { bodyScanBucketName, bodyScanCloudEnabled, bodyScanProviderId } from "../../body_scan/flags";
import { FakePhotoEstimator } from "./fakes";

const saved = { ...process.env };
afterEach(() => {
  __setTestEstimatorForTests(undefined);
  process.env = { ...saved };
});

function expectNotConfigured(): void {
  let err: any;
  try {
    resolveEstimator();
  } catch (e) {
    err = e;
  }
  expect(err).toBeDefined();
  expect(err.code).toBe("failed-precondition");
  expect(err.message).toBe("provider-not-configured");
}

describe("resolveEstimator", () => {
  test("constants", () => {
    expect(LICENSED_API_PROVIDER_ID).toBe("licensed-api");
    expect(TEST_FAKE_PROVIDER_ID).toBe("test-fake");
    expect(PROVIDER_NOT_CONFIGURED).toBe("provider-not-configured");
  });

  test("unset provider -> provider-not-configured", () => {
    delete process.env.BODY_SCAN_PROVIDER;
    __setTestEstimatorForTests(new FakePhotoEstimator());
    expectNotConfigured();
  });

  test.each(["", "   ", "licensed-api", "provisional", "Deurenberg", "TEST-FAKE"])(
    "provider %j -> provider-not-configured even with a double installed",
    (id) => {
      process.env.BODY_SCAN_PROVIDER = id;
      __setTestEstimatorForTests(new FakePhotoEstimator());
      expectNotConfigured();
    },
  );

  test("test-fake without an installed double -> provider-not-configured", () => {
    process.env.BODY_SCAN_PROVIDER = "test-fake";
    expectNotConfigured();
  });

  test("test-fake with an installed double resolves exactly that object; clearing the seam un-resolves it", () => {
    process.env.BODY_SCAN_PROVIDER = "  test-fake  ";
    const double = new FakePhotoEstimator();
    __setTestEstimatorForTests(double);
    expect(resolveEstimator()).toBe(double);
    __setTestEstimatorForTests(undefined);
    expectNotConfigured();
  });

  test("test-fake is NOT resolvable outside a test runtime (production can never reach a double)", () => {
    process.env.BODY_SCAN_PROVIDER = "test-fake";
    __setTestEstimatorForTests(new FakePhotoEstimator());
    const worker = process.env.JEST_WORKER_ID;
    delete process.env.JEST_WORKER_ID;
    delete process.env.FUNCTIONS_EMULATOR;
    try {
      expectNotConfigured();
      expect(() => __setTestEstimatorForTests(new FakePhotoEstimator())).toThrow(/emulator or jest/);
    } finally {
      process.env.JEST_WORKER_ID = worker;
    }
  });

  test("the emulator flag also counts as a test runtime", () => {
    process.env.BODY_SCAN_PROVIDER = "test-fake";
    const double = new FakePhotoEstimator();
    __setTestEstimatorForTests(double);
    const worker = process.env.JEST_WORKER_ID;
    delete process.env.JEST_WORKER_ID;
    process.env.FUNCTIONS_EMULATOR = "true";
    try {
      expect(resolveEstimator()).toBe(double);
    } finally {
      process.env.JEST_WORKER_ID = worker;
    }
  });
});

describe("EstimatorTerminalError", () => {
  test("is an Error with a stable name and a default message", () => {
    const e = new EstimatorTerminalError();
    expect(e).toBeInstanceOf(Error);
    expect(e.name).toBe("EstimatorTerminalError");
    expect(e.message).toBe("estimator-terminal");
    expect(new EstimatorTerminalError("x").message).toBe("x");
  });
});

describe("server flags (flags.ts)", () => {
  test("unset bucket -> disabled", () => {
    delete process.env.BODY_SCAN_BUCKET;
    expect(bodyScanBucketName()).toBeUndefined();
    expect(bodyScanCloudEnabled()).toBe(false);
  });

  test.each(["", "  ", "ab", "UPPER-case", "-leading", "trailing-", "has space", "slash/inside", "x".repeat(224)])(
    "malformed bucket %j is treated as not configured",
    (name) => {
      process.env.BODY_SCAN_BUCKET = name;
      expect(bodyScanBucketName()).toBeUndefined();
      expect(bodyScanCloudEnabled()).toBe(false);
    },
  );

  test.each(["abc", "body-scan.bucket_1", "a".repeat(222)])("valid bucket %j is accepted (trimmed)", (name) => {
    process.env.BODY_SCAN_BUCKET = `  ${name} `;
    expect(bodyScanBucketName()).toBe(name);
    expect(bodyScanCloudEnabled()).toBe(true);
  });

  test("the provider id is read per call and trimmed; blank is unset", () => {
    process.env.BODY_SCAN_PROVIDER = " licensed-api ";
    expect(bodyScanProviderId()).toBe("licensed-api");
    process.env.BODY_SCAN_PROVIDER = "   ";
    expect(bodyScanProviderId()).toBeUndefined();
  });
});
