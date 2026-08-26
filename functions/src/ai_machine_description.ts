/**
 * `aiMachineDescription` -- G1's third callable, replicating `ai_equipment_recognition.ts`'s
 * pattern for the "what is this and what is it for" fallback shown when a photo does not match
 * anything in the catalog.
 *
 * Ports `GeminiMachineDescriber.buildPrompt`
 * (`mobile/lib/features/visual_equipment/data/machine_describer.dart`) server-side unchanged. The
 * only caller-controlled input besides the photo is `languageCode`, and it is NOT interpolated as
 * free text: this file accepts only the exact strings "ru"/"en" and maps each to a fixed,
 * server-owned literal ("Russian"/"English") before it ever reaches the prompt template. That is a
 * narrower injection surface even than `ai_coach_advice.ts`'s `subjectName` (a validated but
 * still-interpolated field) -- here the caller chooses between exactly two literals this server
 * wrote, never a string of their own.
 *
 * Same scope discipline as `ai_equipment_recognition.ts`: this callable does the model call and
 * returns the model's raw JSON text unchanged. `parseDescription` -- turning that JSON into a
 * `MachineCard` -- stays entirely client-side, untouched by this migration; it never touched the
 * network to begin with.
 */
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { AI_METERED } from "./scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, quotaFor } from "./abuse_guard";
import { generate, InlineImage } from "./ai_gateway";
import { validateImageInput } from "./image_validation";

/** Matches every other callable's `signInProvider` extraction. */
function signInProvider(request: CallableRequest): string | undefined {
  return request.auth?.token?.firebase?.sign_in_provider;
}

/** The only two languages the app ships (`languageCode == 'ru' ? 'Russian' : 'English'` in the
 * mobile source this ports). Server-owned map, not a caller-supplied string -- see this file's
 * header. */
const LANGUAGE_NAMES: Record<string, string> = { ru: "Russian", en: "English" };

interface MachineDescriptionInput {
  image: InlineImage;
  languageName: string;
}

function parseInput(data: unknown): MachineDescriptionInput {
  const d = (data ?? {}) as Record<string, unknown>;
  const mimeType = d.mimeType;
  const base64 = d.imageBase64;
  const languageCode = d.languageCode;
  if (typeof mimeType !== "string") {
    throw new HttpsError("invalid-argument", "mimeType must be one of image/jpeg, image/png, image/webp.");
  }
  if (typeof base64 !== "string") {
    throw new HttpsError("invalid-argument", "imageBase64 is required.");
  }
  if (typeof languageCode !== "string" || !(languageCode in LANGUAGE_NAMES)) {
    throw new HttpsError("invalid-argument", 'languageCode must be exactly "ru" or "en".');
  }
  return {
    image: validateImageInput(mimeType, base64),
    languageName: LANGUAGE_NAMES[languageCode],
  };
}

/** Exact copy of `GeminiMachineDescriber.buildPrompt()`, with `language` already resolved to a
 * fixed literal by `parseInput` above -- never the caller's raw string. */
function buildPrompt(language: string): string {
  return `A gym app user photographed a piece of equipment the app has no page for. Look
ONLY at the machine closest to the centre of the photo; ignore what is at the
edges.

Answer with JSON only:
{"isGymEquipment": true or false,
 "name": "<short everyday name of this machine>",
 "summary": "<1-2 sentences: what it is and what it trains>",
 "uses": ["<one short exercise done on it>", "..."]}

Rules:
- Write "name", "summary" and every line of "uses" in ${language}.
- If the photo is not gym equipment at all — a person, a pet, a room, a meal —
  answer {"isGymEquipment": false} and nothing else. Do not describe it.
- Name the machine by what it is, not by a brand you think you recognise.
- 3 to 5 lines in "uses", each a real exercise performed on THIS machine, at
  most about six words.
- No markdown, no commentary.`;
}

export const aiMachineDescription = onCall(AI_METERED, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to describe equipment.");
  }
  noteAppCheck(request, "aiMachineDescription");
  const input = parseInput(request.data);

  await enforceDailyQuota(
    request.auth.uid,
    "aiMachineDescription",
    quotaFor(QUOTAS.aiMachineDescription, signInProvider(request)),
  );

  // Matches `GeminiMachineDescriber`'s own generationConfig exactly: JSON mode, temperature 0,
  // thinking disabled -- same reasoning as `ai_equipment_recognition.ts`'s identical choice (2-5s
  // vs 25-31s, verified live 2026-07-30 for the shared `firebaseCloudAsk` wiring both call sites
  // used before this migration).
  //
  // `timeoutMs: 20_000` bounds only this call (the model itself), matching
  // `ai_equipment_recognition.ts`'s own 20s server-side budget -- deliberately NOT the mobile
  // client's end-to-end budget, for the same client/server timeout-race reason documented there:
  // this budget only starts after auth, `parseInput`, and the quota transaction above have already
  // run, so a client-side timer of the same duration could discard a legitimate, already-paid
  // answer. The mobile side (`GeminiMachineDescriber.timeout` plus, one layer further out,
  // `visual_equipment_providers.dart`'s `describeTimeoutProvider`) gives real margin over this
  // number rather than matching it.
  const text = await generate({
    prompt: buildPrompt(input.languageName),
    image: input.image,
    jsonResponse: true,
    temperature: 0,
    disableThinking: true,
    timeoutMs: 20_000,
    // The JSON reply is a name, a 1-2 sentence summary, and up to 5 short exercise lines -- a few
    // short fields, comparable in shape to `aiEquipmentRecognition`'s reply. 384 tokens gives
    // headroom for the longer free-text summary/uses fields (vs. that callable's single machine
    // name) while still being a real, provider-enforced ceiling per `ai_gateway.ts`'s
    // `GenerateOptions.maxOutputTokens` doc.
    maxOutputTokens: 384,
  });

  return { text };
});
