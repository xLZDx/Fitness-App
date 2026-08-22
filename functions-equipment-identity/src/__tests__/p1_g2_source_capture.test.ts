import { loadSourceCaptureFixture, SourceCaptureFixtureError } from "../p1/adapters/source_capture";

const VALID_RAW = {
  schemaVersion: 1,
  sourceId: "example_product_catalog",
  capturedAt: "2026-08-22T00:00:00Z",
  records: [
    {
      brandNameRaw: "Example Brand",
      productNameRaw: "Example Leg Press",
      modelCodeRaw: "EX-1",
      typeHintsRaw: ["leg_press"],
      sourceUrl: "https://example.com/leg-press",
      retrievalMethod: "DIRECT_FETCH",
    },
  ],
};

describe("loadSourceCaptureFixture", () => {
  test("accepts a valid fixture and returns a deterministic sha256", () => {
    const { fixture, fixtureSha256 } = loadSourceCaptureFixture(VALID_RAW);
    expect(fixture.sourceId).toBe("example_product_catalog");
    expect(fixture.records).toHaveLength(1);
    expect(fixtureSha256).toMatch(/^[0-9a-f]{64}$/);
  });

  test("is deterministic across repeated calls with the same input", () => {
    const a = loadSourceCaptureFixture(VALID_RAW);
    const b = loadSourceCaptureFixture(JSON.parse(JSON.stringify(VALID_RAW)));
    expect(a.fixtureSha256).toBe(b.fixtureSha256);
  });

  test("rejects a fixture missing a required field (modelCodeRaw)", () => {
    const broken = {
      ...VALID_RAW,
      records: [{ ...VALID_RAW.records[0], modelCodeRaw: undefined }],
    };
    expect(() => loadSourceCaptureFixture(broken)).toThrow(SourceCaptureFixtureError);
  });

  test("rejects an empty records array", () => {
    const broken = { ...VALID_RAW, records: [] };
    expect(() => loadSourceCaptureFixture(broken)).toThrow(SourceCaptureFixtureError);
  });

  test("rejects an unknown retrievalMethod (not one of the two honest values)", () => {
    const broken = {
      ...VALID_RAW,
      records: [{ ...VALID_RAW.records[0], retrievalMethod: "GUESSED" }],
    };
    expect(() => loadSourceCaptureFixture(broken)).toThrow(SourceCaptureFixtureError);
  });

  test("rejects an unknown extra field on a record (strict schema)", () => {
    const broken = {
      ...VALID_RAW,
      records: [{ ...VALID_RAW.records[0], unexpectedField: "nope" }],
    };
    expect(() => loadSourceCaptureFixture(broken)).toThrow(SourceCaptureFixtureError);
  });

  test("rejects a malformed capturedAt (date with no time/offset) at fixture-load time, not deep in candidate mapping", () => {
    // Reviewer-found gap (P1.G2 review, 2026-08-22): capturedAt used to be
    // a bare non-empty string, so this only failed later, inside
    // mapRecordToCandidate, with an error that didn't point at the fixture.
    const broken = { ...VALID_RAW, capturedAt: "2026-08-22" };
    expect(() => loadSourceCaptureFixture(broken)).toThrow(SourceCaptureFixtureError);
  });
});

describe("real committed source-capture fixtures", () => {
  const FIXTURE_IDS = [
    "technogym_product_catalog",
    "matrix_fitness_product_catalog",
    "life_fitness_hammer_strength_product_catalog",
    "core_health_fitness_nautilus_product_catalog",
  ];

  test.each(FIXTURE_IDS)("%s loads and validates", (sourceId) => {
    // eslint-disable-next-line global-require, @typescript-eslint/no-var-requires
    const raw = require(`../generated/source_captures/${sourceId}.json`);
    const { fixture } = loadSourceCaptureFixture(raw);
    expect(fixture.sourceId).toBe(sourceId);
    expect(fixture.records.length).toBeGreaterThan(0);
    for (const record of fixture.records) {
      expect(record.modelCodeRaw.length).toBeGreaterThan(0);
    }
  });
});
