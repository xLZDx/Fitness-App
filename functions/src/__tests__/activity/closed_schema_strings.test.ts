/** F91: per-string-field regex table for lap and provenance strings (design 5.1a closing check). */
import { readFileSync } from "fs";
import { join } from "path";
import { validateStreamPayload } from "../../activity_streams/validate";
import { validateUploadedStream } from "../../activity_streams/upload_validate";
import { uploadOf, validPayload } from "./support/fakes";

const fixture = JSON.parse(readFileSync(join(__dirname, "fixtures", "stream_schema_keys.json"), "utf8"));
const clone = (): any => JSON.parse(JSON.stringify(validPayload()));

/** Places `value` into the named field of a fresh payload. */
function put(where: "lap" | "prov" | "field", field: string, value: string): any {
  const p = clone();
  if (where === "lap") p.meta.laps[0][field] = value;
  else if (where === "prov") p.meta.provenance[0][field] = value;
  else p.meta.provenance[0].fieldsContributed = [value];
  return p;
}

const lapFields = Object.keys(fixture.lapStringPatterns);
const provFields = Object.keys(fixture.provenanceStringPatterns);
const COORD = ["51.5007,-0.1276", "173.25", "lat 51.7351", "-0.1276"];

describe("F91 the fixture carries a regex for every string field", () => {
  test("lap string fields are exactly kind and strokeType; every provenance key except fieldsContributed has a regex", () => {
    expect(lapFields.sort()).toEqual(["kind", "strokeType"]);
    const expected = (fixture.provenanceKeys as string[]).filter((k) => k !== "fieldsContributed");
    expect(provFields.sort()).toEqual([...expected].sort());
    expect(typeof fixture.fieldContributedPattern).toBe("string");
    expect(typeof fixture.coordinateLike).toBe("string");
  });
});

describe("F91 coordinate-like strings are rejected in every string field", () => {
  const rows: Array<[string, "lap" | "prov" | "field", string]> = [
    ...lapFields.map((f) => [`lap.${f}`, "lap", f] as [string, "lap", string]),
    ...provFields.map((f) => [`provenance.${f}`, "prov", f] as [string, "prov", string]),
    ["provenance.fieldsContributed[]", "field", "fieldsContributed"],
  ];
  for (const [name, where, field] of rows) {
    test.each(COORD)(`${name} rejects %s with bare bad_string and nothing to promote`, async (c) => {
      const p = put(where, field, c);
      expect(validateStreamPayload(p)).toEqual({ ok: false, code: "bad_string" });
      const u = uploadOf(p);
      expect(await validateUploadedStream(u.bytes, u.sha)).toEqual({ ok: false, code: "bad_string" });
    });
  }
  test("a length-bounded regex-conformant free field that merely CONTAINS a decimal pair is rejected by the shared denial", () => {
    expect(validateStreamPayload(put("prov", "sourceId", "173.25")).ok).toBe(false);
    expect(validateStreamPayload(put("prov", "deviceModel", "Pixel 51.5007")).ok).toBe(false);
    expect(validateStreamPayload(put("prov", "appPackage", "com.example.v173.25")).ok).toBe(false);
    expect(validateStreamPayload(put("prov", "externalId", "ext:51.5007")).ok).toBe(false);
  });
  test("honest limit (design 5.1a): an opaque geohash-like id passes, the test pins that it is not claimed rejected", () => {
    expect(validateStreamPayload(put("prov", "externalId", "gcpvj0duq")).ok).toBe(true);
  });
});

describe("F91 length bounds", () => {
  const over: Array<[string, "prov" | "field", string, string]> = [
    ["sourceId 65", "prov", "sourceId", "a".repeat(65)],
    ["deviceModel 65", "prov", "deviceModel", "a".repeat(65)],
    ["appPackage 129", "prov", "appPackage", "a".repeat(129)],
    ["externalId 129", "prov", "externalId", "a".repeat(129)],
    ["fieldsContributed element 33", "field", "x", "a".repeat(33)],
    ["importedAt with a 7-digit fraction", "prov", "importedAt", "2026-10-15T10:00:00.1234567Z"],
  ];
  test.each(over)("%s matching the charset but over the bound is rejected", (_n, where, field, v) => {
    expect(validateStreamPayload(put(where, field, v))).toEqual({ ok: false, code: "bad_string" });
  });
  const exact: Array<[string, "prov" | "field", string, string]> = [
    ["sourceId 64", "prov", "sourceId", "a".repeat(64)],
    ["deviceModel 64", "prov", "deviceModel", "a".repeat(64)],
    ["appPackage 128", "prov", "appPackage", "a".repeat(128)],
    ["externalId 128", "prov", "externalId", "a".repeat(128)],
    ["fieldsContributed element 32", "field", "x", "a".repeat(32)],
    ["importedAt whole seconds", "prov", "importedAt", "2026-10-15T10:00:00Z"],
  ];
  test.each(exact)("boundary control: %s is accepted", (_n, where, field, v) => {
    expect(validateStreamPayload(put(where, field, v)).ok).toBe(true);
  });
  test("an impossible date that fits the shape (month 13) is rejected", () => {
    expect(validateStreamPayload(put("prov", "importedAt", "2026-13-15T10:00:00Z"))).toEqual({ ok: false, code: "bad_string" });
  });
  test("design 17.3: importedAt with a fraction of two or more digits is rejected as coordinate-like, one digit is accepted", () => {
    expect(validateStreamPayload(put("prov", "importedAt", "2026-10-15T10:00:00.123456Z")).ok).toBe(false);
    expect(validateStreamPayload(put("prov", "importedAt", "2026-10-15T10:00:00.1Z")).ok).toBe(true);
  });
  test("enum fields reject case variants and unknown names", () => {
    for (const v of ["AUTO", "Auto", "other", " auto"]) expect(validateStreamPayload(put("lap", "kind", v)).ok).toBe(false);
    for (const v of ["FREE", "crawl"]) expect(validateStreamPayload(put("lap", "strokeType", v)).ok).toBe(false);
    expect(validateStreamPayload(put("prov", "sourceKind", "wearable")).ok).toBe(false);
  });
  test("an empty string is rejected in every optional string field", () => {
    for (const f of ["deviceModel", "appPackage", "externalId", "sourceId"]) {
      expect(validateStreamPayload(put("prov", f, "")).ok).toBe(false);
    }
  });
});
