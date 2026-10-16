/** F51 (closed schema at every depth) and F53 (key sets pinned to the shared fixture). */
import { readFileSync } from "fs";
import { join } from "path";
import { validateStreamPayload } from "../../activity_streams/validate";
import { validateUploadedStream } from "../../activity_streams/upload_validate";
import * as schema from "../../activity_streams/schema";
import { uploadOf, validPayload } from "./support/fakes";

const fixture = JSON.parse(readFileSync(join(__dirname, "fixtures", "stream_schema_keys.json"), "utf8"));
const clone = (): any => JSON.parse(JSON.stringify(validPayload()));

function setOwn(target: any, key: string, value: unknown): void {
  Object.defineProperty(target, key, { value, enumerable: true, configurable: true, writable: true });
}

const positions: Array<[string, (p: any) => any]> = [
  ["top level", (p) => p],
  ["kinds", (p) => p.kinds],
  ["gps record", (p) => p.kinds.gps],
  ["altitude record", (p) => p.kinds.altitude],
  ["speed record", (p) => p.kinds.speed],
  ["meta", (p) => p.meta],
  ["lap", (p) => p.meta.laps[0]],
  ["provenance record", (p) => p.meta.provenance[0]],
];
const extraKeys = ["avgHrBpm", "hr", "heartRate", "unknownKey", "__proto__"];

describe("F51 unknown keys are rejected (not stripped) at every depth", () => {
  const rows = positions.flatMap(([pos, at]) => extraKeys.map((k) => [pos, k, at] as const));
  test.each(rows)("%s + key %s", async (_pos, key, at) => {
    const p = clone();
    setOwn(at(p), key, 1);
    const res = validateStreamPayload(p);
    expect(res.ok).toBe(false);
    if (!res.ok) expect(["unknown_key", "forbidden_kind"]).toContain(res.code);
    // Byte layer: nothing to promote.
    const u = uploadOf(p);
    const r = await validateUploadedStream(u.bytes, u.sha);
    expect(r.ok).toBe(false);
  });

  test("a nested object where a scalar belongs is rejected", () => {
    const p = clone();
    p.meta.laps[0].index = { a: 1 };
    expect(validateStreamPayload(p).ok).toBe(false);
  });
  test("a list where a scalar belongs is rejected, a scalar where a list belongs too", () => {
    const p = clone();
    p.meta.laps[0].durationS = [1];
    expect(validateStreamPayload(p).ok).toBe(false);
    const q = clone();
    q.kinds.gps.lats = 5;
    expect(validateStreamPayload(q)).toEqual({ ok: false, code: "bad_shape" });
  });
  test.each([["NaN", NaN], ["Infinity", Infinity], ["-Infinity", -Infinity]])("%s sample element is bad_number", (_n, v) => {
    const p = clone();
    p.kinds.altitude.values = [1, v];
    expect(validateStreamPayload(p)).toEqual({ ok: false, code: "bad_number" });
  });
  test("a sample element that is an object or a string is bad_number", () => {
    const p = clone();
    p.kinds.speed.values = [1, { hr: 170 }];
    expect(validateStreamPayload(p)).toEqual({ ok: false, code: "bad_number" });
    const q = clone();
    q.kinds.gps.accuracies = [1, "2", 3];
    expect(validateStreamPayload(q)).toEqual({ ok: false, code: "bad_number" });
  });
  test("an over-long string is bad_string", () => {
    const p = clone();
    p.kinds.gps.sourceId = "a".repeat(65);
    expect(validateStreamPayload(p)).toEqual({ ok: false, code: "bad_string" });
  });
  test("too many list elements: laps, provenance records, fieldsContributed", () => {
    const lap = clone().meta.laps[0];
    const p = clone();
    p.meta.laps = Array.from({ length: schema.MAX_LAPS + 1 }, () => lap);
    expect(validateStreamPayload(p)).toEqual({ ok: false, code: "too_many" });
    const q = clone();
    q.meta.provenance = Array.from({ length: schema.MAX_PROVENANCE_RECORDS + 1 }, () => clone().meta.provenance[0]);
    expect(validateStreamPayload(q)).toEqual({ ok: false, code: "too_many" });
    const r = clone();
    r.meta.provenance[0].fieldsContributed = Array.from({ length: schema.MAX_FIELDS_CONTRIBUTED + 1 }, () => "distance");
    expect(validateStreamPayload(r)).toEqual({ ok: false, code: "too_many" });
  });
  test.each([
    ["HR key in meta", (p: any) => { p.meta.hr = [1]; }],
    ["HR key in a lap", (p: any) => { p.meta.laps[0].avgHrBpm = 140; }],
    ["userEdits inside meta", (p: any) => { p.meta.userEdits = {}; }],
    ["explicitValues inside meta", (p: any) => { p.meta.explicitValues = {}; }],
    ["HR in a GPS sample record", (p: any) => { p.kinds.gps.hr = [150, 151, 152]; }],
  ])("%s is rejected", (_n, mutate) => {
    const p = clone();
    mutate(p);
    expect(validateStreamPayload(p).ok).toBe(false);
  });
  test("input that is not a plain object is bad_shape and never throws", () => {
    for (const bad of [null, 5, "x", [], undefined, new Date(), Object.create({ schema: 1 })]) {
      expect(validateStreamPayload(bad)).toEqual({ ok: false, code: "bad_shape" });
    }
  });
  test("control: the clean payload is accepted", () => {
    expect(validateStreamPayload(clone()).ok).toBe(true);
  });
});

describe("F53 key sets pinned to the shared fixture", () => {
  const kindKeys = (k: "gps" | "altitude" | "speed"): string[] =>
    schema.STREAM_KEYS.filter((key) => (k === "gps" ? key !== "values" : !["lats", "lons", "accuracies"].includes(key)));
  test.each(["gps", "altitude", "speed"] as const)("%s key set equals the fixture", (k) => {
    expect([...kindKeys(k)].sort()).toEqual([...fixture.streamKeys[k]].sort());
  });
  test("lap and provenance key sets equal the fixture", () => {
    expect([...schema.LAP_KEYS].sort()).toEqual([...fixture.lapKeys].sort());
    expect([...schema.PROVENANCE_KEYS].sort()).toEqual([...fixture.provenanceKeys].sort());
  });
  test("string patterns equal the fixture byte for byte", () => {
    for (const [k, src] of Object.entries(fixture.lapStringPatterns)) {
      expect(schema.LAP_STRING_RULES[k].pattern.source).toBe(new RegExp(src as string).source);
    }
    for (const [k, src] of Object.entries(fixture.provenanceStringPatterns)) {
      expect(schema.PROVENANCE_STRING_RULES[k].pattern.source).toBe(new RegExp(src as string).source);
    }
    expect(schema.FIELD_CONTRIBUTED_RULE.pattern.source).toBe(new RegExp(fixture.fieldContributedPattern).source);
  });
  test("no fixture key names heart rate", () => {
    const all = [...Object.values(fixture.streamKeys).flat(), ...fixture.lapKeys, ...fixture.provenanceKeys] as string[];
    for (const k of all) expect(k).not.toMatch(/hr|heart/i);
  });
  test.each(["gps", "altitude", "speed"] as const)("the validator accepts a %s record with exactly the fixture keys and rejects every other key", (k) => {
    const base = clone();
    const rec = base.kinds[k];
    expect(Object.keys(rec).filter((x) => !fixture.streamKeys[k].includes(x))).toEqual([]);
    const others = (fixture.streamKeys.gps as string[]).concat(["values"]).filter((x) => !fixture.streamKeys[k].includes(x));
    for (const extra of others) {
      const p = clone();
      p.kinds[k][extra] = k === "gps" ? [1, 2, 3] : [1, 2];
      expect(validateStreamPayload(p).ok).toBe(false);
    }
  });
  test("every fixture lap key and provenance key is accepted in place (the fixture is the whole allowed set)", () => {
    const p = clone();
    expect(Object.keys(p.meta.laps[0]).sort()).toEqual([...fixture.lapKeys].sort());
    expect(Object.keys(p.meta.provenance[0]).sort()).toEqual([...fixture.provenanceKeys].sort());
    expect(validateStreamPayload(p).ok).toBe(true);
  });
});
