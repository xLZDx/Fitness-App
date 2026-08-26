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
import { QUOTAS, enforceDailyQuota, noteAppCheck, quotaFor } from "./abuse_guard";
import { generate, InlineImage } from "./ai_gateway";

/** Matches every other callable's `signInProvider` extraction. */
function signInProvider(request: CallableRequest): string | undefined {
  return request.auth?.token?.firebase?.sign_in_provider;
}

/** 9 MB of DECODED bytes, comfortably above the mobile client's own
 * `resizeForCloud` output in practice (1024px-long-edge JPEG at quality 88) —
 * this bounds request size against a hostile/buggy caller, not against a real
 * photo. Checked against the decoded buffer, not the base64 string, so the
 * ~4/3 encoding overhead cannot be used to sneak a larger payload past a
 * string-length check. */
const MAX_IMAGE_BYTES = 9_000_000;

/** The longest a canonical base64 string can be while still possibly decoding
 * to <= `MAX_IMAGE_BYTES` (base64 is 4 characters per 3 bytes). Checked
 * BEFORE decoding — GPT-PM's G1 round-2 review caught that the original
 * fix checked `bytes.length` only after `Buffer.from` had already allocated
 * and decoded the full string, so an oversized-but-syntactically-valid
 * payload paid the decode/allocation cost before being refused, and before
 * `enforceDailyQuota` even ran: an unmetered CPU/memory cost per request,
 * not bounded by anything. This is a cheap guard on the STRING the caller
 * sent, ahead of the real (decoded-bytes) limit enforced further down. */
const MAX_IMAGE_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES / 3) * 4;

const ALLOWED_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

/** RFC 4648 base64 alphabet, with 0-2 trailing `=` padding characters. Node's
 * `Buffer.from(x, "base64")` silently ignores characters outside this
 * alphabet rather than throwing, so this is what actually rejects malformed
 * input — GPT-PM's G1 round-1 review of this file caught that the original
 * version had no such check at all. */
const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;

/**
 * Strictly decodes base64 and verifies it round-trips to the same string —
 * catches both non-alphabet characters and non-canonical padding/length that
 * `Buffer.from` would otherwise decode leniently.
 */
function decodeStrictBase64(value: string, field: string): Buffer {
  if (!BASE64_RE.test(value)) {
    throw new HttpsError("invalid-argument", `${field} is not valid base64.`);
  }
  const buf = Buffer.from(value, "base64");
  if (buf.toString("base64") !== value) {
    throw new HttpsError("invalid-argument", `${field} is not valid base64.`);
  }
  return buf;
}

/**
 * Reads the file-signature bytes every one of the three allowed formats
 * starts with, independent of the caller's claimed `mimeType` — the only way
 * to actually verify "this is a JPEG/PNG/WebP" rather than "the caller said
 * so". GPT-PM's G1 round-1 review named the exact hole this closes: without
 * it, `parseInput` accepted ANY non-empty base64 string labelled `image/jpeg`
 * (its own test suite's "valid" fixture was literally the base64 for the text
 * "hello"), meaning arbitrary bytes could reach the paid model billed and
 * quota-charged as a photo.
 */
function sniffImageMimeType(bytes: Buffer): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    return "image/png";
  }
  if (
    bytes.length >= 12 &&
    bytes.toString("ascii", 0, 4) === "RIFF" &&
    bytes.toString("ascii", 8, 12) === "WEBP"
  ) {
    return "image/webp";
  }
  return null;
}

interface EquipmentRecognitionInput {
  image: InlineImage;
}

function parseInput(data: unknown): EquipmentRecognitionInput {
  const d = (data ?? {}) as Record<string, unknown>;
  const mimeType = d.mimeType;
  const base64 = d.imageBase64;
  if (typeof mimeType !== "string" || !ALLOWED_MIME_TYPES.has(mimeType)) {
    throw new HttpsError("invalid-argument", "mimeType must be one of image/jpeg, image/png, image/webp.");
  }
  if (typeof base64 !== "string" || base64.length === 0) {
    throw new HttpsError("invalid-argument", "imageBase64 is required.");
  }
  if (base64.length > MAX_IMAGE_BASE64_LENGTH) {
    throw new HttpsError("invalid-argument", "imageBase64 is larger than this endpoint accepts.");
  }

  const bytes = decodeStrictBase64(base64, "imageBase64");
  if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) {
    throw new HttpsError("invalid-argument", "imageBase64 is larger than this endpoint accepts.");
  }
  const sniffed = sniffImageMimeType(bytes);
  if (sniffed === null) {
    throw new HttpsError("invalid-argument", "imageBase64 does not look like a JPEG, PNG, or WebP image.");
  }
  if (sniffed !== mimeType) {
    throw new HttpsError("invalid-argument", "mimeType does not match the image's actual file signature.");
  }

  return { image: { mimeType, base64 } };
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
