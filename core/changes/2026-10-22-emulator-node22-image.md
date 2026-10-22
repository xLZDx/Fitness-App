# Change record: Node 22 emulator image (2026-10-22)

Adds `tools/emulator-node22/Dockerfile` and README: a Linux image with Node 22 (Debian trixie), OpenJDK 21 and firebase-tools 15.17.0 for the rules and emulator test runs after the Cloud Functions runtime moved to nodejs22. No existing file changed. The image was built and its tool versions were printed; the Firestore emulator start check (emulators:exec, demo project) exited 0; no rules or e2e test was executed. Affected paths: `tools/emulator-node22/`.
