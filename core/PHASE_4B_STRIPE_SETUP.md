# Phase 4B — Stripe + Cloud Functions runbook

**Status:** code shipped, awaiting your deploy + webhook configuration.
Phase 4A shipped the local-first foundation (mock checkout + 14-day
trial); Phase 4B replaces the mock with real Stripe billing wired
through `users/{uid}/subscription/main` via a webhook.

## Deploy steps (run from `D:\Repo\Fitness_App`)

These commands need your terminal because they write secrets to Google
Secret Manager and your Firebase auth.

**Two Functions codebases exist since P0.G6 (2026-08-22):** this runbook's
`functions/` (`default` codebase, everything below) and a separate
`functions-equipment-identity/` (`equipment-identity` codebase) added for
the equipment-recognition ML feature -- currently exports nothing, not yet
production-deployed. Every command below is deliberately scoped to
`functions:default` so it can never touch the identity codebase, even once
that codebase ships real functions. See
`core/equipment_identity/p0/P0_G6_DEPLOYMENT_ISOLATION.md` for why.

### 1. Install Functions dependencies

```powershell
cd "D:\Repo\Fitness_App\functions"
npm install
```

(Node 20 is required; `firebase.json` pins the runtime to nodejs20.)

### 2. Set the four Functions secrets

From the project root (`D:\Repo\Fitness_App`):

```powershell
firebase functions:secrets:set STRIPE_SECRET_KEY
# paste sk_test_... when prompted

firebase functions:secrets:set STRIPE_PRICE_STANDARD
# paste price_1TUtmg4fkjClK2wmBB8xNStR

firebase functions:secrets:set STRIPE_PRICE_CELEBRITY
# paste price_1TUtnE4fkjClK2wmjXe8srza

# placeholder — replace after step 4 below
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
# paste any string for now (e.g. "placeholder")
```

### 3. First deploy

```powershell
firebase deploy --only firestore:rules,functions:default
```

Two things happen:
- The tightened `firestore.rules` (no client writes to subscription docs)
  goes live.
- Three callable HTTPS endpoints become available. Note the
  `stripeWebhook` URL the deploy prints — looks like
  `https://us-central1-traidingbot-b4061.cloudfunctions.net/stripeWebhook`.

### 4. Add the Stripe webhook endpoint

1. <https://dashboard.stripe.com/test/webhooks> → **Add endpoint**.
2. URL: paste the `stripeWebhook` URL from step 3.
3. Events to send (click "Select events", filter, then check):
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.paid`
   - `invoice.payment_failed`
4. **Add endpoint**.
5. On the new endpoint's page, click **"Reveal signing secret"** → copy
   the `whsec_...` string.

### 5. Replace the placeholder webhook secret + redeploy

```powershell
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
# paste the whsec_... from step 4

firebase deploy --only functions:default
```

### 6. Smoke test on the emulator

1. Build + install the app: `flutter run` (or rebuild the APK if the
   emulator is already running).
2. Sign in → finish onboarding → /subscription.
3. Tap **Choose** on Standard.
4. App opens Stripe checkout in an external browser.
5. Use card `4242 4242 4242 4242`, any future date, any CVC.
6. After "Payment successful", return to the app.
7. Within ~1s the status card should flip to "Active · Standard"
   (driven by the webhook → Firestore → StreamProvider chain).
8. Tap **Manage subscription** → opens the Stripe Customer Portal.
9. Cancel from the portal → status flips to "Cancelling at period end".

If something goes wrong: Stripe dashboard → Developers → Webhooks →
your endpoint → "Send test event" + `firebase functions:log` to read
what the function received.

## Captured config (test mode)

Filled in 2026-05-08 as the user creates the Stripe products. The
Functions code reads these from Secret Manager (see step 3) — they're
not secrets but recording them here saves a dashboard round-trip.

| Slot                         | Value                                         |
| ---------------------------- | --------------------------------------------- |
| `STRIPE_PRICE_STANDARD`      | `price_1TUtmg4fkjClK2wmBB8xNStR` (Standard, $9.99/mo)         |
| `STRIPE_PRICE_CELEBRITY`     | `price_1TUtnE4fkjClK2wmjXe8srza` (Celebrity trainer, $19.99/mo) |
| `STRIPE_SECRET_KEY`          | *user pastes via `firebase functions:secrets:set`* |
| `STRIPE_WEBHOOK_SECRET`      | *filled after first deploy + endpoint creation*    |
| Stripe publishable key       | *user pastes into `lib/main.dart` later*           |

## Architecture

```
┌─ Flutter app
│   StripeCheckoutAction.startCheckout(tier)
│      └→ HTTPS callable: createCheckoutSession({tier})
│            └→ returns Stripe checkout URL
│      └→ launches Custom Tab / SFSafariViewController to that URL
│      └→ user pays on stripe.com
│      └→ Stripe redirects to fitness://stripe-return
│
├─ Cloud Functions (TypeScript, Firebase project traidingbot-b4061)
│   createCheckoutSession   — signs the session + tier-priced line item
│   createPortalSession     — opens Stripe Customer Portal (manage / cancel)
│   stripeWebhook (HTTPS)   — verifies signature, mirrors state into
│                             users/{uid}/subscription/main
│
└─ Stripe
    Products: Standard ($9.99/mo)  + Celebrity ($19.99/mo)
    Webhook  → /stripeWebhook
    Events   → customer.subscription.created / updated / deleted,
               invoice.paid, invoice.payment_failed
```

The app **never** writes the subscription doc directly any more — the
webhook is the single source of truth. `firestore.rules` will be
tightened to disallow client writes to `users/{uid}/subscription/**`.

## Costs / what's billable

- **Stripe** — pay-as-you-go (≈2.9% + $0.30 per transaction for cards
  in the US; check your country). No monthly fee.
- **Cloud Functions (Blaze plan)** — required to call external HTTPS
  (Stripe API). Free tier covers the first 2M invocations/month, which
  is more than enough for any pre-launch testing.
- Switching the Firebase project to Blaze is the one **manual upgrade**
  you have to do before deploys will work. Cost stays $0 within the
  free tier; you set a budget alert at $1 to be safe.

## What you do (manual prerequisites)

These steps need you because they require accounts I can't create or
keys I can't read. After each numbered step, paste the requested string
back into chat — I'll wire it into the right config file.

### 1. Stripe account + products

1. Sign up at <https://dashboard.stripe.com/register>.
2. Confirm you're in **Test mode** (toggle in the top-right reads
   "Viewing test data").
3. Developers → API keys. Copy these two and save them somewhere safe:
   - **Publishable key** — `pk_test_...` (safe to ship in the app).
   - **Secret key** — `sk_test_...` (server-only, never goes in the
     app).
4. Products → Add product:
   - "Fitness App — Standard" — recurring, $9.99 USD / month → click
     "Save price". Copy the **price id** (`price_1Ab...XYZ`).
   - "Fitness App — Celebrity trainer" — recurring, $19.99 USD / month
     → save → copy that price id too.
5. Settings → Customer portal → Activate test link, save defaults
   (allow cancellation + plan switch).

   **Paste back to me:** the two price ids. I don't need either Stripe
   key — those go straight into Functions secrets in step 3.

### 2. Upgrade Firebase project to Blaze

1. Open <https://console.firebase.google.com/project/traidingbot-b4061/usage/details>.
2. "Modify plan" → Blaze (Pay as you go).
3. Add a billing account / card.
4. Set a budget alert at **$1/month** so you get an email before
   anything unexpected happens.

   **Tell me back:** "Blaze done." That's all I need.

### 3. Initialise Cloud Functions in this repo

I'll do this for you once Blaze is live. The actual commands I'll run
from inside `D:\Repo\Fitness_App`:

```
firebase init functions          # TypeScript, no ESLint, no install yet
firebase functions:secrets:set STRIPE_SECRET_KEY    # paste sk_test_...
firebase functions:secrets:set STRIPE_PRICE_STANDARD   # paste price_id
firebase functions:secrets:set STRIPE_PRICE_CELEBRITY  # paste price_id
```

You'll be prompted to paste the values — they're stored encrypted in
Google Secret Manager, never in this repo. The webhook signing secret
slot stays empty for now; we set it after the first deploy in step 5.

### 4. Code I'll write once 1+2 are done

- `functions/src/index.ts` — the three handlers:
  - `createCheckoutSession` — callable, takes `{ tier }`, returns
    `{ url }`. Looks up or creates the Stripe customer, attaches the
    user's `uid` as customer metadata.
  - `createPortalSession` — callable, returns the customer-portal URL
    so users can cancel/manage from inside the app.
  - `stripeWebhook` — HTTPS, verifies signature with
    `STRIPE_WEBHOOK_SECRET`, normalises the event into a
    `Subscription` record, writes to `users/{uid}/subscription/main`.
- Add the `flutter_stripe` package + a `StripeCheckoutAction` notifier
  that opens the checkout URL with `url_launcher` (or
  `flutter_custom_tabs` on Android for the smoother in-app browser).
- Tighten `firestore.rules`: keep client read access, deny client
  write to `users/{uid}/subscription/**`.
- Replace the mock body of
  `SubscriptionAction.chooseTier()` with the callable invocation
  (`startTrial()` stays local — Stripe doesn't price trial-only state).
- Tests: mock the callable, verify the action transitions to
  `loading → data` and writes don't happen client-side.

### 5. After my code lands — deploy and configure the webhook

1. `firebase deploy --only functions:default` from `D:\Repo\Fitness_App`.
2. Copy the deployed `stripeWebhook` URL from the deploy output (looks
   like `https://us-central1-traidingbot-b4061.cloudfunctions.net/stripeWebhook`).
3. Stripe dashboard → Developers → Webhooks → Add endpoint:
   - URL: paste the function URL.
   - Events:
     - `customer.subscription.created`
     - `customer.subscription.updated`
     - `customer.subscription.deleted`
     - `invoice.paid`
     - `invoice.payment_failed`
   - Reveal **Signing secret** (`whsec_...`).
4. `firebase functions:secrets:set STRIPE_WEBHOOK_SECRET` → paste the
   `whsec_...`.
5. `firebase deploy --only functions:default` again so the function
   picks up the new secret.

### 6. Smoke test on the emulator

1. Open the app, sign in, navigate to /subscription.
2. Tap "Choose" on Standard.
3. App opens Stripe checkout (test mode).
4. Use card `4242 4242 4242 4242`, any future date, any CVC.
5. Stripe completes → app returns → `users/.../subscription/main`
   updates within ~1s (webhook fires).
6. Status card flips to "Active · Standard". Profile tile reflects it.
7. Tap "Cancel subscription" → opens customer portal → cancel.
8. Webhook fires `subscription.deleted` → status flips to "Cancelling".

If any step fails: Stripe dashboard → Developers → Webhooks →
Endpoint → "Send test event" + check the function logs in
`firebase functions:log` to see exactly what the webhook received.

## What stays out of scope (Phase 4C+)

- iOS-specific entitlement (App Store IAP) — Apple doesn't allow Stripe
  for digital subscriptions on iOS. We'll need StoreKit + a separate
  Cloud Function bridge before iOS launch.
- Promo codes / lifetime deals.
- Family / shared plans.
- Tax handling (Stripe Tax integration).

## Quick start checklist

| Step | Who | Blocking?     |
| ---- | --- | ------------- |
| Stripe account + 2 price ids | you | yes |
| Firebase Blaze upgrade       | you | yes |
| `firebase init functions` + secrets | me | no (waits on the two above) |
| Functions code               | me | no |
| `flutter_stripe` wiring      | me | no |
| `firebase deploy --only functions:default` | you | yes (need your auth) |
| Webhook endpoint + signing secret | you + me | yes |
| Smoke test                   | you | — |
