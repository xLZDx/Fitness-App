import { REGION, APP_CHECK_ENFORCED, EQUIPMENT_IDENTITY_CALLABLE_OPTIONS } from "../callable_options";

describe("EQUIPMENT_IDENTITY_CALLABLE_OPTIONS -- the single source both callables share", () => {
  test("region matches the default codebase's own REGION constant", () => {
    expect(REGION).toBe("europe-west1");
  });

  test("is exactly {region, enforceAppCheck} -- no other option drifts in silently", () => {
    expect(EQUIPMENT_IDENTITY_CALLABLE_OPTIONS).toEqual({
      region: REGION,
      enforceAppCheck: APP_CHECK_ENFORCED,
    });
    expect(Object.keys(EQUIPMENT_IDENTITY_CALLABLE_OPTIONS).sort()).toEqual(["enforceAppCheck", "region"]);
  });
});
