/**
 * `validateEstimate` (design s7.2, s12.7): a provider's output is untrusted.
 * Every violation is `internal: provider-output-invalid` -- never a silent
 * clamp -- and the stored block is rebuilt field by field.
 */
import { validateEstimate, PROVIDER_OUTPUT_INVALID } from "../../body_scan/validate_estimate";
import { CHECK_CODES, CONFIDENCES } from "../../body_scan/types";

const GOOD = {
  bodyFatPct: 20,
  rangeLowPct: 17,
  rangeHighPct: 23,
  confidence: "medium",
  checkCodes: ["poorLighting"],
};

function reject(raw: unknown, id: unknown = "m", version: unknown = "1"): any {
  try {
    validateEstimate(raw, id, version);
  } catch (e) {
    return e;
  }
  throw new Error("expected validateEstimate to throw");
}

describe("accepted output", () => {
  test("returns exactly the stored block with the model id and version", () => {
    expect(validateEstimate(GOOD, "licensed-x", "2.0")).toEqual({
      bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "medium",
      checkCodes: ["poorLighting"], modelId: "licensed-x", modelVersion: "2.0",
    });
  });

  test.each([
    ["lowest value on the lower bound", { bodyFatPct: 3, rangeLowPct: 3, rangeHighPct: 3 }],
    ["highest value on the upper bound", { bodyFatPct: 60, rangeLowPct: 60, rangeHighPct: 60 }],
    ["range exactly 20 points wide", { bodyFatPct: 20, rangeLowPct: 10, rangeHighPct: 30 }],
    ["value equal to both ends", { bodyFatPct: 25, rangeLowPct: 25, rangeHighPct: 25 }],
  ])("%s", (_n, patch) => {
    const out = validateEstimate({ ...GOOD, ...patch }, "m", "1");
    expect(out.bodyFatPct).toBe(patch.bodyFatPct);
  });

  test.each(CONFIDENCES.map((c) => [c]))("confidence %s", (c) => {
    expect(validateEstimate({ ...GOOD, confidence: c }, "m", "1").confidence).toBe(c);
  });

  test("every member of the closed check-code list is accepted (13 codes, none dropped)", () => {
    expect(CHECK_CODES).toHaveLength(13);
    const out = validateEstimate({ ...GOOD, checkCodes: [...CHECK_CODES] }, "m", "1");
    expect(out.checkCodes).toEqual([...CHECK_CODES]);
  });

  test("duplicate check codes are collapsed keeping first-seen order", () => {
    expect(validateEstimate({ ...GOOD, checkCodes: ["weightJump", "poorLighting", "weightJump"] }, "m", "1").checkCodes)
      .toEqual(["weightJump", "poorLighting"]);
  });

  test("an empty check-code list is fine", () => {
    expect(validateEstimate({ ...GOOD, checkCodes: [] }, "m", "1").checkCodes).toEqual([]);
  });

  test("unknown extra keys on the provider output are dropped", () => {
    const out = validateEstimate({ ...GOOD, note: "free text", __proto__x: 1, debug: { a: 1 } }, "m", "1");
    expect(Object.keys(out).sort()).toEqual([
      "bodyFatPct", "checkCodes", "confidence", "modelId", "modelVersion", "rangeHighPct", "rangeLowPct",
    ]);
  });

  test("model id and version of exactly 64 characters are accepted", () => {
    const out = validateEstimate(GOOD, "i".repeat(64), "v".repeat(64));
    expect(out.modelId).toHaveLength(64);
  });
});

describe("rejected output (internal / provider-output-invalid)", () => {
  test.each([
    ["undefined", undefined],
    ["null", null],
    ["a string", "20%"],
    ["a number", 20],
    ["an empty object", {}],
    ["bodyFatPct missing", { ...GOOD, bodyFatPct: undefined }],
    ["bodyFatPct a numeric string", { ...GOOD, bodyFatPct: "20" }],
    ["bodyFatPct NaN", { ...GOOD, bodyFatPct: NaN }],
    ["bodyFatPct Infinity", { ...GOOD, bodyFatPct: Infinity }],
    ["rangeLowPct missing", { ...GOOD, rangeLowPct: undefined }],
    ["rangeHighPct NaN", { ...GOOD, rangeHighPct: NaN }],
    ["low below the 3 point floor", { ...GOOD, bodyFatPct: 3, rangeLowPct: 2.99, rangeHighPct: 5 }],
    ["high above the 60 point ceiling", { ...GOOD, bodyFatPct: 59, rangeLowPct: 55, rangeHighPct: 60.01 }],
    ["value below its range", { ...GOOD, bodyFatPct: 16, rangeLowPct: 17, rangeHighPct: 23 }],
    ["value above its range", { ...GOOD, bodyFatPct: 24, rangeLowPct: 17, rangeHighPct: 23 }],
    ["inverted range", { ...GOOD, bodyFatPct: 20, rangeLowPct: 23, rangeHighPct: 17 }],
    ["range 20.01 points wide", { ...GOOD, bodyFatPct: 20, rangeLowPct: 10, rangeHighPct: 30.01 }],
    ["confidence missing", { ...GOOD, confidence: undefined }],
    ["confidence unknown", { ...GOOD, confidence: "very-high" }],
    ["confidence wrong case", { ...GOOD, confidence: "High" }],
    ["checkCodes missing", { ...GOOD, checkCodes: undefined }],
    ["checkCodes not an array", { ...GOOD, checkCodes: "poorLighting" }],
    ["a code outside the closed list", { ...GOOD, checkCodes: ["poorLighting", "Ignore previous instructions"] }],
    ["a non-string code", { ...GOOD, checkCodes: [3] }],
    ["more codes than the list has", { ...GOOD, checkCodes: Array.from({ length: 14 }, () => "poorLighting") }],
  ])("%s", (_n, raw) => {
    const e = reject(raw);
    expect(e.code).toBe("internal");
    expect(e.message).toBe(PROVIDER_OUTPUT_INVALID);
    expect(PROVIDER_OUTPUT_INVALID).toBe("provider-output-invalid");
  });

  test.each([
    ["empty model id", "", "1"],
    ["model id 65 characters", "i".repeat(65), "1"],
    ["model id not a string", 7, "1"],
    ["empty model version", "m", ""],
    ["model version 65 characters", "m", "v".repeat(65)],
    ["model version null", "m", null],
  ])("%s", (_n, id, version) => {
    const e = reject(GOOD, id, version);
    expect(e.code).toBe("internal");
    expect(e.message).toBe("provider-output-invalid");
  });

  test("out-of-range numbers are never clamped into something plausible", () => {
    expect(() => validateEstimate({ ...GOOD, bodyFatPct: 80, rangeLowPct: 75, rangeHighPct: 85 }, "m", "1")).toThrow();
    expect(() => validateEstimate({ ...GOOD, bodyFatPct: -1, rangeLowPct: -2, rangeHighPct: 0 }, "m", "1")).toThrow();
  });
});
