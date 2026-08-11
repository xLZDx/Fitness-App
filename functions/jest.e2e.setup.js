/**
 * Environment for the e2e suite, set before `src/index.ts` is imported.
 *
 * `index.ts:53` calls `admin.initializeApp()` at module load. The two
 * emulator host variables have to exist by then, or the Admin SDK resolves
 * production endpoints and looks for credentials that are not there — so this
 * belongs in `setupFiles` (before the module registry) and not in the test
 * file's `beforeAll`.
 */
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = "demo-fitness-e2e";

// `stripeClient()` reads `STRIPE_SECRET_KEY.value()` at request time even when
// the Stripe module itself is mocked, and `defineSecret().value()` throws on an
// unset secret. Not a credential: the suite's Stripe mock never sees it.
process.env.STRIPE_SECRET_KEY = "sk_test_fake_e2e_key_not_real";
