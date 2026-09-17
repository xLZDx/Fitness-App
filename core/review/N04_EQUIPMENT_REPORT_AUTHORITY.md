# N-04 — Who may file an equipment report

**Disposition: `RETAIN CURRENT BEHAVIOUR`. Two defects found while deciding it are fixed. One
question remains genuinely the product owner's, and it is not the one N-04 was opened to ask.**

N-04 asked whether filing a broken-equipment report should require a verified gym association. It
was carried for days as `OPERATOR_DECISION_REQUIRED` on the premise that *there is nothing to
associate a report with*. That premise was measured rather than assumed this time, and it is
half true in a way that mattered.

## What is actually there

| | Measured at HEAD |
|---|---|
| `gymId` on a report | Client-chosen, bounded to 128 chars, defaults to the literal `"unknown"` (`functions/src/index.ts`) |
| The only caller in `lib/` | `equipment_detail_page.dart:108` passes `equipmentId` and `equipmentName` and **no gymId** — so every report filed today carries the sentinel |
| `gyms/` collection | Exists in `firestore.rules`, readable by any signed-in client, **written by nothing in this repository** |
| Gym onboarding tooling | `firestore.rules` says the server writes `gyms/` "via the gym-onboarding tooling". No such tooling exists. |
| Webhook dispatch | `gyms/{gymId}.maintenanceWebhookUrl` → Slack-shaped POST. Unreachable today, because no gym document is ever created. |
| Membership model | None, in `mobile/lib`, `functions/src/index.ts` or `firestore.rules` |

So the blast radius of a malicious report today is a bounded note in a collection no client can
read. Nobody outside the console receives a byte.

## Why B loses, and it is not close

Requiring a verified association means building the domain wholesale: onboarding tooling that does
not exist, membership issuance and revocation, a verification signal (QR, geofence or staff invite —
each its own subsystem), a migration for every existing `gymId: "unknown"`, and a permanent support
surface for users whose gym was never onboarded. That is a B2B platform build, sequenced before the
feature has a single real customer.

It would also land on the wrong report. The top fault category in
`mobile/lib/features/equipment/data/equipment_report.dart` is `unsafe` — a frayed cable, a cracked
plate, a missing safety pin. Putting an onboarding handshake in front of *that* report is the worst
available trade, and it is the report the feature exists for.

And a client-side association would be decoration regardless: `reportEquipment` writes through the
Admin SDK, which bypasses `firestore.rules` entirely. Any membership predicate written as a rule is
dead code on this path. The only enforceable location is inside the callable.

## The two defects found while deciding

Neither is the authority question. Both were reproduced, fixed, tested and mutation-proven, and both
would have stood however N-04 was answered.

### `gyms/unknown` was a catch-all relay waiting for one console write

`gymId` defaults to `"unknown"`, every report carries that value, and nothing excluded it from the
`gyms/{gymId}` lookup. A document created at `gyms/unknown` with a `maintenanceWebhookUrl` would
have relayed **every report from every user** to that single endpoint — no deploy, no code change,
no pull request. An onboarding tool that seeds a placeholder gym under the obvious placeholder id
does it by accident.

The sentinel now has a name, `UNASSIGNED_GYM`, and the dispatch returns before the lookup. The
report is still filed; refusing to relay is not refusing to record.

### The webhook pushed an identity the app promises to share only on request

`app_en.arb:141` and `app_ru.arb:124` both tell the user: *"Your identity is shared with the gym
only if they ask to follow up."* The payload interpolated `Reporter: ${auth.uid}` unconditionally.
That is a push model behind a published pull promise, and it is worse than the on-platform
equivalent: `deleteAccount` rewrites `reporterUid` to `DELETED_UID` on the Firestore copy, but a uid
already POSTed to somebody's Slack cannot be recalled.

The payload now carries `Report: <reportId>` instead. `reporterUid` stays on the document, so a gym
that asks to follow up quotes the report id and gets an answer — which is the model the copy already
describes. **Making the code match the published promise was the conservative direction.** Changing
the promise to admit a push would be a product decision; it is recorded as one below.

The `note` is now also sanitised in the structured field, not only in `text`. The same string
shipped clean in one field and raw in another is worse than either choice made consistently: a
receiver cannot tell which field is safe to render, and the unsafe one is what a non-Slack
integration reaches for.

## What remains the product owner's — and it is a different question

N-04 asked about authority. The measurement turned up something else.

### DECISION P-1 — is a gym's maintenance webhook a disclosed processor?

`app_en.arb`'s privacy body states: **"Two processors are involved, and no others: Google
(Firebase Authentication, Firestore, Crashlytics, App Check, and the Gemini model) and Stripe
(payments)."**

A gym-controlled `maintenanceWebhookUrl` is a third recipient. It receives equipment id, gym id,
fault category, the user's free-text note and the report id. With the uid removed it no longer
receives an identifier this app assigns — but a free-text note is written by a person and can
contain anything.

This is currently harmless because no gym exists. It stops being harmless on the day one does, with
no code change in between. There are exactly two honest resolutions and both are product's:

* **Disclose it.** Amend the processor sentence to name gym maintenance endpoints as recipients of
  report contents, before any gym is onboarded.
* **Do not ship it.** Remove the webhook dispatch and let reports surface only in the console.

To authorize either: *"Gym maintenance endpoints are/are not a disclosed processor. Amend the
privacy copy accordingly / remove the webhook dispatch."*

### DECISION P-2 — who is the customer for an equipment report?

The code is built for the gym (routed work-order, gym identity load-bearing, webhook dispatch). It
behaves as though the customer is the user (no gymId is ever supplied, nothing is routed anywhere).
The UI claims the first.

If the customer is the **gym**, then onboarding tooling is on the roadmap, gym identity becomes
load-bearing, and the association question returns — properly, with something to associate to. If
the customer is the **user**, then `gymId`, the webhook and this entire authority question can be
deleted rather than hardened.

Nothing in this repository can settle that, and it is the question that decides whether N-04 ever
comes back.

## The deferral needs a mechanism, because nothing fires

The disposition above is "retain, and revisit when `gyms/` gains a writer". A reviewer pointed out
that this trigger is inert: every webhook test primes the gym document itself, so the branch is
green today and stays identically green the day a real writer ships. `gyms/` becoming non-empty is
a Firestore write in a console. **No test, CI check or runtime guard is keyed to it.**

That is recorded rather than papered over. **Built, 2026-09-17, once the deferral was actually
recorded** (`core/decisions/N-04.md` — the operator kept the deferral, which is exactly the
precondition this residual names): `functions/src/__tests__/n04_gym_association_guard.test.ts`
scans production source for a `gyms/` writer and, if one appears, requires `reportEquipment` to
carry a caller-to-gym association check — today it passes vacuously (no writer exists yet), and
fails against two synthetic cases (a writer with no check, and confirms a writer with a check
passes), so it is not decoration. The residual marker is retired; the guard is the mechanism.
