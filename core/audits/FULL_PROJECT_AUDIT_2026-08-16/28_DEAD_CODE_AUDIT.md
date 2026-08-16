# 28 - Dead, legacy and unreferenced code

Nothing was deleted. This is an inventory.

## A correction this audit made to itself

The first pass counted a provider dead if fewer than two FILES mentioned it. That measure reported
15 dead providers and was wrong: it misses same-file consumers. `aiCoachServiceProvider` was on that
list, and `ai_coach_service.dart:55` watches it four lines below its own declaration. Re-measured by
counting OCCURRENCES across `lib/` and `test/` and discounting the declaration itself, the real
figure is **7 of 196**. The wrong number is recorded here rather than quietly replaced, because the
same shape of mistake is what this audit is looking for elsewhere.

## Genuinely unreferenced providers - 7 of 196

| Provider | Declared in | Reading |
|---|---|---|
| `momentControllerProvider` | `mobile/lib/features/moments/state/moment_providers.dart:31` | DEAD |
| `launchCountProvider` | `moment_providers.dart:36` | DEAD |
| `injuryFilterUsesProvider` | `moment_providers.dart:40` | DEAD |
| `hasShownProvider` | `moment_providers.dart:44` | DEAD |
| `photoMonthsProvider` | `mobile/lib/features/progress_photos/state/progress_photos_providers.dart:216` | DEAD |
| `watchPairedProvider` | `mobile/lib/core/wear/state/wear_providers.dart:9` | DEAD |
| `wearIncomingProvider` | `mobile/lib/core/wear/state/wear_providers.dart:13` | DEAD |

These are not scattered noise. They are **two whole features with no reader**: the entire `moments`
provider set, and both halves of the Wear OS surface. `injuryFilterUsesProvider` is the more
interesting of the two groups - a counter of how often the injury filter did something, which would
have been the telemetry for the safety feature, wired to nothing.

## Deliberately retained, not dead

- `exercisesForEquipmentWithAiFallbackProvider` (`equipment_providers.dart:125`) -
  `@visibleForTesting`, no `lib/` consumer **by design** since commit `6a72dce`, documented in place.
- `XorPhotoCipher` - test-only cipher, no `lib/` caller outside its own definition.
- `PrefsPhotoKeyStore` - `@Deprecated`, retained for one-way migration off plaintext key storage.
- `_legacyContainer` (`app_router.dart:409`) - referenced within its own file; not dead.

## Lifecycle shape

Only **5 of 196** providers are `autoDispose`. Most are app-scoped repositories, where that is
correct. The ones worth a targeted look are the `.family` providers keyed on an exercise or
equipment id, which under this default accumulate an entry per key for the life of the process.
