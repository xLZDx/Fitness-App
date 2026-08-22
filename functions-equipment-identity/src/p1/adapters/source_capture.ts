/**
 * P1.G2 — loads and validates a source-capture fixture that was imported
 * via a static, compile-time JSON import (`resolveJsonModule`), the same
 * pattern P1.G1's type_snapshot.ts already established for the P0
 * functional-type snapshot. No runtime `fs` read: the fixture ships inside
 * the compiled adapter, so there is no path-depth fragility between
 * ts-jest (running against src/) and a built `lib/` tree -- see
 * P1_G1_SCHEMA.md §7's self-caught isolation-probe defect for exactly the
 * class of bug that pattern avoids.
 *
 * `fixtureSha256` is a hash of the RE-SERIALIZED fixture content, not raw
 * file bytes -- there are no raw bytes available once the fixture arrives
 * as an already-parsed JS object via `import`. Deterministic because V8
 * enumerates a parsed object's own string keys in a fixed, spec-defined
 * order (integer-index-like keys ascending first, then remaining string
 * keys in insertion order -- NOT simply "whatever order they appeared in
 * the source text," corrected per P1.G2 review, 2026-08-22) and
 * `JSON.stringify` walks that same order deterministically -- so two runs
 * against an unchanged, already-parsed object always hash identically.
 * This hash is TS-adapter-internal provenance only and is never compared
 * against a hash computed by any other language/tool, and is NOT a
 * guarantee that two textually-different-but-content-equal source files
 * (e.g. differing only in key order) would hash the same.
 */
import { createHash } from "crypto";
import { SourceCaptureFixtureSchema, SourceCaptureFixture } from "./contracts";

export class SourceCaptureFixtureError extends Error {}

export function loadSourceCaptureFixture(rawImportedJson: unknown): {
  fixture: SourceCaptureFixture;
  fixtureSha256: string;
} {
  const result = SourceCaptureFixtureSchema.safeParse(rawImportedJson);
  if (!result.success) {
    throw new SourceCaptureFixtureError(
      `source-capture fixture failed schema validation: ${result.error.message}`,
    );
  }
  const fixtureSha256 = createHash("sha256")
    .update(JSON.stringify(result.data), "utf-8")
    .digest("hex");
  return { fixture: result.data, fixtureSha256 };
}
