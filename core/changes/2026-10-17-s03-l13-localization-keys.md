# S03 lane L13: localization keys

Date: 2026-10-17. Kind: production resources, stories S03-01 to S03-16 (strings of design section 6).

## What changed
- mobile/lib/l10n/app_en.arb and mobile/lib/l10n/app_ru.arb: 129 new keys each, nine groups (6.1 to 6.9), appended before the closing brace; English keys carry descriptions and typed placeholders; plural and select forms as in the design where given.

## Why
Every user-visible string of S03 comes from an ARB key (design 6); the dock, the shell, the mode screens, Home, Progress, Sources and sign-out lanes use the generated getters.

## Affected contracts and paths
Existing keys are untouched (legalPrivacyBody stays as it is). The generated AppLocalizations is not tracked and is produced by the build. The tests (ARB parity, plural forms, word ban, length budgets) belong to S03-18.

## Verification state
Nothing was generated or run by the coordinator. The implementation agent parsed both files as JSON after the insertion. Everything else NOT_RUN until the test agents.
