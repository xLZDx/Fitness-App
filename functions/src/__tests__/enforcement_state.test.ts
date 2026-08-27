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

const oneFunction = {
  functions: [
    {
      name: "projects/p/locations/europe-west1/functions/deleteAccount",
      state: "ACTIVE",
      environment: "GEN_2",
      updateTime: "2026-08-01T00:00:00Z",
      serviceConfig: { revision: "deleteaccount-00002-fac" },
    },
  ],
};
const oneRelease = {
  releases: [
    {
      name: "projects/p/releases/cloud.firestore",
      rulesetName: "projects/p/rulesets/abc123",
      updateTime: "2026-08-01T00:00:00Z",
    },
  ],
};
const emptyServices = { services: [] };
const validIdentityConfig = { name: "projects/p/config", signIn: { anonymous: { enabled: true } } };

/** The four calls this probe makes, in call order, all reading cleanly. */
function healthyFetchJson(): jest.Mock {
  return jest
    .fn()
    .mockResolvedValueOnce(okJson(oneFunction))
    .mockResolvedValueOnce(okJson(oneRelease))
    .mockResolvedValueOnce(okJson(emptyServices))
    .mockResolvedValueOnce(okJson(validIdentityConfig));
}

describe("runEnforcementStateProbe — overall status computation", () => {
  test("OK when every section reads cleanly", async () => {
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson: healthyFetchJson(),
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
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(failJson(503, "synthetic: Firestore Rules API unavailable"))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
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
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.status).toBe("DEGRADED");
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
  });
});

describe("runEnforcementStateProbe — fails closed on empty/malformed results (GPT-PM remediation)", () => {
  test("zero functions is UNAVAILABLE, not a silently-accepted empty success", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson({})) // no `functions` key at all
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/empty result/);
  });

  test("zero firestore rule releases is UNAVAILABLE", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(okJson({ releases: [] }))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.firestoreRules.status).toBe("UNAVAILABLE");
    expect(result.sections.firestoreRules.error).toMatch(/empty result/);
  });

  test("zero App Check services is still OK (a real, meaningful state for this project)", async () => {
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson: healthyFetchJson(),
    });
    expect(result.sections.appCheck.status).toBe("OK");
    expect(result.sections.appCheck.data?.count).toBe(0);
  });

  test("a 200 whose list key is present but not an array is UNAVAILABLE, not silently coerced", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson({ functions: "not-an-array" }))
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/not an array/);
  });

  test("a 200 whose body is not a JSON object is UNAVAILABLE", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson("this is not an object"))
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/not a JSON object/);
  });

  test("an Identity Toolkit config missing its own resource name is UNAVAILABLE", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson({ signIn: { anonymous: { enabled: true } } })); // no `name`
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.identityToolkit.status).toBe("UNAVAILABLE");
    expect(result.sections.identityToolkit.error).toMatch(/missing config resource name/);
  });
});

describe("runEnforcementStateProbe — pagination (GPT-PM remediation)", () => {
  test("follows nextPageToken across multiple pages and accumulates every item", async () => {
    const page1 = {
      functions: [
        {
          name: "projects/p/locations/x/functions/a",
          state: "ACTIVE",
          updateTime: "2026-08-01T00:00:00Z",
        },
      ],
      nextPageToken: "page-2-token",
    };
    const page2 = {
      functions: [
        {
          name: "projects/p/locations/x/functions/b",
          state: "ACTIVE",
          updateTime: "2026-08-01T00:00:00Z",
        },
      ],
    };
    // Sections run concurrently (Promise.all in runEnforcementStateProbe), so
    // the four sections' first-page calls interleave before any of them
    // resolves -- a positional mockResolvedValueOnce chain does not line up
    // with call order once one section makes more than one call. Dispatch on
    // the URL instead, which is stable regardless of interleaving.
    const fetchJson = jest.fn(async (url: string) => {
      if (url.includes("cloudfunctions.googleapis.com")) {
        return url.includes("pageToken=page-2-token") ? okJson(page2) : okJson(page1);
      }
      if (url.includes("firebaserules.googleapis.com")) return okJson(oneRelease);
      if (url.includes("firebaseappcheck.googleapis.com")) return okJson(emptyServices);
      if (url.includes("identitytoolkit.googleapis.com")) return okJson(validIdentityConfig);
      throw new Error(`unexpected URL in test: ${url}`);
    });
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("OK");
    expect(result.sections.functions.data?.count).toBe(2);
    // The second functions-section call must have carried page 1's token.
    const functionsCalls = fetchJson.mock.calls.filter(([url]) =>
      String(url).includes("cloudfunctions.googleapis.com"),
    );
    expect(functionsCalls.length).toBe(2);
    expect(functionsCalls[1][0]).toContain("pageToken=page-2-token");
  });

  test("a pagination loop that never terminates is UNAVAILABLE, not an infinite loop", async () => {
    const alwaysNextPage = { functions: [], nextPageToken: "same-token-forever" };
    const fetchJson = jest.fn().mockResolvedValue(okJson(alwaysNextPage));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/did not terminate/);
    // Bounded, not unbounded -- MAX_PAGES calls for this section, not more.
    const functionsCalls = fetchJson.mock.calls.filter(([url]) =>
      String(url).includes("cloudfunctions"),
    );
    expect(functionsCalls.length).toBeLessThanOrEqual(20);
  });
});

describe("runEnforcementStateProbe — section extraction shape", () => {
  test("functions section extracts name/state/environment/updateTime/revision, sorted by name", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(
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
      )
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));

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
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson: healthyFetchJson(),
    });
    expect(result.sections.firestoreRules.data).toEqual({
      count: 1,
      releases: [
        { release: "cloud.firestore", ruleset: "abc123", updateTime: "2026-08-01T00:00:00Z" },
      ],
    });
  });

  test("app check section derives anyEnforcementOff from the returned services", async () => {
    // "UNENFORCED" is the real API value (confirmed live during the round-2
    // remediation) -- round 1's code compared against "OFF", which no real
    // response ever returns, so this is also the regression test for that.
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(
        okJson({
          services: [
            { name: "projects/p/services/firestore.googleapis.com", enforcementMode: "ENFORCED" },
            { name: "projects/p/services/y", enforcementMode: "UNENFORCED" },
          ],
        }),
      )
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.appCheck.data?.anyEnforcementOff).toBe(true);
    // firestore.googleapis.com is explicitly ENFORCED here, so it must not
    // be reported as an unenforced intended service -- isolates this
    // assertion from the "y" service, which is the thing actually driving
    // anyEnforcementOff in this fixture.
    expect(result.sections.appCheck.data?.unenforcedIntendedServices).toEqual([]);
  });

  test("an App Check services list that never mentions firestore.googleapis.com "
    + "flags it as an unenforced intended service (GPT-PM round-2 remediation)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    // Still OK -- the read itself succeeded and the (empty) data is
    // structurally valid; see this file's own module header for why status
    // does not mean "the observed state is the desired one."
    expect(result.sections.appCheck.status).toBe("OK");
    expect(result.sections.appCheck.data?.unenforcedIntendedServices).toEqual([
      "firestore.googleapis.com",
    ]);
    expect(result.sections.appCheck.data?.anyEnforcementOff).toBe(true);
  });

  test("a function row missing its required state field is UNAVAILABLE, not \"?\" (GPT-PM round-2)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(
        okJson({ functions: [{ name: "projects/p/locations/x/functions/a" }] }), // no state
      )
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/name\/state/);
  });

  test("a rule release row missing its required rulesetName field is UNAVAILABLE (GPT-PM round-2)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(
        okJson({ releases: [{ name: "projects/p/releases/cloud.firestore" }] }), // no rulesetName
      )
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.firestoreRules.status).toBe("UNAVAILABLE");
    expect(result.sections.firestoreRules.error).toMatch(/name\/rulesetName/);
  });

  test("a non-empty releases list with no cloud.firestore release is UNAVAILABLE (GPT-PM round-2)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(
        okJson({
          releases: [
            {
              name: "projects/p/releases/some.other.release",
              rulesetName: "projects/p/rulesets/xyz",
              updateTime: "2026-08-01T00:00:00Z",
            },
          ],
        }),
      )
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.firestoreRules.status).toBe("UNAVAILABLE");
    expect(result.sections.firestoreRules.error).toMatch(/cloud\.firestore/);
    // Partial evidence is retained, not thrown away.
    expect(result.sections.firestoreRules.data?.count).toBe(1);
  });

  test("an App Check service row missing its required enforcementMode field is UNAVAILABLE (GPT-PM round-2)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson({ services: [{ name: "projects/p/services/x" }] })) // no enforcementMode
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.appCheck.status).toBe("UNAVAILABLE");
    expect(result.sections.appCheck.error).toMatch(/name\/enforcementMode/);
  });

  test("a non-empty unreachable[] on the Functions list makes the section UNAVAILABLE, "
    + "retaining what was read (GPT-PM round-2)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(
        okJson({ ...oneFunction, unreachable: ["projects/p/locations/us-central1"] }),
      )
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/unreachable/);
    expect(result.sections.functions.error).toContain("us-central1");
    expect(result.sections.functions.data?.count).toBe(1);
  });

  test("an already-exhausted probe deadline fails every section closed before any request (GPT-PM round-2)", async () => {
    // First call (computing `deadlineAt` in runEnforcementStateProbe) sees 0;
    // every call after that -- every section's own deadline check -- sees a
    // value already past the deadline, regardless of call order.
    let calls = 0;
    const now = () => (calls++ === 0 ? 0 : 100_000);
    const fetchJson = jest.fn();
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
      now,
    });
    expect(result.status).toBe("FAILED");
    for (const section of Object.values(result.sections)) {
      expect(section.status).toBe("UNAVAILABLE");
      expect(section.error).toMatch(/probe deadline exceeded/);
    }
    expect(fetchJson).not.toHaveBeenCalled();
  });

  test("a probe deadline that expires between pages stops issuing further page requests (GPT-PM round-2)", async () => {
    let expired = false;
    const now = () => (expired ? 999_999_999 : 0);
    const page1 = {
      functions: [{ name: "projects/p/locations/x/functions/a", state: "ACTIVE" }],
      nextPageToken: "page-2-token",
    };
    const fetchJson = jest.fn(async (url: string) => {
      if (url.includes("cloudfunctions.googleapis.com")) {
        if (url.includes("pageToken=page-2-token")) {
          throw new Error("should never reach page 2 -- the deadline must stop pagination first");
        }
        expired = true; // simulate the clock crossing the deadline while page 1 was "in flight"
        return okJson(page1);
      }
      if (url.includes("firebaserules.googleapis.com")) return okJson(oneRelease);
      if (url.includes("firebaseappcheck.googleapis.com")) return okJson(emptyServices);
      if (url.includes("identitytoolkit.googleapis.com")) return okJson(validIdentityConfig);
      throw new Error(`unexpected URL in test: ${url}`);
    });
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
      now,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/probe deadline exceeded/);
    const functionsCalls = fetchJson.mock.calls.filter(([url]) =>
      String(url).includes("cloudfunctions.googleapis.com"),
    );
    expect(functionsCalls.length).toBe(1);
  });

  test("a hung token acquisition is still bounded by the probe deadline (GPT-PM round-3)", async () => {
    const fetchJson = jest.fn();
    const result = await runEnforcementStateProbe({
      getAccessToken: () => new Promise<string>(() => {}), // never resolves
      fetchJson,
      // Forces the deadline branch to win deterministically -- no real
      // elapsed wall-clock wait, no fake system timers.
      raceDeadline: async (_promise, _remainingMs, label) => {
        throw new Error(`probe deadline exceeded during ${label}`);
      },
    });
    expect(result.status).toBe("FAILED");
    expect(result.sections.functions.error).toMatch(
      /probe deadline exceeded during token acquisition/,
    );
    // No section made it past token acquisition to attempt a real request.
    expect(fetchJson).not.toHaveBeenCalled();
  });

  test("an already-exhausted deadline fails token acquisition closed without racing at all (GPT-PM round-3)", async () => {
    let calls = 0;
    const now = () => (calls++ === 0 ? 0 : 100_000);
    const raceDeadline = jest.fn();
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson: jest.fn(),
      now,
      raceDeadline,
    });
    expect(result.status).toBe("FAILED");
    expect(result.sections.functions.error).toMatch(/probe deadline exceeded/);
    // The deadline was already gone before token acquisition even started --
    // raceDeadline itself is never reached, just like fetchJson.
    expect(raceDeadline).not.toHaveBeenCalled();
  });

  test("a cloud.firestore release with an invalid updateTime is UNAVAILABLE, not silently OK (GPT-PM round-3)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(okJson(oneFunction))
      .mockResolvedValueOnce(
        okJson({
          releases: [
            {
              name: "projects/p/releases/cloud.firestore",
              rulesetName: "projects/p/rulesets/abc123",
              updateTime: "not-a-real-timestamp",
            },
          ],
        }),
      )
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.firestoreRules.status).toBe("UNAVAILABLE");
    expect(result.sections.firestoreRules.error).toMatch(/invalid updateTime/);
    expect(result.sections.firestoreRules.data?.count).toBe(1);
  });

  test("a function row missing updateTime is UNAVAILABLE, not defaulted to \"?\" (GPT-PM round-3)", async () => {
    const fetchJson = jest
      .fn()
      .mockResolvedValueOnce(
        okJson({
          functions: [{ name: "projects/p/locations/x/functions/a", state: "ACTIVE" }], // no updateTime
        }),
      )
      .mockResolvedValueOnce(okJson(oneRelease))
      .mockResolvedValueOnce(okJson(emptyServices))
      .mockResolvedValueOnce(okJson(validIdentityConfig));
    const result = await runEnforcementStateProbe({
      getAccessToken: async () => "fake-token",
      fetchJson,
    });
    expect(result.sections.functions.status).toBe("UNAVAILABLE");
    expect(result.sections.functions.error).toMatch(/name\/state\/updateTime/);
  });

  test("firestore rules and identity toolkit calls carry the X-Goog-User-Project header", async () => {
    const fetchJson = healthyFetchJson();
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

  test("the App Check call also carries the X-Goog-User-Project header (remediation: confirmed live it needs it too)", async () => {
    const fetchJson = healthyFetchJson();
    await runEnforcementStateProbe({ getAccessToken: async () => "fake-token", fetchJson });

    const appCheckCall = fetchJson.mock.calls.find(([url]) =>
      String(url).includes("firebaseappcheck"),
    );
    expect(appCheckCall?.[2]).toEqual({ "X-Goog-User-Project": "fitness-app-korostelev" });
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

    const result = _internal.extractIdentityToolkitState(raw);
    if (!result.ok) throw new Error(`expected ok, got error: ${result.error}`);
    const serialized = JSON.stringify(result.value);

    expect(serialized).not.toContain("super-secret-signer-key-value");
    expect(serialized).not.toContain("AIzaSy-fake-secret-web-api-key");
    expect(serialized).not.toContain("signerKey");
    expect(serialized).not.toContain("apiKey");

    expect(result.value.anonymousEnabled).toBe(true);
    expect(result.value.mfaState).toBe("DISABLED");
    expect(result.value.authorizedDomainsCount).toBe(2);
    expect(result.value.signInMethodsConfigured).toEqual(["anonymous"]);
  });

  test("missing input degrades to nulls, never throws", () => {
    expect(() => _internal.extractIdentityToolkitState({})).not.toThrow();
    const result = _internal.extractIdentityToolkitState({});
    if (!result.ok) throw new Error(`expected ok, got error: ${result.error}`);
    expect(result.value.anonymousEnabled).toBeNull();
    expect(result.value.authorizedDomainsCount).toBeNull();
    expect(result.value.signInMethodsConfigured).toEqual([]);
    expect(result.value.multiTenantAllowTenants).toBeNull();
    expect(result.value.monitoringRequestLoggingEnabled).toBeNull();
    expect(result.value.smsRegionPolicy).toEqual({ mode: "NONE", regionCount: null });
  });

  // Round-4 (GPT-PM live-activation review): the extractor used to serialize whole
  // CONTAINER objects (`raw.multiTenant`, `raw.monitoring.requestLogging`,
  // `raw.smsRegionConfig.allowlistOnly`) instead of the actual nested scalar fields --
  // invisible against this project's own live data because every container happens to
  // be empty (`{}`) in this project's never-configured state, so these fixtures use
  // realistic NON-EMPTY API-shaped values to actually exercise the extraction depth,
  // confirmed against Google's Identity Platform / SMS-regions REST schema.
  test("extracts the real nested scalar fields, not their containers, when actually configured", () => {
    const raw = {
      multiTenant: { allowTenants: true, defaultTenantLocationRef: { locationId: "us-central1" } },
      monitoring: { requestLogging: { enabled: true } },
      smsRegionConfig: { allowlistOnly: { allowedRegions: ["US", "IN", "GB"] } },
    };
    const result = _internal.extractIdentityToolkitState(raw);
    if (!result.ok) throw new Error(`expected ok, got error: ${result.error}`);
    expect(result.value.multiTenantAllowTenants).toBe(true);
    expect(result.value.monitoringRequestLoggingEnabled).toBe(true);
    expect(result.value.smsRegionPolicy).toEqual({ mode: "ALLOWLIST_ONLY", regionCount: 3 });
  });

  test("multiTenant/monitoring container present but scalar false is preserved, not lost as falsy", () => {
    const raw = {
      multiTenant: { allowTenants: false },
      monitoring: { requestLogging: { enabled: false } },
    };
    const result = _internal.extractIdentityToolkitState(raw);
    if (!result.ok) throw new Error(`expected ok, got error: ${result.error}`);
    expect(result.value.multiTenantAllowTenants).toBe(false);
    expect(result.value.monitoringRequestLoggingEnabled).toBe(false);
  });

  // Round-4 PART 2 (GPT-PM round-5 review): a present-but-malformed value used to pass
  // through silently (e.g. a string coerced through `?? null` as-is) instead of failing
  // the section closed -- these fixtures simulate an upstream/proxy schema regression.
  test("multiTenant.allowTenants present but not a boolean -> fails closed, not silently coerced", () => {
    const result = _internal.extractIdentityToolkitState({ multiTenant: { allowTenants: "false" } });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("multiTenant.allowTenants");
  });

  test("monitoring.requestLogging.enabled present but not a boolean -> fails closed", () => {
    const result = _internal.extractIdentityToolkitState({ monitoring: { requestLogging: { enabled: {} } } });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("monitoring.requestLogging.enabled");
  });

  test("malformed nested smsRegionPolicy propagates as a whole-section failure", () => {
    const result = _internal.extractIdentityToolkitState({
      smsRegionConfig: { allowlistOnly: { allowedRegions: "US" } },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("allowedRegions");
  });
});

describe("extractSmsRegionPolicy — real oneof shape, never a bare container", () => {
  test("allowlistOnly mode reports the allowed-region count", () => {
    const result = _internal.extractSmsRegionPolicy({
      smsRegionConfig: { allowlistOnly: { allowedRegions: ["US", "IN"] } },
    });
    expect(result).toEqual({ ok: true, value: { mode: "ALLOWLIST_ONLY", regionCount: 2 } });
  });

  test("allowByDefault mode reports the disallowed-region count", () => {
    const result = _internal.extractSmsRegionPolicy({
      smsRegionConfig: { allowByDefault: { disallowedRegions: ["RU"] } },
    });
    expect(result).toEqual({ ok: true, value: { mode: "ALLOW_BY_DEFAULT", regionCount: 1 } });
  });

  test("no smsRegionConfig at all -> NONE with a null count, never throws", () => {
    expect(_internal.extractSmsRegionPolicy({})).toEqual({
      ok: true,
      value: { mode: "NONE", regionCount: null },
    });
  });

  test("empty allowlistOnly container (this project's real current state) -> ALLOWLIST_ONLY, count null", () => {
    // Confirmed live this round: this project's real smsRegionConfig.allowlistOnly is `{}`
    // (SMS regions never configured) -- `allowedRegions` is absent, not an empty array.
    const result = _internal.extractSmsRegionPolicy({ smsRegionConfig: { allowlistOnly: {} } });
    expect(result).toEqual({ ok: true, value: { mode: "ALLOWLIST_ONLY", regionCount: null } });
  });

  // Round-4 PART 2 (GPT-PM round-5 review): a present-but-malformed regions field, or
  // both oneof branches set at once, used to silently degrade to `regionCount: null` or
  // silently prefer allowlistOnly -- both are now explicit failures.
  test("allowedRegions present but not an array -> fails closed", () => {
    const result = _internal.extractSmsRegionPolicy({
      smsRegionConfig: { allowlistOnly: { allowedRegions: "US" } },
    });
    expect(result.ok).toBe(false);
  });

  test("allowedRegions array with a non-string element -> fails closed", () => {
    const result = _internal.extractSmsRegionPolicy({
      smsRegionConfig: { allowlistOnly: { allowedRegions: ["US", 42] } },
    });
    expect(result.ok).toBe(false);
  });

  test("disallowedRegions present but not an array -> fails closed", () => {
    const result = _internal.extractSmsRegionPolicy({
      smsRegionConfig: { allowByDefault: { disallowedRegions: { US: true } } },
    });
    expect(result.ok).toBe(false);
  });

  test("both allowlistOnly and allowByDefault set at once -> fails closed, never silently prefers one", () => {
    const result = _internal.extractSmsRegionPolicy({
      smsRegionConfig: {
        allowlistOnly: { allowedRegions: ["US"] },
        allowByDefault: { disallowedRegions: ["RU"] },
      },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toContain("both allowlistOnly and allowByDefault");
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
