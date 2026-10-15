/**
 * `safeFetch` -- the ONE outbound HTTP helper for the nutrition data sources
 * (design s7.9, D-65). Every upstream call from `lookupBarcode`, `searchFoods`
 * and the USDA/OFF enrichment goes through it, so the defences below cannot be
 * forgotten at one call site.
 *
 *  - The URL is built with `URL` and `URLSearchParams`, never by string
 *    concatenation: a query term such as `x&api_key=evil` stays ONE percent-
 *    encoded parameter value, and a path segment such as `../x` stays one
 *    encoded segment.
 *  - The host is a fixed allowlist constant; the caller names one of the
 *    allowed hosts, it never supplies a URL.
 *  - `redirect: "manual"`: a redirect is followed only to the SAME host over
 *    https (at most `MAX_REDIRECTS` hops), otherwise it is rejected.
 *  - A request timeout (5 s default, covering the body read) and a response
 *    body cap (1 MiB): a larger body is aborted and treated as an upstream
 *    failure.
 *  - Credentials travel in headers (the USDA key goes in `X-Api-Key`, never the
 *    query string), and every failure is mapped to a closed slug BEFORE it can
 *    be logged: an `UpstreamError` carries the slug and nothing else -- no
 *    URL, key, header or body.
 *
 * No module-scope state, and the `fetch` implementation is injectable, so the
 * helper is testable without a network.
 */

/** The only hosts the nutrition sources may reach. */
export const NUTRITION_HOSTS = [
  "world.openfoodfacts.org",
  "search.openfoodfacts.org",
  "api.nal.usda.gov",
] as const;
export type NutritionHost = (typeof NUTRITION_HOSTS)[number];

/** The closed set of upstream failure slugs (the only thing ever logged). */
export const UPSTREAM_ERROR_SLUGS = [
  "upstream-host-not-allowed",
  "upstream-timeout",
  "upstream-unreachable",
  "upstream-rate-limited",
  "upstream-unavailable",
  "upstream-redirect-rejected",
  "upstream-too-large",
  "upstream-invalid-request",
] as const;
export type UpstreamErrorSlug = (typeof UPSTREAM_ERROR_SLUGS)[number];

/** An upstream failure. `message` IS the slug; there is no other field. */
export class UpstreamError extends Error {
  readonly slug: UpstreamErrorSlug;
  constructor(slug: UpstreamErrorSlug) {
    super(slug);
    this.name = "UpstreamError";
    this.slug = slug;
  }
}

export const DEFAULT_TIMEOUT_MS = 5_000;
export const MAX_BODY_BYTES = 1024 * 1024;
export const MAX_REDIRECTS = 3;

export interface SafeFetchRequest {
  host: NutritionHost;
  /** Path segments, each percent-encoded by this helper (no slashes inside). */
  pathSegments: readonly string[];
  /** Query parameters; `undefined` values are skipped. */
  query?: Readonly<Record<string, string | number | undefined>>;
  /** Request headers, e.g. `User-Agent` or `X-Api-Key`. Never put keys in `query`. */
  headers?: Readonly<Record<string, string>>;
  timeoutMs?: number;
  maxBytes?: number;
}

export interface SafeFetchResult {
  /** Final HTTP status; 429 and 5xx never reach the caller (they throw). */
  status: number;
  /** Response body decoded as UTF-8 (at most `maxBytes`). */
  body: string;
}

export interface SafeFetchDeps {
  fetchImpl?: typeof fetch;
}

/** Builds the request URL. Exported for tests; throws for a host off the allowlist. */
export function buildUrl(req: Pick<SafeFetchRequest, "host" | "pathSegments" | "query">): URL {
  if (!(NUTRITION_HOSTS as readonly string[]).includes(req.host)) {
    throw new UpstreamError("upstream-host-not-allowed");
  }
  // A dot segment is the one thing percent-encoding cannot neutralise: the URL
  // parser treats "..", "." and their %2e forms as path navigation and would
  // silently collapse the path ("/fdc/../x" -> "/x"). No caller has a legitimate
  // reason to send one, so it is refused rather than normalised.
  if (req.pathSegments.some((s) => s === "." || s === "..")) {
    throw new UpstreamError("upstream-invalid-request");
  }
  const url = new URL(`https://${req.host}`);
  url.pathname = "/" + req.pathSegments.map((s) => encodeURIComponent(s)).join("/");
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(req.query ?? {})) {
    if (v !== undefined) params.append(k, String(v));
  }
  url.search = params.toString();
  return url;
}

/** Reads at most `maxBytes` of the body; throws `upstream-too-large` beyond that. */
async function readCapped(res: Response, maxBytes: number): Promise<string> {
  const declared = Number(res.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new UpstreamError("upstream-too-large");
  }
  const reader = res.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw new UpstreamError("upstream-too-large");
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString("utf8");
}

export async function safeFetch(
  req: SafeFetchRequest,
  deps: SafeFetchDeps = {},
): Promise<SafeFetchResult> {
  const doFetch = deps.fetchImpl ?? fetch;
  const maxBytes = req.maxBytes ?? MAX_BODY_BYTES;
  const first = buildUrl(req);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), req.timeoutMs ?? DEFAULT_TIMEOUT_MS);
  try {
    let url = first;
    for (let hop = 0; ; hop++) {
      let res: Response;
      try {
        res = await doFetch(url.toString(), {
          method: "GET",
          headers: req.headers ? { ...req.headers } : undefined,
          redirect: "manual",
          signal: controller.signal,
        });
      } catch {
        throw new UpstreamError(controller.signal.aborted ? "upstream-timeout" : "upstream-unreachable");
      }

      if (res.status >= 300 && res.status < 400) {
        const location = res.headers.get("location");
        await res.body?.cancel().catch(() => undefined);
        if (!location || hop >= MAX_REDIRECTS) throw new UpstreamError("upstream-redirect-rejected");
        let next: URL;
        try {
          next = new URL(location, url);
        } catch {
          throw new UpstreamError("upstream-redirect-rejected");
        }
        if (next.protocol !== "https:" || next.hostname !== first.hostname) {
          throw new UpstreamError("upstream-redirect-rejected");
        }
        url = next;
        continue;
      }

      if (res.status === 429) {
        await res.body?.cancel().catch(() => undefined);
        throw new UpstreamError("upstream-rate-limited");
      }
      if (res.status >= 500) {
        await res.body?.cancel().catch(() => undefined);
        throw new UpstreamError("upstream-unavailable");
      }

      try {
        return { status: res.status, body: await readCapped(res, maxBytes) };
      } catch (e) {
        if (e instanceof UpstreamError) throw e;
        throw new UpstreamError(controller.signal.aborted ? "upstream-timeout" : "upstream-unreachable");
      }
    }
  } finally {
    clearTimeout(timer);
  }
}
