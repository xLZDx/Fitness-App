# 32 — What this audit could not verify

Listed so that no reader mistakes silence for a pass. Each line states exactly what would close it.

| # | Claim / area | Status | What would close it |
|---|---|---|---|
| 1 | Every clip depicts the exercise it is attached to | UNAVAILABLE | Human review of 2,539 clips against their text. No automated check can see a seated/standing or left/right mismatch. **This is the largest unverifiable surface in the product.** |
| 2 | Exercise technique text is coaching-sound | UNAVAILABLE | Qualified trainer/physiotherapist review. The project's own scope already records this as C9 needing external budget, and 403 of the `purpose` texts were written by an assistant, not a trainer. |
| 3 | Figma ↔ production parity | UNAVAILABLE | No Figma file or token export exists in the tree. `docs/Redisign/` is prose. |
| 4 | Equipment recognition accuracy in a real gym | UNAVAILABLE | The model README reports top-1 0.617 / top-3 0.835 on **web-crawled** photos and calls that an upper bound. Closing it needs a labelled set of real gym photos. |
| 5 | Scanner pipeline behaviour: camera lifecycle, rotation, background/resume, permission denial, multi-object frames | UNAVAILABLE | Device or emulator session. |
| 6 | Form Check biomechanical validity | UNAVAILABLE | Physiotherapy review plus on-device capture. A known property is already recorded from an earlier device session: ML Kit holds `inFrameLikelihood >= 0.7` for landmarks **outside** the frame, so likelihood is not a usable in-frame test. |
| 7 | Rest timer across background, screen lock and app kill | UNAVAILABLE | Device session. |
| 8 | Workout resumption after process death | UNAVAILABLE | Device session. |
| 9 | Live Firestore rules as deployed | UNAVAILABLE | The rules file is read and CI runs emulator tests, but the **deployed** ruleset is not inspected here. `firebase deploy --only firestore:rules --dry-run` or console read. |
| 10 | Account deletion against real data | PARTIAL | Code traced end to end and a CI e2e job exists; not executed against a live project in this audit. |
| 11 | Stripe entitlement race conditions and refund/grace behaviour | UNAVAILABLE | Stripe test-mode session. G3 (5 price IDs) is also still unbuilt, so annual/family/lifetime SKUs cannot be exercised at all. |
| 12 | Performance: startup, catalogue parse, camera FPS, inference latency, memory | UNAVAILABLE | Profile run on a device. Note the catalogue is a **3.1 MB JSON parsed per language**; whether it is re-parsed per screen is a real question this audit did not measure. |
| 13 | Offline and degraded-network behaviour | UNAVAILABLE | Device session with airplane mode. |
| 14 | Accessibility beyond semantics: contrast, font scaling, tap targets | UNAVAILABLE | Device session with a screen reader and large-text settings. |
| 15 | CI job pass/fail history on the remote | UNAVAILABLE | `gh run list`. |
| 16 | Health Connect / Wear OS integrations | NOT_CHECKED | 9 files under `wear/`; two Wear providers have no reader. Not audited in this pass. |
| 17 | Voice control | NOT_CHECKED | `features/voice/` not audited in this pass. |
