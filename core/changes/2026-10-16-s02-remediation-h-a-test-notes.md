# S02 remediation H-A, item H4: test notes

Date: 2026-10-16. Area: documentation only.

Adds heading "H-A" to `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md` (the H-B section is kept unchanged): 19
oracles for the consent store, settings client, uploader and startup wiring (deterministic interleavings with gates;
each fails if the named guard is removed) and the list of stale fakes and older assertions the new contracts break
(`FakeConsent`, five `Fake implements ActivityCloudSettingsClient` classes needing `reset()`, five
`AccountScopedConsentStore` subclasses, the `resume` ordering, the write-before-sign-in test, the once-per-instance
delete test).

Verification state: documentation only, nothing compiled or run.
