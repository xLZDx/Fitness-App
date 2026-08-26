/**
 * G1 — the one place server code is allowed to talk to Gemini.
 *
 * WHY THIS EXISTS
 *
 * Before this, four mobile call sites (`GeminiVisualEquipmentService`,
 * `GeminiMachineDescriber`, `AiCoachService`, `AiExerciseGenerator`) built
 * their own prompts on the phone and called `FirebaseAI.googleAI()` directly.
 * `abuse_guard.ts`'s quota system — the only per-user ceiling in this
 * codebase — had zero references from any of them: nothing metered these
 * calls, and nothing stopped a client from sending an arbitrary prompt to a
 * paid model, because the client chose the prompt.
 *
 * This module is the shared executor underneath four narrow, server-owned
 * callables (`ai_coach_advice.ts` and its siblings). It deliberately does
 * NOT expose a generic `askGemini(prompt)` — that would just move the same
 * arbitrary-prompt proxy server-side and still let a caller spend money on
 * anything they liked. Every caller of this module passes a fully-built
 * `GenerateContentRequest` that IT constructed from a fixed template plus
 * validated, structured input; no CALLER of this module — none of the four
 * `ai_*.ts` callables — accepts an entire model prompt from
 * `CallableRequest.data` and forwards it here unmodified. That is a real
 * boundary and the whole point of this module existing.
 *
 * It is a narrower claim than "no caller-controlled text ever reaches the
 * model", though, and worth being precise about: a validated FIELD inside
 * the structured input — `ai_coach_advice.ts`'s `subjectName`, for one — can
 * still be interpolated into a fixed template, which is a real, acknowledged
 * prompt-injection surface even though the caller never controls the
 * template itself. See `ai_coach_advice.ts`'s `FORBIDDEN_SUBJECT_NAME_CHARS`
 * for the current defense-in-depth on that specific field and its honestly
 * stated limits.
 *
 * WHY VERTEX AI VIA ADC, NOT AN API KEY
 *
 * The mobile app used the Gemini Developer API backend (`FirebaseAI.googleAI()`,
 * key held by the Firebase AI Logic SDK, never on the phone). Server-side,
 * there is no equivalent reason to hold a key at all: Cloud Functions already
 * runs as a service account, and `@google/genai`'s Vertex AI mode
 * authenticates through Application Default Credentials — the same
 * credential-free pattern `video_urls.ts` already uses for `getSignedUrl`
 * (see that file's header for why a key file is the thing to avoid). No
 * Gemini API key exists anywhere in this repo or in the mobile app after G1.
 */
import { GoogleGenAI, HarmCategory, HarmBlockThreshold } from "@google/genai";
import * as logger from "firebase-functions/logger";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * `gemini-2.5-flash` 404s for this project; `gemini-3-flash-preview` answers
 * — verified live 2026-07-30, but against the Gemini Developer API backend
 * (`GEMINI_VISION_MODEL_NOTE` in the mobile source, i.e. the OLD direct
 * `FirebaseAI.googleAI()` path), not against Vertex AI. That distinction
 * matters and was wrongly elided in this comment until GPT-PM's G1 round-1
 * review caught it: `gemini-3-flash-preview` is a DEPRECATED model on Vertex
 * AI (Google's own docs point migrators at `gemini-3.5-flash`), independently
 * confirmed 2026-08-26 via Google Cloud's own model and release-notes pages.
 *
 * The model id is kept as-is here anyway, deliberately, rather than silently
 * swapped to `gemini-3.5-flash`: a model swap is a real behavior/cost/latency
 * change to what was manually verified, not a transport-only migration, and
 * making that call without operator sign-off would be scope creep hiding
 * inside what this gate calls a pure client→server transport move. This is
 * the SAME reason the four ai_*.ts callables port each mobile prompt
 * unchanged rather than "improving" it in passing.
 *
 * Left as an explicit, loud TODO rather than resolved silently: migrate off
 * this deprecated model, in its own reviewed change, before relying on this
 * gateway in production long-term. Track this alongside the location fix
 * below — both are pre-deployment gaps this sandboxed session cannot close
 * on its own (no live GCP credentials to smoke-test against).
 */
export const AI_MODEL = "gemini-3-flash-preview";

/**
 * Same provider-moderation policy the mobile clients set directly, ported
 * unchanged. See `mobile/lib/features/ai_coach/provider_safety_settings.dart`
 * for the full reasoning this is a copy of — provider moderation only, not
 * this product's own injury/eligibility safety layer, which lives entirely in
 * `features/safety/` on the client and is never touched by this module.
 */
const SAFETY_SETTINGS = [
  HarmCategory.HARM_CATEGORY_HARASSMENT,
  HarmCategory.HARM_CATEGORY_HATE_SPEECH,
  HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
  HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
].map((category) => ({ category, threshold: HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE }));

/**
 * Vertex AI location. Read once, at module load — like `scaling.ts`'s
 * `APP_CHECK_ENFORCED*` flags, not like `abuse_guard.ts`'s `db()` getter:
 * `process.env` needs no live Firebase app, so there is no import-time cost
 * to defer here, unlike `admin.firestore()`. What IS deferred to first call
 * is the SDK CLIENT construction (`ai()` below) — that one really would fail
 * at import time without credentials, same reasoning as `db()`. Tested the
 * same way `scaling.test.ts` tests its own module-load-time flags:
 * `jest.isolateModules` plus a fresh `require`, not a live env mutation after
 * import — see `ai_gateway.test.ts`.
 *
 * `"global"`, NOT `europe-west1`. The first draft of this file defaulted to
 * `europe-west1` reasoning that compute and the model call should share a
 * region with `scaling.ts`'s Cloud Functions region — plausible, and wrong:
 * `gemini-3-flash-preview` (see `AI_MODEL` above) is documented as a
 * global-endpoint model on Vertex AI, independently confirmed 2026-08-26
 * against Google Cloud's own model documentation after GPT-PM's G1 round-1
 * review flagged the mismatch as a BLOCKER. A region-scoped location for a
 * global-only model is exactly the kind of failure that is invisible to
 * every test in this file's own suite (`ai_gateway.test.ts` mocks the SDK
 * client) and only surfaces as a live provider/location error — which this
 * sandboxed session has no live GCP credentials to actually trigger and
 * catch, so this remains a real, NOT YET independently smoke-tested,
 * pre-deployment verification gap. Still overridable via env var: Vertex
 * model/location support is a live GCP fact that can shift, and a wrong
 * default should be a one-line env fix, not a code change under pressure —
 * same posture as the `APP_CHECK_ENFORCED*` flags in `scaling.ts`.
 */
const LOCATION = process.env.VERTEX_AI_LOCATION ?? "global";

let client: GoogleGenAI | undefined;

function ai(): GoogleGenAI {
  client ??= new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT ?? "fitness-app-korostelev",
    location: LOCATION,
  });
  return client;
}

/** Test seam: the module-scope client would otherwise leak a real SDK instance between cases. */
export function __resetAiClient(): void {
  client = undefined;
}

/**
 * One inline image part, already resized. Callers resize before calling —
 * this module does not touch bytes, matching the four mobile services, all of
 * which resized client-side before the network call (`resizeForCloud`,
 * shared by the classifier and the machine describer). The upload-size
 * saving that resize bought is not undone by moving the model call
 * server-side; the client still sends a small JPEG, not a raw camera still.
 */
export interface InlineImage {
  mimeType: string;
  base64: string;
}

/**
 * What a caller may ask for. Every field here maps directly onto the model
 * call — nothing else reaches it.
 *
 * `temperature` and `disableThinking` are both optional and both omitted by
 * default, on purpose: `AiCoachService._askCloud` (the mobile source this
 * gateway replaces for coach advice) built its `GenerativeModel` with no
 * `GenerationConfig` at all — no temperature override, no
 * `thinkingConfig`, no JSON mode. That is a real, deliberate difference from
 * the other three mobile call sites (`GeminiVisualEquipmentService`,
 * `GeminiMachineDescriber`, `AiExerciseGenerator`), which all set
 * `temperature: 0`/`0.4` and `thinkingConfig: ThinkingConfig(thinkingBudget: 0)`
 * explicitly — NOT a uniform policy across every mobile caller. Porting a
 * forced `thinkingBudget: 0` onto coach advice would silently change its
 * latency and answer variance from what shipped. Each `ai_*.ts` callable
 * passes exactly what its own mobile source passed, no more.
 */
export interface GenerateOptions {
  /** The fully-built prompt text. Built by the CALLER (one of the four
   * `ai_*.ts` files below), from a fixed template plus validated structured
   * input — never copied from `request.data` verbatim. */
  prompt: string;
  /** Present only for the two vision surfaces (recognition, description). */
  image?: InlineImage;
  /** `application/json` for the three surfaces whose caller parses JSON;
   * omitted for coach advice, which returns prose. */
  jsonResponse?: boolean;
  /** 0 for the three deterministic/structured surfaces; 0.4 for the exercise
   * generator; omitted (model default) for coach advice — see the interface
   * doc above. */
  temperature?: number;
  /** True for the three surfaces whose mobile source disabled thinking for
   * latency (2-5s vs 25-31s, verified live 2026-07-30); omitted for coach
   * advice, which never set this. */
  disableThinking?: boolean;
  timeoutMs: number;
  /**
   * Hard cap on response tokens. Required, not optional — GPT-PM's G1
   * round-2 review named the gap this closes: the subject-name
   * prompt-injection defense in `ai_coach_advice.ts` (see
   * `FORBIDDEN_SUBJECT_NAME_CHARS`) explicitly does not claim to stop every
   * imperative-looking label, only the ones using a quote or control
   * character. A natural-language "under 180 words" instruction inside the
   * prompt is not an enforceable ceiling — a model that is talked into
   * ignoring it can still generate an arbitrarily long, arbitrarily billed
   * response. `maxOutputTokens` is a real one, enforced by the provider
   * itself rather than requested of it, so it is required at the call site
   * rather than left as another optional a caller could forget. Each
   * `ai_*.ts` callable sets its own value against its own expected response
   * shape — see `ai_coach_advice.ts` for the ~180-word case.
   */
  maxOutputTokens: number;
}

/**
 * Runs one Gemini call and returns its text, or throws `HttpsError`.
 *
 * Deliberately the only export that touches the model. A caller cannot reach
 * the underlying SDK client, the safety settings, or the model id — those are
 * this module's to own, matching every mobile prompt-builder's own
 * `@visibleForTesting` split: the prompt text is testable without a network
 * call, and the network call itself has exactly one implementation.
 */
export async function generate(opts: GenerateOptions): Promise<string> {
  const parts: Array<{ text: string } | { inlineData: { mimeType: string; data: string } }> = [
    { text: opts.prompt },
  ];
  if (opts.image) {
    parts.unshift({
      inlineData: { mimeType: opts.image.mimeType, data: opts.image.base64 },
    });
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
  try {
    const result = await ai().models.generateContent({
      model: AI_MODEL,
      contents: [{ role: "user", parts }],
      config: {
        safetySettings: SAFETY_SETTINGS,
        maxOutputTokens: opts.maxOutputTokens,
        ...(opts.temperature !== undefined ? { temperature: opts.temperature } : {}),
        ...(opts.disableThinking ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
        ...(opts.jsonResponse ? { responseMimeType: "application/json" } : {}),
        // AbortSignal on the request itself, not a bare setTimeout race: a
        // fire-and-forget timer that outlives the request would leak the
        // outbound call (and its billed tokens) even after this function has
        // already thrown to its caller. Lives under `config` per the SDK's
        // own `GenerateContentConfig` shape, not top-level on the parameters
        // object — confirmed against `node_modules/@google/genai/dist/genai.d.ts`,
        // not assumed from the API's general convention.
        abortSignal: controller.signal,
      },
    });
    const text = result.text;
    if (!text || !text.trim()) {
      throw new HttpsError("internal", "The AI assistant returned no answer.");
    }
    return text;
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    if (controller.signal.aborted) {
      logger.warn("ai_gateway: call timed out", { timeoutMs: opts.timeoutMs });
      throw new HttpsError("deadline-exceeded", "The AI assistant took too long to answer.");
    }
    logger.error("ai_gateway: generate failed", { error: String(e) });
    throw new HttpsError("internal", "Could not reach the AI assistant.");
  } finally {
    clearTimeout(timer);
  }
}
