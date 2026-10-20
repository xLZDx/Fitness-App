/**
 * T04 (RULES-12): the DEFAULT Storage bucket is deny-all.
 *
 * `storage.rules` is a single `allow read, write: if false` over
 * `/b/{bucket}/o/{allPaths=**}`. Before it existed there was no storage rules
 * file at all and nobody knew what was deployed. The app does not use the
 * `firebase_storage` plugin and the Body Scan photos live in a SEPARATE private
 * bucket governed by IAM and V4 signed URLs, so no client has any business
 * here. The Admin SDK bypasses these rules, so this file says nothing about the
 * server paths; it describes the CLIENT's reach.
 *
 * Runs against the Storage emulator:
 *
 *     node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage \
 *       demo-fitness-rules src/__rules__/storage_rules.test.ts
 *
 * Every refusal is paired with the same operation done with security rules
 * disabled (the Admin-equivalent), which must succeed -- otherwise "refused"
 * could just mean the emulator or the path is broken.
 */
import { assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { readFileSync } from "fs";
import { resolve } from "path";
import { ref, uploadBytes, getBytes, getMetadata, deleteObject, listAll } from "firebase/storage";

let env: RulesTestEnvironment;

const OWNER = "alice";
const OTHER = "bob";
const BYTES = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-fitness-rules",
    storage: {
      rules: readFileSync(resolve(__dirname, "../../../storage.rules"), "utf8"),
      host: "127.0.0.1",
      // 9199 is firebase.json's storage emulator port; overridable for the same
      // reason as FIRESTORE_EMULATOR_PORT in firestore_rules.test.ts.
      port: Number(process.env.STORAGE_EMULATOR_PORT ?? 9199),
    },
  });
});

afterAll(async () => env?.cleanup());
beforeEach(async () => env.clearStorage());

const asOwner = () => env.authenticatedContext(OWNER).storage();
const asOther = () => env.authenticatedContext(OTHER).storage();
const asCanary = () => env.authenticatedContext("canary-fixed-uid", { canary: true }).storage();
const anonymous = () => env.unauthenticatedContext().storage();

/** Writes an object the way the server (Admin SDK) would: rules do not apply. */
const seed = (path: string) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), path), BYTES, { contentType: "image/jpeg" });
  });

const PATHS = [
  `users/${OWNER}/scans/scan-1/front.jpg`, // the Body Scan photo path shape (must NOT be reachable here)
  `users/${OWNER}/scans/scan-1/side.jpg`,
  `users/${OWNER}/profile.jpg`,
  "random/file.txt",
  "file-at-root.txt",
  "public/anything.png",
];

describe("default bucket is deny-all", () => {
  test("positive control: the server path (rules disabled) can write and read every probe path", async () => {
    for (const path of PATHS) {
      await assertSucceeds(seed(path));
      await env.withSecurityRulesDisabled(async (ctx) => {
        const bytes = await getBytes(ref(ctx.storage(), path));
        expect(Array.from(new Uint8Array(bytes))).toEqual(Array.from(BYTES));
      });
    }
  });

  describe.each([
    ["the owner", asOwner],
    ["another signed-in user", asOther],
    ["the canary identity", asCanary],
    ["an anonymous (unauthenticated) caller", anonymous],
  ] as const)("%s", (_who, ctx) => {
    test.each(PATHS)("write to %s is refused", async (path) => {
      await assertFails(uploadBytes(ref(ctx(), path), BYTES, { contentType: "image/jpeg" }));
    });

    test.each(PATHS)("read of an EXISTING object at %s is refused", async (path) => {
      await seed(path);
      await assertFails(getBytes(ref(ctx(), path)));
      await assertFails(getMetadata(ref(ctx(), path)));
    });

    test.each(PATHS)("delete of an existing object at %s is refused (and the object survives)", async (path) => {
      await seed(path);
      await assertFails(deleteObject(ref(ctx(), path)));
      await env.withSecurityRulesDisabled(async (c) => {
        await assertSucceeds(getBytes(ref(c.storage(), path)));
      });
    });

    test("listing the bucket root and a user folder is refused", async () => {
      await seed(PATHS[0]);
      await assertFails(listAll(ref(ctx(), "")));
      await assertFails(listAll(ref(ctx(), `users/${OWNER}`)));
      await assertFails(listAll(ref(ctx(), `users/${OWNER}/scans/scan-1`)));
    });
  });

  test("an owner write of a well-formed Body Scan photo path (image/jpeg, small) is refused and leaves nothing behind", async () => {
    const path = `users/${OWNER}/scans/scan-9/back.jpg`;
    await assertFails(uploadBytes(ref(asOwner(), path), BYTES, { contentType: "image/jpeg" }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Rules are disabled here, so the only reason this can fail is that the object is absent.
      await expect(getBytes(ref(ctx.storage(), path))).rejects.toMatchObject({ code: "storage/object-not-found" });
    });
  });

  test("overwriting an existing server-written object is refused and keeps the original bytes", async () => {
    const path = `users/${OWNER}/scans/scan-1/front.jpg`;
    await seed(path);
    await assertFails(uploadBytes(ref(asOwner(), path), new Uint8Array([9, 9, 9]), { contentType: "image/jpeg" }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const bytes = await getBytes(ref(ctx.storage(), path));
      expect(Array.from(new Uint8Array(bytes))).toEqual(Array.from(BYTES));
    });
  });
});

describe("storage.rules source", () => {
  const source = readFileSync(resolve(__dirname, "../../../storage.rules"), "utf8");
  const code = source
    .split(/\r?\n/)
    .filter((l) => !l.trim().startsWith("//"))
    .join("\n");

  test("contains exactly one allow statement and it is `if false`", () => {
    const allows = code.match(/allow\s+[^;]+;/g) ?? [];
    expect(allows).toHaveLength(1);
    expect((allows[0] ?? "").replace(/\s+/g, " ")).toBe("allow read, write: if false;");
  });

  test("contains no condition that could grant access (auth, request, resource, true)", () => {
    expect(code).not.toMatch(/request\.auth/);
    expect(code).not.toMatch(/\bresource\b/);
    expect(code).not.toMatch(/if\s+true/);
    expect(code).not.toMatch(/firestore\.get|firestore\.exists/);
  });

  test("covers every path with the recursive wildcard", () => {
    expect(code).toContain("match /{allPaths=**}");
    expect(code).toContain("match /b/{bucket}/o");
  });
});

// ---------------------------------------------------------------------------
// S02 test epic 5 (plan ids S01-S03): the private activity-stream bucket is NOT
// governed by Storage rules; the DEFAULT bucket stays deny-all for the stream
// object shapes too (design 5, option (b)). Every refusal is paired with the
// Admin-equivalent write/read that succeeds.
// ---------------------------------------------------------------------------
describe("S02 activity stream paths in the default bucket", () => {
  const STREAM_PATHS = [
    `streams/${OWNER}/act_${"a".repeat(40)}/v1.json.gz`,
    `quarantine/${OWNER}/act_${"a".repeat(40)}/upload-1`,
  ];
  const WHO = [
    ["the owner", asOwner],
    ["another signed-in user", asOther],
    ["the canary identity", asCanary],
    ["an anonymous caller", anonymous],
  ] as const;

  describe.each(WHO)("%s", (_who, ctx) => {
    test.each(STREAM_PATHS)("S01: read, metadata, write, list and delete of %s are refused and the object survives", async (path) => {
      await assertSucceeds(seed(path)); // control: the Admin-equivalent write works
      await assertFails(getBytes(ref(ctx(), path)));
      await assertFails(getMetadata(ref(ctx(), path)));
      await assertFails(uploadBytes(ref(ctx(), path), new Uint8Array([7, 7]), { contentType: "application/gzip" }));
      await assertFails(listAll(ref(ctx(), path.slice(0, path.lastIndexOf("/")))));
      await assertFails(deleteObject(ref(ctx(), path)));
      await env.withSecurityRulesDisabled(async (c) => {
        const bytes = await getBytes(ref(c.storage(), path));
        expect(Array.from(new Uint8Array(bytes))).toEqual(Array.from(BYTES)); // original bytes untouched
      });
    });
  });

  test("S02: the owner cannot create an object under quarantine/ (a signed URL is the only write path) and nothing is left behind", async () => {
    // A path no other test seeds: clearStorage does not remove objects between tests of this emulator.
    const path = `quarantine/${OWNER}/act_${"b".repeat(40)}/upload-fresh`;
    await assertFails(uploadBytes(ref(asOwner(), path), BYTES, { contentType: "application/gzip" }));
    await assertFails(uploadBytes(ref(asOwner(), `quarantine/${OTHER}/x/y`), BYTES));
    await env.withSecurityRulesDisabled(async (ctx) => {
      // Rules are disabled, so an empty listing can only mean the denied uploads left nothing behind.
      const listing = await listAll(ref(ctx.storage(), path.slice(0, path.lastIndexOf("/"))));
      expect(listing.items).toHaveLength(0);
    });
    await assertSucceeds(seed(path));
    await env.withSecurityRulesDisabled(async (ctx) => {
      const listing = await listAll(ref(ctx.storage(), path.slice(0, path.lastIndexOf("/"))));
      expect(listing.items).toHaveLength(1); // the listing is a real instrument: it sees the seeded object
    }); // control: the path itself is writable by the server
  });
});

describe("S03 storage.rules loosening guard for the S02 stream prefixes", () => {
  const source = readFileSync(resolve(__dirname, "../../../storage.rules"), "utf8");
  const stripComments = (s: string) => s.split(/\r?\n/).filter((l) => !l.trim().startsWith("//")).join("\n");
  const lint = (text: string): string[] => {
    const code = stripComments(text);
    const out: string[] = [];
    const allows = (code.match(/allow\s+[^;]+;/g) ?? []).map((a) => a.replace(/\s+/g, " "));
    if (allows.length !== 1 || allows[0] !== "allow read, write: if false;") out.push(`allows: ${JSON.stringify(allows)}`);
    if (/streams\/|quarantine\//.test(code)) out.push("streams/ or quarantine/ named in a rule");
    if (/request\.auth|firestore\.(get|exists)/.test(code)) out.push("a condition reads auth or firestore");
    return out;
  };

  test("the real storage.rules has exactly the single deny-all and names no stream prefix in code", () => {
    expect(lint(source)).toEqual([]);
  });

  test("the lint detects an added allow for streams/ and an added allow for quarantine/ (mutated copies)", () => {
    const withStreams = source.replace(
      "match /{allPaths=**} {",
      "match /streams/{uid}/{rest=**} { allow read: if request.auth.uid == uid; }\n    match /{allPaths=**} {",
    );
    expect(withStreams).not.toBe(source);
    expect(lint(withStreams).length).toBeGreaterThan(0);
    const withQuarantine = source.replace("allow read, write: if false;", "allow read, write: if false;\n    allow create: if true;");
    expect(withQuarantine).not.toBe(source);
    expect(lint(withQuarantine).length).toBeGreaterThan(0);
  });
});
