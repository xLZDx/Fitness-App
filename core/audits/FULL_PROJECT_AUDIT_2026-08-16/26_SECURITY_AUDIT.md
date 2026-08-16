# 26 - Security and privacy

Reviewed by the `security-reviewer` role. **Partial: the reviewer listed seven areas it had not
inspected rather than reporting them clean, and those remain open.** That honesty is recorded here
rather than smoothed over.

## Firestore rules - VERIFIED sound in the main

`firestore.rules`, 130 lines, read in full.

- `users/{uid}/{coll}/**` - read and write require `request.auth.uid == uid`, with `subscription`
  carved out as server-write-only. Ownership properly enforced.
- `equipment`, `exercises`, `gyms` - authenticated read, `write: if false`.
- `donor_wall` - `allow read: if true`, deliberate and documented, no sensitive fields.
- `equipment_reports`, `coach_bookings` - closed to clients entirely.
- `debug_sessions` - create-own only, with a field allowlist and a 500-event cap; read, update and
  delete all denied.

No `allow read, write: if true` outside the deliberate donor-wall case.

**Two findings (F005, F006):** the `users/{uid}/**` wildcard excludes only `subscription`, so a
client can write `users/{uid}/usage/{day}` - the abuse-guard quota ledger - and
`users/{uid}/receipts/{year}`. The first lets a user reset their own rate limit on signed video URLs.

**F-INFO:** `coach_listings` has no explicit rules block. Default-deny protects it today; an absent
rule is indistinguishable from a deliberate deny to the next reader.

## Cloud Functions auth - VERIFIED

Every callable requires `request.auth` and uses `auth.uid`, never a client-supplied uid.
`stripeWebhook` verifies the Stripe HMAC signature and takes the uid from server-stamped metadata.
`bookCoachSession` accepts a `coachUid` parameter, which is a foreign key rather than an
authorisation bypass - `clientUid` is server-set.

**App Check is measured but not enforced** (`scaling.ts:113-124`, both flags default false). This is
an explicit, documented, staged-rollout decision. Today it provides no protection on any callable.
The deployed values are UNAVAILABLE without access to the environment.

## Account deletion - VERIFIED end to end

Stripe subscriptions cancelled first (failure aborts), then `recursiveDelete` on `users/{uid}`,
`donor_wall/{uid}` and `coach_listings/{uid}`, then `sweepSharedRecords` anonymises or deletes shared
`coach_bookings` and `equipment_reports` and hard-deletes `debug_sessions`, then the Auth user last,
treating not-found as success.

**F011:** the code documents that a token minted just before deletion stays valid for up to about an
hour, because `onCall` does not check revocation. A real, acknowledged post-deletion window.

## Progress photos - VERIFIED encrypted

AES-256-GCM via PointyCastle, 32-byte key, random 12-byte IV per file, tag stored alongside. Keys in
`flutter_secure_storage`, Keystore/Keychain-backed, one per uid. The legacy plaintext-SharedPreferences
key store is `@Deprecated` and unwired, and migration deletes the old entry.

**Still CLAIMED rather than VERIFIED:** that photo bytes never leave the device. Two independent code
comments assert it; `photo_store.dart` was not read for the absence of an upload call. This is the
single most load-bearing unclosed item in this section.

## Secrets - VERIFIED clean on what was read

The only `AIza` key is the public Firebase client key, which is safe to embed. Function secrets are
`defineSecret` references resolved from Secret Manager; the literals in comments are placeholders.

**NOT_CHECKED:** `functions/jest.setup.js`, `jest.e2e.setup.js`, `functions/scripts/create_prices.mjs`,
`scripts/catalog/provision_video_bucket.py`, `core/PHASE_4B_STRIPE_SETUP.md`.

## LLM exposure - VERIFIED clean, from the other reviews

The clinical and recommendation reviewers both traced all three prompt builders independently:
`ai_coach_context.dart:97`, `ai_exercise_generator.dart:71`, `gemini_equipment_service.dart:118`
carry subject name, language and image bytes only. **No health field reaches any model.**

## PII in logs

Spot findings only. **F009:** `photo_key_store.dart:184` interpolates a key name containing the uid
into `debugPrint` on a corrupt-key path. A broad sweep of `form_check/`, `health/`, `scanner/` and
`ai_coach/` for pose landmarks and health data in logs was **NOT_CHECKED**.

## Open

`photo_store.dart` upload path · the five secret-grep files above · a full log sweep · `public/*.html`
· outbound surfaces (`server_export.dart`, `backup_transfer.dart`, `clip_url_resolver.dart`, wear
sync) and the `reportEquipment` Slack-webhook payload · whether any test disables a security check.
