/**
 * T11 (RULES-15): `firestore.indexes.json` carries the two body-scan
 * COLLECTION_GROUP composite indexes and the `nutrition_cache.expireAt` TTL
 * override, the file parses, and the pre-existing entries are untouched.
 *
 * It also closes the loop with the code that needs them: every
 * `collectionGroup("body_scans")` equality + range query in `body_scan/purge.ts`
 * must be served by an index in the file (an unserved query fails at runtime
 * with FAILED_PRECONDITION only in production, never in the emulator).
 *
 * Pure file reads: no emulator, no Firebase SDK.
 */
import * as fs from "fs";
import * as path from "path";

const ROOT = path.resolve(__dirname, "..", "..", "..");
const INDEXES_PATH = path.join(ROOT, "firestore.indexes.json");

type IndexField = { fieldPath: string; order?: string };
type CompositeIndex = { collectionGroup: string; queryScope: string; fields: IndexField[] };
type FieldOverride = {
  collectionGroup: string;
  fieldPath: string;
  ttl?: boolean;
  indexes?: Array<{ order: string; queryScope: string }>;
};
type IndexesFile = { indexes: CompositeIndex[]; fieldOverrides: FieldOverride[] };

const raw = fs.readFileSync(INDEXES_PATH, "utf8");
const file = JSON.parse(raw) as IndexesFile;

const findIndex = (group: string, fields: string[]): CompositeIndex[] =>
  file.indexes.filter(
    (i) =>
      i.collectionGroup === group &&
      i.fields.length === fields.length &&
      i.fields.every((f, n) => f.fieldPath === fields[n]),
  );

describe("firestore.indexes.json (body scan + nutrition)", () => {
  test("the file parses and has the two top-level arrays", () => {
    expect(Array.isArray(file.indexes)).toBe(true);
    expect(Array.isArray(file.fieldOverrides)).toBe(true);
  });

  test("body_scans (photosState ASC, photosExpireAt ASC) exists exactly once as a COLLECTION_GROUP index", () => {
    const found = findIndex("body_scans", ["photosState", "photosExpireAt"]);
    expect(found).toHaveLength(1);
    expect(found[0].queryScope).toBe("COLLECTION_GROUP");
    expect(found[0].fields).toEqual([
      { fieldPath: "photosState", order: "ASCENDING" },
      { fieldPath: "photosExpireAt", order: "ASCENDING" },
    ]);
  });

  test("body_scans (status ASC, pendingExpiresAt ASC) exists exactly once as a COLLECTION_GROUP index", () => {
    const found = findIndex("body_scans", ["status", "pendingExpiresAt"]);
    expect(found).toHaveLength(1);
    expect(found[0].queryScope).toBe("COLLECTION_GROUP");
    expect(found[0].fields).toEqual([
      { fieldPath: "status", order: "ASCENDING" },
      { fieldPath: "pendingExpiresAt", order: "ASCENDING" },
    ]);
  });

  test("the body_scans indexes are COLLECTION_GROUP, never COLLECTION (the purge queries span all users)", () => {
    const bodyScanIndexes = file.indexes.filter((i) => i.collectionGroup === "body_scans");
    expect(bodyScanIndexes).toHaveLength(2);
    for (const i of bodyScanIndexes) expect(i.queryScope).toBe("COLLECTION_GROUP");
  });

  test("nutrition_cache.expireAt is a TTL field override (budget counters expire after a day)", () => {
    const overrides = file.fieldOverrides.filter((o) => o.collectionGroup === "nutrition_cache" && o.fieldPath === "expireAt");
    expect(overrides).toHaveLength(1);
    expect(overrides[0].ttl).toBe(true);
    // Keeps single-field indexing on the TTL field in both directions, like the
    // existing accountDeletionRetries override.
    expect(overrides[0].indexes).toEqual([
      { order: "ASCENDING", queryScope: "COLLECTION" },
      { order: "DESCENDING", queryScope: "COLLECTION" },
    ]);
  });

  test("pre-existing entries are untouched: equipment_model_text_keys, accountDeletionRetries index and its TTL", () => {
    expect(findIndex("equipment_model_text_keys", ["catalogVersion", "lookupKey"])).toHaveLength(1);
    expect(findIndex("accountDeletionRetries", ["status", "nextAttemptAt"])).toHaveLength(1);
    const adr = file.fieldOverrides.filter((o) => o.collectionGroup === "accountDeletionRetries" && o.fieldPath === "expireAt");
    expect(adr).toHaveLength(1);
    expect(adr[0].ttl).toBe(true);
  });

  test("the index set is exactly the five known composites and two overrides (an unreviewed addition fails here)", () => {
    expect(file.indexes.map((i) => `${i.collectionGroup}:${i.fields.map((f) => f.fieldPath).join("+")}`).sort()).toEqual(
      [
        "accountDeletionRetries:status+nextAttemptAt",
        "activity_streams:state+expiresAt",
        "body_scans:photosState+photosExpireAt",
        "body_scans:status+pendingExpiresAt",
        "equipment_model_text_keys:catalogVersion+lookupKey",
      ].sort(),
    );
    expect(file.fieldOverrides.map((o) => `${o.collectionGroup}.${o.fieldPath}`).sort()).toEqual([
      "accountDeletionRetries.expireAt",
      "activity_settings.recomputePending",
      "activity_settings.streamDeletePending",
      "activity_streams.pendingSince",
      "activity_tombstones.expireAt",
      "nutrition_cache.expireAt",
    ]);
  });

  test("no duplicate composite indexes", () => {
    const keys = file.indexes.map((i) => `${i.collectionGroup}|${i.queryScope}|${i.fields.map((f) => `${f.fieldPath}:${f.order}`).join(",")}`);
    expect(new Set(keys).size).toBe(keys.length);
  });

  test("every composite index field has an explicit ASCENDING or DESCENDING order", () => {
    for (const i of file.indexes) {
      for (const f of i.fields) expect(["ASCENDING", "DESCENDING"]).toContain(f.order);
    }
  });

  test("firebase.json points at this indexes file and at storage.rules, and declares a storage emulator", () => {
    const fb = JSON.parse(fs.readFileSync(path.join(ROOT, "firebase.json"), "utf8"));
    expect(fb.firestore.indexes).toBe("firestore.indexes.json");
    expect(fb.storage.rules).toBe("storage.rules");
    expect(fb.emulators.storage).toEqual({ port: 9199 });
  });
});

describe("every body_scans collection-group query in the purge job is served by an index", () => {
  const purgeSource = fs.readFileSync(path.join(ROOT, "functions", "src", "body_scan", "purge.ts"), "utf8");
  // collectionGroup("body_scans").where(A, "==", ...).where(B, "<=", ...)
  const pattern = /collectionGroup\("body_scans"\)\s*\.where\("(\w+)",\s*"=="[^)]*\)\s*\.where\("(\w+)",\s*"<="/g;
  const queries = [...purgeSource.matchAll(pattern)].map((m) => ({ eq: m[1], range: m[2] }));

  test("the purge job has the four expected equality+range queries (so this check is not vacuous)", () => {
    expect(queries.map((q) => `${q.eq}+${q.range}`).sort()).toEqual([
      "photosState+photosExpireAt",
      "status+pendingExpiresAt",
      "status+pendingExpiresAt",
      "status+pendingExpiresAt",
    ]);
  });

  test.each([0, 1, 2, 3])("query #%d has a matching composite index (equality field first, range field second)", (n) => {
    const q = queries[n];
    expect(q).toBeDefined();
    expect(findIndex("body_scans", [q.eq, q.range]).length).toBeGreaterThanOrEqual(1);
  });
});
