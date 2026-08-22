/**
 * P1.G1 §6.5 (T5) — server-side port of scripts/equipment_identity/
 * type_snapshot.py's `validate_type_reference`. Same semantics, same
 * error triggers, deliberately kept behaviorally identical (see
 * __tests__/p1_type_snapshot.test.ts, which cross-tests both languages
 * against core/equipment_identity/p1/type_reference_validation_fixtures.json).
 *
 * This is the FIRST point in the whole program where a real server-side
 * exact-model consumer of P0.G4's functional-type snapshot exists.
 */
import generatedSnapshot from "../generated/functional_type_snapshot_v1.json";

export interface FunctionalTypeEntry {
  id: string;
  name: string;
  manufacturer: string;
  category: string;
  description: string;
}

export interface FunctionalTypeSnapshot {
  schemaVersion: number;
  sourcePath: string;
  sourceSha256: string;
  typeCount: number;
  types: FunctionalTypeEntry[];
}

export class TypeSnapshotError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TypeSnapshotError";
  }
}

/** The generated deployment copy synced from P0.G4 (see §5.14 and
 * scripts/sync_p0_type_snapshot.js). `npm run check:p0-snapshot` (part of
 * `npm run build`) fails the build if this copy has drifted from the
 * Python-owned source. */
export function loadGeneratedSnapshot(): FunctionalTypeSnapshot {
  return generatedSnapshot as FunctionalTypeSnapshot;
}

/**
 * Pure validator for one exact-model's type references against a snapshot.
 * Throws `TypeSnapshotError` on any invalid reference -- never silently
 * normalizes, drops, or defaults an unknown id. Mirrors
 * type_snapshot.py's `validate_type_reference` exactly, including error
 * ordering (a caller relying on "first failure wins" gets the same failure
 * in both languages for the same bad input).
 */
export function validateTypeReference(
  primaryTypeId: string,
  supportedTypeIds: string[],
  snapshot: FunctionalTypeSnapshot,
): void {
  if (typeof primaryTypeId !== "string" || primaryTypeId.length === 0) {
    throw new TypeSnapshotError(
      `primaryTypeId must be a non-empty string, got ${JSON.stringify(primaryTypeId)}`,
    );
  }

  if (!Array.isArray(supportedTypeIds)) {
    throw new TypeSnapshotError("supportedTypeIds must be an array");
  }
  const nonStrings = supportedTypeIds.filter((t) => typeof t !== "string" || t.length === 0);
  if (nonStrings.length > 0) {
    throw new TypeSnapshotError(
      `supportedTypeIds must contain only non-empty strings, got ${JSON.stringify(nonStrings)}`,
    );
  }

  const counts = new Map<string, number>();
  for (const t of supportedTypeIds) counts.set(t, (counts.get(t) ?? 0) + 1);
  const dupes = [...counts.entries()].filter(([, n]) => n > 1).map(([t]) => t).sort();
  if (dupes.length > 0) {
    throw new TypeSnapshotError(`duplicate type id(s) in supportedTypeIds: ${JSON.stringify(dupes)}`);
  }

  if (!snapshot || !Array.isArray(snapshot.types)) {
    throw new TypeSnapshotError("snapshot must be an object with a 'types' array");
  }
  const badEntries = snapshot.types.filter(
    (t) => typeof t !== "object" || t === null || typeof t.id !== "string",
  );
  if (badEntries.length > 0) {
    throw new TypeSnapshotError("snapshot.types contains an entry with no string 'id'");
  }

  const knownIds = new Set(snapshot.types.map((t) => t.id));

  if (!knownIds.has(primaryTypeId)) {
    throw new TypeSnapshotError(
      `primaryTypeId ${JSON.stringify(primaryTypeId)} does not exist in the type snapshot`,
    );
  }

  const unknown = supportedTypeIds.filter((t) => !knownIds.has(t));
  if (unknown.length > 0) {
    throw new TypeSnapshotError(
      `supportedTypeId(s) ${JSON.stringify(unknown)} do not exist in the type snapshot`,
    );
  }

  if (!supportedTypeIds.includes(primaryTypeId)) {
    throw new TypeSnapshotError(
      `primaryTypeId ${JSON.stringify(primaryTypeId)} must be present in supportedTypeIds ` +
        `${JSON.stringify(supportedTypeIds)} -- the default path is one of the model's own ` +
        "supported functions, not a separate claim",
    );
  }
}
