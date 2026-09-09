import * as fs from "fs";
import * as path from "path";
import {
  RightsDecisionSchema,
  EquipmentSourceSchema,
  Sha256HexSchema,
  SCOPE_IDENTIFIER_PATTERN,
  SNAPSHOT_PATH_PATTERN,
} from "../p1/contracts";

// This suite is one third of a three-engine parity proof. The same identifier
// cases, from the same file, are also run through Python's `re` and through
// the Draft-07 JSON Schema (with the `jsonschema` package, which compiles
// `pattern` with Python's own `re`) in
// scripts/equipment_identity/test_rights.py. Each layer is checked against the
// verdicts recorded in that file rather than against another layer, so a
// divergence fails in whichever engine drifted and names itself.
//
// Comparing the pattern TEXT across the three files would prove nothing. The
// four `cross_runtime` cases are precisely the inputs on which two engines
// handed byte-identical patterns return DIFFERENT answers: Python's `\S`
// rejects U+0085 and accepts U+FEFF while JavaScript's does the reverse, and
// Python's `$` matches before a trailing newline while JavaScript's does not.
// That measurement is why the shared grammar uses an enumerated ASCII alphabet
// and ends with `(?![\s\S])` instead of `$`.

const CASES = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, "..", "..", "..", "scripts", "equipment_identity", "scope_identifier_cases.json"),
    "utf8",
  ),
) as {
  valid: string[];
  invalid: string[];
  cross_runtime: string[];
  snapshot_path_valid: string[];
  snapshot_path_invalid: string[];
  sha256_valid: string[];
  sha256_invalid: string[];
};

const SNAPSHOT_PATH =
  "core/equipment_identity/p0/terms_snapshots/synthetic_test_terms.txt";
const SNAPSHOT_SHA256 =
  "115f485416170f03685c4db9195f215596cf4913228134f2864896669a4f53c2";

function baseRights(overrides: Record<string, unknown> = {}): unknown {
  return {
    legalReviewState: "UNREVIEWED",
    commercialAllowed: false,
    displayAllowed: false,
    recognitionProcessingAllowed: false,
    trainingAllowed: false,
    derivativeAllowed: false,
    redistributionAllowed: false,
    attributionRequired: false,
    shareAlike: false,
    noAiRestriction: true,
    termsCaptured: false,
    ...overrides,
  };
}

const EVIDENCE = {
  termsCaptured: true,
  termsSnapshotPath: SNAPSHOT_PATH,
  termsSnapshotSha256: SNAPSHOT_SHA256,
};

const WHOLE_SOURCE_SCOPE = { kind: "WHOLE_SOURCE", keyNamespace: "test" };

function reviewedRights(overrides: Record<string, unknown> = {}): unknown {
  return baseRights({
    legalReviewState: "REVIEWED",
    reviewedAt: "2026-08-22T00:00:00Z",
    ...EVIDENCE,
    rightsScope: WHOLE_SOURCE_SCOPE,
    ...overrides,
  });
}

describe("the scope identifier grammar", () => {
  it.each(CASES.valid)("accepts %j", (value) => {
    expect(
      RightsDecisionSchema.safeParse(
        reviewedRights({ rightsScope: { kind: "WHOLE_SOURCE", keyNamespace: value } }),
      ).success,
    ).toBe(true);
  });

  it.each(CASES.invalid)("refuses %j", (value) => {
    expect(
      RightsDecisionSchema.safeParse(
        reviewedRights({ rightsScope: { kind: "WHOLE_SOURCE", keyNamespace: value } }),
      ).success,
    ).toBe(false);
  });

  it("refuses every case on which two regex engines disagree", () => {
    // Listed separately because these four are the whole reason the grammar
    // avoids `\S` and `$`. If this ever passes for a pattern using either,
    // the three-layer parity claim is false regardless of what the text says.
    for (const value of CASES.cross_runtime) {
      expect(CASES.invalid).toContain(value);
      expect(new RegExp(SCOPE_IDENTIFIER_PATTERN).test(value)).toBe(false);
    }
  });

  it("would have admitted a trailing newline under a $ anchor", () => {
    // The premise, asserted rather than assumed: in JavaScript `$` already
    // rejects this, which is exactly why the divergence is invisible from
    // this side and had to be found by running Python.
    expect(/^[A-Za-z0-9]+$/.test("abc\n")).toBe(false);
    expect(new RegExp(SCOPE_IDENTIFIER_PATTERN).test("abc\n")).toBe(false);
  });

  it("refuses a subset that covers nothing", () => {
    expect(
      RightsDecisionSchema.safeParse(
        reviewedRights({
          rightsScope: { kind: "SUBSET", keyNamespace: "wger", keys: [] },
        }),
      ).success,
    ).toBe(false);
  });

  it("accepts a subset that names its keys", () => {
    expect(
      RightsDecisionSchema.safeParse(
        reviewedRights({
          rightsScope: { kind: "SUBSET", keyNamespace: "wger", keys: ["123", "456"] },
        }),
      ).success,
    ).toBe(true);
  });

  it("refuses an unrecognised scope kind", () => {
    expect(
      RightsDecisionSchema.safeParse(
        reviewedRights({
          rightsScope: { kind: "EVERYTHING_FOREVER", keyNamespace: "wger" },
        }),
      ).success,
    ).toBe(false);
  });
});

describe("the evidence and scope matrix", () => {
  // Same four rows as rights_decision.schema.json's allOf blocks and
  // validate_rights() in rights.py.

  it("accepts UNREVIEWED with nothing extra", () => {
    expect(RightsDecisionSchema.safeParse(baseRights()).success).toBe(true);
  });

  it("accepts UNREVIEWED that has captured its terms", () => {
    // Capture-before-review, deliberately preserved: terms text can honestly
    // exist before anyone has reviewed it. The matrix requires that a capture
    // be re-checkable, not that it wait for a review.
    expect(RightsDecisionSchema.safeParse(baseRights(EVIDENCE)).success).toBe(true);
  });

  it("refuses a snapshot recorded without the flag admitting it", () => {
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({ termsSnapshotPath: SNAPSHOT_PATH, termsSnapshotSha256: SNAPSHOT_SHA256 }),
      ).success,
    ).toBe(false);
  });

  it("refuses termsCaptured=true with no path to the bytes", () => {
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({ termsCaptured: true, termsSnapshotSha256: SNAPSHOT_SHA256 }),
      ).success,
    ).toBe(false);
  });

  it("refuses a scope on an UNREVIEWED source", () => {
    expect(
      RightsDecisionSchema.safeParse(baseRights({ rightsScope: WHOLE_SOURCE_SCOPE })).success,
    ).toBe(false);
  });

  it("accepts a complete REVIEWED decision", () => {
    expect(RightsDecisionSchema.safeParse(reviewedRights()).success).toBe(true);
  });

  it("refuses a REVIEWED decision with no scope", () => {
    const rights = reviewedRights() as Record<string, unknown>;
    delete rights.rightsScope;
    expect(RightsDecisionSchema.safeParse(rights).success).toBe(false);
  });

  it("refuses a REVIEWED decision with no captured terms", () => {
    const rights = reviewedRights() as Record<string, unknown>;
    delete rights.termsSnapshotPath;
    delete rights.termsSnapshotSha256;
    rights.termsCaptured = false;
    expect(RightsDecisionSchema.safeParse(rights).success).toBe(false);
  });

  it("accepts a complete BLOCKED decision", () => {
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({
          legalReviewState: "BLOCKED",
          reviewedAt: "2026-08-22T00:00:00Z",
          ...EVIDENCE,
        }),
      ).success,
    ).toBe(true);
  });

  it("refuses a BLOCKED decision carrying a scope", () => {
    // BLOCKED grants nothing, so a scope on it could only mean a PARTIAL
    // block — which this contract cannot express and must not appear to.
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({
          legalReviewState: "BLOCKED",
          reviewedAt: "2026-08-22T00:00:00Z",
          ...EVIDENCE,
          rightsScope: WHOLE_SOURCE_SCOPE,
        }),
      ).success,
    ).toBe(false);
  });

  it("refuses a BLOCKED decision with no captured terms", () => {
    // BLOCKED is a human legal conclusion, not an absence. A source whose
    // terms could not be reached at all is UNREVIEWED, which is already
    // fail-closed and already the honest word for "nobody could look".
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({ legalReviewState: "BLOCKED", reviewedAt: "2026-08-22T00:00:00Z" }),
      ).success,
    ).toBe(false);
  });
});

describe("strictness was not traded away to make the rest pass", () => {
  it("still refuses an unknown field on a rights decision", () => {
    expect(
      RightsDecisionSchema.safeParse(reviewedRights({ termsSnapshotUrl: "https://x/" }))
        .success,
    ).toBe(false);
  });

  it("still refuses an unknown field on a source", () => {
    const source = {
      sourceId: "technogym_interior_design",
      providerName: "Technogym",
      sourceClass: "OFFICIAL_MANUFACTURER",
      priority: "P0",
      canonicalUrl: "https://www.technogym.com/",
      retrievedAt: "2026-08-22T00:00:00Z",
      termsUrl: null,
      rights: reviewedRights(),
    };
    expect(EquipmentSourceSchema.safeParse(source).success).toBe(true);
    expect(
      EquipmentSourceSchema.safeParse({ ...source, notAField: 1 }).success,
    ).toBe(false);
  });
});

describe("the two evidence fields, on the same shared cases", () => {
  // Added after a closure review found that the parity claim above covered
  // the scope identifier ONLY. The two fields carrying the actual legal
  // evidence had been left behind: Python rejected a whitespace-only
  // termsSnapshotPath that this layer and the JSON Schema both accepted, and
  // all three still spelled the sha256 rule with `$` — which Python matches
  // before a trailing newline and JavaScript does not. Parity that covers one
  // field out of three is not parity, and the tests said it was.

  it.each(CASES.snapshot_path_valid)("accepts snapshot path %j", (value) => {
    expect(new RegExp(SNAPSHOT_PATH_PATTERN).test(value)).toBe(true);
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({
          termsCaptured: true,
          termsSnapshotPath: value,
          termsSnapshotSha256: SNAPSHOT_SHA256,
        }),
      ).success,
    ).toBe(true);
  });

  it.each(CASES.snapshot_path_invalid)("refuses snapshot path %j", (value) => {
    expect(new RegExp(SNAPSHOT_PATH_PATTERN).test(value)).toBe(false);
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({
          termsCaptured: true,
          termsSnapshotPath: value,
          termsSnapshotSha256: SNAPSHOT_SHA256,
        }),
      ).success,
    ).toBe(false);
  });

  it.each(CASES.sha256_valid)("accepts digest %j", (value) => {
    expect(Sha256HexSchema.safeParse(value).success).toBe(true);
  });

  it.each(CASES.sha256_invalid)("refuses digest %j", (value) => {
    expect(Sha256HexSchema.safeParse(value).success).toBe(false);
    expect(
      RightsDecisionSchema.safeParse(
        baseRights({
          termsCaptured: true,
          termsSnapshotPath: SNAPSHOT_PATH,
          termsSnapshotSha256: value,
        }),
      ).success,
    ).toBe(false);
  });

  it("keeps `..` a filesystem question, not a lexical one", () => {
    // `sub/../terms.txt` is deliberately LEGAL to all three grammars. Only
    // rights.py refuses it, in a separate guard that runs before this
    // pattern, so each of the two stays independently mutation-provable
    // instead of one silently subsuming the other. A schema cannot resolve a
    // path anyway; claiming to enforce containment here would be a promise
    // this layer has no way to keep.
    expect(CASES.snapshot_path_valid).toContain("sub/../terms.txt");
    expect(new RegExp(SNAPSHOT_PATH_PATTERN).test("sub/../terms.txt")).toBe(true);
  });

  it("refuses the NTFS alternate data stream on this side too", () => {
    // Measured, not predicted: before the grammar existed, a record naming
    // `tracked.txt:legal-review` validated in Python and its digest matched —
    // bytes that exist in no checkout of this repository, because Git stores
    // no alternate stream and `.gitattributes -text` cannot preserve one.
    // The colon is refused on every platform, including the ones with no such
    // concept: a path that means one file on Linux and a hidden stream on
    // Windows is not the portable reference this field claims to be.
    for (const value of ["terms.txt:legal-review", "a/b.txt:x"]) {
      expect(new RegExp(SNAPSHOT_PATH_PATTERN).test(value)).toBe(false);
    }
  });

  it("would have admitted a digest with a trailing newline under a $ anchor", () => {
    // The premise asserted rather than assumed, same shape as the identifier
    // case above: JavaScript's `$` already rejects this, which is exactly why
    // the divergence was invisible from this side until Python was run.
    const digest = "a".repeat(64);
    expect(/^[0-9a-f]{64}$/.test(digest + "\n")).toBe(false);
    expect(Sha256HexSchema.safeParse(digest + "\n").success).toBe(false);
    expect(CASES.sha256_invalid).toContain(digest + "\n");
  });
});

describe("the real registry still parses", () => {
  it("accepts every generated source record unchanged", () => {
    // The tightening must not have invalidated a single existing record —
    // every source is UNREVIEWED with termsCaptured=false, so none of them
    // acquires a snapshot or scope obligation.
    const registry = JSON.parse(
      fs.readFileSync(
        path.join(__dirname, "..", "generated", "source_registry.json"),
        "utf8",
      ),
    );
    const sources = Array.isArray(registry) ? registry : registry.sources;
    expect(sources.length).toBeGreaterThan(0);
    for (const source of sources) {
      const parsed = EquipmentSourceSchema.safeParse(source);
      expect(parsed.success).toBe(true);
    }
  });
});
