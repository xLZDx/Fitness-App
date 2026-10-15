/**
 * USDA FoodData Central client (design s17.4, s17.5, D-65).
 *
 * Data is CC0 1.0. Generic whole foods come from the Foundation and SR Legacy
 * data types; a barcode fallback queries Branded foods and keeps only an exact
 * `gtinUpc` match.
 *
 * The API key is a REGISTERED key held in Secret Manager (`USDA_FDC_API_KEY`)
 * and read here at runtime (never `defineSecret`, never in code, never in a
 * query string): it travels in the `X-Api-Key` header via `safeFetch`. The
 * public `DEMO_KEY` (30 requests/hour per IP, intermittently failing) is never
 * used. When the secret is absent or unreadable `getUsdaApiKey` resolves `null`
 * and callers SKIP USDA -- a missing secret is "source not configured", not a
 * deploy or request failure.
 */
import { SecretManagerServiceClient } from "@google-cloud/secret-manager";
import * as logger from "firebase-functions/logger";
import { sanitiseDisplayText } from "../food_text";
import { withBreaker } from "../nutrition_breaker";
import { USDA_SECRET_ID } from "../nutrition_config";
import { safeFetch, UpstreamError } from "../nutrition_http";
import { normaliseUsdaNutrients, toFiniteNumber } from "../nutrition_normalise";
import type { FoodCandidate, SourceDeps } from "./types";

export const USDA_PAGE_SIZE = 10;
const MAX_BRAND = 40;

export const USDA_ATTRIBUTION = {
  source: "USDA FoodData Central",
  licence: "CC0 1.0",
  url: "https://fdc.nal.usda.gov/",
} as const;

// ---------------------------------------------------------------------------
// API key (Secret Manager, runtime read)
// ---------------------------------------------------------------------------

let secretClient: SecretManagerServiceClient | undefined;
let cachedKey: { value: string | null; expiresAtMs: number } | undefined;

/** A present key is reused for 10 minutes; an absent one is re-checked after 1 minute (an operator may add it). */
const KEY_TTL_MS = 10 * 60 * 1000;
const ABSENT_TTL_MS = 60 * 1000;

function secretVersionName(): string {
  const project = process.env.GCLOUD_PROJECT ?? "fitness-app-korostelev";
  return `projects/${project}/secrets/${USDA_SECRET_ID}/versions/latest`;
}

/** Test seam: the key cache is module-scope. */
export function __resetUsdaKeyForTests(): void {
  cachedKey = undefined;
  secretClient = undefined;
}

/**
 * The registered USDA key, or `null` when the secret does not exist, is empty
 * or cannot be read (logged by slug only; the error text can embed the secret
 * path). Never throws.
 */
export async function getUsdaApiKey(nowMs: number = Date.now()): Promise<string | null> {
  if (cachedKey && cachedKey.expiresAtMs > nowMs) return cachedKey.value;
  let value: string | null = null;
  try {
    secretClient ??= new SecretManagerServiceClient();
    const [version] = await secretClient.accessSecretVersion({ name: secretVersionName() });
    const payload = version.payload?.data?.toString().trim();
    value = payload ? payload : null;
  } catch (e) {
    const code = (e as { code?: unknown } | null)?.code;
    // 5 = NOT_FOUND: the expected "not configured yet" state, not worth a log line.
    if (code !== 5) logger.warn("usda_key_unreadable", { code: typeof code === "number" ? code : "unknown" });
    value = null;
  }
  cachedKey = { value, expiresAtMs: nowMs + (value ? KEY_TTL_MS : ABSENT_TTL_MS) };
  return value;
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

function asRecord(v: unknown): Record<string, unknown> | undefined {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;
}

function parseJson(body: string): unknown {
  try {
    return JSON.parse(body);
  } catch {
    return undefined;
  }
}

/** Maps one USDA search row to a candidate; `null` when it has no usable nutrition. */
export function mapUsdaFood(raw: unknown): FoodCandidate | null {
  const food = asRecord(raw);
  if (!food) return null;
  const fdcId = toFiniteNumber(food.fdcId);
  if (fdcId === undefined || !Number.isInteger(fdcId) || fdcId <= 0) return null;
  const nutrition = normaliseUsdaNutrients(food.foodNutrients);
  if (!nutrition) return null;
  const name = sanitiseDisplayText(food.description);
  if (name === "") return null;
  const brand = sanitiseDisplayText(food.brandName ?? food.brandOwner, MAX_BRAND);
  const unit = typeof food.servingSizeUnit === "string" ? food.servingSizeUnit.toLowerCase() : "";
  const serving = toFiniteNumber(food.servingSize);

  const out: FoodCandidate = {
    foodRef: `usda:${fdcId}`,
    name,
    per100g: nutrition.per100g,
    source: "usda_fdc",
    sourceRef: String(fdcId),
    completeness: nutrition.dataQuality,
  };
  if (brand) out.brand = brand;
  if ((unit === "g" || unit === "ml") && serving !== undefined && serving > 0 && serving <= 3000) out.servingG = serving;
  if (nutrition.derivedEnergy) out.derivedEnergy = true;
  return out;
}

async function searchRaw(
  apiKey: string,
  query: Record<string, string | number>,
  deps: SourceDeps,
): Promise<unknown[]> {
  return withBreaker("usda", deps.now ?? Date.now, async () => {
    const res = await safeFetch(
      {
        host: "api.nal.usda.gov",
        pathSegments: ["fdc", "v1", "foods", "search"],
        query,
        headers: { "X-Api-Key": apiKey, Accept: "application/json" },
        timeoutMs: deps.timeoutMs,
      },
      { fetchImpl: deps.fetchImpl },
    );
    // 400/403 mean our key or request is wrong: an upstream failure, never "no such food".
    if (res.status !== 200) throw new UpstreamError("upstream-unavailable");
    const foods = asRecord(parseJson(res.body))?.foods;
    return Array.isArray(foods) ? foods : [];
  });
}

/** Generic whole-food search over Foundation and SR Legacy. Throws `UpstreamError` on upstream failure. */
export async function searchUsda(apiKey: string, query: string, deps: SourceDeps = {}): Promise<FoodCandidate[]> {
  const foods = await searchRaw(
    apiKey,
    { query, dataType: "Foundation,SR Legacy", pageSize: USDA_PAGE_SIZE },
    deps,
  );
  const out: FoodCandidate[] = [];
  for (const f of foods) {
    const c = mapUsdaFood(f);
    if (c) out.push(c);
  }
  return out;
}

const stripLeadingZeros = (s: string): string => s.replace(/^0+/, "");

/**
 * Branded lookup by barcode: the search is text-based, so only a food whose
 * `gtinUpc` EQUALS the barcode (leading zeros are not significant between
 * UPC-A and EAN-13) is accepted. `null` when none matches.
 */
export async function lookupUsdaByGtin(
  apiKey: string,
  barcode: string,
  deps: SourceDeps = {},
): Promise<FoodCandidate | null> {
  const foods = await searchRaw(apiKey, { query: barcode, dataType: "Branded", pageSize: 5 }, deps);
  const want = stripLeadingZeros(barcode);
  for (const f of foods) {
    const rec = asRecord(f);
    const gtin = typeof rec?.gtinUpc === "string" ? stripLeadingZeros(rec.gtinUpc) : "";
    if (gtin === "" || gtin !== want) continue;
    const c = mapUsdaFood(f);
    if (c) return c;
  }
  return null;
}
