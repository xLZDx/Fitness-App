/**
 * Price-id -> app-tier mapping, kept pure and separate from `index.ts`.
 *
 * Extracted so it can be unit-tested without a Secret Manager round trip and
 * without exporting anything extra from the functions entry point. The bug this
 * guards against was a silent one: the mapping covered only the two monthly
 * price ids, so an annual or family subscriber paid Stripe and was then written
 * back into Firestore as tier `free`.
 */

export interface TierPriceIds {
  /** Every recurring price that bills the Supporter tier. */
  standard: readonly (string | undefined)[];
  /** Every recurring price that bills the Sustainer tier. */
  celebrity: readonly (string | undefined)[];
}

/**
 * Resolves the tier a recurring price belongs to.
 *
 * Returns `"free"` for anything unrecognised — a price we do not know must
 * never silently grant a paid tier. Blank/undefined configured ids are ignored
 * so an unset secret cannot match an equally unset price id.
 */
export function tierForPriceId(
  priceId: string | undefined,
  ids: TierPriceIds,
): "standard" | "celebrityTrainer" | "free" {
  if (!priceId) return "free";
  const known = (list: readonly (string | undefined)[]) =>
    list.some((id) => !!id && id === priceId);
  if (known(ids.standard)) return "standard";
  if (known(ids.celebrity)) return "celebrityTrainer";
  return "free";
}
