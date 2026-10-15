/**
 * Open Food Facts client (design s17.4, s17.5, D-64, D-65).
 *
 * Every call goes through `safeFetch` (fixed hosts, `URL`/`URLSearchParams`, no
 * redirects off-host, timeout, body cap), behind a per-instance breaker and the
 * GLOBAL per-minute budget (`nutrition_budget.ts`): a call that cannot win a
 * budget slot never leaves the process. `User-Agent: FitnessApp/<v> (<contact>)`
 * is mandatory per OFF policy and comes from config.
 *
 * Behavioural notes re-authored from OFF's public API documentation and the
 * researcher's live checks (FINDINGS 2026-10-15); `OpenNutriTracker` (GPL-3.0)
 * was read as a design reference only (Search-a-licious primary, legacy
 * `cgi/search.pl` as fallback, breaker) and nothing was pasted from it.
 *
 *  - Product: `GET /api/v3/product/<barcode>.json?fields=...` (v2 is deprecated).
 *    `serving_size` can be ABSENT; per-100 g values come from `<n>_100g` only.
 *  - Search: Search-a-licious first; when it is down (timeout / unreachable /
 *    5xx) the legacy endpoint answers instead. A 429 stops the chain.
 *
 * Data licence: ODbL 1.0 (database), DbCL 1.0 (contents); images (CC BY-SA) are
 * not used. Attribute "Open Food Facts".
 */
import { sanitiseDisplayText } from "../food_text";
import { withBreaker } from "../nutrition_breaker";
import { takeUpstreamBudget } from "../nutrition_budget";
import { offUserAgent } from "../nutrition_config";
import { safeFetch, UpstreamError } from "../nutrition_http";
import { normaliseOffNutriments, toFiniteNumber } from "../nutrition_normalise";
import type { FoodCandidate, SourceDeps } from "./types";

export const OFF_PRODUCT_FIELDS =
  "code,product_name,brands,quantity,product_quantity,serving_size,serving_quantity,nutrition_data_per,nutriments";
const SEARCH_FIELDS = "code,product_name,brands,serving_size,serving_quantity,nutriments";
export const OFF_PAGE_SIZE = 20;
const MAX_BRAND = 40;

export const OFF_ATTRIBUTION = {
  source: "Open Food Facts",
  licence: "ODbL 1.0 (database), DbCL 1.0 (contents)",
  url: "https://world.openfoodfacts.org/",
} as const;

function clock(deps: SourceDeps): () => number {
  return deps.now ?? Date.now;
}

function headers(): Record<string, string> {
  return { "User-Agent": offUserAgent(), Accept: "application/json" };
}

/** Takes a global budget slot or throws the calm `upstream-unavailable` (no network call is made). */
async function takeSlot(kind: "read" | "search", deps: SourceDeps): Promise<void> {
  const ok = await (deps.takeBudget ?? ((k) => takeUpstreamBudget(k, clock(deps)())))(kind);
  if (!ok) throw new UpstreamError("upstream-unavailable");
}

function parseJson(body: string): unknown {
  try {
    return JSON.parse(body);
  } catch {
    return undefined;
  }
}

function asRecord(v: unknown): Record<string, unknown> | undefined {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;
}

/** "30 g", "250,5 ml" -> grams (1 ml = 1 g), else `undefined`. */
export function servingGramsFromText(text: unknown): number | undefined {
  if (typeof text !== "string") return undefined;
  const m = /(\d+(?:[.,]\d+)?)\s*(g|gr|ml|г|мл)(?![\p{L}\p{N}])/iu.exec(text);
  if (!m) return undefined;
  const n = Number(m[1].replace(",", "."));
  return Number.isFinite(n) && n > 0 && n <= 3000 ? n : undefined;
}

/** Maps one OFF record (product or search hit) to a candidate; `null` when no usable nutrition. */
export function mapOffRecord(raw: unknown): FoodCandidate | null {
  const rec = asRecord(raw);
  if (!rec) return null;
  const code = typeof rec.code === "string" ? rec.code : typeof rec.code === "number" ? String(rec.code) : "";
  if (!/^\d{8,14}$/.test(code)) return null;
  const nutrition = normaliseOffNutriments(rec.nutriments);
  if (!nutrition) return null;

  const brandsRaw = Array.isArray(rec.brands) ? rec.brands.join(", ") : rec.brands;
  const brand = sanitiseDisplayText(typeof brandsRaw === "string" ? brandsRaw.split(",")[0] : "", MAX_BRAND);
  const name = sanitiseDisplayText(rec.product_name) || brand || "Product";
  const servingG = toFiniteNumber(rec.serving_quantity) ?? servingGramsFromText(rec.serving_size);

  const out: FoodCandidate = {
    foodRef: `off:${code}`,
    name,
    per100g: nutrition.per100g,
    source: "open_food_facts",
    sourceRef: code,
    completeness: nutrition.dataQuality,
  };
  if (brand) out.brand = brand;
  if (servingG !== undefined && servingG > 0 && servingG <= 3000) out.servingG = servingG;
  if (nutrition.derivedEnergy) out.derivedEnergy = true;
  return out;
}

export type OffProductResult =
  | { status: "found"; candidate: FoodCandidate }
  /** OFF has no such product. */
  | { status: "not_found" }
  /** OFF knows the product but its nutrition is missing or implausible. */
  | { status: "unusable" };

/** `GET /api/v3/product/<barcode>.json`. Throws `UpstreamError` on any upstream failure. */
export async function fetchOffProduct(barcode: string, deps: SourceDeps = {}): Promise<OffProductResult> {
  const now = clock(deps);
  return withBreaker("off_read", now, async () => {
    await takeSlot("read", deps);
    const res = await safeFetch(
      {
        host: "world.openfoodfacts.org",
        pathSegments: ["api", "v3", "product", `${barcode}.json`],
        query: { fields: OFF_PRODUCT_FIELDS },
        headers: headers(),
        timeoutMs: deps.timeoutMs,
      },
      { fetchImpl: deps.fetchImpl },
    );
    if (res.status === 404) return { status: "not_found" } as const;
    if (res.status !== 200) throw new UpstreamError("upstream-unavailable");
    const body = asRecord(parseJson(res.body));
    const product = asRecord(body?.product);
    if (!body || !product) return { status: "not_found" } as const;
    const candidate = mapOffRecord({ ...product, code: product.code ?? body.code });
    return candidate ? ({ status: "found", candidate } as const) : ({ status: "unusable" } as const);
  });
}

function mapHits(hits: unknown): FoodCandidate[] {
  if (!Array.isArray(hits)) return [];
  const out: FoodCandidate[] = [];
  for (const h of hits) {
    const c = mapOffRecord(h);
    if (c) out.push(c);
  }
  return out;
}

async function searchSearchALicious(query: string, lang: string, deps: SourceDeps): Promise<FoodCandidate[]> {
  return withBreaker("off_search", clock(deps), async () => {
    await takeSlot("search", deps);
    const res = await safeFetch(
      {
        host: "search.openfoodfacts.org",
        pathSegments: ["search"],
        query: { q: query, langs: `${lang},en`, page_size: OFF_PAGE_SIZE, fields: SEARCH_FIELDS },
        headers: headers(),
        timeoutMs: deps.timeoutMs,
      },
      { fetchImpl: deps.fetchImpl },
    );
    if (res.status !== 200) throw new UpstreamError("upstream-unavailable");
    return mapHits(asRecord(parseJson(res.body))?.hits);
  });
}

async function searchLegacy(query: string, deps: SourceDeps): Promise<FoodCandidate[]> {
  return withBreaker("off_legacy", clock(deps), async () => {
    await takeSlot("search", deps);
    const res = await safeFetch(
      {
        host: "world.openfoodfacts.org",
        pathSegments: ["cgi", "search.pl"],
        query: {
          search_terms: query,
          search_simple: 1,
          action: "process",
          json: 1,
          page_size: OFF_PAGE_SIZE,
          fields: SEARCH_FIELDS,
        },
        headers: headers(),
        timeoutMs: deps.timeoutMs,
      },
      { fetchImpl: deps.fetchImpl },
    );
    if (res.status !== 200) throw new UpstreamError("upstream-unavailable");
    return mapHits(asRecord(parseJson(res.body))?.products);
  });
}

/** Failures that mean "Search-a-licious is down", where the legacy endpoint may still answer. */
const FALLBACK_SLUGS: ReadonlySet<string> = new Set([
  "upstream-timeout",
  "upstream-unreachable",
  "upstream-unavailable",
]);

/** Text search: Search-a-licious, else the legacy endpoint. Throws `UpstreamError` when both fail. */
export async function searchOff(query: string, lang: string, deps: SourceDeps = {}): Promise<FoodCandidate[]> {
  try {
    return await searchSearchALicious(query, lang, deps);
  } catch (e) {
    if (!(e instanceof UpstreamError) || !FALLBACK_SLUGS.has(e.slug)) throw e;
    return searchLegacy(query, deps);
  }
}
