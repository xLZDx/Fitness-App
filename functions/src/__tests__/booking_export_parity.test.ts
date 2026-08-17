import * as fs from "fs";
import * as path from "path";

import { __bookingExportContract } from "../account_export";

/**
 * Every field written into a booking is classified as exportable or withheld.
 *
 * ## The defect
 *
 * `redactBooking` used to remove three named fields and spread the rest.
 * Traced field by field, that deny-list covered everything the writers
 * produce -- so there was no leak, and this is not a bug fix. What it could
 * not do is stay correct: a field added to a booking writer would have reached
 * a coach's export with nothing anywhere noticing.
 *
 * That is the shape this codebase has produced four times (F014 twice, N-02,
 * N-01): a field reaches the writer and the serialiser and not the guard. The
 * export now names what may LEAVE, and this holds the two in step.
 *
 * ## Why it parses the source
 *
 * The alternative is a hand-written list of the booking's fields, which is a
 * third place to forget. The keys come out of the object literals `index.ts`
 * actually writes, so a field added there appears here on the same commit --
 * which is the commit on which it becomes exportable.
 *
 * BOTH writers are read: `bookCoachSession` creates the row and `stripeWebhook`
 * merges `status`/`confirmedAt` into it after payment. A field written by the
 * second is exactly as exportable as one written by the first, and reading
 * only the creation literal is how the second would have been missed.
 *
 * ## What it does not claim
 *
 * That withholding the right things is the right POLICY. It claims that no
 * field is unclassified. `account_export.test.ts` asserts the behaviour --
 * that a client's uid and a payment-intent id do not appear in a coach's
 * export -- and this asserts that the classification cannot fall behind the
 * writers.
 */
describe("booking export parity", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "index.ts"), "utf8");

  /** Index just past the group opening at `src[i]`. */
  function balanced(i: number, open: string, close: string): number {
    let depth = 0;
    for (let j = i; j < src.length; j++) {
      if (src[j] === open) depth++;
      if (src[j] === close) {
        depth--;
        if (depth === 0) return j;
      }
    }
    return -1;
  }

  /** Top-level keys of one object literal starting at `open`. */
  function keysOf(open: number): string[] {
    const end = balanced(open, "{", "}");
    expect(end).toBeGreaterThan(open);
    const body = src
      .slice(open + 1, end)
      // Comments first: a key named only in a comment must not count, and a
      // commented-out key must not count either.
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .split("\n")
      .filter((l) => !l.trim().startsWith("//"))
      .join("\n");

    const keys: string[] = [];
    let nesting = 0;
    for (const raw of body.split("\n")) {
      const line = raw.trim();
      // Only top-level keys; a nested object's keys are not document fields.
      if (nesting === 0) {
        // `name: value` AND shorthand `name,`. The first version matched only
        // the colon form, which found five of the nine fields -- and the four
        // it missed included `coachUid`, one of the two the redaction exists
        // for. A parser that cannot see the field it is auditing proves
        // nothing, which is the same failure it exists to detect.
        const m = /^([A-Za-z_$][\w$]*)\s*(?::|,\s*$|$)/.exec(line);
        if (m) keys.push(m[1]);
      }
      for (const ch of line) {
        if (ch === "{" || ch === "[" || ch === "(") nesting++;
        if (ch === "}" || ch === "]" || ch === ")") nesting--;
      }
    }
    return keys;
  }

  /** Every field any writer puts into a `coach_bookings` document. */
  function writtenFields(): string[] {
    const found = new Set<string>();
    const target = "coach_bookings/${bookingId}`).set(";
    let at = src.indexOf(target);
    let writers = 0;
    while (at >= 0) {
      writers++;
      const open = src.indexOf("{", at + target.length);
      expect(open).toBeGreaterThan(at);
      for (const k of keysOf(open)) found.add(k);
      at = src.indexOf(target, at + target.length);
    }
    // Both writers, named rather than assumed: creation and the webhook merge.
    expect(writers).toBe(2);
    return [...found];
  }

  it("the parser found the literals it is supposed to police", () => {
    // A source-scanning test that matches nothing reports success. This is the
    // guard on the guard.
    const fields = writtenFields();
    expect(fields.length).toBeGreaterThanOrEqual(9);
    for (const expected of [
      "clientUid",
      "coachUid",
      "priceCents",
      "stripePaymentIntentId",
      "confirmedAt",
    ]) {
      expect(fields).toContain(expected);
    }
  });

  it("the contract lists are disjoint and non-empty", () => {
    const { self, withheld } = __bookingExportContract;
    expect(self.length).toBeGreaterThan(0);
    expect(withheld.length).toBeGreaterThan(0);
    const both = self.filter((f) => (withheld as readonly string[]).includes(f));
    expect(both).toEqual([]);
  });

  it("every written field is either exported or explicitly withheld", () => {
    const { self, withheld } = __bookingExportContract;
    const classified = new Set<string>([...self, ...withheld]);
    const unclassified = writtenFields().filter((f) => !classified.has(f));
    expect(unclassified).toEqual([]);
  });
});
