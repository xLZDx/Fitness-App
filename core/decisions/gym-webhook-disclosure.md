# Decision: `gym-webhook-disclosure`

**Decision: DISCLOSE.** A gym-registered maintenance webhook is an authorized conditional third
*recipient* of equipment-report content, conditioned on the gym having registered one. The privacy
copy is amended accordingly; the dispatch itself (`functions/src/index.ts`'s `reportEquipment`) is
kept as-is, not removed.

**Why recipient, not processor (purposes-and-means analysis, GDPR Art. 4(8)/28).** A gym that
receives a fault report about its own equipment fixes its own equipment -- its own operational
purpose, using its own means, not a purpose or method the app sets for it and not "on behalf of" or
"per the instructions of" the app in the Art. 4(8) sense. That is recipient/independent-actor
behaviour, not processor behaviour, regardless of paperwork. The privacy copy already states the
operative fact: "a gym does not act on this app's instructions and nothing here governs what it
does with what it receives." Codex review, 2026-08-21 (round 4), caught the first version of this
record leaning on "no controller-processor agreement governs it" as if the absence of an agreement
were itself what settled the question -- backwards: the absence of an Art. 28 agreement is the
*consequence* of the gym acting independently, not the reason it does. Restated here with the
actual test first.

## Who decided, and how

Recorded from a live, in-session exchange with the operator (the product's sole owner --
`korostelevivan@gmail.com`, the same address named as the privacy contact in
`scripts/legal/legal_text.py`), 2026-08-21, while porting Gate F (`gym identity`, MRD-02) from
`marketing/site-prototype-2026-08-19` onto `master`. A Codex review of that port raised this as a
BLOCKER: Gate F is the first client code to ever supply a real (non-`"unknown"`) `gymId` on a
report, which is what turns the previously-unreachable `gyms/{gymId}.maintenanceWebhookUrl`
dispatch (`core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md`: "Unreachable today, because no gym
document is ever created") into a reachable one -- while the published privacy text still said
"Two processors are involved, and no others." Presented with exactly that framing -- disclose vs.
land Gate F without wiring the report-routing consumer vs. do not port Gate F at all -- the operator
chose disclosure.

## What changed as a result

- `scripts/legal/legal_text.py` (the single canonical source for both `mobile/lib/l10n/app_{en,ru}.arb`'s
  `legalPrivacyBody` and `public/privacy.html`, per `scripts/legal/build_legal.py`): added an
  "Equipment reports"/"Сообщения о неисправном оборудовании" paragraph naming the conditional
  third recipient, and rewrote the "Two processors... no others" sentence to "Two processors handle
  everything else... A gym you name in an equipment report can be a third recipient of that report's
  contents, but only that report, and only when that specific gym has registered its own maintenance
  channel... Unlike Google and Stripe, a gym does not act on this app's instructions and nothing here
  governs what it does with what it receives."
- Regenerated `mobile/lib/l10n/app_en.arb`, `mobile/lib/l10n/app_ru.arb`, `public/privacy.html`,
  `public/terms.html` via `python scripts/legal/build_legal.py`; `--check` passes.
- `STAMP` (the "Last updated" line, both locales) bumped to 21 August 2026.

## What did not change

No product code. The webhook dispatch in `functions/src/index.ts` is unchanged; this decision
authorizes what was already built, rather than requiring new engineering. `gymId` remains a free-text
onboarding field (Gate F's own scope), not a validated/registry-backed identifier -- a separate,
already-flagged MAJOR from the same Codex pass, deliberately out of scope for this specific decision.

## Reopening

Per `core/CURRENT_STATE.md`'s own invariant (`gym_webhook_disclosure_stays_honest` in
`scripts/review/state_ledger.py`): this closes only while the amended copy stays in sync across
`legal_text.py`, both generated `.arb` files and `public/privacy.html` (six surfaces, both
locales), the webhook dispatch in `functions/src/index.ts` stays in place, and this file exists. If
any surface reverts to claiming there are only two processors, if the dispatch is removed, or if
this file disappears, the row reopens.

The Terms of Service ("What you contribute") was found out of step with this disclosure during the
same review round -- it still described an equipment report's purpose as "to correct the
catalogue," which stopped being the whole truth once a registered gym became a possible recipient
of the report's contents. Corrected in the same commit (`legal_text.py`'s `TERMS_EN`/`TERMS_RU`);
the invariant does not check Terms, since Terms was never the disclosure surface -- Privacy is.
