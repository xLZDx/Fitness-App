/**
 * Signed, expiring URLs for the licensed exercise clips.
 *
 * WHY THIS EXISTS
 *
 * The vendor's written permission to host and stream their footage is
 * conditional, and the condition is exactly what our current bucket violates:
 *
 *   "users can only view them within your app and are not given access to the
 *    raw files, public storage folders, or permanent downloadable links."
 *
 * The existing bucket grants `objectViewer` to `allUsers` and the catalog ships
 * absolute, permanent URLs. That was a reasonable arrangement for unlicensed
 * development footage — it is not one for content we have paid for and agreed
 * terms on.
 *
 * So the licensed library goes in a private bucket and the app asks for a URL
 * per clip. The URL expires; the bucket answers nobody without one.
 *
 * WHY SIGNED URLS AND NOT A STREAMING PROXY
 *
 * A function that read the object and piped the bytes would also satisfy the
 * licence, and would be much worse: every byte of every clip would pass through
 * Cloud Functions, billed as compute and egress, with a cold start in front of
 * it and no CDN behind it. A signed URL is one small call; the video itself
 * comes straight from storage at storage's speed.
 *
 * HOW THE SIGNING WORKS WITHOUT A KEY FILE
 *
 * `getSignedUrl` normally wants a service-account private key. Downloading one
 * and committing it anywhere near this repo is how key leaks happen. On Cloud
 * Functions the SDK can instead sign through IAM using the runtime service
 * account's own identity, provided that account holds
 * `roles/iam.serviceAccountTokenCreator` on itself. That grant is a one-line
 * setup step (see `runbooks/video_bundle_import.md`) and no secret ever exists
 * on disk.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getStorage } from "firebase-admin/storage";
import { VIDEO_BATCH, VIDEO_HOT } from "./scaling";

/**
 * Where the licensed library lives. Private — no `allUsers` binding.
 *
 * F0·1: named after the deploying project rather than hardcoded, so a
 * project split does not silently point signed URLs at the old project's
 * bucket. `GCLOUD_PROJECT` is injected by the Cloud Functions runtime; the
 * fallback is the current project so local/emulator runs keep resolving.
 *
 * The `-videos-private` suffix is the convention this bucket already
 * follows, so the new project's bucket must be created with the same
 * suffix for this to resolve — that is a step in the F0·4 data move, not
 * something this expression can guarantee on its own.
 */
export const LICENSED_BUCKET = `${
  process.env.GCLOUD_PROJECT ?? "fitness-app-korostelev"
}-videos-private`;

/**
 * How long a link lives.
 *
 * Long enough to watch a clip and scrub back through it, short enough that a
 * URL pasted into a chat is dead before anyone opens it. Fifteen minutes also
 * comfortably outlives the offline prefetch of a week's sessions, which is the
 * longest legitimate use of a single URL.
 */
const TTL_MINUTES = 15;

/**
 * How long one signature may be handed to more than one caller.
 *
 * ## Why a signature is shareable at all
 *
 * A V4 signature covers the bucket, the object, the expiry and the signing
 * identity. Nothing about the caller enters it — look at the `getSignedUrl`
 * call below and note that `request.auth` is not one of its inputs, and could
 * not be. So two users asking for the same clip in the same minute were being
 * given two different strings that authorise exactly the same thing.
 *
 * That was the whole waste. Each signature is an external IAM `signBlob`
 * round trip: the runtime service account has no key file, so
 * `@google-cloud/storage` signs through `iamcredentials.googleapis.com` using
 * its own identity. Nothing in that chain memoises. 1,000 users opening the
 * same squat clip meant 1,000 IAM calls for 1,000 interchangeable results.
 *
 * ## Why the numbers are what they are
 *
 * The client caches a URL for 13 minutes (`clip_url_resolver.dart`, and it
 * ignores `expiresInSeconds` — the 13 is hardcoded there). The original
 * arrangement was a 15-minute URL against that 13-minute cache: a 2-minute
 * margin, so a clip that starts playing cannot 403 part-way through.
 *
 * Reusing a signature spends that margin, so the signature has to be minted
 * with the reuse window added rather than taken out of the margin. A URL is
 * therefore signed for 20 minutes and served only while at least 15 remain.
 * Every URL handed out still has the full 15 minutes of life it always had,
 * the client's 13-minute cache still lands 2 minutes inside it, and one
 * signature now serves everyone who asks within a 5-minute window.
 *
 * ## What it costs
 *
 * A link's worst-case lifetime goes from 15 minutes to 20. That is the one
 * thing given up, and it is given up against the licence condition quoted at
 * the top of this file — a URL pasted into a chat now has five more minutes
 * to be opened. Five minutes was chosen rather than an hour for that reason:
 * it collapses a burst completely (a burst is seconds wide) and it is the
 * smallest window that does so.
 */
const REUSE_MINUTES = 5;

/** Minted life of a signature. See [REUSE_MINUTES] for why it exceeds the TTL. */
const SIGNED_FOR_MS = (TTL_MINUTES + REUSE_MINUTES) * 60 * 1000;

/** Below this remaining life a cached signature is no longer handed out. */
const MIN_REMAINING_MS = TTL_MINUTES * 60 * 1000;

/**
 * Signatures held between invocations on the same instance.
 *
 * Module scope, so it survives per-request handler calls and is shared by
 * every request on the instance — at the platform's default concurrency of
 * 80, one instance can collapse up to 80 simultaneous asks for a popular clip
 * into a single `signBlob`.
 *
 * Deliberately not a shared cache (Redis, Firestore). A lookup that costs a
 * network round trip would replace the thing being avoided with the same
 * thing wearing a different hat, and cold instances re-signing is not a
 * problem worth a dependency.
 */
const signatures = new Map<string, { url: string; expiresAt: number }>();

/**
 * Signatures being minted right now, so a burst does not all miss together.
 *
 * Without this the cache alone is nearly useless against the case it exists
 * for: 80 concurrent requests for one clip all find an empty map, all sign,
 * and the 79 redundant results race to overwrite each other.
 */
const inFlight = new Map<string, Promise<string>>();

/** Roughly 2,500 clips exist; a full map is a few MB of strings. */
const MAX_CACHED = 4000;

function evictExpired(now: number): void {
  for (const [object, entry] of signatures) {
    if (entry.expiresAt - now < MIN_REMAINING_MS) signatures.delete(object);
  }
}

/**
 * A URL for [object] with at least [TTL_MINUTES] of life, minted or reused.
 *
 * Callers must have checked authentication before reaching this — the cache
 * is a store of signatures, not a bypass of the auth gate.
 */
function signedUrl(object: string, now: number): Promise<string> {
  const hit = signatures.get(object);
  if (hit) {
    if (hit.expiresAt - now >= MIN_REMAINING_MS) return Promise.resolve(hit.url);
    signatures.delete(object);
  }

  const already = inFlight.get(object);
  if (already) return already;

  const expiresAt = now + SIGNED_FOR_MS;
  const task = getStorage()
    .bucket(LICENSED_BUCKET)
    .file(object)
    .getSignedUrl({ version: "v4", action: "read", expires: expiresAt })
    .then(([url]) => {
      if (signatures.size >= MAX_CACHED) evictExpired(now);
      signatures.set(object, { url, expiresAt });
      return url;
    })
    .finally(() => inFlight.delete(object));

  inFlight.set(object, task);
  return task;
}

/** Life left in the URL just handed out, never less than [TTL_MINUTES]. */
function remainingSeconds(object: string, now: number): number {
  const entry = signatures.get(object);
  if (!entry) return TTL_MINUTES * 60;
  return Math.floor((entry.expiresAt - now) / 1000);
}

/** Test seam: the module-scope cache would otherwise leak between cases. */
export function __resetSignatureCache(): void {
  signatures.clear();
  inFlight.clear();
}

/** Object keys must look like `exercises/<body>/<Group>/<file>.mp4`. */
const OBJECT_PATTERN = /^exercises\/(girl|men)\/[^/]{1,120}\/[^/]{1,160}\.mp4$/;

/**
 * Rejects anything that is not one of our own clip paths.
 *
 * The parameter arrives from a phone and is used to name an object, so it is
 * the one input here that can be hostile. The allow-list shape rules out
 * traversal, absolute paths and any attempt to reach another prefix in the same
 * bucket — a `..` cannot survive a regex that permits no slashes inside a
 * segment.
 */
function assertSafeObject(raw: unknown): string {
  const path = String(raw ?? "");
  if (!OBJECT_PATTERN.test(path)) {
    throw new HttpsError("invalid-argument", "Not a clip path.");
  }
  return path;
}

/**
 * Returns a short-lived URL for one clip.
 *
 * Signed in on purpose: an anonymous caller could otherwise mint links for the
 * whole library in a loop, which is the "public storage folder" the licence
 * prohibits, just spelled differently.
 */
export const clipUrl = onCall(VIDEO_HOT, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to watch clips.");
  }
  const object = assertSafeObject(request.data?.object);

  try {
    const now = Date.now();
    const url = await signedUrl(object, now);
    return { url, expiresInSeconds: remainingSeconds(object, now) };
  } catch (e) {
    // Surfaced rather than swallowed: the two ways this fails in practice —
    // the object genuinely missing, and the runtime account lacking
    // tokenCreator on itself — look identical from the phone, and only the
    // log can tell them apart.
    logger.error("could not sign clip url", { object, error: String(e) });
    throw new HttpsError("internal", "Could not prepare that clip.");
  }
});

/**
 * The same thing for a whole session, so the offline prefetch is one round
 * trip rather than forty.
 *
 * Capped at 60. The cap is not politeness — an uncapped list turns one call
 * into an unbounded number of signing operations, and signing goes through IAM.
 */
export const clipUrls = onCall(VIDEO_BATCH, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to watch clips.");
  }
  const raw = request.data?.objects;
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new HttpsError("invalid-argument", "No clips requested.");
  }
  if (raw.length > 60) {
    throw new HttpsError("invalid-argument", "Too many clips in one request.");
  }
  const objects = raw.map(assertSafeObject);
  const now = Date.now();

  const entries = await Promise.all(
    objects.map(async (object) => {
      try {
        return [object, await signedUrl(object, now)] as const;
      } catch (e) {
        // One bad object must not fail the other fifty-nine: a prefetch of a
        // week's workouts should deliver what it can.
        logger.warn("skipped clip", { object, error: String(e) });
        return [object, null] as const;
      }
    }),
  );

  const urls: Record<string, string> = {};
  for (const [object, url] of entries) {
    if (url) urls[object] = url;
  }
  // The shortest life among the URLs actually returned, so a client that
  // honoured this field could not outlive the weakest one in the batch. Every
  // entry is guaranteed at least TTL_MINUTES regardless.
  const lives = Object.keys(urls).map((o) => remainingSeconds(o, now));
  return {
    urls,
    expiresInSeconds: lives.length ? Math.min(...lives) : TTL_MINUTES * 60,
  };
});
