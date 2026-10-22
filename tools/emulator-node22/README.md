# Firebase emulator image on Node 22

Build: `docker build -t fitness-emulator:node22 tools/emulator-node22`

Contents: Node 22 (Debian bookworm slim), OpenJDK 17 headless (needed by the Firestore emulator), firebase-tools 15.17.0 (the version pinned in `functions/package.json`). Verified versions on build 2026-10-22: node v22.23.4, java 17.0.20.1, firebase 15.17.0.

The image only provides the toolchain; mount the repository at `/work`. No test was run with it as part of this change.
