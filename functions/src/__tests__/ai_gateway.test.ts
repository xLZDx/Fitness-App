/**
 * The one place server code is allowed to talk to Gemini.
 *
 * Written after GPT-PM's G1 round-1 review flagged that no test in
 * `ai_coach_advice.test.ts` (which mocks this whole module) could ever catch
 * a wrong model id, a wrong Vertex location, missing safety settings, or a
 * misplaced `abortSignal` — exactly the class of bug that BLOCKER turned out
 * to be (`europe-west1` is not a supported Vertex location for the model this
 * gateway calls). This suite pins what actually reaches the SDK client.
 *
 * It cannot prove Vertex AI accepts the model/location/config combination —
 * that needs a real network call against live GCP credentials, which this
 * suite does not have. What it can and does prove is that the values this
 * module SENDS are the ones this module INTENDS to send.
 */
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

const generateContent = jest.fn();
const GoogleGenAI = jest.fn().mockImplementation((config: unknown) => ({
  __config: config,
  models: { generateContent },
}));

jest.mock("@google/genai", () => {
  const actual = jest.requireActual("@google/genai");
  return { ...actual, GoogleGenAI };
});

import { generate, AI_MODEL, __resetAiClient } from "../ai_gateway";

const OK_RESPONSE = { text: "some advice" };

/** Every field `generate` requires, so each test only has to override what
 * it is actually asserting on. `maxOutputTokens: 999` is an arbitrary but
 * fixed sentinel — the dedicated `maxOutputTokens` tests below pin the field
 * itself; every other test just needs a valid, present value. */
const BASE = { prompt: "hi", timeoutMs: 1000, maxOutputTokens: 999 } as const;

beforeEach(() => {
  jest.clearAllMocks();
  __resetAiClient();
  delete process.env.VERTEX_AI_LOCATION;
  delete process.env.GCLOUD_PROJECT;
  generateContent.mockResolvedValue(OK_RESPONSE);
});

describe("client construction", () => {
  test("uses Vertex AI mode via ADC, never an API key", async () => {
    await generate(BASE);
    expect(GoogleGenAI).toHaveBeenCalledWith(
      expect.objectContaining({ vertexai: true }),
    );
    const config = GoogleGenAI.mock.calls[0][0];
    expect(config).not.toHaveProperty("apiKey");
  });

  test("defaults to the global location, not a region", async () => {
    // The BLOCKER this suite exists to prevent a recurrence of:
    // gemini-3-flash-preview is a global-endpoint-only model on Vertex AI, and
    // the first draft of this file defaulted to `europe-west1` instead.
    await generate(BASE);
    expect(GoogleGenAI).toHaveBeenCalledWith(
      expect.objectContaining({ location: "global" }),
    );
  });

  test("VERTEX_AI_LOCATION overrides the default without a code change", async () => {
    // LOCATION is read once at module load (like scaling.ts's own
    // APP_CHECK_ENFORCED* flags), so the override has to be in the
    // environment BEFORE the module is required, not set on an
    // already-imported module — same pattern scaling.test.ts's `withEnv`
    // helper uses for its own module-load-time flags.
    const saved = process.env.VERTEX_AI_LOCATION;
    process.env.VERTEX_AI_LOCATION = "us-central1";
    let freshGenerate!: typeof generate;
    jest.isolateModules(() => {
      freshGenerate = require("../ai_gateway").generate;
    });
    process.env.VERTEX_AI_LOCATION = saved;

    await freshGenerate(BASE);
    expect(GoogleGenAI).toHaveBeenCalledWith(
      expect.objectContaining({ location: "us-central1" }),
    );
  });

  test("the client is built once and reused across calls", async () => {
    await generate({ ...BASE, prompt: "one" });
    await generate({ ...BASE, prompt: "two" });
    expect(GoogleGenAI).toHaveBeenCalledTimes(1);
    expect(generateContent).toHaveBeenCalledTimes(2);
  });
});

describe("the request sent to the model", () => {
  test("uses AI_MODEL, not a hardcoded literal elsewhere", async () => {
    await generate(BASE);
    expect(generateContent.mock.calls[0][0].model).toBe(AI_MODEL);
  });

  test("always sends the four safety categories at the medium threshold", async () => {
    await generate(BASE);
    const settings = generateContent.mock.calls[0][0].config.safetySettings;
    expect(settings).toHaveLength(4);
    for (const s of settings) expect(s.threshold).toBe("BLOCK_MEDIUM_AND_ABOVE");
  });

  test("the prompt text is the sole content part when no image is given", async () => {
    await generate({ ...BASE, prompt: "hello coach" });
    const contents = generateContent.mock.calls[0][0].contents;
    expect(contents).toEqual([{ role: "user", parts: [{ text: "hello coach" }] }]);
  });

  test("an image is prepended before the text part", async () => {
    await generate({
      ...BASE,
      prompt: "what is this",
      image: { mimeType: "image/jpeg", base64: "AAAA" },
    });
    const parts = generateContent.mock.calls[0][0].contents[0].parts;
    expect(parts[0]).toEqual({
      inlineData: { mimeType: "image/jpeg", data: "AAAA" },
    });
    expect(parts[1]).toEqual({ text: "what is this" });
  });

  test("temperature is omitted, not sent as undefined, unless the caller sets it", async () => {
    await generate(BASE);
    expect(generateContent.mock.calls[0][0].config).not.toHaveProperty("temperature");

    await generate({ ...BASE, temperature: 0 });
    expect(generateContent.mock.calls[1][0].config.temperature).toBe(0);
  });

  test("thinkingConfig is only sent when disableThinking is true", async () => {
    await generate(BASE);
    expect(generateContent.mock.calls[0][0].config).not.toHaveProperty("thinkingConfig");

    await generate({ ...BASE, disableThinking: true });
    expect(generateContent.mock.calls[1][0].config.thinkingConfig).toEqual({
      thinkingBudget: 0,
    });
  });

  test("responseMimeType is only sent when jsonResponse is true", async () => {
    await generate(BASE);
    expect(generateContent.mock.calls[0][0].config).not.toHaveProperty("responseMimeType");

    await generate({ ...BASE, jsonResponse: true });
    expect(generateContent.mock.calls[1][0].config.responseMimeType).toBe(
      "application/json",
    );
  });

  test("maxOutputTokens is always sent — it is a required field, not an opt-in", async () => {
    // GPT-PM's G1 round-2 review: a natural-language "keep it short"
    // instruction inside a prompt is not an enforceable cost ceiling, and the
    // subject-name injection defense in ai_coach_advice.ts explicitly does
    // not claim to stop every imperative-looking label. Making this field
    // required in GenerateOptions (see that interface's doc comment) means a
    // caller cannot forget it; this test is the mirror check that the value
    // actually reaches the provider call, not just the type signature.
    await generate({ ...BASE, maxOutputTokens: 512 });
    expect(generateContent.mock.calls[0][0].config.maxOutputTokens).toBe(512);
  });

  test("an abortSignal lives under config, matching the SDK's GenerateContentConfig shape", async () => {
    await generate(BASE);
    const call = generateContent.mock.calls[0][0];
    expect(call.config.abortSignal).toBeInstanceOf(AbortSignal);
    expect(call).not.toHaveProperty("abortSignal");
  });
});

describe("failure mapping", () => {
  test("an empty answer is an internal error, not a silent success", async () => {
    generateContent.mockResolvedValue({ text: "   " });
    await expect(generate(BASE)).rejects.toMatchObject({ code: "internal" });
  });

  test("a missing text field is an internal error", async () => {
    generateContent.mockResolvedValue({ text: undefined });
    await expect(generate(BASE)).rejects.toMatchObject({ code: "internal" });
  });

  test("an SDK failure becomes an internal error, not a leaked raw exception", async () => {
    generateContent.mockRejectedValue(new Error("permission denied"));
    await expect(generate(BASE)).rejects.toMatchObject({ code: "internal" });
  });

  test("a call that outlives its timeout is a deadline-exceeded error", async () => {
    // A real fetch-based transport rejects once its AbortSignal fires; this
    // mock has to simulate that explicitly, or the awaited promise would
    // simply hang forever regardless of whether the signal ever aborts.
    generateContent.mockImplementation(
      ({ config }: { config: { abortSignal: AbortSignal } }) =>
        new Promise((_resolve, reject) => {
          config.abortSignal.addEventListener("abort", () =>
            reject(new Error("aborted")),
          );
        }),
    );
    await expect(
      generate({ ...BASE, timeoutMs: 10 }),
    ).rejects.toMatchObject({ code: "deadline-exceeded" });
  });

  test("a successful call clears its timeout and does not fire late", async () => {
    jest.useFakeTimers();
    const p = generate({ ...BASE, timeoutMs: 50_000 });
    await Promise.resolve(); // let the microtask queue settle the mocked resolve
    jest.runAllTimers();
    await expect(p).resolves.toBe("some advice");
    jest.useRealTimers();
  });
});
