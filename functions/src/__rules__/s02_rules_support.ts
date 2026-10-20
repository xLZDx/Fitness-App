/**
 * Shared support for the S02 "unified activity" rules tests (test epic 5).
 *
 * Not a test file (the name does not end in `.test.ts`), so jest does not run
 * it. It holds three things the S02 rules files share:
 *
 *   1. LITERAL oracles taken from the design (S02_DESIGN.md section 3.2): the
 *      key allowlist and the numeric bounds. They are copied here on purpose
 *      and never derived from `firestore.rules`, so a rules edit that drifts
 *      from the design fails a test instead of silently moving the oracle.
 *   2. Builders for a valid summary and for ids.
 *   3. Rules-TEXT helpers: remove one wildcard exclusion from a COPY of the
 *      rules text (the falsification tests load the mutated copy into a second
 *      emulator project, `firestore.rules` itself is never edited), and a
 *      parser/lint for the permanent floor of design 12.1.
 */
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { resolve } from "path";
import { Timestamp } from "firebase/firestore";

export const ALICE = "alice";
export const BOB = "bob";

export const RULES_PATH = resolve(__dirname, "../../../firestore.rules");
export const POLICY_PATH = resolve(__dirname, "../../../scripts/ci/data_lifecycle_policy.json");
export const GOLDEN_PATH = resolve(__dirname, "fixtures/s02_summaries_100.json");

export const readRules = (): string => readFileSync(RULES_PATH, "utf8");

/** Starts a rules test environment on its own emulator project id. */
export async function makeEnv(projectId: string, rules: string = readRules()): Promise<RulesTestEnvironment> {
  return initializeTestEnvironment({
    projectId,
    firestore: {
      rules,
      host: "127.0.0.1",
      port: Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080),
    },
  });
}

// ---------------------------------------------------------------------------
// Ids and timestamps
// ---------------------------------------------------------------------------

/** A valid deterministic-style activity id: `act_` + 40 lowercase hex digits. */
export const actId = (n: number): string => "act_" + n.toString(16).padStart(40, "0");

export const ts = (iso: string | Date): Timestamp =>
  Timestamp.fromDate(typeof iso === "string" ? new Date(iso) : iso);

export const START = "2026-03-01T10:00:00.000Z";
export const END = "2026-03-01T11:00:00.000Z";

export const activityPath = (uid: string, id: string): string => `users/${uid}/activities/${id}`;

// ---------------------------------------------------------------------------
// Design 3.2 oracles
// ---------------------------------------------------------------------------

/** Every key a cloud summary may carry (design 3.2 table), nothing else. */
export const ALLOWLIST: readonly string[] = [
  "schema", "sport", "startUtc", "endUtc", "utcOffsetMinutes", "movingTimeS", "distanceM",
  "ascentM", "descentM", "avgSpeedMps", "avgCadence", "avgPowerW", "normalizedPowerW",
  "activeEnergyKcal", "steps", "strokeCount", "poolLengthM", "lapCount", "avgSwolf",
  "routeTrimMeters", "primarySourceId", "primarySourceKind", "sourceCount", "userEditCount",
  "mergeNoteCount", "hasRoute", "formulaVersion", "metricDefinitionVersion",
  "thresholdPolicyVersion", "sourceTermsSnapshot", "rev", "updatedAt",
];

export const REQUIRED_KEYS = ["schema", "sport", "startUtc", "endUtc", "rev"] as const;

export interface Bound {
  key: string;
  min: number;
  max: number;
  int: boolean;
}

/** Numeric bounds of design 3.2 (rev is tested separately: create is fixed to 1). */
export const BOUNDS: readonly Bound[] = [
  { key: "schema", min: 1, max: 1000, int: true },
  { key: "utcOffsetMinutes", min: -840, max: 840, int: true },
  { key: "sourceCount", min: 0, max: 64, int: true },
  { key: "userEditCount", min: 0, max: 64, int: true },
  { key: "mergeNoteCount", min: 0, max: 64, int: true },
  { key: "movingTimeS", min: 0, max: 604800, int: false },
  { key: "distanceM", min: 0, max: 10000000, int: false },
  { key: "ascentM", min: 0, max: 100000, int: false },
  { key: "descentM", min: 0, max: 100000, int: false },
  { key: "avgSpeedMps", min: 0, max: 120, int: false },
  { key: "avgCadence", min: 0, max: 400, int: false },
  { key: "avgPowerW", min: 0, max: 5000, int: false },
  { key: "normalizedPowerW", min: 0, max: 5000, int: false },
  { key: "activeEnergyKcal", min: 0, max: 50000, int: false },
  { key: "steps", min: 0, max: 1000000, int: false },
  { key: "strokeCount", min: 0, max: 100000, int: false },
  { key: "poolLengthM", min: 0, max: 1000, int: false },
  { key: "lapCount", min: 0, max: 1000, int: false },
  { key: "avgSwolf", min: 0, max: 300, int: false },
  { key: "routeTrimMeters", min: 0, max: 2000, int: false },
];

export const SOURCE_KINDS = ["platformHealth", "bleSensor", "vendorCloud", "companionApp", "fileImport"] as const;

/** A minimal valid create body (the five required keys, rev 1). */
export function minimalSummary(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema: 2,
    sport: "running",
    startUtc: ts(START),
    endUtc: ts(END),
    rev: 1,
    ...over,
  };
}

/** A realistic valid create body with several optional keys. */
export function summary(over: Record<string, unknown> = {}): Record<string, unknown> {
  return minimalSummary({
    utcOffsetMinutes: 120,
    movingTimeS: 3300,
    distanceM: 10000,
    avgSpeedMps: 3.03,
    primarySourceId: "ble-strap-1",
    primarySourceKind: "bleSensor",
    sourceCount: 1,
    userEditCount: 0,
    mergeNoteCount: 0,
    hasRoute: false,
    formulaVersion: "formula-1",
    ...over,
  });
}

/** A document that carries EVERY allowlisted key at a valid value. */
export function fullSummary(over: Record<string, unknown> = {}): Record<string, unknown> {
  return minimalSummary({
    utcOffsetMinutes: 60,
    movingTimeS: 3300,
    distanceM: 10000,
    ascentM: 120.5,
    descentM: 118.25,
    avgSpeedMps: 3.03,
    avgCadence: 172,
    avgPowerW: 250,
    normalizedPowerW: 261,
    activeEnergyKcal: 640,
    steps: 9000,
    strokeCount: 0,
    poolLengthM: 25,
    lapCount: 10,
    avgSwolf: 40,
    routeTrimMeters: 200,
    primarySourceId: "app",
    primarySourceKind: "companionApp",
    sourceCount: 2,
    userEditCount: 1,
    mergeNoteCount: 0,
    hasRoute: true,
    formulaVersion: "formula-1",
    metricDefinitionVersion: "metrics-1",
    thresholdPolicyVersion: "thresholds-1",
    sourceTermsSnapshot: "terms-2026-10:319",
    updatedAt: ts("2026-03-01T11:00:05.000Z"),
    ...over,
  });
}

export function without(obj: Record<string, unknown>, ...keys: string[]): Record<string, unknown> {
  const copy = { ...obj };
  for (const k of keys) delete copy[k];
  return copy;
}

// ---------------------------------------------------------------------------
// Golden fixture (produced by Dart, epic 1 U30)
// ---------------------------------------------------------------------------

export interface GoldenEntry {
  id: string;
  summary: Record<string, unknown>;
}

const TIMESTAMP_KEYS = ["startUtc", "endUtc", "updatedAt"];

/** Converts ISO-8601 strings of the fixture into Firestore timestamps (the Dart writer does the same). */
export function toWireSummary(raw: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(raw)) {
    out[k] = TIMESTAMP_KEYS.includes(k) && typeof v === "string" ? ts(v) : v;
  }
  return out;
}

export function loadGolden(): GoldenEntry[] {
  const parsed = JSON.parse(readFileSync(GOLDEN_PATH, "utf8")) as { summaries: GoldenEntry[] };
  return parsed.summaries;
}

// ---------------------------------------------------------------------------
// Rules-text helpers
// ---------------------------------------------------------------------------

export const FLOOR_NAMES = ["activities", "activity_streams", "activity_settings", "activity_tombstones"] as const;
export type FloorName = (typeof FLOOR_NAMES)[number];

/** Rules text with line comments removed (comments may name the very tokens a lint looks for). */
export const stripComments = (src: string): string => src.replace(/\/\/[^\n]*/g, "");

const WILDCARD_MATCH = "match /users/{uid}/{coll}/{document=**}";

/** [start, end) of the `allow <clause>:` statement of the owner wildcard block. */
function wildcardClauseRange(src: string, clause: "read" | "write"): [number, number] {
  const blockStart = src.indexOf(WILDCARD_MATCH);
  if (blockStart < 0) throw new Error("owner wildcard block not found in rules text");
  const start = src.indexOf(`allow ${clause}:`, blockStart);
  if (start < 0) throw new Error(`wildcard allow ${clause} not found`);
  const end = src.indexOf(";", start);
  return [start, end + 1];
}

/** The text of the wildcard's read or write condition (comments stripped). */
export function wildcardClause(src: string, clause: "read" | "write"): string {
  const [s, e] = wildcardClauseRange(src, clause);
  return stripComments(src.slice(s, e));
}

/** A COPY of the rules text with one `coll != '<name>'` term removed from one wildcard clause. */
export function removeExclusion(src: string, clause: "read" | "write", name: FloorName): string {
  const [s, e] = wildcardClauseRange(src, clause);
  const segment = src.slice(s, e);
  const re = new RegExp(`\\s*&&\\s*coll\\s*!=\\s*'${name}'(;?)`);
  if (!re.test(segment)) throw new Error(`exclusion ${name} not found in the ${clause} clause`);
  const mutated = segment.replace(re, (_m, semi: string) => semi);
  return src.slice(0, s) + mutated + src.slice(e);
}

/** A COPY of the rules text whose `activities` block lets the owner delete. */
export function openActivitiesDelete(src: string): string {
  const blockStart = src.indexOf("match /users/{uid}/activities/{activityId} {");
  if (blockStart < 0) throw new Error("activities block not found");
  const needle = "allow delete: if false;";
  const at = src.indexOf(needle, blockStart);
  if (at < 0) throw new Error("activities delete rule not found");
  return (
    src.slice(0, at) +
    "allow delete: if isOrdinaryUser() && request.auth.uid == uid;" +
    src.slice(at + needle.length)
  );
}

/** A COPY of the rules text where the named server-only block grants the owner `write`. */
export function openServerBlockWrite(src: string, name: FloorName): string {
  const marker = `match /users/{uid}/${name}/{id} {`;
  const blockStart = src.indexOf(marker);
  if (blockStart < 0) throw new Error(`block for ${name} not found`);
  const needle = "allow write: if false;";
  const at = src.indexOf(needle, blockStart);
  if (at < 0) throw new Error(`write rule of ${name} not found`);
  return (
    src.slice(0, at) +
    "allow write: if isOrdinaryUser() && request.auth.uid == uid;" +
    src.slice(at + needle.length)
  );
}

export interface AllowStatement {
  verbs: string[];
  condition: string;
}

export interface MatchBlock {
  path: string;
  allows: AllowStatement[];
}

/** Extracts the `match <path> { ... }` blocks (comments stripped) with their allow statements. */
export function parseMatchBlocks(src: string): MatchBlock[] {
  const code = stripComments(src);
  const blocks: MatchBlock[] = [];
  const re = /match\s+(\/\S+)\s+\{/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(code)) !== null) {
    let depth = 1;
    let i = re.lastIndex;
    while (i < code.length && depth > 0) {
      if (code[i] === "{") depth++;
      else if (code[i] === "}") depth--;
      i++;
    }
    const body = code.slice(re.lastIndex, i - 1);
    const allows: AllowStatement[] = [];
    const allowRe = /allow\s+([a-z,\s]+?)\s*:\s*if\s+([^;]+);/g;
    let a: RegExpExecArray | null;
    while ((a = allowRe.exec(body)) !== null) {
      allows.push({
        verbs: a[1].split(",").map((v) => v.trim()),
        condition: a[2].replace(/\s+/g, " ").trim(),
      });
    }
    blocks.push({ path: m[1], allows });
  }
  return blocks;
}

/**
 * The permanent-floor lint of design 12.1 (test R31). Returns one message per
 * violation, an empty list when the floor holds.
 */
export function floorViolations(src: string): string[] {
  const out: string[] = [];
  const readClause = wildcardClause(src, "read");
  const writeClause = wildcardClause(src, "write");
  for (const name of FLOOR_NAMES) {
    const term = new RegExp(`coll\\s*!=\\s*'${name}'`);
    if (!term.test(readClause)) out.push(`read clause lacks the exclusion of ${name}`);
    if (!term.test(writeClause)) out.push(`write clause lacks the exclusion of ${name}`);
  }
  const blocks = parseMatchBlocks(src);
  for (const name of FLOOR_NAMES) {
    const block = blocks.find((b) => new RegExp(`^/users/\\{uid\\}/${name}/\\{[A-Za-z]+\\}$`).test(b.path));
    if (!block) {
      out.push(`no match block for users/{uid}/${name}`);
      continue;
    }
    if (name === "activities") {
      const del = block.allows.filter((a) => a.verbs.includes("delete") || a.verbs.includes("write"));
      if (del.length === 0) out.push("activities has no delete statement (delete must be an explicit `if false`)");
      for (const d of del) {
        if (d.condition !== "false") out.push(`activities grants ${d.verbs.join(",")} with a condition other than false`);
      }
    } else {
      for (const a of block.allows) {
        const writes = a.verbs.some((v) => ["write", "create", "update", "delete"].includes(v));
        if (writes && a.condition !== "false") {
          out.push(`${name} grants ${a.verbs.join(",")} with a condition other than false`);
        }
      }
    }
  }
  return out;
}

/** Firestore stored-size estimate of one document (documented size formula, simplified for our value types). */
export function estimateDocBytes(docPath: string, data: Record<string, unknown>): number {
  const utf8 = (s: string) => Buffer.byteLength(s, "utf8");
  // Document name: path segments (utf8 + 1 each) + 16.
  let size = docPath.split("/").reduce((n, seg) => n + utf8(seg) + 1, 0) + 16;
  for (const [k, v] of Object.entries(data)) {
    size += utf8(k) + 1;
    if (typeof v === "string") size += utf8(v) + 1;
    else if (typeof v === "number") size += 8;
    else if (typeof v === "boolean") size += 1;
    else if (v instanceof Timestamp) size += 8;
    else throw new Error(`estimateDocBytes: unsupported value for ${k}`);
  }
  return size + 32; // per-document overhead
}
