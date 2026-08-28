/**
 * `aiExerciseGeneration` -- G1's fourth callable. This suite protects: the request is validated
 * (equipmentId must resolve to a real machine, languageCode restricted to exactly "ru"/"en"),
 * neither field reaches the prompt as raw untrusted text, the daily quota gates the model call,
 * the exact vision-generation config the mobile source used is preserved, and -- the property
 * unique to this callable -- the embedded EQUIPMENT_NAMES_EN/RU maps and MUSCLE_VOCAB list stay
 * in exact lockstep with the live mobile assets/source they were ported from, rather than
 * silently drifting the way CANONICAL_MACHINES in ai_equipment_recognition.ts already documents
 * as an accepted, unguarded risk.
 */
import * as fs from "fs";
import * as path from "path";

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

import {
  aiExerciseGeneration,
  EQUIPMENT_NAMES_EN,
  EQUIPMENT_NAMES_RU,
  MUSCLE_VOCAB,
} from "../ai_exercise_generation";
import { QUOTAS } from "../abuse_guard";

const req = (data: unknown, uid: string | null = "u1"): any => ({
  data,
  auth: uid ? { uid, token: {} } : undefined,
});

const VALID = { equipmentId: "treadmill", languageCode: "en" };

const GOOD_ANSWER =
  '[{"title": "Incline walk", "steps": ["Set incline", "Walk"], "muscles": ["quads"], ' +
  '"primaryMuscles": ["quads"], "difficulty": "beginner", "durationMinutes": 8}]';

beforeEach(() => {
  jest.clearAllMocks();
  usage = {};
  generate.mockResolvedValue(GOOD_ANSWER);
});

describe("aiExerciseGeneration", () => {
  test("requires sign-in", async () => {
    await expect(aiExerciseGeneration.run(req(VALID, null))).rejects.toThrow(/Sign in/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a missing languageCode", async () => {
    await expect(
      aiExerciseGeneration.run(req({ equipmentId: "treadmill" })),
    ).rejects.toThrow(/languageCode/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects a languageCode outside the ru/en allowlist", async () => {
    await expect(
      aiExerciseGeneration.run(req({ equipmentId: "treadmill", languageCode: "fr" })),
    ).rejects.toThrow(/languageCode/);
    expect(generate).not.toHaveBeenCalled();
  });

  test.each(["constructor", "toString", "__proto__", "hasOwnProperty", "valueOf"])(
    "rejects the JS-prototype-chain languageCode %j",
    async (languageCode) => {
      await expect(
        aiExerciseGeneration.run(req({ equipmentId: "treadmill", languageCode })),
      ).rejects.toThrow(/languageCode/);
      expect(generate).not.toHaveBeenCalled();
    },
  );

  test("checks languageCode before doing any equipmentId lookup", async () => {
    // An invalid languageCode paired with an equally invalid equipmentId must report the
    // language error first -- matching aiMachineDescription's own established ordering
    // discipline (cheap checks before lookups).
    await expect(
      aiExerciseGeneration.run(req({ equipmentId: "not_a_real_machine", languageCode: "fr" })),
    ).rejects.toThrow(/languageCode/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects an equipmentId that is not a string", async () => {
    await expect(
      aiExerciseGeneration.run(req({ equipmentId: 123, languageCode: "en" })),
    ).rejects.toThrow(/equipmentId/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("rejects an unrecognised equipmentId", async () => {
    await expect(
      aiExerciseGeneration.run(req({ equipmentId: "not_a_real_machine", languageCode: "en" })),
    ).rejects.toThrow(/not a recognised machine/);
    expect(generate).not.toHaveBeenCalled();
  });

  test.each(["constructor", "toString", "__proto__", "hasOwnProperty", "valueOf", "size", "get"])(
    "rejects the JS-prototype/Map-member equipmentId %j rather than resolving it to a real member",
    async (equipmentId) => {
      // EQUIPMENT_NAMES_EN/RU are real Maps, not object literals, so Map.get() on these values
      // returns undefined rather than resolving to a prototype/own member -- this is the
      // regression test proving that property, mirroring the languageCode prototype test above
      // but for the lookup this callable adds that the other three don't have.
      await expect(
        aiExerciseGeneration.run(req({ equipmentId, languageCode: "en" })),
      ).rejects.toThrow(/not a recognised machine/);
      expect(generate).not.toHaveBeenCalled();
    },
  );

  test("the prompt carries the resolved English name, not the raw equipmentId", async () => {
    await aiExerciseGeneration.run(req({ equipmentId: "treadmill", languageCode: "en" }));
    const prompt = generate.mock.calls[0][0].prompt as string;
    expect(prompt).toContain("Treadmill");
    expect(prompt).not.toContain('"treadmill"');
  });

  test("the prompt carries the resolved Russian name for languageCode ru", async () => {
    await aiExerciseGeneration.run(req({ equipmentId: "treadmill", languageCode: "ru" }));
    const prompt = generate.mock.calls[0][0].prompt as string;
    expect(prompt).toContain("Беговая дорожка");
    expect(prompt).toContain("in Russian");
  });

  test("returns the model's raw text unchanged -- parsing stays client-side", async () => {
    const res = await aiExerciseGeneration.run(req(VALID));
    expect(res.text).toBe(GOOD_ANSWER);
  });

  test("matches the mobile source's generationConfig exactly: JSON mode, temperature 0.4, thinking disabled", async () => {
    await aiExerciseGeneration.run(req(VALID));
    const opts = generate.mock.calls[0][0];
    expect(opts.jsonResponse).toBe(true);
    expect(opts.temperature).toBe(0.4);
    expect(opts.disableThinking).toBe(true);
  });

  test("uses a 25s model-call timeout, matching the mobile client's existing network budget", async () => {
    await aiExerciseGeneration.run(req(VALID));
    expect(generate.mock.calls[0][0].timeoutMs).toBe(25_000);
  });

  test("caps the response at 1024 tokens", async () => {
    await aiExerciseGeneration.run(req(VALID));
    expect(generate.mock.calls[0][0].maxOutputTokens).toBe(1024);
  });

  test("the prompt embeds the full muscle vocabulary", async () => {
    await aiExerciseGeneration.run(req(VALID));
    const prompt = generate.mock.calls[0][0].prompt as string;
    for (const m of MUSCLE_VOCAB) {
      expect(prompt).toContain(m);
    }
  });

  test("charges the aiExerciseGeneration quota before calling the model", async () => {
    usage = { aiExerciseGeneration: QUOTAS.aiExerciseGeneration };
    await expect(aiExerciseGeneration.run(req(VALID))).rejects.toThrow(/limit for this action/);
    expect(generate).not.toHaveBeenCalled();
  });

  test("one call short of the ceiling still works and charges one unit", async () => {
    usage = { aiExerciseGeneration: QUOTAS.aiExerciseGeneration - 1 };
    await aiExerciseGeneration.run(req(VALID));
    expect(usage.aiExerciseGeneration).toBe(QUOTAS.aiExerciseGeneration);
  });

  test("an anonymous caller is refused before the quota is even checked (G4 Step 2: AI_ALLOW_ANONYMOUS defaults off)", async () => {
    const anon = (data: unknown): any => ({
      data,
      auth: { uid: "anon1", token: { firebase: { sign_in_provider: "anonymous" } } },
    });
    await expect(aiExerciseGeneration.run(anon(VALID))).rejects.toThrow(/real account/i);
    expect(generate).not.toHaveBeenCalled();
  });
});

describe("EQUIPMENT_NAMES_EN/RU parity with the live mobile assets", () => {
  const mobileDataDir = path.resolve(__dirname, "..", "..", "..", "mobile", "assets", "data");

  test("EQUIPMENT_NAMES_EN matches equipment.json exactly (size and every id->name pair)", () => {
    const raw = JSON.parse(fs.readFileSync(path.join(mobileDataDir, "equipment.json"), "utf8"));
    expect(Array.isArray(raw)).toBe(true);
    expect(EQUIPMENT_NAMES_EN.size).toBe(raw.length);
    for (const entry of raw) {
      expect(EQUIPMENT_NAMES_EN.get(entry.id)).toBe(entry.name);
    }
  });

  test("EQUIPMENT_NAMES_RU matches equipment.ru.json exactly (size and every id->name pair)", () => {
    const raw = JSON.parse(
      fs.readFileSync(path.join(mobileDataDir, "equipment.ru.json"), "utf8"),
    ) as Record<string, { name: string }>;
    const ids = Object.keys(raw);
    expect(EQUIPMENT_NAMES_RU.size).toBe(ids.length);
    for (const id of ids) {
      expect(EQUIPMENT_NAMES_RU.get(id)).toBe(raw[id].name);
    }
  });

  test("EN and RU maps share the exact same id set as each other", () => {
    const enIds = new Set(EQUIPMENT_NAMES_EN.keys());
    const ruIds = new Set(EQUIPMENT_NAMES_RU.keys());
    expect(enIds.size).toBe(ruIds.size);
    for (const id of enIds) {
      expect(ruIds.has(id)).toBe(true);
    }
  });
});

describe("MUSCLE_VOCAB parity with the real Dart source", () => {
  test("MUSCLE_VOCAB matches AiExerciseGenerator.kMuscleVocab in ai_exercise_generator.dart exactly", () => {
    const dartPath = path.resolve(
      __dirname, "..", "..", "..", "mobile", "lib", "features", "ai_coach",
      "ai_exercise_generator.dart",
    );
    const source = fs.readFileSync(dartPath, "utf8");
    const matches = source.match(/kMuscleVocab\s*=\s*\[([\s\S]*?)\];/g);
    expect(matches).not.toBeNull();
    // Fail loudly rather than silently comparing against the wrong declaration if the source
    // ever gains a second occurrence of this exact pattern (e.g. a second file importing and
    // re-declaring it) -- per GPT-PM's own review note on this test's design.
    expect(matches!.length).toBe(1);
    const body = matches![0].match(/\[([\s\S]*?)\]/)![1];
    const dartVocab = body
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
      .map((s) => s.replace(/^'|'$/g, ""));
    expect(dartVocab).toEqual(MUSCLE_VOCAB);
  });
});
