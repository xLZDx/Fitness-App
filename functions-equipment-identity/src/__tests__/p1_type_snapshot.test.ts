import * as fs from "fs";
import * as path from "path";
import {
  loadGeneratedSnapshot,
  validateTypeReference,
  TypeSnapshotError,
  type FunctionalTypeSnapshot,
} from "../p1/type_snapshot";

const FIXTURES_PATH = path.resolve(
  __dirname,
  "..",
  "..",
  "..",
  "core",
  "equipment_identity",
  "p1",
  "type_reference_validation_fixtures.json",
);

interface FixtureCase {
  name: string;
  primaryTypeId: string;
  supportedTypeIds: string[];
  valid: boolean;
  errorContains?: string;
}

interface Fixtures {
  snapshot: FunctionalTypeSnapshot;
  cases: FixtureCase[];
}

function loadFixtures(): Fixtures {
  return JSON.parse(fs.readFileSync(FIXTURES_PATH, "utf8"));
}

describe("loadGeneratedSnapshot", () => {
  test("loads the generated P0 snapshot copy with real types", () => {
    const snapshot = loadGeneratedSnapshot();
    expect(snapshot.typeCount).toBeGreaterThan(0);
    expect(snapshot.types.length).toBe(snapshot.typeCount);
    expect(snapshot.types[0]).toHaveProperty("id");
  });
});

describe("validateTypeReference against the real current snapshot", () => {
  test("a single-function reference to a real type id passes", () => {
    const snapshot = loadGeneratedSnapshot();
    const id = snapshot.types[0].id;
    expect(() => validateTypeReference(id, [id], snapshot)).not.toThrow();
  });

  test("a multi-function reference to two real type ids passes", () => {
    const snapshot = loadGeneratedSnapshot();
    const [a, b] = snapshot.types;
    expect(() => validateTypeReference(a.id, [a.id, b.id], snapshot)).not.toThrow();
  });

  test("an unknown primaryTypeId is rejected", () => {
    const snapshot = loadGeneratedSnapshot();
    expect(() =>
      validateTypeReference("nonexistent_equipment_id", [snapshot.types[0].id], snapshot),
    ).toThrow(TypeSnapshotError);
  });
});

// P1.G1 T5: cross-language behavioral-parity fixtures. The same cases in
// core/equipment_identity/p1/type_reference_validation_fixtures.json also
// drive scripts/equipment_identity/test_type_snapshot.py's Python
// validate_type_reference. Both languages must agree case-by-case.
describe("shared cross-language type-reference-validation fixtures", () => {
  const fixtures = loadFixtures();

  test.each(fixtures.cases.map((c) => [c.name, c] as const))(
    "%s",
    (_name, testCase) => {
      if (testCase.valid) {
        expect(() =>
          validateTypeReference(
            testCase.primaryTypeId,
            testCase.supportedTypeIds,
            fixtures.snapshot,
          ),
        ).not.toThrow();
      } else {
        expect(() =>
          validateTypeReference(
            testCase.primaryTypeId,
            testCase.supportedTypeIds,
            fixtures.snapshot,
          ),
        ).toThrow(testCase.errorContains);
      }
    },
  );
});
