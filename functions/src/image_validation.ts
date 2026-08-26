/**
 * Shared image-validation logic for the G1 vision callables (`aiEquipmentRecognition`,
 * `aiMachineDescription`).
 *
 * Extracted out of `ai_equipment_recognition.ts`, where this logic first shipped and was then
 * hardened across two GPT-PM review rounds: round 1 added the file-signature sniff (the original
 * version accepted ANY non-empty base64 string labelled with an allowed MIME type -- its own
 * test's "valid" fixture was literally the base64 for the text "hello"); round 2 added the
 * pre-decode string-length guard (the round-1 fix decoded the FULL base64 before checking size,
 * so an oversized-but-syntactically-valid payload paid the decode/allocation cost unmetered,
 * before quota was even touched).
 *
 * Both `aiEquipmentRecognition` and `aiMachineDescription` need byte-identical validation --
 * duplicating this into a second file would re-risk the exact same MAJOR-class bugs GPT-PM already
 * found and fixed once on the original. `ai_equipment_recognition.ts` now imports this module
 * rather than owning the logic itself; that refactor is behavior-preserving, proven by its own
 * existing test suite staying green unchanged.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { InlineImage } from "./ai_gateway";

/** 9 MB of DECODED bytes. Bounds request size against a hostile/buggy caller, not against a real
 * photo -- comfortably above the mobile client's own `resizeForCloud` output in practice (1024px-
 * long-edge JPEG at quality 88). Checked against the decoded buffer, not the base64 string, so the
 * ~4/3 encoding overhead cannot be used to sneak a larger payload past a string-length check. */
export const MAX_IMAGE_BYTES = 9_000_000;

/** The longest a canonical base64 string can be while still possibly decoding to
 * <= `MAX_IMAGE_BYTES` (base64 is 4 characters per 3 bytes). Checked BEFORE decoding -- see this
 * module's header for why: an oversized-but-syntactically-valid payload must not pay the
 * decode/allocation cost before being refused, and before `enforceDailyQuota` even runs. */
export const MAX_IMAGE_BASE64_LENGTH = Math.ceil(MAX_IMAGE_BYTES / 3) * 4;

export const ALLOWED_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

/** RFC 4648 base64 alphabet, with 0-2 trailing `=` padding characters. Node's
 * `Buffer.from(x, "base64")` silently ignores characters outside this alphabet rather than
 * throwing, so this is what actually rejects malformed input. */
const BASE64_RE = /^[A-Za-z0-9+/]*={0,2}$/;

/**
 * Strictly decodes base64 and verifies it round-trips to the same string -- catches both
 * non-alphabet characters and non-canonical padding/length that `Buffer.from` would otherwise
 * decode leniently.
 */
export function decodeStrictBase64(value: string, field: string): Buffer {
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
 * Reads the file-signature bytes every one of the three allowed formats starts with, independent
 * of the caller's claimed `mimeType` -- the only way to actually verify "this is a JPEG/PNG/WebP"
 * rather than "the caller said so".
 */
export function sniffImageMimeType(bytes: Buffer): string | null {
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

/**
 * Validates a raw `{mimeType, imageBase64}` pair exactly the way both vision callables receive it
 * from `request.data` -- type checks, allowed-MIME allowlist, non-empty, cheap pre-decode length
 * guard, strict base64 decode, decoded-size cap (defense-in-depth -- provably unreachable given the
 * pre-decode guard, kept in case the two constants ever drift apart), file-signature sniff, and
 * MIME/signature equality.
 *
 * Takes `unknown` for both fields -- not `string` -- and owns the type checks itself, rather than
 * leaving each callable's own `parseInput` to type-check before calling in. GPT-PM's round-1 review
 * of this slice caught the gap that split created: `ai_equipment_recognition.ts`'s original,
 * pre-extraction code checked the mimeType allowlist BEFORE checking whether `imageBase64` was even
 * present (`{mimeType: "image/gif"}` with no image failed on the mimeType message). The first
 * version of this extraction had each callable's `parseInput` check `typeof mimeType === "string"`
 * and `typeof base64 === "string"` itself, in that order, before ever calling this function --
 * which silently reordered that exact case to fail on the base64 message instead, an observable
 * behavior change the "pure refactor" claim did not actually hold to. Owning both type checks here,
 * in the original order, is what makes both callables share the true original ordering permanently
 * rather than by each caller happening to type-check in the same sequence.
 */
export function validateImageInput(mimeType: unknown, base64: unknown): InlineImage {
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

  return { mimeType, base64 };
}
