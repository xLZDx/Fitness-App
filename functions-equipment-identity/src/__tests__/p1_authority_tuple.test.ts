import { z } from "zod";
import {
  freezeAuthorityTuple,
  assertAuthorityTupleUnchanged,
  AuthorityTupleMismatchError,
} from "../p1/authority_tuple";

const BASE_TUPLE = {
  catalogVersion: "catalog-v1-test",
  ocrVersion: "ocr-1",
  textPolicyVersion: "text-1",
  fusionPolicyVersion: "fusion-1",
  identityPolicyVersion: "identity-1",
};

describe("freezeAuthorityTuple", () => {
  test("returns a validated, frozen tuple", () => {
    const tuple = freezeAuthorityTuple(BASE_TUPLE);
    expect(Object.isFrozen(tuple)).toBe(true);
    expect(tuple.catalogVersion).toBe("catalog-v1-test");
  });

  test("a mutation attempt on the frozen tuple does not change its value", () => {
    "use strict";
    const tuple = freezeAuthorityTuple(BASE_TUPLE);
    expect(() => {
      (tuple as { catalogVersion: string }).catalogVersion = "catalog-v2-forged";
    }).toThrow(TypeError);
    expect(tuple.catalogVersion).toBe("catalog-v1-test");
  });

  test("rejects an invalid candidate", () => {
    expect(() => freezeAuthorityTuple({ ...BASE_TUPLE, catalogVersion: "" })).toThrow(
      z.ZodError,
    );
  });
});

describe("assertAuthorityTupleUnchanged", () => {
  test("does not throw when the tuple is identical", () => {
    const before = freezeAuthorityTuple(BASE_TUPLE);
    const after = freezeAuthorityTuple({ ...BASE_TUPLE });
    expect(() => assertAuthorityTupleUnchanged(before, after)).not.toThrow();
  });

  test("throws AuthorityTupleMismatchError naming the changed field", () => {
    const before = freezeAuthorityTuple(BASE_TUPLE);
    const after = freezeAuthorityTuple({ ...BASE_TUPLE, catalogVersion: "catalog-v2-forged" });
    expect(() => assertAuthorityTupleUnchanged(before, after)).toThrow(
      AuthorityTupleMismatchError,
    );
    try {
      assertAuthorityTupleUnchanged(before, after);
      fail("expected assertAuthorityTupleUnchanged to throw");
    } catch (err) {
      expect(err).toBeInstanceOf(AuthorityTupleMismatchError);
      expect((err as AuthorityTupleMismatchError).changedFields).toEqual(["catalogVersion"]);
    }
  });

  test("detects a change in an optional field going from absent to present", () => {
    const before = freezeAuthorityTuple(BASE_TUPLE);
    const after = freezeAuthorityTuple({ ...BASE_TUPLE, identityParserVersion: "parser-1" });
    expect(() => assertAuthorityTupleUnchanged(before, after)).toThrow(
      AuthorityTupleMismatchError,
    );
  });

  test("reports every changed field, not just the first", () => {
    const before = freezeAuthorityTuple(BASE_TUPLE);
    const after = freezeAuthorityTuple({
      ...BASE_TUPLE,
      catalogVersion: "catalog-v2-forged",
      ocrVersion: "ocr-2-forged",
    });
    try {
      assertAuthorityTupleUnchanged(before, after);
      fail("expected assertAuthorityTupleUnchanged to throw");
    } catch (err) {
      expect((err as AuthorityTupleMismatchError).changedFields).toEqual([
        "catalogVersion",
        "ocrVersion",
      ]);
    }
  });
});
