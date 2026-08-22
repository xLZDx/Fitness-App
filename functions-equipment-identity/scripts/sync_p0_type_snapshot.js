// P1.G1 §5.14 (SPTR Equipment Recognition v4.4) — generated deployment copy
// of P0.G4's functional-type snapshot. `core/equipment_identity/p0/
// functional_type_snapshot_v1.json` stays the single source of truth
// (Python-owned, per scripts/equipment_identity/type_snapshot.py); this
// script only copies it into a location the TypeScript build can `import`
// without reaching outside functions-equipment-identity's own tree.
//
//   node scripts/sync_p0_type_snapshot.js          # rewrite the generated copy
//   node scripts/sync_p0_type_snapshot.js --check  # fail if the copy is stale
//
// `check` is what `npm run build` calls — it never silently rewrites, so a
// developer who changed the P0 source without re-running `sync` finds out
// at build time, not from a diff nobody asked for.
"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const SOURCE_PATH = path.join(
  REPO_ROOT,
  "core",
  "equipment_identity",
  "p0",
  "functional_type_snapshot_v1.json",
);
const GENERATED_PATH = path.join(
  __dirname,
  "..",
  "src",
  "generated",
  "functional_type_snapshot_v1.json",
);

function readSource() {
  const raw = fs.readFileSync(SOURCE_PATH, "utf8");
  return { raw, parsed: JSON.parse(raw) };
}

function sync() {
  const { raw } = readSource();
  fs.mkdirSync(path.dirname(GENERATED_PATH), { recursive: true });
  fs.writeFileSync(GENERATED_PATH, raw, "utf8");
  const { parsed } = readSource();
  console.log(
    `wrote ${path.relative(REPO_ROOT, GENERATED_PATH)} ` +
      `(${parsed.typeCount} types, sourceSha256=${parsed.sourceSha256.slice(0, 16)}...)`,
  );
  return 0;
}

function check() {
  if (!fs.existsSync(GENERATED_PATH)) {
    console.error(
      `${path.relative(REPO_ROOT, GENERATED_PATH)} does not exist. ` +
        "Run: node scripts/sync_p0_type_snapshot.js",
    );
    return 1;
  }
  const source = fs.readFileSync(SOURCE_PATH, "utf8");
  const generated = fs.readFileSync(GENERATED_PATH, "utf8");
  if (source !== generated) {
    console.error(
      "P1_SNAPSHOT_STALE: the generated copy of the P0 functional-type " +
        "snapshot differs from core/equipment_identity/p0/" +
        "functional_type_snapshot_v1.json. Run: node scripts/sync_p0_type_snapshot.js",
    );
    return 1;
  }
  const parsed = JSON.parse(generated);
  console.log(
    `OK: generated snapshot matches P0 source (${parsed.typeCount} types, ` +
      `sourceSha256=${parsed.sourceSha256.slice(0, 16)}...)`,
  );
  return 0;
}

function main() {
  const mode = process.argv.includes("--check") ? "check" : "sync";
  process.exit(mode === "check" ? check() : sync());
}

main();
