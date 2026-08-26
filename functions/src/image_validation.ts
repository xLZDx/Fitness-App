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
 * The byte-level work shared by both entry points below: cheap pre-decode length guard, strict
 * base64 decode, decoded-size cap (defense-in-depth -- provably unreachable given the pre-decode
 * guard, kept in case the two constants ever drift apart), file-signature sniff, and MIME/signature
 * equality. Assumes `mimeType` is already known to be an allowlisted string and `base64` a
 * non-empty string -- both entry points check that themselves, in their own different orders, before
 * calling in here. Not exported: this is the one place the actual security-sensitive logic lives,
 * and it must not be reachable except through a caller that has already done its own allowlist/
 * empty checks.
 */
function validateImageBytes(mimeType: string, base64: string): InlineImage {
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

/**
 * The RAW type checks only -- `typeof mimeType === "string"`, `typeof base64 === "string"` -- and
 * nothing else. No allowlist check, no empty-string check, no decoding.
 *
 * For `aiMachineDescription`'s `parseInput`, which needs to check its OWN cheap field --
 * `languageCode` -- in between this and `decodeAndValidateImageBytes`, reproducing `6e52bd6`'s
 * exact original three-phase order (raw type checks, then language, then everything else about the
 * image). GPT-PM's G1 review took three rounds to pin this boundary down precisely: round 1 treated
 * the WHOLE image validation as "cheap" and ran it all before language; round 2's fix bundled the
 * MIME allowlist AND empty-base64 checks in with the raw type checks and ran that whole bundle
 * before language, when the true original only ran the two bare `typeof` checks there -- the
 * allowlist and empty-string checks lived inside the original `validateImageInput` and ran AFTER
 * language. Deliberately narrower than it might look: ONLY the two `typeof` checks, because that is
 * all that ran before `languageCode` in the commit this reproduces.
 *
 * NOT used by `validateImageInput` below -- `aiEquipmentRecognition` has no third field to
 * interleave, and its own original ordering combined the type-check and the allowlist-check for
 * EACH field into one condition (see that function's own header for why composing this function
 * with `decodeAndValidateImageBytes` would have gotten that different, coarser ordering wrong).
 */
export function checkImageFieldsAreStrings(
  mimeType: unknown,
  base64: unknown,
): { mimeType: string; base64: string } {
  if (typeof mimeType !== "string") {
    throw new HttpsError("invalid-argument", "mimeType must be one of image/jpeg, image/png, image/webp.");
  }
  if (typeof base64 !== "string") {
    throw new HttpsError("invalid-argument", "imageBase64 is required.");
  }
  return { mimeType, base64 };
}

/**
 * The allowlist check, the empty-base64 check, and the byte-level work (`validateImageBytes`) --
 * everything `aiMachineDescription`'s `parseInput` runs AFTER `languageCode`. Takes strings already
 * passed through `checkImageFieldsAreStrings`.
 */
export function decodeAndValidateImageBytes(mimeType: string, base64: string): InlineImage {
  if (!ALLOWED_MIME_TYPES.has(mimeType)) {
    throw new HttpsError("invalid-argument", "mimeType must be one of image/jpeg, image/png, image/webp.");
  }
  if (base64.length === 0) {
    throw new HttpsError("invalid-argument", "imageBase64 is required.");
  }
  return validateImageBytes(mimeType, base64);
}

/**
 * Validates a raw `{mimeType, imageBase64}` pair for `aiEquipmentRecognition`, which has no third
 * field to interleave a check between -- so this reproduces that callable's own original,
 * COARSER ordering directly, rather than composing `checkImageFieldsAreStrings` +
 * `decodeAndValidateImageBytes` (which would run the two fields' type checks as two separate
 * conditions ahead of BOTH fields' allowlist/empty checks -- not what the original single-function
 * `validateImageInput` did, which combined each field's type-check and content-check into one
 * condition, mimeType entirely before base64).
 */
export function validateImageInput(mimeType: unknown, base64: unknown): InlineImage {
  if (typeof mimeType !== "string" || !ALLOWED_MIME_TYPES.has(mimeType)) {
    throw new HttpsError("invalid-argument", "mimeType must be one of image/jpeg, image/png, image/webp.");
  }
  if (typeof base64 !== "string" || base64.length === 0) {
    throw new HttpsError("invalid-argument", "imageBase64 is required.");
  }
  return validateImageBytes(mimeType, base64);
}
