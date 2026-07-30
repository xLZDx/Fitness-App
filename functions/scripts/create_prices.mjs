#!/usr/bin/env node
/**
 * Creates the five Stripe prices the Cloud Functions expect but that were never
 * set up: annual (both tiers), two Standard family sizes, and the Celebrity
 * lifetime one-off.
 *
 * The amounts are NOT invented here — they are the ones the app already
 * documents and displays (mobile/lib/features/subscription/data/
 * subscription_models.dart:16-23). Charging something other than what the
 * paywall shows would be a worse bug than the missing prices.
 *
 * SECRET HANDLING: the Stripe secret key is read from STDIN only. Never from
 * argv (visible in process listings and shell history), never from a file in
 * the repo, and it is never printed — the script only ever emits price ids,
 * which are not sensitive. Intended use:
 *
 *   firebase functions:secrets:access STRIPE_SECRET_KEY --project <p> \
 *     | node functions/scripts/create_prices.mjs <standardPriceId> <celebrityPriceId>
 *
 * IDEMPOTENT: each price carries a `lookup_key`, and an existing price with
 * that key is reused rather than duplicated, so re-running is safe.
 *
 * LIVE-MODE GUARD: refuses an `sk_live_` key unless --allow-live is passed.
 * Creating live prices is a money-adjacent action and must be deliberate.
 */
import Stripe from "stripe";

const args = process.argv.slice(2).filter((a) => a !== "--allow-live");
const allowLive = process.argv.includes("--allow-live");
const [standardMonthlyId, celebrityMonthlyId] = args;

if (!standardMonthlyId || !celebrityMonthlyId) {
  console.error(
    "usage: <stdin: sk_...> node functions/scripts/create_prices.mjs " +
      "<STRIPE_PRICE_STANDARD> <STRIPE_PRICE_CELEBRITY> [--allow-live]",
  );
  process.exit(2);
}

/** Reads the whole of stdin, trimmed. Nothing is echoed. */
async function readKey() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8").trim();
}

/**
 * The five missing prices. `product` is resolved from the existing monthly
 * price of the same tier, so annual/family/lifetime sit on the SAME Stripe
 * product as the plan they belong to instead of inventing parallel ones.
 */
const PLAN = [
  {
    secret: "STRIPE_PRICE_STANDARD_ANNUAL",
    lookupKey: "standard_annual",
    tier: "standard",
    unitAmount: 5999,
    recurring: { interval: "year" },
    nickname: "Supporter — annual",
  },
  {
    secret: "STRIPE_PRICE_CELEBRITY_ANNUAL",
    lookupKey: "celebrity_annual",
    tier: "celebrity",
    unitAmount: 11999,
    recurring: { interval: "year" },
    nickname: "Sustainer — annual",
  },
  {
    secret: "STRIPE_PRICE_STANDARD_FAMILY2",
    lookupKey: "standard_family2",
    tier: "standard",
    unitAmount: 1499,
    recurring: { interval: "month" },
    nickname: "Supporter — family, 2 seats",
  },
  {
    secret: "STRIPE_PRICE_STANDARD_FAMILY4",
    lookupKey: "standard_family4",
    tier: "standard",
    unitAmount: 1999,
    recurring: { interval: "month" },
    nickname: "Supporter — family, 4 seats",
  },
  {
    secret: "STRIPE_PRICE_CELEBRITY_LIFETIME",
    lookupKey: "celebrity_lifetime",
    tier: "celebrity",
    unitAmount: 49900,
    recurring: null, // one-time
    nickname: "Sustainer — lifetime",
  },
];

const key = await readKey();
if (!key.startsWith("sk_")) {
  console.error("stdin did not look like a Stripe secret key");
  process.exit(2);
}
const live = key.startsWith("sk_live_");
if (live && !allowLive) {
  console.error(
    "refusing to create LIVE prices without --allow-live. " +
      "Re-run deliberately if that is really the intent.",
  );
  process.exit(3);
}
console.log(`mode: ${live ? "LIVE" : "test"}`);

const stripe = new Stripe(key);

// Resolve the product behind each tier's existing monthly price.
const products = {};
for (const [tier, priceId] of [
  ["standard", standardMonthlyId],
  ["celebrity", celebrityMonthlyId],
]) {
  const price = await stripe.prices.retrieve(priceId);
  products[tier] =
    typeof price.product === "string" ? price.product : price.product.id;
  console.log(`${tier}: product ${products[tier]} (from ${priceId})`);
}

const results = {};
for (const p of PLAN) {
  const existing = await stripe.prices.list({
    lookup_keys: [p.lookupKey],
    limit: 1,
  });
  if (existing.data.length > 0) {
    results[p.secret] = existing.data[0].id;
    console.log(`reused  ${p.secret} = ${existing.data[0].id}`);
    continue;
  }
  const created = await stripe.prices.create({
    product: products[p.tier],
    currency: "usd",
    unit_amount: p.unitAmount,
    nickname: p.nickname,
    lookup_key: p.lookupKey,
    ...(p.recurring ? { recurring: p.recurring } : {}),
  });
  results[p.secret] = created.id;
  console.log(`created ${p.secret} = ${created.id}`);
}

// Machine-readable tail so the caller can set the secrets without re-parsing
// the human log above.
console.log("---JSON---");
console.log(JSON.stringify(results, null, 2));
