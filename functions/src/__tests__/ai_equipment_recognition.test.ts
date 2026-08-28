/**
 * `aiEquipmentRecognition` — G1's second server-owned AI callable. The
 * properties this suite protects: the request is validated (image required,
 * bounded, an allowed mime type), the daily quota gates the model call, the
 * exact vision-generation config the mobile source used is preserved, and the
 * ported `CANONICAL_MACHINES` list stays in step with the equipment registry
 * — the same two-directional tripwire
 * `gemini_equipment_service_test.dart` ran before this list had a server-side
 * copy, now run against BOTH copies so a registry change that updates one but
 * not the other fails here.
 */
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

let usage: Record<string, number> = {};
jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({
    doc: jest.fn((path: string) => ({ path })),
    runTransaction: jest.fn(async (fn: (tx: any) => Promise<void>) =>
      fn({
        get: async () => ({ data: () => ({ ...usage }) }),
        set: (_ref: any, data: Record<string, number>) => {
          usage = { ...usage, ...data };
        },
      }),
    ),
  })),
}));

const generate = jest.fn();
jest.mock("../ai_gateway", () => ({ generate: (...args: unknown[]) => generate(...args) }));

import * as fs from "fs";
import * as path from "path";
import { aiEquipmentRecognition, CANONICAL_MACHINES } from "../ai_equipment_recognition";
import { QUOTAS } from "../abuse_guard";

const req = (data: unknown, uid: string | null = "u1"): any => ({
  data,
  auth: uid ? { uid, token: {} } : undefined,
});

// Real file-signature bytes, not just "any non-empty base64 string" — GPT-PM's
// G1 round-1 review caught that the original fixture here was the base64 for
// the plain text "hello", which the callable accepted and forwarded to the
// model as `image/jpeg`. `parseInput` now sniffs the actual bytes, so these
// fixtures have to look like real images to exercise the success paths below.
const JPEG_BASE64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]).toString(
  "base64",
);
const PNG_BASE64 = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]).toString(
  "base64",
);
const NOT_AN_IMAGE_BASE64 = Buffer.from("hello").toString("base64");

const VALID = { mimeType: "image/jpeg", imageBase64: JPEG_BASE64 };

beforeEach(() => {
  jest.clearAllMocks();
  usage = {};
  generate.mockResolvedValue('{"machine": "smith machine", "confidence": 0.8}');
});

describe("aiEquipmentRecognition", () => {
  test("requires sign-in", async () => {
    await expect(aiEquipmentRecognition.run(req(VALID, null))).rejects.toThrow(/Sign in/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a missing mimeType", async () => {
    await expect(
      aiEquipmentRecognition.run(req({ imageBase64: "aGVsbG8=" })),
    ).rejects.toThrow(/mimeType/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a mimeType outside the fixed allowlist", async () => {
    await expect(
      aiEquipmentRecognition.run(req({ mimeType: "image/gif", imageBase64: "aGVsbG8=" })),
    ).rejects.toThrow(/mimeType/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a missing image", async () => {
    await expect(
      aiEquipmentRecognition.run(req({ mimeType: "image/jpeg" })),
    ).rejects.toThrow(/imageBase64/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects an oversized image payload via the cheap pre-decode length guard", async () => {
    // GPT-PM's G1 round-1 review caught the original version checking the
    // base64 STRING length rather than the decoded byte count, which the ~4/3
    // encoding overhead could be used to sneak a larger real payload past.
    // Round-2 review then caught the fix for that going too far the other
    // way: checking `bytes.length` only AFTER `Buffer.from` had already
    // allocated and decoded the whole string meant an oversized payload paid
    // the decode cost — unmetered, before quota — before being refused. This
    // length (12,000,004, a multiple of 4, one group past the 12,000,000
    // ceiling for 9,000,000 decoded bytes) is rejected by the cheap
    // string-length guard specifically, never reaching `decodeStrictBase64`
    // at all — see `MAX_IMAGE_BASE64_LENGTH`'s own doc comment. Any encoded
    // length within that ceiling provably decodes to at most `MAX_IMAGE_BYTES`
    // (4 base64 chars per 3 bytes), so the decoded-bytes check right after it
    // in `parseInput` is unreachable given this guard — kept anyway as
    // defense in depth against the two constants ever drifting apart.
    await expect(
      aiEquipmentRecognition.run(
        req({ mimeType: "image/jpeg", imageBase64: "a".repeat(12_000_004) }),
      ),
    ).rejects.toThrow(/imageBase64/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects malformed base64", async () => {
    await expect(
      aiEquipmentRecognition.run(req({ mimeType: "image/jpeg", imageBase64: "not valid base64!!" })),
    ).rejects.toThrow(/base64/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a payload that is not actually an image, regardless of the claimed mimeType", async () => {
    // The exact hole GPT-PM's G1 round-1 review named: base64 for the plain
    // text "hello", labelled image/jpeg, used to sail straight through to the
    // paid model.
    await expect(
      aiEquipmentRecognition.run(req({ mimeType: "image/jpeg", imageBase64: NOT_AN_IMAGE_BASE64 })),
    ).rejects.toThrow(/does not look like/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a mimeType that does not match the image's real file signature", async () => {
    // Real JPEG bytes, claimed as image/png — the mismatch itself is the
    // defect being caught, independent of whether the bytes are a real image
    // of SOME kind.
    await expect(
      aiEquipmentRecognition.run(req({ mimeType: "image/png", imageBase64: JPEG_BASE64 })),
    ).rejects.toThrow(/does not match/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("accepts a real PNG matching its declared mimeType", async () => {
    await aiEquipmentRecognition.run(req({ mimeType: "image/png", imageBase64: PNG_BASE64 }));
    expect(generate).toHaveBeenCalledTimes(1);
  });

  test("returns the model's raw text unchanged — resolution stays client-side", async () => {
    const res = await aiEquipmentRecognition.run(req(VALID));
    expect(res.text).toBe('{"machine": "smith machine", "confidence": 0.8}');
  });

  test("sends the image through to generate()", async () => {
    await aiEquipmentRecognition.run(req(VALID));
    expect(generate.mock.calls[0][0].image).toEqual({
      mimeType: "image/jpeg",
      base64: JPEG_BASE64,
    });
  });

  test("matches the mobile source's generationConfig exactly: JSON mode, temperature 0, thinking disabled", async () => {
    await aiEquipmentRecognition.run(req(VALID));
    const opts = generate.mock.calls[0][0];
    expect(opts.jsonResponse).toBe(true);
    expect(opts.temperature).toBe(0);
    expect(opts.disableThinking).toBe(true);
  });

  test("uses a 20s timeout, matching GeminiVisualEquipmentService's own `timeout` field", async () => {
    await aiEquipmentRecognition.run(req(VALID));
    expect(generate.mock.calls[0][0].timeoutMs).toBe(20_000);
  });

  test("caps the response at 256 tokens", async () => {
    await aiEquipmentRecognition.run(req(VALID));
    expect(generate.mock.calls[0][0].maxOutputTokens).toBe(256);
  });

  test("the prompt tells the model to look at the CENTER of the frame", async () => {
    await aiEquipmentRecognition.run(req(VALID));
    const prompt = generate.mock.calls[0][0].prompt as string;
    expect(prompt).toContain("center");
    expect(prompt).toContain("unknown");
  });

  test("charges the aiEquipmentRecognition quota before calling the model", async () => {
    usage = { aiEquipmentRecognition: QUOTAS.aiEquipmentRecognition };
    await expect(aiEquipmentRecognition.run(req(VALID))).rejects.toThrow(/limit for this action/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("one call short of the ceiling still works and charges one unit", async () => {
    usage = { aiEquipmentRecognition: QUOTAS.aiEquipmentRecognition - 1 };
    await aiEquipmentRecognition.run(req(VALID));
    expect(usage.aiEquipmentRecognition).toBe(QUOTAS.aiEquipmentRecognition);
  });

  test("an anonymous caller is refused before the quota is even checked (G4 Step 2: AI_ALLOW_ANONYMOUS defaults off)", async () => {
    const anon = (data: unknown): any => ({
      data,
      auth: { uid: "anon1", token: { firebase: { sign_in_provider: "anonymous" } } },
    });
    await expect(aiEquipmentRecognition.run(anon(VALID))).rejects.toThrow(/real account/i);
    expect(generate).not.toHaveBeenCalled();
  });
});

/**
 * The same two-directional registry tripwire
 * `gemini_equipment_service_test.dart` already ran client-side, now run
 * against the alias/registry JSON directly, using the same exact + whole-word
 * -longest-match semantics as production `EquipmentAliasIndex.resolve` (see
 * `resolve()` below). NOT pass-1-only: an earlier draft of this comment
 * claimed every `CANONICAL_MACHINES` entry is registered as an exact alias,
 * which GPT-PM's G1 round-1 review disproved directly — "hip abductor
 * machine" is not itself an alias and only resolves via pass 2 against the
 * shorter alias "hip abductor". Keeping that claim here would invite a future
 * maintainer to "simplify" this test back to exact-match-only, silently
 * reintroducing the false-positive this gate already hit once.
 */
describe("CANONICAL_MACHINES vs. the equipment registry", () => {
  const ASSETS_DIR = path.join(__dirname, "..", "..", "..", "mobile", "assets", "data");
  const aliasesJson: Record<string, string[]> = JSON.parse(
    fs.readFileSync(path.join(ASSETS_DIR, "equipment_aliases.json"), "utf8"),
  );
  const equipmentIds: string[] = (
    JSON.parse(fs.readFileSync(path.join(ASSETS_DIR, "equipment.json"), "utf8")) as Array<{ id: string }>
  ).map((e) => e.id);

  /**
   * Exact port of `EquipmentAliasIndex.normalise` (`equipment_alias_index.dart`):
   * lowercase, ё→е, every run of characters outside `[a-zа-я0-9]` collapsed to
   * a single space, then trimmed. GPT-PM's G1 round-1 review of this file
   * caught the first version of this test using a bare `toLowerCase().trim()`
   * instead — close enough that the current ~70-entry English-only list
   * happened not to expose the gap (nothing in it collides only through
   * punctuation folding), but a genuinely different algorithm from the one
   * this test exists to hold production to. A future alias containing an
   * apostrophe, hyphen, or slash (`equipment_aliases.json` already has
   * `"hip abductor / adductor machine"`) could disagree between this
   * simplified version and real production resolution without this test ever
   * noticing — exactly the false confidence the finding named.
   */
  const normalise = (s: string) =>
    s
      .toLowerCase()
      .replace(/ё/g, "е")
      .replace(/[^a-zа-я0-9]+/g, " ")
      .trim();

  const aliasToId = new Map<string, string>();
  for (const [id, aliases] of Object.entries(aliasesJson)) {
    for (const a of aliases) aliasToId.set(normalise(a), id);
  }

  /**
   * Port of `EquipmentAliasIndex.resolve`'s first two passes: (1) the whole
   * text IS an alias; (2) an alias appears in the text as a whole-word
   * phrase, longest alias wins. Needed because a canonical name like "hip
   * abductor machine" is not itself a registered alias but resolves via pass
   * 2 against the shorter alias "hip abductor" — exactly what the real
   * production code does, so the test must too or it reports drift that is
   * not actually there.
   */
  function resolve(freeText: string): string | undefined {
    const text = normalise(freeText);
    const direct = aliasToId.get(text);
    if (direct) return direct;
    let bestId: string | undefined;
    let bestLen = 0;
    const padded = ` ${text} `;
    for (const [alias, id] of aliasToId) {
      if (alias.length <= bestLen) continue;
      if (padded.includes(` ${alias} `)) {
        bestId = id;
        bestLen = alias.length;
      }
    }
    return bestId;
  }

  test("every canonical prompt name resolves in the alias registry", () => {
    const unresolved = CANONICAL_MACHINES.filter((name) => resolve(name) === undefined);
    expect(unresolved).toEqual([]);
  });

  test("every registry machine is reachable through the prompt", () => {
    const reachable = new Set(
      CANONICAL_MACHINES.map((name) => resolve(name)).filter((id): id is string => id !== undefined),
    );
    const unreachable = equipmentIds.filter((id) => !reachable.has(id)).sort();
    expect(unreachable).toEqual([]);
  });
});
