/**
 * P1.G2 structural guarantee: an adapter emits a StagedEquipmentModelCandidate
 * and nothing else -- it must never be able to reach the publication
 * pipeline (catalog_repository.ts's writeEquipmentModel/EquipmentModelStore,
 * or anything P1.G6 later adds under a `publish`/`catalog_publish` name).
 * Runtime enforcement, not a style convention -- mirrors P0.G6's own
 * verify_deployment_isolation.py's "grep every .ts file for a forbidden
 * substring" approach (see that module's own comment on why a chokepoint
 * function alone isn't enough: a future refactor could still add a new call
 * site, but it could never make this test stop noticing the import).
 */
import * as fs from "fs";
import * as path from "path";

const ADAPTERS_DIR = path.resolve(__dirname, "..", "p1", "adapters");

const FORBIDDEN_SUBSTRINGS = ["catalog_repository", "writeEquipmentModel", "EquipmentModelStore"];

function listAdapterSourceFiles(): string[] {
  return fs
    .readdirSync(ADAPTERS_DIR)
    .filter((f) => f.endsWith(".ts") && !f.endsWith(".test.ts"))
    .map((f) => path.join(ADAPTERS_DIR, f));
}

describe("P1.G2 adapters never import the publication pipeline", () => {
  test("no adapter source file references catalog_repository.ts or its exports", () => {
    const files = listAdapterSourceFiles();
    expect(files.length).toBeGreaterThan(0);
    const offenders: string[] = [];
    for (const file of files) {
      const text = fs.readFileSync(file, "utf-8");
      for (const forbidden of FORBIDDEN_SUBSTRINGS) {
        if (text.includes(forbidden)) {
          offenders.push(`${path.basename(file)} references ${JSON.stringify(forbidden)}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });
});
