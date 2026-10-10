# Fitness App

Fitness App is a mobile-first fitness and coaching project with a Flutter application, Firebase-related services, supporting backend functions, wearable experiments, and project-specific fitness/recommendation agents.

## Repository layout

- `mobile/` — Flutter application and its unit, widget, and device integration tests.
- `functions/` and `functions-equipment-identity/` — supporting cloud functions.
- `wear/` — wearable-related source and experiments.
- `core/` — implementation plans, reviews, design decisions, and historical engineering evidence.
- `docs/`, `runbooks/`, and `reports/` — documentation, operational guidance, and dated verification artifacts.
- `scripts/` — development and verification scripts.

## Local development

Install the Flutter SDK and the additional prerequisites described in [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md). From the Flutter application directory:

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
```

The device/emulator suite is separate from `flutter test`. Use the documented integration-test workflow and verify important UI changes on actual supported hardware or an emulator before claiming completion.

## Quality and safety

The app covers health and exercise-related interactions. Do not infer clinical safety, payment compliance, or production readiness from unit-test success. Respect the project rules for injury-sensitive features, privacy, Firebase access, subscription configuration, and consent.

**Repository authority:** This README is an entry point, not a release approval. Follow [AGENTS.md](AGENTS.md), [CLAUDE.md](CLAUDE.md), and the latest verified project status before any deployment.


## Historical Reviews Translated into English

Two original source-citation review reports are available with linked English companions:

- [Citation verification: 4 of 4 supported at the original checkpoint](reports/citation_verification_report.en.md).
- [Equipment identity citations: 1 supported and 3 unverified](reports/equipment_identity_citation_review.en.md).

The original Russian-language HTML reports remain unchanged as historical evidence. These review results are **not** current product, device, privacy or release approval.

## Contribution language

All newly authored GitHub descriptions, documentation, code comments, commit messages, issue/PR bodies, and review comments must be in English. Preserve immutable source data and machine-readable identifiers in their original form where translation would change behavior.
