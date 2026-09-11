// P2.G3 (SPTR Equipment Recognition v4.4) -- generated deployment copy of
// P0.G0's APP_CHECK_PLATFORM_READINESS status. core/equipment_identity/p0/
// p0_g0_app_check_platform_readiness.json stays the single, platform/P0-
// owned source of truth; this script only copies it into a location the
// TypeScript build can `import` without reaching outside
// functions-equipment-identity's own tree -- same pattern and same reason
// as sync_p0_type_snapshot.js.
//
// This exists precisely so P2 code never hardcodes an "authoritative
// current readiness = X" assertion of its own (GPT-PM round-2 MAJOR,
// P2.G3 plan review, 2026-09-10): P2 only ever reads this generated copy,
// and the tracked P0 artifact is the one place the real value lives. A
// future operator-authorized platform migration updates ONE file
// (core/equipment_identity/p0/p0_g0_app_check_platform_readiness.json)
// and P2 observes the transition on its next sync/build -- no P2 code
// change required.
//
//   node scripts/sync_p0_app_check_readiness.js          # rewrite the generated copy
//   node scripts/sync_p0_app_check_readiness.js --check  # fail if the copy is stale
//
// `check` is what `npm run build`/`pretest` call -- it never silently
// rewrites, so a developer who changed the P0 source without re-running
// `sync` finds out at build time, not from a diff nobody asked for.
"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const SOURCE_PATH = path.join(
  REPO_ROOT,
  "core",
  "equipment_identity",
  "p0",
  "p0_g0_app_check_platform_readiness.json",
);
const GENERATED_PATH = path.join(
  __dirname,
  "..",
  "src",
  "generated",
  "p0_g0_app_check_platform_readiness.json",
);

function readSource() {
  const raw = fs.readFileSync(SOURCE_PATH, "utf8");
  return { raw, parsed: JSON.parse(raw) };
}

function sync() {
  const { raw, parsed } = readSource();
  fs.mkdirSync(path.dirname(GENERATED_PATH), { recursive: true });
  fs.writeFileSync(GENERATED_PATH, raw, "utf8");
  console.log(
    `wrote ${path.relative(REPO_ROOT, GENERATED_PATH)} (status=${parsed.status})`,
  );
  return 0;
}

function check() {
  if (!fs.existsSync(GENERATED_PATH)) {
    console.error(
      `${path.relative(REPO_ROOT, GENERATED_PATH)} does not exist. ` +
        "Run: node scripts/sync_p0_app_check_readiness.js",
    );
    return 1;
  }
  const source = fs.readFileSync(SOURCE_PATH, "utf8");
  const generated = fs.readFileSync(GENERATED_PATH, "utf8");
  if (source !== generated) {
    console.error(
      "P0_G0_READINESS_STALE: the generated copy of the P0.G0 App Check " +
        "platform-readiness status differs from core/equipment_identity/p0/" +
        "p0_g0_app_check_platform_readiness.json. Run: " +
        "node scripts/sync_p0_app_check_readiness.js",
    );
    return 1;
  }
  const parsed = JSON.parse(generated);
  console.log(`OK: generated readiness status matches P0 source (status=${parsed.status})`);
  return 0;
}

function main() {
  const mode = process.argv.includes("--check") ? "check" : "sync";
  process.exit(mode === "check" ? check() : sync());
}

main();
