# S02-02 change record: stream cipher and secure-storage key provider

Date: 2026-10-16. Story: S02-02 "Local journal" (design 3.4, 3.5; GPS-PRIV-084; test ids I07, I24).

## What changed

- New `mobile/lib/features/activity/repository/journal_cipher.dart`: `JournalCipher` with an AES-256-GCM implementation (magic `AJS1`, 12-byte random IV, ciphertext plus tag), `JournalKeyProvider` with a `flutter_secure_storage` implementation and an in-memory one, and the `JournalSecureStorage` seam.

## Why

`streams.bin` must hold no plaintext coordinates (design 3.4). The key provider keeps the three outcomes of the photo key store (absent, unreadable, corrupt): an unreadable store never mints a new key, an absent key means a lost stream (design 3.5).

## Affected contracts and paths

`mobile/lib/features/activity/repository/journal_cipher.dart` only. The seam is re-declared instead of importing `progress_photos` so the features stay independent.

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
