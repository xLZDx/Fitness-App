import { tierForPriceId } from "../tiers";

/**
 * Regression: the tier mapping in index.ts covered only the two MONTHLY price
 * ids. `priceFor()` can hand Checkout an annual or family price too, so a user
 * who paid for a year was written back into Firestore as tier "free" —
 * downgraded by the very webhook that confirmed their payment.
 */
const ids = {
  standard: [
    "price_std_monthly",
    "price_std_annual",
    "price_std_family2",
    "price_std_family4",
  ],
  celebrity: ["price_cel_monthly", "price_cel_annual"],
};

describe("tierForPriceId", () => {
  it("maps every Supporter price to standard", () => {
    for (const id of ids.standard) {
      expect(tierForPriceId(id, ids)).toBe("standard");
    }
  });

  it("maps every Sustainer price to celebrityTrainer", () => {
    for (const id of ids.celebrity) {
      expect(tierForPriceId(id, ids)).toBe("celebrityTrainer");
    }
  });

  it("does not downgrade an annual subscriber to free", () => {
    expect(tierForPriceId("price_std_annual", ids)).toBe("standard");
    expect(tierForPriceId("price_cel_annual", ids)).toBe("celebrityTrainer");
  });

  it("does not downgrade a family subscriber to free", () => {
    expect(tierForPriceId("price_std_family2", ids)).toBe("standard");
    expect(tierForPriceId("price_std_family4", ids)).toBe("standard");
  });

  it("returns free for an unknown price", () => {
    expect(tierForPriceId("price_someone_elses", ids)).toBe("free");
  });

  it("returns free when the subscription carries no price", () => {
    expect(tierForPriceId(undefined, ids)).toBe("free");
  });

  // An unset secret resolves to an empty string. Two blanks must not "match"
  // and hand out a paid tier.
  it("an unset configured id never matches a blank price id", () => {
    const withBlanks = { standard: ["", undefined], celebrity: [""] };
    expect(tierForPriceId("", withBlanks)).toBe("free");
    expect(tierForPriceId(undefined, withBlanks)).toBe("free");
  });

  it("a price configured for both tiers resolves as standard, not both", () => {
    const overlap = {
      standard: ["price_shared"],
      celebrity: ["price_shared"],
    };
    expect(tierForPriceId("price_shared", overlap)).toBe("standard");
  });
});
