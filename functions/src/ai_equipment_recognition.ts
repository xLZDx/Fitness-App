/**
 * `aiEquipmentRecognition` — G1's second callable, replicating `ai_coach_advice.ts`'s
 * pattern for the camera-based equipment classifier.
 *
 * Ports `GeminiVisualEquipmentService.buildPrompt`/`kCanonicalMachines`
 * (`mobile/lib/features/visual_equipment/data/gemini_equipment_service.dart`)
 * server-side unchanged. Unlike coach advice, this prompt has NO caller-controlled
 * TEXT field at all — the machine list is a fixed constant and the only per-call
 * input is the photo itself — so there is no prompt-injection surface of the
 * `subjectName` kind (`ai_coach_advice.ts`'s quoted-label attack) to defend here.
 * That is narrower than "no prompt-injection surface at all", and GPT-PM's G1
 * round-1 review of this file correctly named the gap in the original wording:
 * text rendered INSIDE the photo (a sign, a sticker, a phone held up to the
 * camera) reaches the model exactly like any other multimodal input, and a
 * syntactically valid JSON answer would still pass this file's own output
 * shape check even if the model was talked into it by something visible in the
 * frame rather than by genuine visual evidence. Not solved here — the risk
 * already existed on the old direct-client-to-Gemini path and the output has
 * limited agency (a machine name from a fixed list, resolved against the
 * catalog client-side, never free text) — but recorded honestly rather than
 * claimed away.
 *
 * Deliberately narrow scope, matching `ai_coach_advice.ts`'s own precedent: this
 * callable does the model call and returns the model's raw JSON text unchanged.
 * `parseResponse`/`EquipmentAliasIndex` resolution — turning a model-named machine
 * into a catalog id — stays entirely client-side, exactly as before. That logic
 * never touches the network or the model; moving it server-side would need the
 * ~1,887-row equipment registry to exist in Functions, which it does not today, and
 * doing so is a real, separate change out of scope for a transport-only migration.
 */
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { AI_METERED } from "./scaling";
import {
  QUOTAS,
  enforceAiGatewayEnabled,
  enforceDailyQuota,
  enforceNonAnonymousForAi,
  noteAppCheck,
  quotaFor,
} from "./abuse_guard";
import { generate, InlineImage } from "./ai_gateway";
import { validateImageInput } from "./image_validation";

/** Matches every other callable's `signInProvider` extraction. */
function signInProvider(request: CallableRequest): string | undefined {
  return request.auth?.token?.firebase?.sign_in_provider;
}

interface EquipmentRecognitionInput {
  image: InlineImage;
}

/** Image validation itself -- type checks, base64 strict-decode, size caps, file-signature sniff
 * -- lives entirely in `image_validation.ts`, shared with `aiMachineDescription`. See that
 * module's own header for why `validateImageInput` owns the raw type checks too, not just the
 * byte-level validation. */
function parseInput(data: unknown): EquipmentRecognitionInput {
  const d = (data ?? {}) as Record<string, unknown>;
  return { image: validateImageInput(d.mimeType, d.imageBase64) };
}

/**
 * Canonical EN machine names the prompt offers. Exact copy of
 * `GeminiVisualEquipmentService.kCanonicalMachines` — see that file's own doc
 * comment for the drift history (4 machines were missing for a while before
 * being added back 2026-08-03). Duplicated here rather than shared because
 * Functions and the Flutter app are separate build targets with no shared
 * source tree; this is the SAME tradeoff `ai_coach_advice.ts`'s prompt port
 * already accepted, and carries the same risk: a future registry addition to
 * `equipment.json` must be added to BOTH lists by hand, or the camera silently
 * cannot recognise the new item even though its catalog page exists. Not
 * solved in this transport-only gate; tracked as a known residual risk.
 */
export const CANONICAL_MACHINES: readonly string[] = [
  "treadmill", "rowing machine", "squat rack", "bench press station",
  "cable machine", "leg press", "lat pulldown", "barbell", "dumbbells",
  "kettlebell", "elliptical trainer", "exercise bike", "recumbent bike",
  "stair climber", "air bike", "ski erg", "smith machine",
  "hack squat machine", "leg extension machine", "leg curl machine",
  "hip abductor machine", "glute kickback machine", "calf raise machine",
  "chest press machine", "pec deck", "shoulder press machine",
  "seated row machine", "t-bar row", "assisted pull-up machine",
  "pull-up bar", "dip station", "preacher curl bench",
  "biceps curl machine", "triceps extension machine", "ab crunch machine",
  "rotary torso machine", "back extension bench", "captain's chair",
  "flat bench", "ez curl bar", "weight plates", "resistance bands",
  "suspension trainer", "medicine ball", "battle ropes", "plyo box",
  "punching bag", "foam roller",
  "stability ball", "skipping rope", "ab wheel", "parallettes",
  "seated dip machine", "multi hip machine", "lateral raise machine",
  "sissy squat machine", "agility ladder", "mini trampoline",
  "balance board", "yoga blocks", "weighted sled", "ab mat", "bosu ball",
  "sliding discs", "sandbag", "gymnastic rings", "tyre",
  "vertical pole", "outdoor air walker",
  "push-up blocks", "aerobic step",
] as const;

/** Exact copy of `GeminiVisualEquipmentService.buildPrompt()`. No input is
 * interpolated — the whole string is a fixed constant plus the machine list
 * above, both server-owned. */
function buildPrompt(): string {
  return `You identify gym equipment. Look ONLY at the machine closest to the center of
the photo; ignore machines at the edges — gyms are crowded and the user aimed
the center of the frame at the one they mean.

Answer with JSON only:
{"machine": "<name from the list below, or unknown>", "confidence": <0.0-1.0>,
 "alternatives": [{"machine": "<name>", "confidence": <0.0-1.0>}]}

"confidence" is YOUR honest certainty; use low values when unsure. Give up to
2 alternatives only when they are genuinely plausible. Machine list:
${CANONICAL_MACHINES.join(", ")}`;
}

export const aiEquipmentRecognition = onCall(AI_METERED, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to identify equipment.");
  }
  noteAppCheck(request, "aiEquipmentRecognition");
  enforceNonAnonymousForAi(signInProvider(request));
  await enforceAiGatewayEnabled("aiEquipmentRecognition");
  const input = parseInput(request.data);

  await enforceDailyQuota(
    request.auth.uid,
    "aiEquipmentRecognition",
    quotaFor(QUOTAS.aiEquipmentRecognition, signInProvider(request)),
  );

  // Matches `GeminiVisualEquipmentService`'s own generationConfig exactly:
  // JSON mode, temperature 0, thinking disabled — verified live 2026-07-30 in
  // the mobile source as the difference between a 2-5s and a 25-31s answer.
  //
  // `timeoutMs: 20_000` bounds only THIS call (the model itself); it is
  // deliberately NOT the same number as the client's end-to-end budget.
  // GPT-PM's G1 round-1 review caught the original version giving both layers
  // an equal 20s, which is a race: auth, `parseInput`, and the quota
  // transaction above all run BEFORE this call starts, so the client's clock
  // (which starts at the callable invocation, before any of that) could
  // strike zero and fall back to the weak on-device recognizer while this
  // call is still legitimately in flight and about to succeed — discarding a
  // paid answer the caller already has quota charged for. Fixed on the client
  // side instead of shortening this budget: `GeminiVisualEquipmentService.timeout`
  // (`gemini_equipment_service.dart`) now gives real margin over this number
  // rather than matching it exactly. See that file's own comment for the
  // reasoning against the alternative (shrinking THIS timeout would cut into
  // the occasional legitimate 15-18s preview-model queueing this value was
  // already tuned against).
  const text = await generate({
    operation: "aiEquipmentRecognition",
    prompt: buildPrompt(),
    image: input.image,
    jsonResponse: true,
    temperature: 0,
    disableThinking: true,
    timeoutMs: 20_000,
    // The JSON reply is at most one machine name, a confidence float, and up
    // to 2 alternatives — a few short fields. 256 tokens is generous headroom
    // over any real reply while still being a real ceiling, matching
    // `ai_coach_advice.ts`'s reasoning for why `maxOutputTokens` is required
    // rather than left to the "answer with JSON only" instruction alone.
    maxOutputTokens: 256,
  });

  return { text };
});
