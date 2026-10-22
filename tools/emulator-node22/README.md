# Firebase emulator image on Node 22

Build: `docker build -t fitness-emulator:node22 tools/emulator-node22`

Contents: Node 22 (Debian trixie slim), OpenJDK 21 headless (firebase-tools 15 requires Java 21 or newer for the emulators), firebase-tools 15.17.0 (the version pinned in `functions/package.json`). Verified versions on build 2026-10-22: node v22.23.4, java 21.0.12.1, firebase 15.17.0. Smoke check in the container: `firebase emulators:exec --only firestore --project demo-smoke "echo SMOKE_OK"` started the Firestore emulator, ran the command and exited with code 0 (this is a start check, not a rules test).

The image only provides the toolchain; mount the repository at `/work`. No test was run with it as part of this change.
