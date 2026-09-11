import {
  AppCheckPlatformReadinessStatusSchema,
  loadAppCheckPlatformReadiness,
  resolveAppCheckEnforcement,
  resolveReadinessArtifact,
  isAppCheckEnforcedForLane,
} from "../app_check_readiness";

describe("resolveReadinessArtifact -- fail-closed consumption", () => {
  it("accepts a valid artifact and returns it unchanged", () => {
    const valid = {
      schemaVersion: 1,
      status: "READY_FOR_SHADOW",
      updatedAt: "2026-09-10T00:00:00Z",
      evidenceRef: "some evidence",
    };
    expect(resolveReadinessArtifact(valid)).toEqual(valid);
  });

  it("fails closed on undefined (simulates a missing/unreadable artifact)", () => {
    const result = resolveReadinessArtifact(undefined);
    expect(result.status).toBe("BLOCKED_EXTERNAL_PLATFORM_MIGRATION");
    expect(result.evidenceRef).toMatch(/^fail-closed:/);
  });

  it("fails closed on a malformed object missing required fields", () => {
    const result = resolveReadinessArtifact({ status: "READY_FOR_PRODUCTION" });
    expect(result.status).toBe("BLOCKED_EXTERNAL_PLATFORM_MIGRATION");
    expect(result.evidenceRef).toMatch(/^fail-closed:/);
  });

  it("fails closed on an unknown/invalid status string", () => {
    const result = resolveReadinessArtifact({
      schemaVersion: 1,
      status: "SOMETHING_ELSE_ENTIRELY",
      updatedAt: "2026-09-10T00:00:00Z",
      evidenceRef: "x",
    });
    expect(result.status).toBe("BLOCKED_EXTERNAL_PLATFORM_MIGRATION");
    expect(result.evidenceRef).toMatch(/^fail-closed:/);
  });

  it("fails closed on a status that is a lowercase/near-miss variant of a real value", () => {
    const result = resolveReadinessArtifact({
      schemaVersion: 1,
      status: "ready_for_production",
      updatedAt: "2026-09-10T00:00:00Z",
      evidenceRef: "x",
    });
    expect(result.status).toBe("BLOCKED_EXTERNAL_PLATFORM_MIGRATION");
  });
});

describe("loadAppCheckPlatformReadiness -- real synced artifact", () => {
  it("loads the real generated copy, currently BLOCKED_EXTERNAL_PLATFORM_MIGRATION", () => {
    // This is a live assertion against the tracked P0 artifact, not a
    // fixture: it will (correctly) start failing the day someone updates
    // core/equipment_identity/p0/p0_g0_app_check_platform_readiness.json
    // to a READY_* value without updating this test -- exactly the
    // "P0.G0 stays BLOCKED, decision log/tests must say so explicitly"
    // discipline the plan's own binding DoD requires.
    const artifact = loadAppCheckPlatformReadiness();
    expect(artifact.status).toBe("BLOCKED_EXTERNAL_PLATFORM_MIGRATION");
    expect(AppCheckPlatformReadinessStatusSchema.safeParse(artifact.status).success).toBe(true);
  });
});

describe("resolveAppCheckEnforcement -- 3 states x 2 lanes", () => {
  const STATES = [
    "BLOCKED_EXTERNAL_PLATFORM_MIGRATION",
    "READY_FOR_SHADOW",
    "READY_FOR_PRODUCTION",
  ] as const;

  it.each(STATES)("SHADOW lane is always unenforced under status=%s", (status) => {
    expect(resolveAppCheckEnforcement(status, "SHADOW")).toBe(false);
  });

  it("PRODUCTION lane is unenforced under BLOCKED_EXTERNAL_PLATFORM_MIGRATION", () => {
    expect(
      resolveAppCheckEnforcement("BLOCKED_EXTERNAL_PLATFORM_MIGRATION", "PRODUCTION"),
    ).toBe(false);
  });

  it("PRODUCTION lane is unenforced under READY_FOR_SHADOW (never independently asserted true)", () => {
    expect(resolveAppCheckEnforcement("READY_FOR_SHADOW", "PRODUCTION")).toBe(false);
  });

  it("PRODUCTION lane is enforced only under READY_FOR_PRODUCTION", () => {
    expect(resolveAppCheckEnforcement("READY_FOR_PRODUCTION", "PRODUCTION")).toBe(true);
  });
});

describe("isAppCheckEnforcedForLane -- end-to-end against the real tracked artifact", () => {
  it("PRODUCTION is not enforced today, because P0.G0 is still BLOCKED", () => {
    expect(isAppCheckEnforcedForLane("PRODUCTION")).toBe(false);
  });

  it("SHADOW is not enforced today either", () => {
    expect(isAppCheckEnforcedForLane("SHADOW")).toBe(false);
  });
});
