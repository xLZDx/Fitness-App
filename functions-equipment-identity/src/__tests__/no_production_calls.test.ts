import * as fs from "fs";
import * as path from "path";

// Structural backstop for the claim P0_G5_CLOUD_FEASIBILITY.md makes in
// prose ("no probe was attempted, no production was touched"): a future PR
// that adds a real Vertex/Firestore/network call to this package would
// compile and could pass every OTHER test here while silently
// contradicting that claim. This test fails loudly the moment that
// happens, rather than relying on the doc staying accurate by itself.
//
// Found by silent-failure-hunter in the P0.G5 review round: the original
// suite had no enforcement of this at all.

const SRC_DIR = path.join(__dirname, "..");

function listTsFiles(dir: string): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listTsFiles(full));
    } else if (entry.isFile() && entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) {
      files.push(full);
    }
  }
  return files;
}

// Package names whose presence in a non-test source file would mean a real
// cloud SDK call is now reachable from this package. Deliberately broader
// than just @google-cloud/aiplatform -- also covers any generic googleapis/
// google-auth surface a future author might reach for instead.
const FORBIDDEN_IMPORT_RE = /from\s+["'](@google-cloud\/(?!.*-types)[^"']+|googleapis|google-auth-library)["']/;

describe("no real cloud SDK call exists yet in this package", () => {
  it("no non-test source file imports a Google Cloud client library", () => {
    const files = listTsFiles(SRC_DIR);
    expect(files.length).toBeGreaterThan(0);
    const offenders = files
      .map((file) => ({ file, content: fs.readFileSync(file, "utf-8") }))
      .filter(({ content }) => FORBIDDEN_IMPORT_RE.test(content))
      .map(({ file }) => path.relative(SRC_DIR, file));
    expect(offenders).toEqual([]);
  });

  it("no non-test source file makes a raw network call (fetch/https.request/http.request)", () => {
    const files = listTsFiles(SRC_DIR);
    const rawNetworkRe = /\b(https?\.request|fetch)\s*\(/;
    const offenders = files
      .map((file) => ({ file, content: fs.readFileSync(file, "utf-8") }))
      .filter(({ content }) => rawNetworkRe.test(content))
      .map(({ file }) => path.relative(SRC_DIR, file));
    expect(offenders).toEqual([]);
  });

  it("index.ts's callable never imports a raw Vertex/Gemini/AI-gateway module -- P2.G3 is text-only lookup against Firestore, never a model call", () => {
    // This test used to assert `index.ts` exported nothing at all
    // ("export {}"), which was P0.G5's honest boundary at the time --
    // no production identity Cloud Function existed yet. P2.G3 is
    // specifically the gate authorized to add one (a Firestore-only
    // exact-model-code lookup), so that assertion is now stale by design,
    // not a regression: the two checks above (no forbidden cloud-SDK
    // import, no raw network call) still enforce the property this file
    // actually exists to guard -- that this package does not silently
    // grow a real network/model call ahead of the gate that legitimizes
    // one. This third check narrows that same guarantee onto index.ts by
    // name, so removing the file's real assertions isn't mistaken for
    // satisfying its stated purpose.
    const indexPath = path.join(SRC_DIR, "index.ts");
    const content = fs.readFileSync(indexPath, "utf-8");
    const forbiddenRe = /from\s+["'](@google-cloud\/(?!.*-types)[^"']+|googleapis|google-auth-library|@google\/generative-ai)["']/;
    expect(forbiddenRe.test(content)).toBe(false);
    expect(/\b(https?\.request|fetch)\s*\(/.test(content)).toBe(false);
  });
});
