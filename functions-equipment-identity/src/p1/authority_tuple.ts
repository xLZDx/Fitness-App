/**
 * P1.G1 §6.4/T4 — RecognitionAuthorityTuple immutability at the schema
 * layer (SPTR Equipment Recognition v4.4, AC-M04-corrected). The *runtime*
 * session-mutation test (proving a live identity-resolution session cannot
 * have its authority tuple changed mid-flight) is P2.G3's DoD item, once a
 * session runtime exists to test against -- see that gate. P1.G1 only
 * proves the type is frozen at construction and that two tuples can be
 * mechanically compared for exact equality, which is the primitive P2.G3's
 * runtime test will build on.
 */
import {
  RecognitionAuthorityTupleSchema,
  type RecognitionAuthorityTuple,
} from "./contracts";

/** Validates and freezes a RecognitionAuthorityTuple so any attempt to
 * mutate a field after construction fails (throws in strict mode, silently
 * no-ops otherwise -- either way the value itself never changes). */
export function freezeAuthorityTuple(
  candidate: unknown,
): RecognitionAuthorityTuple {
  const parsed = RecognitionAuthorityTupleSchema.parse(candidate);
  return Object.freeze(parsed);
}

export class AuthorityTupleMismatchError extends Error {
  constructor(public readonly changedFields: string[]) {
    super(
      `RecognitionAuthorityTuple changed in field(s): ${changedFields.join(", ")} -- ` +
        "an authority tuple must never be mutated after it is bound to a session/record",
    );
    this.name = "AuthorityTupleMismatchError";
  }
}

/**
 * Schema-level immutability assertion: throws `AuthorityTupleMismatchError`
 * if `after` differs from `before` in any field. Field-set-agnostic (does
 * not hardcode the tuple's field list), so it stays correct if the tuple
 * gains an optional field later without needing an edit here.
 */
export function assertAuthorityTupleUnchanged(
  before: RecognitionAuthorityTuple,
  after: RecognitionAuthorityTuple,
): void {
  const beforeKeys = Object.keys(before) as (keyof RecognitionAuthorityTuple)[];
  const afterKeys = Object.keys(after) as (keyof RecognitionAuthorityTuple)[];
  const allKeys = new Set([...beforeKeys, ...afterKeys]);
  const changed: string[] = [];
  for (const key of allKeys) {
    if (before[key] !== after[key]) changed.push(key);
  }
  if (changed.length > 0) {
    throw new AuthorityTupleMismatchError(changed.sort());
  }
}
