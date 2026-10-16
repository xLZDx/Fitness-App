/** S02-04a bucket helpers: identifier patterns and path builders. */
import {
  activityQuarantinePrefix, activityStreamRowPath, activityStreamsPrefix, activitySummaryPath, activityTombstonePath,
  isActivityId, isUploadId, quarantineObjectPath, streamObjectPath, userQuarantinePrefix, userStreamsPrefix,
} from "../../activity_streams/paths";

const ACT = `act_${"a".repeat(40)}`;
const UP = `up_${"b".repeat(32)}`;

describe("identifier patterns", () => {
  test.each([ACT, `act_${"0123456789abcdef".repeat(2)}01234567`])("activity id accepted: %s", (v) => expect(isActivityId(v)).toBe(true));
  test.each([
    `act_${"a".repeat(39)}`, `act_${"a".repeat(41)}`, `act_${"A".repeat(40)}`, "act_x/../y", "", 5, null, `${ACT}\n`, ` ${ACT}`,
  ])("activity id rejected: %p", (v) => expect(isActivityId(v)).toBe(false));
  test("upload id: up_ + 32 lowercase hex only", () => {
    expect(isUploadId(UP)).toBe(true);
    for (const v of [`up_${"b".repeat(31)}`, `up_${"B".repeat(32)}`, "up_../x", ACT, undefined]) expect(isUploadId(v)).toBe(false);
  });
});

describe("path builders", () => {
  test("exact shapes", () => {
    expect(quarantineObjectPath("u1", ACT, UP)).toBe(`quarantine/u1/${ACT}/${UP}`);
    expect(streamObjectPath("u1", ACT, UP)).toBe(`streams/u1/${ACT}/${UP}.json.gz`);
    expect(activityStreamsPrefix("u1", ACT)).toBe(`streams/u1/${ACT}/`);
    expect(activityQuarantinePrefix("u1", ACT)).toBe(`quarantine/u1/${ACT}/`);
    expect(userStreamsPrefix("u1")).toBe("streams/u1/");
    expect(userQuarantinePrefix("u1")).toBe("quarantine/u1/");
    expect(activitySummaryPath("u1", ACT)).toBe(`users/u1/activities/${ACT}`);
    expect(activityStreamRowPath("u1", ACT)).toBe(`users/u1/activity_streams/${ACT}`);
    expect(activityTombstonePath("u1", ACT)).toBe(`users/u1/activity_tombstones/${ACT}`);
  });
  test.each(["", "a/b", "..", "a b", "u".repeat(129), "a\n"])("a bad uid %p throws", (uid) => {
    expect(() => userStreamsPrefix(uid)).toThrow();
    expect(() => streamObjectPath(uid, ACT, UP)).toThrow();
  });
  test("a bad activity or upload id throws instead of building a path", () => {
    expect(() => streamObjectPath("u1", "act_x/../y", UP)).toThrow();
    expect(() => streamObjectPath("u1", ACT, "up_x")).toThrow();
    expect(() => activityTombstonePath("u1", "../x")).toThrow();
  });
  test("a user prefix never matches another user whose uid extends it (abc vs abcd)", () => {
    expect(`streams/abcd/${ACT}/${UP}.json.gz`.startsWith(userStreamsPrefix("abc"))).toBe(false);
    expect(`quarantine/abcd/x`.startsWith(userQuarantinePrefix("abc"))).toBe(false);
  });
});
