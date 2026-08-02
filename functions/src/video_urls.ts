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

/** Where the licensed library lives. Private — no `allUsers` binding. */
export const LICENSED_BUCKET = "traidingbot-b4061-videos-private";

/**
 * How long a link lives.
 *
 * Long enough to watch a clip and scrub back through it, short enough that a
 * URL pasted into a chat is dead before anyone opens it. Fifteen minutes also
 * comfortably outlives the offline prefetch of a week's sessions, which is the
 * longest legitimate use of a single URL.
 */
const TTL_MINUTES = 15;

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
export const clipUrl = onCall({ region: "us-central1" }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to watch clips.");
  }
  const object = assertSafeObject(request.data?.object);

  try {
    const [url] = await getStorage()
      .bucket(LICENSED_BUCKET)
      .file(object)
      .getSignedUrl({
        version: "v4",
        action: "read",
        expires: Date.now() + TTL_MINUTES * 60 * 1000,
      });
    return { url, expiresInSeconds: TTL_MINUTES * 60 };
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
export const clipUrls = onCall({ region: "us-central1" }, async (request) => {
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
  const bucket = getStorage().bucket(LICENSED_BUCKET);
  const expires = Date.now() + TTL_MINUTES * 60 * 1000;

  const entries = await Promise.all(
    objects.map(async (object) => {
      try {
        const [url] = await bucket
          .file(object)
          .getSignedUrl({ version: "v4", action: "read", expires });
        return [object, url] as const;
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
  return { urls, expiresInSeconds: TTL_MINUTES * 60 };
});
