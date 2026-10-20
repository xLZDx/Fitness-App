/** S02 remediation J1: unit tests of the pure `verifyExpectedUid` helper (design 17 item 25). */
import {
  EXPECTED_UID_KEY, EXPECTED_UID_MAX_LENGTH, ExpectedUidError, verifyExpectedUid,
} from "../../activity_streams/expected_uid";

const UID = "uid_alice_1";

function codeOf(fn: () => unknown): string {
  try {
    fn();
  } catch (e) {
    expect(e).toBeInstanceOf(ExpectedUidError);
    return (e as ExpectedUidError).code;
  }
  return "NO_THROW";
}

describe("verifyExpectedUid constants", () => {
  test("the key name and the length bound are pinned", () => {
    expect(EXPECTED_UID_KEY).toBe("expectedUid");
    expect(EXPECTED_UID_MAX_LENGTH).toBe(128);
  });
});

describe("verifyExpectedUid match", () => {
  test("returns a copy without the key, keeps every other key (unknown ones too) and does not mutate the input", () => {
    const input = { expectedUid: UID, activityId: "a", extra: { n: 1 }, uid: "other" };
    const snapshot = JSON.parse(JSON.stringify(input));
    const out = verifyExpectedUid(UID, input) as Record<string, unknown>;
    expect(out).toEqual({ activityId: "a", extra: { n: 1 }, uid: "other" });
    expect("expectedUid" in out).toBe(false);
    expect(out).not.toBe(input);
    expect(input).toEqual(snapshot);
    expect(input.expectedUid).toBe(UID);
  });

  test("a key of exactly 128 characters equal to the uid is accepted", () => {
    const long = "u".repeat(128);
    expect(verifyExpectedUid(long, { expectedUid: long, a: 1 })).toEqual({ a: 1 });
  });

  test("an empty rest stays an empty object", () => {
    expect(verifyExpectedUid(UID, { expectedUid: UID })).toEqual({});
  });
});

describe("verifyExpectedUid mismatch", () => {
  test("another uid is account_changed", () => {
    expect(codeOf(() => verifyExpectedUid(UID, { expectedUid: "uid_bob_2" }))).toBe("account_changed");
  });
  test("a case-different uid is a mismatch (exact comparison)", () => {
    expect(codeOf(() => verifyExpectedUid(UID, { expectedUid: UID.toUpperCase() }))).toBe("account_changed");
  });
  test("a prefix or a whitespace-padded uid is a mismatch", () => {
    expect(codeOf(() => verifyExpectedUid(UID, { expectedUid: UID.slice(0, -1) }))).toBe("account_changed");
    expect(codeOf(() => verifyExpectedUid(UID, { expectedUid: ` ${UID}` }))).toBe("account_changed");
  });
});

describe("verifyExpectedUid malformed key", () => {
  const BAD: Array<[string, Record<string, unknown>]> = [
    ["missing", { a: 1 }],
    ["null", { expectedUid: null }],
    ["undefined value", { expectedUid: undefined }],
    ["number", { expectedUid: 5 }],
    ["object", { expectedUid: { uid: UID } }],
    ["array", { expectedUid: [UID] }],
    ["boolean", { expectedUid: true }],
    ["empty string", { expectedUid: "" }],
    ["129 characters", { expectedUid: "u".repeat(129) }],
  ];
  test.each(BAD)("%s is invalid_request", (_n, data) => {
    expect(codeOf(() => verifyExpectedUid(UID, data))).toBe("invalid_request");
  });

  test("a malformed key never reports account_changed, even when the uid is also different (shape precedes equality)", () => {
    const longUid = "u".repeat(129);
    // 129-character key EQUAL to the uid is still malformed, not accepted.
    expect(codeOf(() => verifyExpectedUid(longUid, { expectedUid: longUid }))).toBe("invalid_request");
    expect(codeOf(() => verifyExpectedUid(UID, { expectedUid: "x".repeat(200) }))).toBe("invalid_request");
    expect(codeOf(() => verifyExpectedUid(UID, { expectedUid: 7 }))).toBe("invalid_request");
  });
});

describe("verifyExpectedUid non-object data", () => {
  test.each<[string, unknown]>([
    ["null", null], ["undefined", undefined], ["array", [{ expectedUid: UID }]], ["string", "x"], ["number", 5], ["boolean", false],
  ])("%s is returned unchanged and does not throw", (_n, data) => {
    expect(verifyExpectedUid(UID, data)).toBe(data);
  });
});
