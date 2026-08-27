#!/usr/bin/env node
/**
 * MVP1.G3 OBS-1 item 4 (CI: equipment-registry parity).
 *
 * `functions/src/ai_equipment_recognition.ts`'s CANONICAL_MACHINES is a
 * second, hand-maintained source of truth for the same equipment vocabulary
 * `mobile/assets/data/equipment.json` already owns -- the exact drift
 * mechanism that already bit this project once (the 08-03 `kCanonicalMachines`
 * fix closed one instance, not the recurrence risk; see
 * core/MASTER_PLAN_2026-08-26.md Sec8 item 10). This script is a real,
 * content-level comparison (not a bare count check, which the item's own DoD
 * explicitly forbids relying on alone) between the two lists, run in CI.
 *
 * Naming conventions differ by design (CANONICAL_MACHINES is a lowercase,
 * space-separated prompt vocabulary; equipment.json uses snake_case ids and
 * a human-formatted `name`), so a naive string-equality check would false-
 * positive on every entry. This script normalizes both sides and additionally
 * consults ALIAS_MAP below for the small number of genuine naming
 * differences that normalization alone cannot bridge (verified by hand,
 * 2026-08-27 -- see the comment on each entry).
 *
 * KNOWN_UNCOVERED lists CANONICAL_MACHINES entries with NO equipment.json
 * counterpart at all, found by this exact check on introduction (not
 * something this gate is closing -- adding/removing catalog entries is
 * content work, out of MVP1.G3's scope). This is an explicit, reviewable
 * allowlist, not a silent pass: anything added to it must be a real,
 * verified gap, and the check still fails on anything NOT on this list --
 * unlike a naive "ignore unmatched" rule, a new drift instance cannot hide
 * here undetected.
 */
const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const FUNCTIONS_TS = path.join(
  REPO_ROOT,
  "functions",
  "src",
  "ai_equipment_recognition.ts"
);
const EQUIPMENT_JSON = path.join(
  REPO_ROOT,
  "mobile",
  "assets",
  "data",
  "equipment.json"
);

/**
 * Genuine naming differences between the two lists, verified by hand
 * 2026-08-27 (`git show` at MVP1.G3's commit introducing this file has the
 * full diff evidence). Keyed by the exact CANONICAL_MACHINES string, valued
 * by the exact equipment.json `id` it refers to -- keying by id means a
 * future rename of that id in equipment.json breaks this map explicitly
 * (the lookup fails), rather than silently going stale.
 */
const ALIAS_MAP = {
  "bench press station": "bench_press", // equipment.json name: "Weight bench"
  "hip abductor machine": "hip_abductor_adductor", // "Hip abductor / adductor machine"
  "flat bench": "adjustable_bench", // "Bench (flat / adjustable)"
  "suspension trainer": "trx", // "Suspension trainer (TRX)"
};

/**
 * CANONICAL_MACHINES entries with no equipment.json counterpart at all,
 * found live by this check (2026-08-27): the camera-recognition prompt can
 * name a machine that has no catalog page behind it. Real, pre-existing gap
 * -- not created by this check, not fixed by it either (content-catalog
 * work is out of MVP1.G3's engineering scope). Recorded here so the check
 * stays strict for everything else while being honest about what it does
 * not yet cover.
 */
const KNOWN_UNCOVERED = new Set(["push-up blocks", "aerobic step"]);

function normalize(s) {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/s\b/g, "")
    .trim();
}

function extractCanonicalMachines(tsSource) {
  const match = tsSource.match(
    /export const CANONICAL_MACHINES: readonly string\[\] = \[([\s\S]*?)\] as const;/
  );
  if (!match) {
    throw new Error(
      "could not find CANONICAL_MACHINES array in ai_equipment_recognition.ts " +
        "-- has its declaration shape changed? Update this script's regex."
    );
  }
  return [...match[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
}

function main() {
  const tsSource = fs.readFileSync(FUNCTIONS_TS, "utf8");
  const canonical = extractCanonicalMachines(tsSource);

  const equipment = JSON.parse(fs.readFileSync(EQUIPMENT_JSON, "utf8"));
  const byNormName = new Map();
  const byNormId = new Map();
  for (const e of equipment) {
    byNormName.set(normalize(e.name), e.id);
    byNormId.set(normalize(e.id.replace(/_/g, " ")), e.id);
  }

  const dupes = canonical.filter((c, i) => canonical.indexOf(c) !== i);
  const unmatched = [];

  for (const c of canonical) {
    if (KNOWN_UNCOVERED.has(c)) continue;
    if (ALIAS_MAP[c]) {
      const targetId = ALIAS_MAP[c];
      const stillExists = equipment.some((e) => e.id === targetId);
      if (!stillExists) {
        unmatched.push(
          `${JSON.stringify(c)} -- ALIAS_MAP points at equipment.json id ` +
            `"${targetId}", which no longer exists (renamed or removed?)`
        );
      }
      continue;
    }
    const n = normalize(c);
    if (byNormName.has(n) || byNormId.has(n)) continue;
    unmatched.push(
      `${JSON.stringify(c)} -- no equipment.json match by name or id, and ` +
        "not in ALIAS_MAP or KNOWN_UNCOVERED. Either a real new drift " +
        "instance, or a genuine new gap that needs an explicit, reviewed " +
        "entry in one of those two maps (never a silent pass)."
    );
  }

  // The allowlists are audited too: an entry that no longer needs its
  // exception (equipment.json grew a matching entry) is stale bookkeeping,
  // not a hard failure, but worth surfacing loudly.
  const staleAllowlistEntries = [];
  for (const c of KNOWN_UNCOVERED) {
    const n = normalize(c);
    if (byNormName.has(n) || byNormId.has(n)) {
      staleAllowlistEntries.push(
        `${JSON.stringify(c)} is in KNOWN_UNCOVERED but equipment.json now ` +
          "has a matching entry -- remove it from the allowlist."
      );
    }
  }

  if (dupes.length > 0) {
    console.error(
      `check_equipment_registry_parity: FAIL -- CANONICAL_MACHINES has ` +
        `duplicate entries: ${JSON.stringify([...new Set(dupes)])}`
    );
    process.exit(1);
  }

  if (unmatched.length > 0) {
    console.error("check_equipment_registry_parity: FAIL");
    for (const u of unmatched) {
      console.error(`  - ${u}`);
    }
    process.exit(1);
  }

  if (staleAllowlistEntries.length > 0) {
    console.error("check_equipment_registry_parity: FAIL (stale allowlist)");
    for (const s of staleAllowlistEntries) {
      console.error(`  - ${s}`);
    }
    process.exit(1);
  }

  console.log(
    `check_equipment_registry_parity: OK -- ${canonical.length} ` +
      `CANONICAL_MACHINES entries all resolve against equipment.json's ` +
      `${equipment.length} entries (${
        Object.keys(ALIAS_MAP).length
      } via ALIAS_MAP, ${KNOWN_UNCOVERED.size} explicitly allowlisted as ` +
      "known content gaps)."
  );
}

main();
