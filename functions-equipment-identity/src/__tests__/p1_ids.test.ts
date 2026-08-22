import {
  generateModelId,
  isValidModelId,
  deriveCandidateId,
  buildProductLineId,
  buildCanonicalSlug,
} from "../p1/ids";

describe("generateModelId / isValidModelId", () => {
  test("generateModelId produces a valid UUID v4", () => {
    const id = generateModelId();
    expect(isValidModelId(id)).toBe(true);
  });

  test("generateModelId is non-deterministic across calls", () => {
    const a = generateModelId();
    const b = generateModelId();
    expect(a).not.toBe(b);
  });

  test("isValidModelId accepts a well-formed UUID v4", () => {
    expect(isValidModelId("11111111-1111-4111-8111-111111111111")).toBe(true);
  });

  test("isValidModelId rejects a non-UUID string", () => {
    expect(isValidModelId("not-a-uuid")).toBe(false);
  });

  test("isValidModelId rejects a UUID v1 (wrong version nibble)", () => {
    expect(isValidModelId("11111111-1111-1111-8111-111111111111")).toBe(false);
  });

  test("isValidModelId rejects a UUID with a bad variant nibble", () => {
    expect(isValidModelId("11111111-1111-4111-0111-111111111111")).toBe(false);
  });
});

describe("deriveCandidateId", () => {
  test("is deterministic: same inputs produce the same id", () => {
    const a = deriveCandidateId("technogym_interior_design", "SEL-LEGPRESS-500");
    const b = deriveCandidateId("technogym_interior_design", "SEL-LEGPRESS-500");
    expect(a).toBe(b);
  });

  test("different sourceStableKey produces a different id", () => {
    const a = deriveCandidateId("technogym_interior_design", "SEL-LEGPRESS-500");
    const b = deriveCandidateId("technogym_interior_design", "SEL-LEGPRESS-501");
    expect(a).not.toBe(b);
  });

  test("different sourceId produces a different id", () => {
    const a = deriveCandidateId("technogym_interior_design", "SEL-LEGPRESS-500");
    const b = deriveCandidateId("matrix_fitness_design_planning", "SEL-LEGPRESS-500");
    expect(a).not.toBe(b);
  });

  test("returns a 64-character lowercase hex SHA-256 digest", () => {
    const id = deriveCandidateId("technogym_interior_design", "SEL-LEGPRESS-500");
    expect(id).toMatch(/^[0-9a-f]{64}$/);
  });

  test("rejects an empty sourceId", () => {
    expect(() => deriveCandidateId("", "key")).toThrow(/sourceId must be non-empty/);
  });

  test("rejects an empty sourceStableKey", () => {
    expect(() => deriveCandidateId("technogym_interior_design", "")).toThrow(
      /sourceStableKey must be non-empty/,
    );
  });

  // Reviewer-found gap (P1.G1 type-design review, 2026-08-22): the `\n`
  // delimiter between sourceId and sourceStableKey is only collision-free
  // if neither side can contain `\n`. This is now enforced locally rather
  // than relying on every caller's sourceId having round-tripped through
  // SlugSchema first.
  test("rejects a sourceId containing a newline", () => {
    expect(() => deriveCandidateId("technogym\ninterior", "key")).toThrow(
      /sourceId must not contain a newline/,
    );
  });

  test("rejects a sourceStableKey containing a newline", () => {
    expect(() => deriveCandidateId("technogym_interior_design", "key\nsuffix")).toThrow(
      /sourceStableKey must not contain a newline/,
    );
  });

  test("without the newline guard, two distinct pairs would have collided (regression proof)", () => {
    // (sourceId="a", key="b\nc") and (sourceId="a\nb", key="c") both
    // concatenate to "a\nb\nc" -- exactly the ambiguity the guard closes.
    // Both are now rejected outright rather than silently colliding.
    expect(() => deriveCandidateId("a", "b\nc")).toThrow();
    expect(() => deriveCandidateId("a\nb", "c")).toThrow();
  });
});

describe("buildProductLineId", () => {
  test("joins brand and line slugs with a hyphen", () => {
    expect(buildProductLineId("technogym", "selection")).toBe("technogym-selection");
  });

  test("slugifies mixed case and spaces", () => {
    expect(buildProductLineId("Technogym", "Selection Pro")).toBe("technogym-selection-pro");
  });

  test("rejects a brandId that slugifies to empty", () => {
    expect(() => buildProductLineId("---", "selection")).toThrow(/brandId slugifies to empty/);
  });

  test("rejects a lineSlug that slugifies to empty", () => {
    expect(() => buildProductLineId("technogym", "***")).toThrow(/lineSlug slugifies to empty/);
  });
});

describe("buildCanonicalSlug", () => {
  test("joins brand + product line + model code/name", () => {
    const slug = buildCanonicalSlug({
      brandId: "technogym",
      productLine: "selection",
      modelCodeOrName: "SEL-LEGPRESS-500",
    });
    expect(slug).toBe("technogym-selection-sel-legpress-500");
  });

  test("omits productLine when absent (null)", () => {
    const slug = buildCanonicalSlug({
      brandId: "matrix",
      productLine: null,
      modelCodeOrName: "G7-S43",
    });
    expect(slug).toBe("matrix-g7-s43");
  });

  test("strips diacritics via NFKD normalization", () => {
    const slug = buildCanonicalSlug({
      brandId: "panatta",
      productLine: undefined,
      modelCodeOrName: "Presse à Épaule",
    });
    expect(slug).toBe("panatta-presse-a-epaule");
  });

  test("never auto-suffixes on what would be a collision -- collision detection is validateCatalogUniqueness's job", () => {
    // Two different inputs that would slugify to visually similar output
    // should never be silently disambiguated by this function -- it just
    // produces its direct output and lets the uniqueness check surface the
    // conflict (if any).
    const a = buildCanonicalSlug({ brandId: "precor", productLine: null, modelCodeOrName: "AMT-100" });
    const b = buildCanonicalSlug({ brandId: "precor", productLine: null, modelCodeOrName: "AMT 100" });
    expect(a).toBe(b);
    expect(a).toBe("precor-amt-100");
  });

  test("rejects input that slugifies to entirely empty", () => {
    expect(() =>
      buildCanonicalSlug({ brandId: "***", productLine: null, modelCodeOrName: "///" }),
    ).toThrow(/all parts slugify to empty/);
  });
});
