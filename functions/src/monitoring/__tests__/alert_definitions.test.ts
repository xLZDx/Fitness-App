import {
  STRIPE_RECONCILIATION_FAILURE_FILTER,
  DELETE_ACCOUNT_FAILURE_FILTER,
  EXPORT_ACCOUNT_FAILURE_FILTER,
  APP_CHECK_ATTESTED_RATIO_METRIC,
  stripeReconciliationAlertFilterString,
  deleteAccountAlertFilterString,
  exportAccountAlertFilterString,
} from "../alert_definitions";
import { matchesLogMatchFilter, type LogEntryFixture } from "../types";
import * as signals from "../log_signals";

function entry(
  functionName: string,
  message: string,
  severity: LogEntryFixture["severity"] = "ERROR",
): LogEntryFixture {
  return { functionName, message, severity };
}

describe("Stripe reconciliation-failure alert filter", () => {
  it("matches both real failure log lines from the webhook", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripeWebhook", signals.STRIPE_RECONCILE_CANCEL_FAILED),
      ),
    ).toBe(true);
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripeWebhook", signals.STRIPE_RECONCILE_FAILED),
      ),
    ).toBe(true);
  });

  it("does not match the two non-failure log lines from the same code path", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripeWebhook", signals.STRIPE_RECONCILE_DUPLICATE_FOUND, "WARNING"),
      ),
    ).toBe(false);
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("stripeWebhook", signals.STRIPE_RECONCILE_CANCEL_OK, "INFO"),
      ),
    ).toBe(false);
  });

  it("does not match the identical message from a different function", () => {
    expect(
      matchesLogMatchFilter(
        STRIPE_RECONCILIATION_FAILURE_FILTER,
        entry("deleteAccount", signals.STRIPE_RECONCILE_FAILED),
      ),
    ).toBe(false);
  });

  it("renders a filter string scoped to the stripeWebhook function", () => {
    const filter = stripeReconciliationAlertFilterString();
    expect(filter).toContain('resource.labels.function_name="stripeWebhook"');
    expect(filter).toContain(signals.STRIPE_RECONCILE_CANCEL_FAILED);
    expect(filter).toContain(signals.STRIPE_RECONCILE_FAILED);
  });
});

describe("deleteAccount operational-failure alert filter", () => {
  it("matches all three explicit failure paths", () => {
    for (const message of [
      signals.DELETE_ACCOUNT_STRIPE_CANCEL_FAILED,
      signals.DELETE_ACCOUNT_FIRESTORE_DELETE_FAILED,
      signals.DELETE_ACCOUNT_AUTH_DELETE_FAILED,
    ]) {
      expect(
        matchesLogMatchFilter(
          DELETE_ACCOUNT_FAILURE_FILTER,
          entry("deleteAccount", message),
        ),
      ).toBe(true);
    }
  });

  it("matches the platform backstop for a failure outside the three named catches", () => {
    // Covers, e.g., the pre-try Firestore read at index.ts:2086 -- no
    // explicit catch names it, but firebase-functions' own https.js wraps
    // the whole handler and logs this exact message for anything that
    // isn't already an HttpsError. See README.md's failure-path audit.
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry("deleteAccount", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(true);
  });

  it("does not match an expected refusal (thrown as HttpsError, never reaches the backstop)", () => {
    // "unauthenticated" and the quota/App-Check refusals inside deleteAccount
    // are thrown as HttpsError, so the platform wrapper's own
    // `!(err instanceof HttpsError)` check means they never produce a
    // PLATFORM_UNHANDLED_ERROR line in the first place. There is no
    // separate log message for them to accidentally match here -- this
    // test documents that absence rather than asserting a fixture.
    expect(DELETE_ACCOUNT_FAILURE_FILTER.messageEquals).not.toContain(
      "unauthenticated",
    );
  });

  it("does not match exportAccountData's identical-shaped failure", () => {
    expect(
      matchesLogMatchFilter(
        DELETE_ACCOUNT_FAILURE_FILTER,
        entry("exportAccountData", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(false);
  });

  it("renders a filter string scoped to the deleteAccount function", () => {
    const filter = deleteAccountAlertFilterString();
    expect(filter).toContain('resource.labels.function_name="deleteAccount"');
    expect(filter).toContain(signals.PLATFORM_UNHANDLED_ERROR);
  });
});

describe("exportAccountData operational-failure alert filter", () => {
  it("matches the explicit failure and the platform backstop", () => {
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("exportAccountData", signals.EXPORT_ACCOUNT_FAILED),
      ),
    ).toBe(true);
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("exportAccountData", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(true);
  });

  it("does not match deleteAccount's identical-shaped failure", () => {
    expect(
      matchesLogMatchFilter(
        EXPORT_ACCOUNT_FAILURE_FILTER,
        entry("deleteAccount", signals.PLATFORM_UNHANDLED_ERROR),
      ),
    ).toBe(false);
  });

  it("renders a filter string scoped to the exportAccountData function", () => {
    const filter = exportAccountAlertFilterString();
    expect(filter).toContain(
      'resource.labels.function_name="exportAccountData"',
    );
  });
});

describe("App Check attested-ratio log-based metric definition", () => {
  it("filters on the exact noteAppCheck event message", () => {
    expect(APP_CHECK_ATTESTED_RATIO_METRIC.filter).toBe(
      `jsonPayload.message="${signals.APP_CHECK_EVENT}"`,
    );
  });

  it("keeps labels bounded to fn and attested -- no uid or other unbounded field", () => {
    expect(APP_CHECK_ATTESTED_RATIO_METRIC.labelKeys).toEqual([
      "fn",
      "attested",
    ]);
    expect(APP_CHECK_ATTESTED_RATIO_METRIC.labelKeys).not.toContain("uid");
  });
});
