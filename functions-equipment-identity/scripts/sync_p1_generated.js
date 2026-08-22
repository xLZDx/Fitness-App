// P1.G2 -- generated deployment copies of two Python/repo-owned inputs
// functions-equipment-identity's adapters need at build time:
//   - core/equipment_identity/p0/source_registry.json (P0.G3, Python-owned)
//   - core/equipment_identity/p1/source_captures/*.json (this gate's real
//     official-manufacturer fixtures)
//
// Same pattern as sync_p0_type_snapshot.js: the repo file stays the single
// source of truth; this script only copies it somewhere the TypeScript
// build can `import` (resolveJsonModule) without reaching outside
// functions-equipment-identity's own tree at runtime.
//
//   node scripts/sync_p1_generated.js          # rewrite the generated copies
//   node scripts/sync_p1_generated.js --check  # fail if any copy is stale
//
// `check` is what `npm run build` calls.
"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");

const SOURCE_REGISTRY_SRC = path.join(
  REPO_ROOT,
  "core",
  "equipment_identity",
  "p0",
  "source_registry.json",
);
const SOURCE_REGISTRY_DST = path.join(__dirname, "..", "src", "generated", "source_registry.json");

const CAPTURES_SRC_DIR = path.join(
  REPO_ROOT,
  "core",
  "equipment_identity",
  "p1",
  "source_captures",
);
const CAPTURES_DST_DIR = path.join(__dirname, "..", "src", "generated", "source_captures");

function listSourceFixtureFiles() {
  if (!fs.existsSync(CAPTURES_SRC_DIR)) return [];
  return fs
    .readdirSync(CAPTURES_SRC_DIR)
    .filter((f) => f.endsWith(".json"))
    .sort();
}

function sync() {
  fs.mkdirSync(path.dirname(SOURCE_REGISTRY_DST), { recursive: true });
  fs.copyFileSync(SOURCE_REGISTRY_SRC, SOURCE_REGISTRY_DST);

  fs.mkdirSync(CAPTURES_DST_DIR, { recursive: true });
  const files = listSourceFixtureFiles();
  for (const f of files) {
    fs.copyFileSync(path.join(CAPTURES_SRC_DIR, f), path.join(CAPTURES_DST_DIR, f));
  }
  console.log(
    `wrote src/generated/source_registry.json and ${files.length} source-capture fixture(s): ${files.join(", ")}`,
  );
  return 0;
}

function check() {
  const problems = [];

  if (!fs.existsSync(SOURCE_REGISTRY_DST)) {
    problems.push("src/generated/source_registry.json is missing");
  } else if (fs.readFileSync(SOURCE_REGISTRY_SRC, "utf8") !== fs.readFileSync(SOURCE_REGISTRY_DST, "utf8")) {
    problems.push("src/generated/source_registry.json is stale");
  }

  const files = listSourceFixtureFiles();
  for (const f of files) {
    const dst = path.join(CAPTURES_DST_DIR, f);
    if (!fs.existsSync(dst)) {
      problems.push(`src/generated/source_captures/${f} is missing`);
      continue;
    }
    if (fs.readFileSync(path.join(CAPTURES_SRC_DIR, f), "utf8") !== fs.readFileSync(dst, "utf8")) {
      problems.push(`src/generated/source_captures/${f} is stale`);
    }
  }

  // An orphaned generated fixture (source deleted/renamed but the copy
  // wasn't) is exactly as dangerous as a stale one -- an adapter could keep
  // importing evidence that no longer exists as tracked source data.
  if (fs.existsSync(CAPTURES_DST_DIR)) {
    const generatedFiles = fs.readdirSync(CAPTURES_DST_DIR).filter((f) => f.endsWith(".json"));
    for (const f of generatedFiles) {
      if (!files.includes(f)) {
        problems.push(`src/generated/source_captures/${f} is orphaned -- no matching source fixture`);
      }
    }
  }

  if (problems.length > 0) {
    console.error("P1_GENERATED_STALE:\n  " + problems.join("\n  "));
    console.error("Run: node scripts/sync_p1_generated.js");
    return 1;
  }
  console.log(
    `OK: src/generated/source_registry.json and ${files.length} source-capture fixture(s) match their sources`,
  );
  return 0;
}

function main() {
  const mode = process.argv.includes("--check") ? "check" : "sync";
  process.exit(mode === "check" ? check() : sync());
}

main();
