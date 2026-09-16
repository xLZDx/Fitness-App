/**
 * Regression test for design doc §7 / plan step 4: the new
 * `equipmentIdentityRecordTelemetry` callable must share the EXACT same
 * `{region, enforceAppCheck}` options as `equipmentIdentityResolveFromText`
 * -- via one shared constant, not two independently-typed literals that
 * could silently drift apart. Source-text based (not an import of
 * `index.ts`, which unconditionally calls `admin.initializeApp()` at
 * module load -- see `p2/identity_handler.ts`'s own header for why that is
 * unsafe from a plain mocked unit test): proves BOTH `onCall(...)` call
 * sites pass the identical `EQUIPMENT_IDENTITY_CALLABLE_OPTIONS` constant,
 * and that no second, independently-typed `{region, enforceAppCheck}`
 * literal exists in the file to drift against it.
 */
import * as fs from "fs";
import * as path from "path";

const INDEX_SOURCE = fs.readFileSync(path.join(__dirname, "..", "index.ts"), "utf8");

describe("index.ts callable options parity", () => {
  test("exactly 2 onCall(...) exports, and both pass EQUIPMENT_IDENTITY_CALLABLE_OPTIONS", () => {
    const onCallArgs = [...INDEX_SOURCE.matchAll(/onCall\(\s*([^,]+),/g)].map((m) => m[1].trim());
    expect(onCallArgs).toHaveLength(2);
    for (const arg of onCallArgs) {
      expect(arg).toBe("EQUIPMENT_IDENTITY_CALLABLE_OPTIONS");
    }
  });

  test("no independent {region, enforceAppCheck} literal exists in index.ts to drift against the shared constant", () => {
    expect(INDEX_SOURCE).not.toMatch(/region\s*:\s*["']/);
    expect(INDEX_SOURCE).not.toMatch(/enforceAppCheck\s*:/);
  });

  test("EQUIPMENT_IDENTITY_CALLABLE_OPTIONS is imported from the shared module, not redefined locally", () => {
    expect(INDEX_SOURCE).toMatch(
      /import\s*\{\s*EQUIPMENT_IDENTITY_CALLABLE_OPTIONS\s*\}\s*from\s*["']\.\/p2\/callable_options["']/,
    );
  });

  test("both callables are still exported", () => {
    expect(INDEX_SOURCE).toMatch(/export const equipmentIdentityResolveFromText = onCall\(/);
    expect(INDEX_SOURCE).toMatch(/export const equipmentIdentityRecordTelemetry = onCall\(/);
  });
});
