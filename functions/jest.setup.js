/**
 * Test-only fake values for the firebase-functions params secrets.
 * defineSecret("X").value() reads process.env.X at runtime, so setting
 * these BEFORE the module under test is imported is all that offline
 * unit tests need. None of these are real credentials.
 */
process.env.STRIPE_SECRET_KEY = "sk_test_fake_unit_test_key_not_real";
process.env.STRIPE_WEBHOOK_SECRET = "whsec_fake_unit_test_not_real";
process.env.STRIPE_PRICE_STANDARD = "price_fake_std_monthly";
process.env.STRIPE_PRICE_CELEBRITY = "price_fake_celeb_monthly";
process.env.STRIPE_PRICE_STANDARD_ANNUAL = "price_fake_std_annual";
process.env.STRIPE_PRICE_CELEBRITY_ANNUAL = "price_fake_celeb_annual";
process.env.STRIPE_PRICE_STANDARD_FAMILY2 = "price_fake_std_family2";
process.env.STRIPE_PRICE_STANDARD_FAMILY4 = "price_fake_std_family4";
process.env.STRIPE_PRICE_CELEBRITY_LIFETIME = "price_fake_celeb_lifetime";
// Keeps firebase-functions internals quiet when defining functions offline.
process.env.GCLOUD_PROJECT = "demo-fitness-unit-tests";
