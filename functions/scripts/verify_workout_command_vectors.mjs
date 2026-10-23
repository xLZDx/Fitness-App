// Independent verifier of docs/v1/fixtures/workout_command_golden_vectors.json.
//
//     node functions/scripts/verify_workout_command_vectors.mjs
//
// Deliberately does NOT import functions/src/workout_commands/canonical.ts: it re-implements the
// canonical form (sorted keys, no whitespace, integers only) and the uidTag with Node crypto, so the
// checked-in hashes are not circular with the code under test. Exit code 1 on any disagreement.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const file = resolve(here, "../../docs/v1/fixtures/workout_command_golden_vectors.json");
const doc = JSON.parse(readFileSync(file, "utf8"));

function canon(v) {
  if (v === null) return "null";
  if (typeof v === "boolean") return v ? "true" : "false";
  if (typeof v === "number") {
    if (!Number.isInteger(v)) throw new Error("non-integer");
    return String(v);
  }
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return "[" + v.map(canon).join(",") + "]";
  const keys = Object.keys(v).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return "{" + keys.map((k) => JSON.stringify(k) + ":" + canon(v[k])).join(",") + "}";
}
const sha = (s) => createHash("sha256").update(Buffer.from(s, "utf8")).digest("hex");
const tag = (uid) => createHash("sha256").update(Buffer.from("u1|" + uid, "utf8")).digest().subarray(0, 6).toString("base64url");

let bad = 0;
const names = new Set();
for (const v of doc.vectors) {
  const err = (m) => { bad++; console.error(`FAIL ${v.name}: ${m}`); };
  if (names.has(v.name)) err("duplicate name");
  names.add(v.name);
  if (tag(v.authUid) !== v.uidTag) err("uidTag");
  if (sha(v.payloadText) !== v.payloadHash) err("payloadHash");
  if (v.payloadObject !== null) {
    if (canon(v.payloadObject) !== v.canonicalText) err("canonicalText");
  } else if (v.canonicalText !== null) err("canonicalText must be null");
}
const byName = Object.fromEntries(doc.vectors.map((v) => [v.name, v]));
for (const v of doc.vectors) {
  if (v.pairedWith) {
    const o = byName[v.pairedWith];
    if (!o) { bad++; console.error(`FAIL ${v.name}: pair missing`); continue; }
    if (o.payloadHash === v.payloadHash) { bad++; console.error(`FAIL ${v.name}: pair hashes equal`); }
    if (o.payloadObject.operationId !== v.payloadObject.operationId) { bad++; console.error(`FAIL ${v.name}: pair operationId differs`); }
  }
}
console.log(`${doc.vectors.length} vectors, ${bad} failures`);
process.exit(bad === 0 ? 0 : 1);
