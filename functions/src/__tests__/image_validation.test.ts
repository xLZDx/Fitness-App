/**
 * `image_validation.ts` — the shared vision-input validator both `aiEquipmentRecognition` and
 * `aiMachineDescription` call. Extracted from `ai_equipment_recognition.ts`, where its own test
 * suite already covers these cases end-to-end through the callable; this file tests the module in
 * isolation so the properties are pinned even if a future callable stops re-exercising all of them
 * through its own request tests.
 */
import { validateImageInput, MAX_IMAGE_BYTES, MAX_IMAGE_BASE64_LENGTH } from "../image_validation";

const JPEG_BASE64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]).toString(
  "base64",
);
const PNG_BASE64 = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]).toString(
  "base64",
);
const WEBP_BASE64 = Buffer.from(
  Buffer.concat([Buffer.from("RIFF"), Buffer.from([0, 0, 0, 0]), Buffer.from("WEBP")]),
).toString("base64");
const NOT_AN_IMAGE_BASE64 = Buffer.from("hello").toString("base64");

describe("validateImageInput", () => {
  test("accepts a real JPEG matching its declared mimeType", () => {
    expect(validateImageInput("image/jpeg", JPEG_BASE64)).toEqual({
      mimeType: "image/jpeg",
      base64: JPEG_BASE64,
    });
  });

  test("accepts a real PNG matching its declared mimeType", () => {
    expect(validateImageInput("image/png", PNG_BASE64).mimeType).toBe("image/png");
  });

  test("accepts a real WebP matching its declared mimeType", () => {
    expect(validateImageInput("image/webp", WEBP_BASE64).mimeType).toBe("image/webp");
  });

  test("rejects a mimeType outside the fixed allowlist", () => {
    expect(() => validateImageInput("image/gif", JPEG_BASE64)).toThrow(/mimeType/);
  });

  test("rejects an empty base64 string", () => {
    expect(() => validateImageInput("image/jpeg", "")).toThrow(/imageBase64/);
  });

  test("rejects an oversized payload via the cheap pre-decode length guard before decoding", () => {
    // One base64 group (4 chars) past MAX_IMAGE_BASE64_LENGTH — see that constant's own doc for
    // why this must be checked before `Buffer.from` ever runs.
    expect(() => validateImageInput("image/jpeg", "a".repeat(MAX_IMAGE_BASE64_LENGTH + 4))).toThrow(
      /imageBase64/,
    );
  });

  test("MAX_IMAGE_BASE64_LENGTH provably bounds decoded bytes to MAX_IMAGE_BYTES", () => {
    expect(Math.floor((MAX_IMAGE_BASE64_LENGTH * 3) / 4)).toBeGreaterThanOrEqual(MAX_IMAGE_BYTES);
    expect(Math.floor(((MAX_IMAGE_BASE64_LENGTH - 4) * 3) / 4)).toBeLessThan(MAX_IMAGE_BYTES + 1);
  });

  test("rejects malformed base64", () => {
    expect(() => validateImageInput("image/jpeg", "not valid base64!!")).toThrow(/base64/);
  });

  test("rejects a payload that is not actually an image, regardless of the claimed mimeType", () => {
    expect(() => validateImageInput("image/jpeg", NOT_AN_IMAGE_BASE64)).toThrow(/does not look like/);
  });

  test("rejects a mimeType that does not match the image's real file signature", () => {
    expect(() => validateImageInput("image/png", JPEG_BASE64)).toThrow(/does not match/);
  });
});
