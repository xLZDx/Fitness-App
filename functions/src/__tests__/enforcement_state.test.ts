/**
 * `enforcement_state.ts`'s own check logic, exercised entirely through its
 * injectable `deps` seam -- no live GCP credentials or network access, same
 * principle `canary_probe.ts`'s emulator-env-var tests use.
 */
import {
  runEnforcementStateProbe,
  _internal,
  type JsonFetchResult,
} from "../enforcement_state";

const okJson = (json: unknown): JsonFetchResult => ({ ok: true, status: 200, json });
const failJson = (status: number, errorText: string): JsonFetchResult => ({
  ok: false,
  status,
  json: null,
  errorText,
});

describe("runEnforcementStateProbe — overall status computation", () => {
  test("OK when every section reads cleanly", async () => {
    const fetchJson = jest.fn().mockResolvedValue(okJson({}));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.status).toBe("OK");
    expect(result.sections.functions.status).toBe("OK");
    expect(result.sections.firestoreRules.status).toBe("OK");
    expect(result.sections.appCheck.status).toBe("OK");
    expect(result.sections.identityToolkit.status).toBe("OK");
  });

  test("DEGRADED when some but not all sections fail", async () => {
    const fetchJson = jest
      .fn()
      // functions
      .mockResolvedValueOnce(okJson({ functions: [] }))
      // firestoreRules -- fails
      .mockResolvedValueOnce(failJson(503, "synthetic: Firestore Rules API unavailable"))
      // appCheck
      .mockResolvedValueOnce(okJson({ services: [] }))
      // identityToolkit
      .mockResolvedValueOnce(okJson({}));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.status).toBe("DEGRADED");
    expect(result.sections.firestoreRules.status).toBe("UNAVAILABLE");
    expect(result.sections.firestoreRules.error).toMatch(/503/);
    expect(result.sections.functions.status).toBe("OK");
  });

  test("FAILED when every section fails", async () => {
    const fetchJson = jest.fn().mockResolvedValue(failJson(500, "synthetic: every API down"));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.status).toBe("FAILED");
  });

  test("FAILED, not a crash, when the access token itself cannot be obtained", async () => {
    const fetchJson = jest.fn();
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => {
        throw new Error("synthetic: no ambient credentials");
      },
      fetchJson,
    });
    expect(result.status).toBe("FAILED");
    expect(result.sections.functions.error).toMatch(/no access token/);
    // No section attempted a real call once the token itself was unobtainable.
    expect(fetchJson).not.toHaveBeenCalled();
  });

  test("a section whose fetcher itself throws (not just returns ok:false) still degrades cleanly", async () => {
    const fetchJson = jest
      .fn()
      .mockRejectedValueOnce(new Error("synthetic: network reset")) // functions
      .mockResolvedValueOnce(okJson({ releases: [] }))
      .mockResolvedValueOnce(okJson({ services: [] }))
      .mockResolvedValueOnce(okJson({}));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.status).toBe("DEGRADED");
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
  });
});

describe("runEnforcementStateProbe — section extraction shape", () => {
  test("functions section extracts name/state/environment/updateTime/revision, sorted by name", async () => {
    const fetchJson = jest.fn().mockResolvedValueOnce(
      okJson({
        functions: [
          {
            name: "projects/p/locations/europe-west1/functions/zebra",
            state: "ACTIVE",
            environment: "GEN_2",
            updateTime: "2026-08-01T00:00:00Z",
            serviceConfig: { revision: "zebra-00001-abc" },
          },
          {
            name: "projects/p/locations/europe-west1/functions/apple",
            state: "ACTIVE",
            environment: "GEN_2",
            updateTime: "2026-08-02T00:00:00Z",
            serviceConfig: { revision: "apple-00003-xyz" },
          },
        ],
      }),
    ).mockResolvedValue(okJson({}));

    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.data?.count).toBe(2);
    const names = (result.sections.functions.data?.functions as Array<{ name: string }>).map(
      (f) => f.name,
    );
    expect(names).toEqual(["apple", "zebra"]);
  });

  test("firestore rules section extracts release/ruleset/updateTime", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson({ functions: [] }))
      .mockResolvedValueOnce(
        okJson({
          releases: [
            {
              name: "projects/p/releases/cloud.firestore",
              rulesetName: "projects/p/rulesets/abc123",
              updateTime: "2026-08-01T00:00:00Z",
            },
          ],
        }),
      )
      .mockResolvedValue(okJson({}));

    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.firestoreRules.data).toEqual({
      count: 1,
      releases: [
        { release: "cloud.firestore", ruleset: "abc123", updateTime: "2026-08-01T00:00:00Z" },
      ],
    });
  });

  test("firestore rules and identity toolkit calls carry the X-Goog-User-Project header", async () => {
    const fetchJson = jest.fn().mockResolvedValue(okJson({}));
    await runEnforcementStateProbe({ getAccessToken: async () => "fake-token", fetchJson });

    const rulesCall = fetchJson.mock.calls.find(([url]) =>
      String(url).includes("firebaserules"),
    );
    expect(rulesCall?.[2]).toEqual({ "X-Goog-User-Project": "fitness-app-korostelev" });

    const idtCall = fetchJson.mock.calls.find(([url]) =>
      String(url).includes("identitytoolkit"),
    );
    expect(idtCall?.[2]).toEqual({ "X-Goog-User-Project": "fitness-app-korostelev" });
  });
});

describe("extractIdentityToolkitState — secret-shaped fields never pass through", () => {
  test("hashConfig (signerKey) and client.apiKey are never present in the extracted output", () => {
    const raw = {
      signIn: {
        anonymous: { enabled: true },
        hashConfig: {
          algorithm: "SCRYPT",
          signerKey: "super-secret-signer-key-value",
          saltSeparator: "Bw==",
          rounds: 8,
          memoryCost: 14,
        },
      },
      client: { apiKey: "AIzaSy-fake-secret-web-api-key", firebaseSubdomain: "x" },
      mfa: { state: "DISABLED" },
      multiTenant: { allowTenants: false },
      authorizedDomains: ["localhost", "fitness-app-korostelev.firebaseapp.com"],
      smsRegionConfig: { allowlistOnly: { allowedRegions: [] } },
      emailPrivacyConfig: { enableImprovedEmailPrivacy: true },
      monitoring: { requestLogging: { enabled: false } },
    };

    const extracted = _internal.extractIdentityToolkitState(raw);
    const serialized = JSON.stringify(extracted);

    expect(serialized).not.toContain("super-secret-signer-key-value");
    expect(serialized).not.toContain("AIzaSy-fake-secret-web-api-key");
    expect(serialized).not.toContain("signerKey");
    expect(serialized).not.toContain("apiKey");

    expect(extracted.anonymousEnabled).toBe(true);
    expect(extracted.mfaState).toBe("DISABLED");
    expect(extracted.authorizedDomainsCount).toBe(2);
    expect(extracted.signInMethodsConfigured).toEqual(["anonymous"]);
  });

  test("missing/malformed input degrades to nulls, never throws", () => {
    expect(() => _internal.extractIdentityToolkitState({})).not.toThrow();
    const extracted = _internal.extractIdentityToolkitState({});
    expect(extracted.anonymousEnabled).toBeNull();
    expect(extracted.authorizedDomainsCount).toBeNull();
    expect(extracted.signInMethodsConfigured).toEqual([]);
  });
});

describe("overallStatus", () => {
  const ok = { status: "OK" as const };
  const bad = { status: "UNAVAILABLE" as const, error: "x" };

  test("all OK -> OK", () => {
    expect(
      _internal.overallStatus({
        functions: ok,
        firestoreRules: ok,
        appCheck: ok,
        identityToolkit: ok,
      }),
    ).toBe("OK");
  });

  test("one UNAVAILABLE -> DEGRADED", () => {
    expect(
      _internal.overallStatus({
        functions: ok,
        firestoreRules: bad,
        appCheck: ok,
        identityToolkit: ok,
      }),
    ).toBe("DEGRADED");
  });

  test("all UNAVAILABLE -> FAILED", () => {
    expect(
      _internal.overallStatus({
        functions: bad,
        firestoreRules: bad,
        appCheck: bad,
        identityToolkit: bad,
      }),
    ).toBe("FAILED");
  });
});
