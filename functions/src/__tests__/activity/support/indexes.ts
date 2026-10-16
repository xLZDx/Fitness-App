/**
 * Query/index limits for the fake Firestore (plan F88). `installIndexGuard()`
 * makes every executed query fail with FAILED_PRECONDITION (code 9) unless the
 * parsed `firestore.indexes.json` allows it, and rejects the shapes Firestore
 * cannot run at all (inequalities on two different fields).
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import * as fs from "fs";
import * as path from "path";
import { firestoreError, fx } from "./fakes";

export interface IndexFile {
  indexes: Array<{ collectionGroup: string; queryScope: string; fields: Array<{ fieldPath: string; order?: string }> }>;
  fieldOverrides: Array<{ collectionGroup: string; fieldPath: string; indexes?: Array<{ order?: string; queryScope: string }> }>;
}

export const INDEX_FILE_PATH = path.resolve(__dirname, "../../../../../firestore.indexes.json");

export function loadIndexFile(): IndexFile {
  return JSON.parse(fs.readFileSync(INDEX_FILE_PATH, "utf8")) as IndexFile;
}

type Q = { kind: "collection" | "group"; name: string; filters: Array<{ f: string; op: string; v: any }>; orders: string[] };

/** The decision for one query; returns an error message or undefined when allowed. */
export function queryProblem(q: Q, file: IndexFile): string | undefined {
  const ineq = [...new Set(q.filters.filter((f) => f.op !== "==").map((f) => f.f))];
  if (ineq.length > 1) return "inequality on more than one field";
  const eq = [...new Set(q.filters.filter((f) => f.op === "==").map((f) => f.f))];
  const orderFields = q.orders.filter((o) => o !== "__name__");
  const range = ineq[0] ?? orderFields[0];
  if (ineq.length === 1 && orderFields.length > 0 && orderFields[0] !== ineq[0]) {
    return "first orderBy must be the inequality field";
  }
  const fields = [...eq, ...(range !== undefined ? [range] : [])];
  const leaf = q.name.split("/").pop() as string;
  const scope = q.kind === "group" ? "COLLECTION_GROUP" : "COLLECTION";
  if (fields.length <= 1) {
    if (fields.length === 0 || q.kind === "collection") return undefined; // automatic single-field index
    const f = fields[0];
    const ovr = file.fieldOverrides.find((o) => o.collectionGroup === leaf && o.fieldPath === f);
    return ovr?.indexes?.some((i) => i.queryScope === "COLLECTION_GROUP") ? undefined : "missing collection-group index";
  }
  const hit = file.indexes.some(
    (i) =>
      i.collectionGroup === leaf &&
      i.queryScope === scope &&
      i.fields.length === fields.length &&
      i.fields.every((x, k) => x.fieldPath === fields[k] || (k < eq.length && eq.includes(x.fieldPath) && eq.includes(fields[k]))),
  );
  return hit ? undefined : "missing composite index";
}

export function installIndexGuard(file: IndexFile = loadIndexFile()): void {
  fx.checkQuery = (q) => {
    const problem = queryProblem(q as Q, file);
    if (problem) throw firestoreError(`FAILED_PRECONDITION: ${problem}`, 9);
  };
}
