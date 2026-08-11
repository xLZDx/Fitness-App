# Data inventory — every store keyed to a user (2026-08-11)

Gate **A0** of `core/plans/PLAN_AUDIT_2026-08-11_REMEDIATION.md`. It exists
because A1 (deletion) and A3 (export) were each about to derive this list
separately, and a divergence between those two lists is exactly how a product
ends up promising "we erase everything" while exporting less than it stores.

CSV twin: `core/DATA_INVENTORY_2026-08-11.csv`.

**Method.** Enumerated from three independent directions and merged, rather
than from memory: `firestore.rules` `match` blocks; every `db.doc(`/
`db.collection(` in `functions/src/index.ts`; every `collection('…')` in
`mobile/lib/`; and every `SharedPreferences` key constant plus every
`getApplicationDocumentsDirectory` / `getTemporaryDirectory` call site in
`mobile/lib/`.

**Baseline as of `3cc8126`.** "Deleted" = removed by `deleteAccount`
(`functions/src/index.ts:1287-1345`) plus the client action
(`account_deletion_providers.dart`). "Exported" = present in
`buildExport` (`mobile/lib/features/data_export/data_export.dart:33-86`).

## Server — Firestore

| Path | Holds | Deleted | Exported |
|---|---|---|---|
| `users/{uid}/profile/main` | profile, goals, **injuries** | yes | yes |
| `users/{uid}/workout_logs/*` | workout history | yes | yes |
| `users/{uid}/workout_sessions/*` | open + completed sessions, sets, difficulty | yes | **no** |
| `users/{uid}/scheduled_sessions/*` | schedule | yes | yes |
| `users/{uid}/programmes/*` | enrolled programmes | yes | yes |
| `users/{uid}/subscription/main` | tier, Stripe customer + subscription ids | yes | **no** |
| `users/{uid}/machine_cards/*` | saved machines + user notes | yes | **no** |
| `users/{uid}/recognised_equipment/*` | recognition history | yes | **no** |
| `users/{uid}/generated_exercises/*` | AI-generated exercises | yes | **no** |
| `users/{uid}/stats/workouts` | aggregate counters | yes | **no** |
| `donor_wall/{uid}` | publicly readable donor entry | yes | **no** |
| `coach_listings/{uid}` | coach profile | yes | **no** |
| `coach_bookings/{id}` | `clientUid` + `coachUid`, times, price, payment intent | **NO** | **no** |
| `equipment_reports/{id}` | `reporterUid`, gym, fault, note | **NO** | **no** |
| `debug_sessions/{id}` | `uid`, device telemetry | **NO** | **no** |
| `gyms/*`, `equipment/*`, `exercises/*` | shared reference data, no user key | n/a | n/a |

Three orphans, and they are not symmetrical: `coach_bookings` names the deleted
user in **either** of two fields, so a sweep that only matches `clientUid`
leaves a coach's own bookings behind. `debug_sessions` is create-only by its
own rule (`firestore.rules:82-87`: `allow update, delete: if false`) — the
client cannot delete it even for itself, so this one can only be swept
server-side.

## Device — SharedPreferences

| Key | Holds | Wiped on delete | Exported |
|---|---|---|---|
| `profile.sensitive.{uid}` | **health/injury blob**, JSON, plaintext | **NO** | via profile, partially |
| `progress_photos.key.v1` | AES-256 key, base64, **not uid-scoped** | **NO** | no (correctly) |
| `settings.language`, `settings.theme_mode`, `settings.notifications_enabled`, `settings.tier_override` | preferences | **NO** | **no** |
| `moment.first_launch_at`, `moment.launch_count`, `moment.injury_filter_uses`, `moment.shown.*` | in-app moment counters | **NO** | **no** |

`profile.sensitive.{uid}` is the one that already has the right shape: it is
uid-keyed and `PrefsSensitiveStore.clear(uid)` exists
(`local_sensitive_store.dart:51,76`). Nothing calls it on deletion — the client
action calls the function and signs out, and that is all
(`account_deletion_providers.dart:16-56`).

## Device — files

| Path | Holds | Wiped on delete | Exported |
|---|---|---|---|
| `<docs>/progress_photos/` | AES-GCM envelopes + **plaintext metadata index** | **NO** | metadata only |
| `<temp>/` camera stills | **plaintext JPEG** of the shot just encrypted | **NO** | no |
| `<docs>/offline_videos/` | cached exercise clips (catalogue content) | no | n/a |
| `<docs>/<model asset path>` | ML model files unpacked by `AssetBootstrap` | no | n/a |
| `<temp>/` export file | the export itself | n/a | n/a |

The photo directory is shared across accounts, and so is its key. Sign out of
account A, sign in as account B on the same device, and B's photo grid reads
A's envelopes with A's key. That is the concrete mechanism behind the audit's
"следующий аккаунт может получить данные предыдущего", and it is a **local**
defect that no amount of server-side deletion fixes.

## What this fixes in the two dependent gates

**A1 must therefore:** sweep `coach_bookings` on both uid fields,
`equipment_reports` on `reporterUid`, and `debug_sessions` on `uid`, all
server-side; and on the client, `clear(uid)` the sensitive store, delete the
whole `<docs>/progress_photos/` directory (directory-level, so it survives
A2's restructure), drop the photo key, and reset the `settings.*`/`moment.*`
keys that describe a person rather than a device.

**A3 must therefore add:** workout sessions, subscription (minus secrets),
machine cards, recognition history, generated exercises, stats, donor entry,
coach listing, coach bookings, equipment reports, debug telemetry — plus a
recorded decision on photo bytes, which today are excluded by a comment in
`data_export.dart:13-22` that the privacy policy does not repeat.
